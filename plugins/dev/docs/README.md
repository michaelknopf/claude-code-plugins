# dev plugin docs

Canonical text for the guidance the plugin's skills, commands, and agents load at runtime.

Skills and agents inline these docs into their *instruction bodies*, so whatever a file says becomes a directive the agent follows. Keeping them in git puts every change to those directives under code review.

## Editing

Edit the file and open a PR. Nothing to publish or sync afterward.

## Loading a doc

```
!`"${CLAUDE_PLUGIN_ROOT}/scripts/inline-doc.sh" "${CLAUDE_PLUGIN_ROOT}/docs/<name>.md"`
```

Pass the doc's full path, built from `${CLAUDE_PLUGIN_ROOT}` in the line itself: Claude Code substitutes the variable into the text but doesn't export it to the script's environment. On any failure the script emits a warning rather than nothing — an empty inline would leave the agent believing no guidance applies.
