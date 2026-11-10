#!/usr/bin/env python3
"""gmail-filters — manage Gmail filter automation from a declarative config.

The mechanical backend for the /mk:gmail-filters command. Writing filters goes through the
`gws` (googleworkspace-cli) binary, which holds the user's OAuth credentials; reading and
labeling mail is the command's job, through the Gmail connector. Only `preflight` and
`apply` touch Gmail.

Subcommands:
  preflight            Verify gws is authed with the gmail.settings.basic scope (needed to
                       write filters). Exits non-zero with a fix hint if not.
  apply    [config]    Idempotently create the labels and filters declared for the account.
                       Dry run by default; pass --apply to mutate.
  queries  [config]    Print each filter as the Gmail search that matches the same mail, for
                       backfilling labels onto existing messages. Offline.
  apps-script [config] Print a Google Apps Script that runs the delayed-archive sweep on a
                       time-driven trigger inside Google. Offline.

DELAYED ARCHIVE. A Gmail filter can only archive at delivery time, never after a delay,
so the sweep stamps a marker label via the API and archives it on a later run. The delay
keeps mail visible long enough for an external consumer (e.g. an expense tool's receipt scraper) to
see it before it leaves the inbox. Configure per account:

  sweep:
    label: Delayed Archive
    days: 7
    queries:
      - from:receipts@example.com
      - label:Receipt

`apps-script --config-url <url>` renders a script that runs server-side and fetches the sweep
stanza from that URL (e.g. the config's raw GitHub URL) on every run, so stanza edits take
effect once published, with no re-paste. Paste it into a project at script.google.com, add
the Gmail advanced service, and run `installTrigger` once.

CONFIG FILE (YAML, JSON also accepted). MULTI-ACCOUNT: a top-level `accounts` map keyed by
the managed email address. `apply` uses the stanza for the account `gws auth status`
reports, so filters cannot land in the wrong mailbox. The offline subcommands take
`--account`, defaulting to the only stanza when there is one. Default location ~/.config/gmail-filters.yaml (override
with $GMAIL_FILTERS_CONFIG or a path arg).

  accounts:
    you@example.com:
      labels:                                   # labels to ensure exist (nested via /)
        - GitHub/my-repo
      filters:
        - criteria: { query: "list:(<my-repo.my-org.github.com>)" }
          labels: [GitHub/my-repo]            # 1+ labels; one filter may stamp many
          archive: false                        # optional: also skip the inbox
          markRead: false                       # optional: also mark read
        - criteria: { from: firebase-noreply@google.com, subject: "Missing dSYM" }
          labels: [Firebase/Missing dSYM]
    other@gmail.com:
      filters: [...]

criteria keys map to Gmail filter criteria (from, to, subject, query, hasAttachment, ...).
For mailing lists, prefer `query: "list:(<list-id>)"` — far more stable than From. Prefer
sender+subject patterns matching a recurring TEMPLATE over a bare `from:`.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import typing

# Conventional config location, overridable via $GMAIL_FILTERS_CONFIG. The file is a
# multi-account YAML (or JSON) keyed by the managed email address — see load_rules().
DEFAULT_CONFIG = os.path.expanduser(
    os.environ.get("GMAIL_FILTERS_CONFIG", "~/.config/gmail-filters.yaml")
)

SETTINGS_SCOPE = "https://www.googleapis.com/auth/gmail.settings.basic"


# --------------------------------------------------------------------------- gws plumbing


def gws(args, params=None, body=None, fmt=True):
    """Invoke gws and return (parsed_json_or_text, error_string_or_None).

    `fmt=False` omits the global `--format json` flag — `auth status` is an older subcommand
    that rejects it but already emits JSON, so it is called with fmt=False.
    """
    cmd = ["gws", *args]
    if fmt:
        cmd += ["--format", "json"]
    if params is not None:
        cmd += ["--params", json.dumps(params)]
    if body is not None:
        cmd += ["--json", json.dumps(body)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        return None, (proc.stderr.strip() or proc.stdout.strip())
    out = proc.stdout
    # gws prefixes a "Using keyring backend: keyring" line on some setups; strip it.
    out = "\n".join(l for l in out.splitlines() if not l.startswith("Using keyring"))
    try:
        return json.loads(out), None
    except json.JSONDecodeError:
        return out, None


def die(msg, code=1) -> "typing.NoReturn":
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def gws_dict(args, params=None, body=None, fmt=True, what="request"):
    """Call gws expecting a JSON object; die() on error or non-dict. Returns a dict."""
    data, err = gws(args, params=params, body=body, fmt=fmt)
    if err or not isinstance(data, dict):
        die(f"{what} failed: {err or 'unexpected non-JSON response'}")
    return data


# --------------------------------------------------------------------------- preflight


def cmd_preflight(_args):
    data, err = gws(["auth", "status"], fmt=False)
    if err or not isinstance(data, dict):
        die(
            "gws is not authenticated. Run `gws auth login` first.\n"
            f"       ({err or 'unexpected auth status output'})"
        )
    assert isinstance(data, dict)  # narrowed by the guard above
    scopes = data.get("scopes", [])
    if SETTINGS_SCOPE not in scopes:
        die(
            "gws is authenticated but MISSING the Gmail settings scope required to write "
            "filters:\n"
            f"         {SETTINGS_SCOPE}\n\n"
            "       Re-authenticate and ensure `gmail.settings.basic` is selected in the "
            "scope picker.\n"
            "       Reading and labeling work without it; only filter CREATE needs it."
        )
    print("ok: gws authenticated with gmail.settings.basic — filter writes are authorized.")


# --------------------------------------------------------------------------- shared: labels


def _parse_config_text(text, path):
    """Parse YAML (preferred) or JSON config text into a dict.

    Uses PyYAML if importable; otherwise falls back to the `yq` binary (YAML is a JSON
    superset, so a .json file also parses fine either way). Dies with a clear hint if
    neither a YAML parser nor valid JSON is available.
    """
    try:
        import yaml  # type: ignore

        return yaml.safe_load(text)
    except ModuleNotFoundError:
        pass
    # Fall back to `yq` to convert YAML -> JSON.
    proc = subprocess.run(["yq", "-o=json", "."], input=text, capture_output=True, text=True)
    if proc.returncode == 0:
        return json.loads(proc.stdout)
    # Last resort: maybe it is already plain JSON.
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        die(
            f"cannot parse {path!r} as YAML or JSON. Install PyYAML (`uv pip install pyyaml`) "
            f"or the `yq` binary.\n       (yq said: {proc.stderr.strip()})"
        )


def active_account():
    """The email address gws is currently authenticated as (from `gws auth status`)."""
    data, err = gws(["auth", "status"], fmt=False)
    if err or not isinstance(data, dict) or not data.get("user"):
        die(f"could not determine the active gws account: {err or 'no user in auth status'}")
    assert isinstance(data, dict)
    return data["user"]


def default_account(path):
    """The account an offline subcommand renders: the config's only stanza, else gws's."""
    path = path or DEFAULT_CONFIG
    try:
        with open(path) as handle:
            config = _parse_config_text(handle.read(), path)
    except OSError:
        config = None
    accounts = config.get("accounts") if isinstance(config, dict) else None
    if isinstance(accounts, dict) and len(accounts) == 1:
        return next(iter(accounts))
    return active_account()


def load_rules(path, account=None):
    """Load the stanza for `account` (default: the active gws account) from the config.

    `path` may be an explicit file or None (use the conventional DEFAULT_CONFIG). The config
    is keyed by managed email address under a top-level `accounts` map; only the stanza whose
    key equals that account is used, so filters can never be applied to the wrong
    mailbox. A single-stanza legacy file (top-level `filters`, no `accounts`) is still accepted
    but only if its implicit account matches.
    """
    path = path or DEFAULT_CONFIG
    try:
        with open(path) as handle:
            text = handle.read()
    except OSError as exc:
        die(
            f"cannot read config {path!r}: {exc}\n"
            f"       Create it (default: {DEFAULT_CONFIG}) or pass an explicit path / "
            f"set $GMAIL_FILTERS_CONFIG."
        )
    config = _parse_config_text(text, path)
    if not isinstance(config, dict):
        die(f"config {path!r} must be a mapping at the top level")

    account = account or active_account()

    # Preferred shape: {accounts: {<email>: {labels, filters}}}
    if "accounts" in config:
        accounts = config["accounts"]
        if not isinstance(accounts, dict):
            die("config 'accounts' must be a mapping of email -> stanza")
        if account not in accounts:
            die(
                f"account {account!r} has no stanza in {path!r}.\n"
                f"       Configured accounts: {', '.join(sorted(accounts)) or '(none)'}\n"
                f"       Add an 'accounts: {account}:' stanza, or switch gws accounts "
                f"(apps-script: pass --account)."
            )
        stanza = accounts[account]
    else:
        # Legacy single-account file: {account: <email>, filters: [...]} or bare {filters:[...]}.
        declared = config.get("account")
        if declared and declared != account:
            die(
                f"config {path!r} is for account {declared!r}, not {account!r}. "
                f"Refusing to apply another account's filters."
            )
        stanza = config

    if not isinstance(stanza, dict) or "filters" not in stanza:
        die(f"the stanza for {account!r} in {path!r} must contain a 'filters' array")
    return stanza


def label_name_to_id():
    data = gws_dict(["gmail", "users", "labels", "list"], params={"userId": "me"}, what="listing labels")
    return {l["name"]: l["id"] for l in data.get("labels", [])}


def ensure_labels(names, dry):
    """Create any missing labels; return name->id map including pre-existing ones."""
    name2id = label_name_to_id()
    for name in names:
        if name in name2id:
            print(f"  label exists   {name}")
            continue
        if dry:
            print(f"  label [dry]    {name}")
            name2id[name] = f"<new:{name}>"
            continue
        res, err = gws(
            ["gmail", "users", "labels", "create"],
            params={"userId": "me"},
            body={"name": name, "labelListVisibility": "labelShow", "messageListVisibility": "show"},
        )
        if err or not isinstance(res, dict):
            print(f"  label ERROR    {name}: {err}")
        else:
            name2id[name] = res["id"]
            print(f"  label created  {name}  ({res['id']})")
    return name2id


def all_label_names(rules):
    names = set(rules.get("labels", []))
    for flt in rules["filters"]:
        names.update(flt.get("labels", []))
    return sorted(names)


def criteria_label(crit):
    return crit.get("query") or crit.get("from") or crit.get("subject") or json.dumps(crit)


def resolve_labels(flt, name2id):
    """Resolve a filter's label names to ids. Return (ids, missing_names)."""
    names = flt.get("labels", [])
    ids = [name2id[n] for n in names if n in name2id]
    missing = [n for n in names if n not in name2id]
    return ids, missing


def archives_out_of_inbox(flt):
    """True if the filter archives — i.e. removes mail from the inbox view.

    Only `archive` hides mail; `markRead` merely clears UNREAD and leaves the message in the
    inbox, so it is not the hidden-mail hazard the no-label refusal guards against.
    """
    return bool(flt.get("archive"))


def criteria_key(crit):
    """Order-independent identity for a filter's criteria, for dedup against existing filters."""
    return json.dumps(crit, sort_keys=True)


def existing_filters_by_criteria():
    """Map criteria_key() -> existing filter record, for idempotent apply and drift detection."""
    data = gws_dict(
        ["gmail", "users", "settings", "filters", "list"],
        params={"userId": "me"},
        what="listing filters",
    )
    return {criteria_key(f.get("criteria", {})): f for f in data.get("filter", [])}


def _fmt_action(summary):
    """Render an (labels, archive, markRead) summary as a one-line human description."""
    labels, archive, mark_read = summary
    parts = ["+".join(labels) or "(no label)"]
    if archive:
        parts.append("+archive")
    if mark_read:
        parts.append("+read")
    return " ".join(parts)


def action_summary(flt):
    """A rule's intended action as (sorted label names, archive, markRead) — the semantic shape
    to compare against an installed filter, by NAME so it holds even in dry-run before label ids
    exist."""
    return (sorted(flt.get("labels", [])), bool(flt.get("archive")), bool(flt.get("markRead")))


def existing_action_summary(existing_filter, id2name):
    """The same (label names, archive, markRead) shape for a filter gws already returned, mapping
    its label ids back to names. Ids we can't resolve to a name fall back to the raw id."""
    action = existing_filter.get("action", {})
    labels = sorted(id2name.get(lid, lid) for lid in action.get("addLabelIds", []))
    removes = action.get("removeLabelIds", [])
    return (labels, "INBOX" in removes, "UNREAD" in removes)


# --------------------------------------------------------------------------- apply


def cmd_apply(args):
    rules = load_rules(args.rules)
    check_sweep_shape(args.rules, active_account())
    dry = not args.apply
    print(f"MODE: {'DRY-RUN' if dry else 'APPLY'}\n=== LABELS ===")
    name2id = ensure_labels(all_label_names(rules), dry)

    print("\n=== FILTERS ===")
    existing_by_criteria = existing_filters_by_criteria()
    id2name = {lid: name for name, lid in name2id.items()}
    for flt in rules["filters"]:
        crit = flt["criteria"]
        installed = existing_by_criteria.get(criteria_key(crit))
        if installed is not None:
            want = action_summary(flt)
            have = existing_action_summary(installed, id2name)
            if want == have:
                print(f"  exists  {criteria_label(crit)}")
            else:
                # Gmail filters are immutable, so re-running apply can't reconcile this — the
                # criteria already exists, so we skip create, but the rule's action has drifted
                # from what's installed. Warn loudly; the agent reconciles via gws (delete the
                # existing filter by id, then re-run) rather than silently dropping the edit.
                print(
                    f"  DIFFERS {criteria_label(crit)}\n"
                    f"          installed: {_fmt_action(have)}\n"
                    f"          rules file: {_fmt_action(want)}\n"
                    f"          Gmail filters are immutable — delete existing filter "
                    f"(id {installed.get('id', '?')}) via gws, then re-run to apply the change."
                )
            continue
        add_ids, missing = resolve_labels(flt, name2id)
        remove_ids = []
        if flt.get("archive"):
            remove_ids.append("INBOX")
        if flt.get("markRead"):
            remove_ids.append("UNREAD")
        action = {"addLabelIds": add_ids}
        if remove_ids:
            action["removeLabelIds"] = remove_ids
        desc = f"{criteria_label(crit):52s} -> {'+'.join(flt.get('labels', [])) or '(no label)'}"
        if flt.get("archive"):
            desc += " +archive"
        if flt.get("markRead"):
            desc += " +read"
        if missing:
            desc += f"  [unresolved: {'+'.join(missing)}]"
        # A filter that archives but resolved no label would strip mail out of the inbox with
        # nothing to find it under. Refuse it rather than create a hidden-mail rule.
        if archives_out_of_inbox(flt) and not add_ids:
            print(f"  SKIP   {desc}: archives but no label resolved — refusing")
            continue
        if dry:
            print(f"  [dry] {desc}")
            continue
        res, err = gws(
            ["gmail", "users", "settings", "filters", "create"],
            params={"userId": "me"},
            body={"criteria": crit, "action": action},
        )
        if err or not isinstance(res, dict):
            print(f"  ERROR {desc}: {err}")
        else:
            print(f"  created {desc}  (id {res.get('id', '?')})")

    if dry:
        print("\nDry run — nothing changed. Re-run with --apply to execute.")


# --------------------------------------------------------------------------- queries


def _q(value):
    """Wrap a criteria value as a single quoted search token so embedded operators/parens
    (e.g. a stray `)` or `OR`) can't widen the search beyond what the filter itself matches."""
    return '"' + str(value).replace('"', r"\"") + '"'


def criteria_to_query(crit):
    """Translate a filter criteria dict into a Gmail SEARCH query string.

    Covers the full documented criteria surface so a backfill matches exactly the set the
    apply-created Gmail filter matches. `query`/`negatedQuery` are raw Gmail search syntax
    and pass through verbatim; the structured keys are quoted to neutralize stray operators.
    """
    parts = []
    if "from" in crit:
        parts.append(f"from:({_q(crit['from'])})")
    if "to" in crit:
        parts.append(f"to:({_q(crit['to'])})")
    if "subject" in crit:
        parts.append(f"subject:({_q(crit['subject'])})")
    if crit.get("hasAttachment"):
        parts.append("has:attachment")
    if crit.get("excludeChats"):
        parts.append("-in:chats")
    if "size" in crit:
        # sizeComparison: "larger" | "smaller" (Gmail default is larger if unspecified).
        op = "smaller" if crit.get("sizeComparison") == "smaller" else "larger"
        parts.append(f"{op}:{int(crit['size'])}")
    if "query" in crit:
        parts.append(crit["query"])
    if "negatedQuery" in crit:
        parts.append(f"-({crit['negatedQuery']})")
    return " ".join(parts)


def cmd_queries(args):
    rules = load_rules(args.rules, account=args.account or default_account(args.rules))
    out = [
        {
            "query": criteria_to_query(flt["criteria"]),
            "labels": flt.get("labels") or [],
            "archive": bool(flt.get("archive")),
            "markRead": bool(flt.get("markRead")),
        }
        for flt in rules["filters"]
    ]
    print(json.dumps(out, indent=2))


# --------------------------------------------------------------------------- sweep


def load_sweep(rules):
    """Return (label, days, queries) from the account's `sweep` stanza, or die."""
    sweep = rules.get("sweep")
    if not sweep:
        die(
            "no 'sweep' stanza in the config for this account.\n"
            "       Add:  sweep:\n"
            "               label: Delayed Archive\n"
            "               days: 7\n"
            "               queries: ['from:receipts@example.com', ...]"
        )
    label = sweep.get("label")
    queries = sweep.get("queries") or []
    if not label or not queries:
        die("the 'sweep' stanza needs both a 'label' and a non-empty 'queries' list")
    return label, sweep.get("days", 7), queries


def check_sweep_shape(path, account):
    """Die unless the Apps Script's line reader sees the same sweep stanza YAML does.

    Mirrors loadSweep_() in APPS_SCRIPT_TEMPLATE; change both together.
    """
    path = path or DEFAULT_CONFIG
    with open(path) as handle:
        text = handle.read()
    expected = load_rules(path, account=account).get("sweep")
    if expected is None:
        return
    expected = {"label": expected.get("label"), "days": expected.get("days", 7),
                "queries": expected.get("queries") or []}
    if read_sweep_lines(text, account) != expected:
        die(
            "the sweep stanza uses YAML the Apps Script cannot read. Keep it to `label:`,\n"
            "       `days:`, and a `queries:` list of one-line scalars."
        )


def read_sweep_lines(text, account):
    lines = text.split("\n")

    def indent(line):
        return len(line) - len(line.lstrip())

    def unquote(value):
        if value.startswith('"'):
            return json.loads(value)
        if value.startswith("'"):
            return value[1:-1].replace("''", "'")
        return value

    start = next((n for n, l in enumerate(lines) if unquote(l.strip().removesuffix(":")) == account), None)
    if start is None:
        return None
    i = start + 1
    while i < len(lines) and not re.fullmatch(r"\s+sweep:\s*", lines[i]):
        if lines[i].strip() and indent(lines[i]) <= indent(lines[start]):
            return None
        i += 1
    if i >= len(lines):
        return None
    sweep_indent = indent(lines[i])
    sweep = {"label": None, "days": 7, "queries": []}
    for line in lines[i + 1:]:
        line = re.sub(r"\s+#.*$", "", line)
        if not line.strip():
            continue
        if indent(line) <= sweep_indent:
            break
        item = re.fullmatch(r"- (.*)", line.strip())
        field = re.fullmatch(r"(label|days):\s*(.*)", line.strip())
        if item:
            sweep["queries"].append(unquote(item.group(1)))
        elif field:
            sweep[field.group(1)] = int(field.group(2)) if field.group(1) == "days" else unquote(field.group(2))
    return sweep


# --------------------------------------------------------------------------- apps-script

# Works message by message through the Gmail advanced service rather than GmailApp, because
# GmailApp archives whole threads, which would pull newer, unmarked replies
# out of the inbox along with the aged message.
APPS_SCRIPT_TEMPLATE = """\
// Generated by `gmail-filters.py apps-script` for __ACCOUNT__.
// The sweep stanza is fetched from CONFIG_URL on every run, so config edits need no re-paste.
// Requires the Gmail advanced service (Services -> + -> Gmail API).

const CONFIG_URL = __CONFIG_URL__;
const ACCOUNT = __ACCOUNT_JSON__;
const EVERY_HOURS = __EVERY_HOURS__;

function sweep() {
  const sweep = loadSweep_();
  const labelId = labelId_(sweep.label);
  const marker = quote_(sweep.label);
  const toMark = new Set();
  for (const query of sweep.queries) {
    for (const id of searchIds_(`in:inbox -label:${marker} (${query})`)) toMark.add(id);
  }
  modify_([...toMark], { addLabelIds: [labelId] });
  const aged = searchIds_(`in:inbox label:${marker} -is:starred older_than:${sweep.days}d`);
  modify_(aged, { removeLabelIds: ['INBOX'] });
  console.log(`Marked ${toMark.size}, archived ${aged.length}.`);
}

// Apps Script has no YAML parser, so this reads only the sweep stanza's fixed shape:
// `label:`, `days:`, and a `queries:` list of one-line scalars. `apps-script` refuses to
// render when the config strays outside that shape.
function loadSweep_() {
  const lines = UrlFetchApp.fetch(CONFIG_URL).getContentText().split('\\n');
  const indent = (line) => line.search(/\\S/);
  const start = lines.findIndex((l) => unquote_(l.trim().replace(/:$/, '')) === ACCOUNT);
  if (start < 0) throw new Error(`${ACCOUNT} not found in ${CONFIG_URL}`);
  let i = start + 1;
  while (i < lines.length && !/^\\s+sweep:\\s*$/.test(lines[i])) {
    if (lines[i].trim() && indent(lines[i]) <= indent(lines[start])) i = lines.length;
    else i += 1;
  }
  if (i >= lines.length) throw new Error(`no sweep stanza for ${ACCOUNT}`);
  const sweepIndent = indent(lines[i]);
  const sweep = { days: 7, queries: [] };
  for (i += 1; i < lines.length; i += 1) {
    const line = lines[i].replace(/\\s+#.*$/, '');
    if (!line.trim()) continue;
    if (indent(line) <= sweepIndent) break;
    const item = line.trim().match(/^- (.*)$/);
    const field = line.trim().match(/^(label|days):\\s*(.*)$/);
    if (item) sweep.queries.push(unquote_(item[1]));
    else if (field) sweep[field[1]] = field[1] === 'days' ? Number(field[2]) : unquote_(field[2]);
  }
  if (!sweep.label || !sweep.queries.length) throw new Error('incomplete sweep stanza');
  return sweep;
}

function unquote_(value) {
  if (value.startsWith('"')) return JSON.parse(value);
  if (value.startsWith("'")) return value.slice(1, -1).replace(/''/g, "'");
  return value;
}

function installTrigger() {
  for (const trigger of ScriptApp.getProjectTriggers()) {
    if (trigger.getHandlerFunction() === 'sweep') ScriptApp.deleteTrigger(trigger);
  }
  ScriptApp.newTrigger('sweep').timeBased().everyHours(EVERY_HOURS).create();
}

function quote_(value) {
  return '"' + value.replace(/"/g, '\\\\"') + '"';
}

function labelId_(name) {
  const existing = (Gmail.Users.Labels.list('me').labels || []).find((l) => l.name === name);
  return existing ? existing.id : Gmail.Users.Labels.create({ name }, 'me').id;
}

function searchIds_(q) {
  const ids = [];
  let pageToken;
  do {
    const page = Gmail.Users.Messages.list('me', { q, maxResults: 500, pageToken });
    for (const m of page.messages || []) ids.push(m.id);
    pageToken = page.nextPageToken;
  } while (pageToken);
  return ids;
}

function modify_(ids, change) {
  for (let i = 0; i < ids.length; i += 1000) {
    Gmail.Users.Messages.batchModify({ ids: ids.slice(i, i + 1000), ...change }, 'me');
  }
}
"""


def cmd_apps_script(args):
    account = args.account or default_account(args.rules)
    load_sweep(load_rules(args.rules, account=account))
    check_sweep_shape(args.rules, account)
    script = (
        APPS_SCRIPT_TEMPLATE.replace("__ACCOUNT__", account)
        .replace("__CONFIG_URL__", json.dumps(args.config_url))
        .replace("__ACCOUNT_JSON__", json.dumps(account))
        .replace("__EVERY_HOURS__", str(args.every_hours))
    )
    sys.stdout.write(script)


# --------------------------------------------------------------------------- main


def main():
    parser = argparse.ArgumentParser(prog="gmail-filters", description=(__doc__ or "").splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("preflight", help="verify gws auth + gmail.settings.basic scope")

    p_apply = sub.add_parser("apply", help="create labels + filters from the config")
    p_apply.add_argument(
        "rules", nargs="?", default=None,
        help=f"path to a rules config (YAML/JSON); default {DEFAULT_CONFIG}",
    )
    p_apply.add_argument("--apply", action="store_true", help="execute (default is dry run)")

    p_queries = sub.add_parser("queries", help="print each filter as a Gmail search, for backfill")
    p_queries.add_argument(
        "rules", nargs="?", default=None,
        help=f"path to a rules config (YAML/JSON); default {DEFAULT_CONFIG}",
    )
    p_queries.add_argument("--account", help="config stanza to use; default is the only one")

    p_script = sub.add_parser("apps-script", help="print an Apps Script that runs the sweep in Google")
    p_script.add_argument(
        "rules", nargs="?", default=None,
        help=f"path to a rules config (YAML/JSON); default {DEFAULT_CONFIG}",
    )
    p_script.add_argument(
        "--account", help="config stanza to render; default is the only one",
    )
    p_script.add_argument(
        "--config-url", required=True,
        help="URL the script fetches the config from at runtime, e.g. a raw GitHub URL",
    )
    p_script.add_argument(
        "--every-hours", type=int, default=1, choices=[1, 2, 4, 6, 8, 12],
        help="trigger interval (Apps Script only accepts these values)",
    )

    args = parser.parse_args()
    {
        "preflight": cmd_preflight,
        "apply": cmd_apply,
        "queries": cmd_queries,
        "apps-script": cmd_apps_script,
    }[args.command](args)


if __name__ == "__main__":
    main()
