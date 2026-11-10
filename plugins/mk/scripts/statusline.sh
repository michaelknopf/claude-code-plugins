#!/usr/bin/env zsh
# Claude Code status line: model, cost, context window, rate limits
#
# Displays a compact one-liner with mini progress bars and ANSI color coding.
# Reads the status JSON object from stdin (piped by Claude Code on each render).
#
# Example output:
#   Opus · $1.23 · ctx ████░░░░ 42% · 5h ██░░░░░░ 23% 3h30m · 7d ███░░░░░ 41% 5d12h
#
# Color thresholds (green < 50%, yellow < 75%, red >= 75%):
#   - context window: % of context used
#   - rate limits: % of quota used
#   - cost: green < $1, yellow < $5, red >= $5
#
# A single jq invocation builds the line; rate-limit and context sections are omitted
# when their data is unavailable.
#
# Usage:
#   Normal:  echo '{"model":...}' | ./statusline.sh    (reads JSON from stdin)
#   Test:    ./statusline.sh --test                     (runs built-in test cases)

# -- jq filter shared by normal mode and test mode --
# Current epoch, passed into jq for countdown computation.
# Single extra process — date is lightweight and unavoidable since jq has no `now`.
NOW=$(date +%s)

JQ_FILTER='
  # ANSI escape helpers
  def reset: "\u001b[0m";
  def cyan: "\u001b[36m";
  def green: "\u001b[32m";
  def yellow: "\u001b[33m";
  def red: "\u001b[31m";
  def dim: "\u001b[2m";

  # 8-char block progress bar: filled=█, empty=░
  def bar(pct):
    (pct / 100 * 8 | floor | if . > 8 then 8 elif . < 0 then 0 else . end) as $filled |
    (8 - $filled) as $empty |
    ([ range($filled) | "█" ] | join("")) +
    ([ range($empty)  | "░" ] | join(""));

  # Compact countdown: seconds remaining → "2h13m", "3d5h", "45m", etc.
  def countdown(secs):
    if secs <= 0 then "now"
    else
      (secs / 86400 | floor) as $d |
      ((secs % 86400) / 3600 | floor) as $h |
      ((secs % 3600) / 60 | floor) as $m |
      if $d > 0 then "\($d)d\($h)h"
      elif $h > 0 then "\($h)h\($m)m"
      else "\($m)m"
      end
    end;

  # Color by percentage thresholds (low=good for context/rate, low=good for cost too)
  def pct_color(pct):
    if pct < 50 then green
    elif pct < 75 then yellow
    else red
    end;

  # Color for cost: green < $1, yellow < $5, red >= $5
  def cost_color(cost):
    if cost < 1 then green
    elif cost < 5 then yellow
    else red
    end;

  # Model segment: cyan model name
  (cyan + .model.display_name + reset) as $model |

  # Cost segment: color-coded dollar amount (rounded to 2 decimal places)
  (.cost.total_cost_usd // 0) as $cost |
  # Format cost to always show 2 decimal places (e.g. $0.04, $1.23, $6.50)
  ($cost * 100 | floor) as $cents |
  (($cents / 100 | floor) | tostring) as $dollars |
  (($cents % 100 | if . < 10 then "0" + tostring else tostring end)) as $decimal |
  (cost_color($cost) + "$" + $dollars + "." + $decimal + reset) as $cost_seg |

  # Context window segment: bar + pct, omitted when null
  (.context_window.used_percentage // null) as $ctx_pct |
  (if $ctx_pct != null then
    " · ctx " + pct_color($ctx_pct) + bar($ctx_pct) + " " + ($ctx_pct | tostring) + "%" + reset
  else "" end) as $ctx_seg |

  # Rate limit segments with countdown to reset, omitted when unavailable
  (.rate_limits.five_hour.used_percentage // null) as $rl5 |
  (.rate_limits.five_hour.resets_at // null) as $rl5_reset |
  (.rate_limits.seven_day.used_percentage // null) as $rl7 |
  (.rate_limits.seven_day.resets_at // null) as $rl7_reset |
  (if $rl5 != null then
    " · 5h " + pct_color($rl5) + bar($rl5) + " " + ($rl5 | round | tostring) + "%" + reset
    + (if $rl5_reset != null then dim + " " + countdown($rl5_reset - $now) + reset else "" end)
  else "" end) as $rl5_seg |
  (if $rl7 != null then
    " · 7d " + pct_color($rl7) + bar($rl7) + " " + ($rl7 | round | tostring) + "%" + reset
    + (if $rl7_reset != null then dim + " " + countdown($rl7_reset - $now) + reset else "" end)
  else "" end) as $rl7_seg |

  $model + " · " + $cost_seg + $ctx_seg + $rl5_seg + $rl7_seg + "\n"
'

run_tests() {
  echo "=== Statusline test cases ===\n"

  # Normal usage: all fields present, mid-range values (green thresholds)
  echo "1. All fields, mid-range (green), resets in 3h30m / 5d12h:"
  render '{
    "model": {"display_name": "Opus"},
    "cost": {"total_cost_usd": 1.234},
    "context_window": {"used_percentage": 42},
    "rate_limits": {
      "five_hour": {"used_percentage": 23.5, "resets_at": '$((NOW + 12600))'},
      "seven_day": {"used_percentage": 41.2, "resets_at": '$((NOW + 475200))'}
    }
  }'

  # High usage: all bars should be red, resets soon
  echo "\n2. High usage (red), resets in 45m / 2d3h:"
  render '{
    "model": {"display_name": "Opus"},
    "cost": {"total_cost_usd": 6.50},
    "context_window": {"used_percentage": 88},
    "rate_limits": {
      "five_hour": {"used_percentage": 80, "resets_at": '$((NOW + 2700))'},
      "seven_day": {"used_percentage": 95, "resets_at": '$((NOW + 183600))'}
    }
  }'

  # No rate limits, null context: early session before first API call
  echo "\n3. Early session (no rate limits, null context):"
  render '{
    "model": {"display_name": "Sonnet"},
    "cost": {"total_cost_usd": 0.045},
    "context_window": {"used_percentage": null}
  }'

  # Near-zero usage: very start of session, resets far out
  echo "\n4. Near-zero usage, resets in 4h52m / 6d22h:"
  render '{
    "model": {"display_name": "Haiku"},
    "cost": {"total_cost_usd": 0.004},
    "context_window": {"used_percentage": 5},
    "rate_limits": {
      "five_hour": {"used_percentage": 5.2, "resets_at": '$((NOW + 17520))'},
      "seven_day": {"used_percentage": 2, "resets_at": '$((NOW + 597600))'}
    }
  }'

  # Yellow thresholds: cost $2-5, context 50-75%, rate limits 50-75%
  echo "\n5. Mid-high usage (yellow), resets in 2h13m / 4d5h:"
  render '{
    "model": {"display_name": "Sonnet"},
    "cost": {"total_cost_usd": 3.75},
    "context_window": {"used_percentage": 62},
    "rate_limits": {
      "five_hour": {"used_percentage": 55, "resets_at": '$((NOW + 7980))'},
      "seven_day": {"used_percentage": 68, "resets_at": '$((NOW + 363600))'}
    }
  }'

  # 100% context, rate limit just expired
  echo "\n6. Maxed out, rate limit just expired:"
  render '{
    "model": {"display_name": "Opus"},
    "cost": {"total_cost_usd": 12.00},
    "context_window": {"used_percentage": 100},
    "rate_limits": {
      "five_hour": {"used_percentage": 100, "resets_at": '$((NOW - 5))'},
      "seven_day": {"used_percentage": 100, "resets_at": '$((NOW + 60))'}
    }
  }'

  echo "
=== Done ==="
}

# render JSON -> runs the jq filter over JSON.
# Shared by the entry point and the test cases so they exercise the same code path.
render() {
  printf '%s' "$1" | jq -rj --argjson now "$NOW" "$JQ_FILTER"
}

# -- Entry point --
if [[ "$1" == "--test" ]]; then
  run_tests
else
  render "$(cat)"
fi
