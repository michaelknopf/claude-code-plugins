#!/usr/bin/env bash
# Kill orphaned Claude Code processes (re-parented to PID 1/launchd).
#
# When a terminal is closed abruptly, its `claude` process can be re-parented to
# PID 1 and linger, holding memory and (historically) draining battery. This
# reaps those orphans. Installed as a launchd job that runs every 60s.
#
# Matching is deliberately narrow: the awk pattern `/\/claude$/` matches ONLY
# processes whose comm field ends with "/claude" — the actual claude binary, not
# MCP servers or other subprocesses whose paths merely contain "claude" (e.g.
# ~/.claude/plugins/.../mcp-remote). Killing those prematurely would make Claude
# hang on shutdown waiting for children that were already dead. Only orphans
# (parent PID 1) are targeted, so live sessions with a real parent are untouched.

ps -eo pid,ppid,comm | awk '$2 == 1 && $3 ~ /\/claude$/ { print $1 }' | while read -r pid; do
  kill "$pid" 2>/dev/null
done
