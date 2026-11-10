# Commit loop: commit changes with a contextual message

1. Gather the git state: `git rev-parse --abbrev-ref HEAD`, `git status`, `git diff --cached`, and `git log --format='%s' -5` for style reference.
2. If the current branch is `main`, create a new branch before committing:
   - Generate a descriptive branch name based on the changes
   - Run `git checkout -b <branch-name>`
3. Analyze the changes and draft a commit message that:
   - Summarizes the nature of the changes (new feature, bug fix, refactor, etc.)
   - Focuses on the "why" rather than the "what"
   - Follows the style of the recent commits
   - If the caller passed a hint, uses it
4. Create the commit, ending the message with any attribution footer your setup requires
