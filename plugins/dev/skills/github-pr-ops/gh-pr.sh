#!/usr/bin/env bash
#
# gh-pr.sh — GitHub PR operations via GraphQL
#
# Subcommands:
#   post-review   Create a review with inline comment threads
#   post-comment  Post a general PR comment (not inline)
#   edit-comment  Edit an existing comment by Node ID
#   get-threads   List unresolved review threads with their Node IDs
#
# All subcommands auto-detect the current PR. Override with --pr <number>.
# All body content is read from files to avoid shell escaping issues.

set -euo pipefail

SUBCOMMAND="${1:-}"
shift || true

usage() {
    cat >&2 <<'EOF'
Usage:
  gh-pr.sh post-review [--event COMMENT|REQUEST_CHANGES] [--body-file FILE] --threads FILE [--pr NUMBER]
  gh-pr.sh post-comment --body-file FILE [--pr NUMBER]
  gh-pr.sh edit-comment --id NODE_ID --body-file FILE
  gh-pr.sh get-threads [--pr NUMBER]

Options:
  --pr NUMBER     PR number (auto-detected from current branch if omitted)
  --event EVENT   Review event: COMMENT (default) or REQUEST_CHANGES
  --body-file FILE  Path to markdown file containing comment/review body
  --threads FILE  Path to JSON file with inline thread definitions
  --id NODE_ID    GraphQL Node ID of comment to edit (IC_... or PRRC_...)
EOF
    exit 1
}

# Parse named args into variables
parse_args() {
    PR_NUMBER=""
    EVENT="COMMENT"
    BODY_FILE=""
    THREADS_FILE=""
    COMMENT_ID=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pr)        PR_NUMBER="$2"; shift 2 ;;
            --event)     EVENT="$2"; shift 2 ;;
            --body-file) BODY_FILE="$2"; shift 2 ;;
            --threads)   THREADS_FILE="$2"; shift 2 ;;
            --id)        COMMENT_ID="$2"; shift 2 ;;
            *) echo "Unknown argument: $1" >&2; usage ;;
        esac
    done
}

get_pr_id() {
    if [[ -n "${PR_NUMBER:-}" ]]; then
        gh pr view "$PR_NUMBER" --json id -q '.id'
    else
        gh pr view --json id -q '.id'
    fi
}

cmd_post_review() {
    parse_args "$@"

    [[ -z "$THREADS_FILE" ]] && { echo "Error: --threads FILE is required" >&2; usage; }
    [[ ! -f "$THREADS_FILE" ]] && { echo "Error: threads file not found: $THREADS_FILE" >&2; exit 1; }

    PR_ID=$(get_pr_id)

    # Bundle query + variables into a single payload for --input.
    # (-f query= alongside --input conflicts in gh 2.88+; --input must carry the full request body)
    QUERY='mutation($input: AddPullRequestReviewInput!) {
        addPullRequestReview(input: $input) {
            pullRequestReview { id state url }
        }
    }'

    if [[ -n "$BODY_FILE" ]]; then
        [[ ! -f "$BODY_FILE" ]] && { echo "Error: body file not found: $BODY_FILE" >&2; exit 1; }
        PAYLOAD=$(jq -n \
            --arg query "$QUERY" \
            --arg prId "$PR_ID" \
            --arg event "$EVENT" \
            --rawfile body "$BODY_FILE" \
            --slurpfile threads "$THREADS_FILE" \
            '{query: $query, variables: {input: {pullRequestId: $prId, event: $event, body: $body, threads: $threads[0]}}}')
    else
        PAYLOAD=$(jq -n \
            --arg query "$QUERY" \
            --arg prId "$PR_ID" \
            --arg event "$EVENT" \
            --slurpfile threads "$THREADS_FILE" \
            '{query: $query, variables: {input: {pullRequestId: $prId, event: $event, threads: $threads[0]}}}')
    fi

    echo "$PAYLOAD" | gh api graphql \
        --input - \
        --jq '.data.addPullRequestReview.pullRequestReview | "Review posted: \(.url)"'
}

cmd_post_comment() {
    parse_args "$@"

    [[ -z "$BODY_FILE" ]] && { echo "Error: --body-file FILE is required" >&2; usage; }
    [[ ! -f "$BODY_FILE" ]] && { echo "Error: body file not found: $BODY_FILE" >&2; exit 1; }

    PR_ID=$(get_pr_id)

    # Bundle query + variables into a single payload for --input (gh 2.88+ fix)
    jq -n \
        --arg query 'mutation($input: AddCommentInput!) {
            addComment(input: $input) {
                commentEdge { node { id url } }
            }
        }' \
        --arg subjectId "$PR_ID" \
        --rawfile body "$BODY_FILE" \
        '{query: $query, variables: {input: {subjectId: $subjectId, body: $body}}}' | \
    gh api graphql \
        --input - \
        --jq '.data.addComment.commentEdge.node | "Comment posted: \(.url) (id: \(.id))"'
}

cmd_edit_comment() {
    parse_args "$@"

    [[ -z "$COMMENT_ID" ]] && { echo "Error: --id NODE_ID is required" >&2; usage; }
    [[ -z "$BODY_FILE" ]]   && { echo "Error: --body-file FILE is required" >&2; usage; }
    [[ ! -f "$BODY_FILE" ]] && { echo "Error: body file not found: $BODY_FILE" >&2; exit 1; }

    # Detect comment type from Node ID prefix. Bundle query + variables for --input (gh 2.88+ fix).
    if [[ "$COMMENT_ID" == IC_* ]]; then
        # General issue/PR comment
        jq -n \
            --arg query 'mutation($input: UpdateIssueCommentInput!) {
                updateIssueComment(input: $input) {
                    issueComment { id }
                }
            }' \
            --arg id "$COMMENT_ID" \
            --rawfile body "$BODY_FILE" \
            '{query: $query, variables: {input: {id: $id, body: $body}}}' | \
        gh api graphql \
            --input - \
            --jq '"Comment updated: \(.data.updateIssueComment.issueComment.id)"'

    elif [[ "$COMMENT_ID" == PRRC_* ]]; then
        # Inline review comment
        jq -n \
            --arg query 'mutation($input: UpdatePullRequestReviewCommentInput!) {
                updatePullRequestReviewComment(input: $input) {
                    pullRequestReviewComment { id }
                }
            }' \
            --arg id "$COMMENT_ID" \
            --rawfile body "$BODY_FILE" \
            '{query: $query, variables: {input: {pullRequestReviewCommentId: $id, body: $body}}}' | \
        gh api graphql \
            --input - \
            --jq '"Review comment updated: \(.data.updatePullRequestReviewComment.pullRequestReviewComment.id)"'
    else
        echo "Error: unrecognized Node ID prefix in: $COMMENT_ID" >&2
        echo "Expected IC_ (issue comment) or PRRC_ (review comment)" >&2
        exit 1
    fi
}

cmd_get_threads() {
    parse_args "$@"
    PR_ID=$(get_pr_id)

    gh api graphql \
        -f query='
            query($pr_id: ID!) {
                node(id: $pr_id) {
                    ... on PullRequest {
                        reviewThreads(first: 100) {
                            nodes {
                                id
                                isResolved
                                path
                                line
                                comments(first: 50) {
                                    nodes {
                                        body
                                        author { login }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        ' \
        -f pr_id="$PR_ID" \
        --jq '
            .data.node.reviewThreads.nodes[]
            | select(.isResolved == false)
            | . as $thread
            | "Thread ID: \(.id)\nFile: \(.path)\(.line // "" | if . == "" then "" else ":\(.)" end)\nAuthor: \(.comments.nodes[0].author.login)\nComment: \(.comments.nodes[0].body)"
            + (
                if (.comments.nodes | length) > 1 then
                    "\n" + (
                        .comments.nodes[1:]
                        | to_entries[]
                        | "\nReply \(.key + 1) (\(.value.author.login)): \(.value.body)"
                    )
                else "" end
              )
            + "\n---"
        '
}

case "$SUBCOMMAND" in
    post-review)   cmd_post_review "$@" ;;
    post-comment)  cmd_post_comment "$@" ;;
    edit-comment)  cmd_edit_comment "$@" ;;
    get-threads)   cmd_get_threads "$@" ;;
    *) echo "Error: unknown subcommand '${SUBCOMMAND}'" >&2; usage ;;
esac
