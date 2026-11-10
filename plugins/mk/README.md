# mk plugin

Personal Claude Code commands, plus a launchd job that reaps orphaned `claude` processes.

## Orphan reaper

`com.mk.kill-orphaned` runs every 60s and kills orphaned `claude` processes (re-parented to PID 1 when a terminal is closed abruptly) that would otherwise linger and drain resources. It matches only the actual `claude` binary, never MCP servers or other subprocesses, and only orphans — live sessions are untouched.

## Install

```bash
plugins/mk/install.sh
```

This installs and loads the launchd job (macOS).

Re-running is safe (idempotent). To remove the job:

```bash
plugins/mk/install.sh --uninstall
```

**Non-macOS:** launchd is macOS-only. On Linux, schedule `kill-orphaned-claude.sh` every 60s yourself (e.g. via cron).

## Logs

- `/tmp/claude-kill-orphaned.log`
