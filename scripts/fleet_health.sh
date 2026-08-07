#!/usr/bin/env bash
# Fleet health monitor for the ammitto/data-* fetch schedules.
#
# Six data-repo schedules once died silently (GitHub deactivates a cron
# workflow after 60 days without repository activity) and nobody noticed
# for ~3 months. This script reads each fleet repo's Actions state — all
# reads, no writes — and flags:
#
#   DEAD    fetch.yml state is not "active" (disabled_inactively is
#           exactly the silent death above; disabled_manually counts too).
#   STALE   no schedule-event run of fetch.yml within the last
#           FLEET_HEALTH_MAX_AGE_HOURS hours (default 48 — one missed
#           daily run plus cron jitter). Catches deaths the state field
#           misses: cron typo, renamed workflow file, archived repo.
#   FAILING FLEET_HEALTH_STREAK (default 3) or more consecutive failed
#           completed runs with no intervening success. failure,
#           timed_out and startup_failure count as failures; cancelled,
#           skipped and neutral neither extend nor break a streak.
#   UNREADABLE fetch.yml missing or the API unreachable. Deliberately
#           unhealthy: an unwatchable repo is not a healthy repo.
#
# A run that commits nothing is HEALTHY: only run conclusions are read,
# never commit deltas, so zero-delta days (data-au has them legitimately)
# are never flagged.
#
# Usage: scripts/fleet_health.sh [--report FILE]
#   Prints a Markdown report (also appended to GITHUB_STEP_SUMMARY when
#   set, and written to FILE with --report).
#   Exit 0: every repo healthy. Exit 1: at least one repo flagged.
#   Any other exit code is a bug in this script, not a health verdict.
#
# Environment:
#   FLEET_HEALTH_ORG            owner org (default ammitto)
#   FLEET_HEALTH_WORKFLOW       workflow file name (default fetch.yml)
#   FLEET_HEALTH_MAX_AGE_HOURS  staleness limit (default 48)
#   FLEET_HEALTH_STREAK         failure-streak limit (default 3)
#   FLEET_HEALTH_REPOS_FILE     repo list (default scripts/fleet_repos.txt)
#   FLEET_HEALTH_FIXTURES       dir of fixture JSON; no network at all
#   FLEET_HEALTH_NOW_EPOCH      freeze "now" for tests
#   GH_TOKEN / GITHUB_TOKEN     optional; raises the API rate limit from
#                               60/h to 1000/h. The fleet is public, so
#                               anonymous reads work (verified 2026-08-07)
#                               but one 15-repo pass costs 45 of the 60.
#
# Needs bash, jq, GNU date, and gh or curl — all present on ubuntu runners.
set -euo pipefail

ORG="${FLEET_HEALTH_ORG:-ammitto}"
WORKFLOW_FILE="${FLEET_HEALTH_WORKFLOW:-fetch.yml}"
MAX_AGE_HOURS="${FLEET_HEALTH_MAX_AGE_HOURS:-48}"
STREAK_LIMIT="${FLEET_HEALTH_STREAK:-3}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOS_FILE="${FLEET_HEALTH_REPOS_FILE:-$SCRIPT_DIR/fleet_repos.txt}"
FIXTURES="${FLEET_HEALTH_FIXTURES:-}"
NOW_EPOCH="${FLEET_HEALTH_NOW_EPOCH:-$(date -u +%s)}"

REPORT_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --report)
      REPORT_FILE="${2:?--report needs a file argument}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

[ -f "$REPOS_FILE" ] || { echo "repos file not found: $REPOS_FILE" >&2; exit 66; }

# Fetch one API document. kind: workflow | schedule_runs | completed_runs.
# Prints the JSON body, or nothing on any failure — the caller treats an
# empty/invalid body as UNREADABLE rather than crashing, so one repo's
# outage cannot hide the state of the other fourteen.
api_get() {
  local kind="$1" repo="$2" path
  if [ -n "$FIXTURES" ]; then
    cat "$FIXTURES/${repo}__${kind}.json" 2>/dev/null || true
    return 0
  fi
  case "$kind" in
    workflow)
      path="repos/$ORG/$repo/actions/workflows/$WORKFLOW_FILE" ;;
    schedule_runs)
      path="repos/$ORG/$repo/actions/workflows/$WORKFLOW_FILE/runs?event=schedule&per_page=1" ;;
    completed_runs)
      path="repos/$ORG/$repo/actions/workflows/$WORKFLOW_FILE/runs?status=completed&per_page=10" ;;
    *)
      return 1 ;;
  esac
  if command -v gh >/dev/null 2>&1 &&
     { [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ] ||
       gh auth token >/dev/null 2>&1; }; then
    gh api "$path" 2>/dev/null || true
  else
    curl -sS --max-time 30 -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/$path" 2>/dev/null || true
  fi
}

table_rows=""
detail_lines=""
unhealthy=0
total=0

# The loop reads the repos file on FD 3 so gh/curl inside the loop can
# never swallow the remaining lines from stdin.
while IFS= read -r repo <&3; do
  repo="${repo%%#*}"
  repo="$(printf '%s' "$repo" | tr -d '[:space:]')"
  [ -n "$repo" ] || continue
  total=$((total + 1))

  workflow_json="$(api_get workflow "$repo")"
  schedule_json="$(api_get schedule_runs "$repo")"
  completed_json="$(api_get completed_runs "$repo")"

  state="$(jq -r '.state // empty' <<<"$workflow_json" 2>/dev/null || true)"
  last_sched="$(jq -r '.workflow_runs[0].created_at // empty' \
    <<<"$schedule_json" 2>/dev/null || true)"
  last_sched_conclusion="$(jq -r '.workflow_runs[0].conclusion // empty' \
    <<<"$schedule_json" 2>/dev/null || true)"
  # Newest-first S/F sequence of decided runs, e.g. "FFFS": F extends a
  # streak, S ends it, everything else (cancelled/skipped/neutral) is
  # dropped so it can neither hide nor fake a failure streak.
  seq="$(jq -r '[.workflow_runs[]? | .conclusion
        | select(. == "success" or . == "failure"
                 or . == "timed_out" or . == "startup_failure")
        | if . == "success" then "S" else "F" end] | join("")' \
    <<<"$completed_json" 2>/dev/null || true)"

  reasons=()

  if [ -z "$state" ]; then
    reasons+=("$WORKFLOW_FILE missing or API unreadable — treat as down until proven otherwise")
    state="(unreadable)"
  elif [ "$state" != "active" ]; then
    reasons+=("workflow state is '$state' — the schedule is not running")
  fi

  age_display="-"
  if [ -n "$last_sched" ]; then
    run_epoch="$(date -ud "$last_sched" +%s 2>/dev/null || echo 0)"
    if [ "$run_epoch" -gt 0 ]; then
      age_hours=$(( (NOW_EPOCH - run_epoch) / 3600 ))
      age_display="${age_hours}h"
      if [ "$age_hours" -gt "$MAX_AGE_HOURS" ]; then
        reasons+=("last schedule run was ${age_hours}h ago (limit ${MAX_AGE_HOURS}h)")
      fi
    else
      reasons+=("unparseable schedule run timestamp: $last_sched")
    fi
  elif [ "$state" = "active" ] || [ "$state" = "(unreadable)" ]; then
    reasons+=("no schedule-event run on record")
  fi

  leading="${seq%%S*}"
  streak="${#leading}"
  if [ "$streak" -ge "$STREAK_LIMIT" ]; then
    reasons+=("$streak consecutive failed runs (limit $STREAK_LIMIT)")
  fi

  if [ "${#reasons[@]}" -eq 0 ]; then
    status="OK"
  else
    status="UNHEALTHY"
    unhealthy=$((unhealthy + 1))
    joined=""
    for r in "${reasons[@]}"; do joined="$joined; $r"; done
    detail_lines="$detail_lines
- **$repo** — ${joined#; }"
  fi

  table_rows="$table_rows
| $repo | $status | $state | ${last_sched:-none} (${last_sched_conclusion:--}) | $age_display | ${seq:-none} | $streak |"
done 3< "$REPOS_FILE"

[ "$total" -gt 0 ] || { echo "repos file lists no repositories" >&2; exit 65; }

report="## Fleet health — $(date -ud "@$NOW_EPOCH" '+%Y-%m-%d %H:%M UTC')

Watching \`$WORKFLOW_FILE\` in $total repos under \`$ORG\`. Limits: schedule
gap > ${MAX_AGE_HOURS}h, failure streak >= ${STREAK_LIMIT}. Recent runs are
newest-first (S success, F failure).

| Repo | Status | Workflow state | Last schedule run | Age | Recent runs | Streak |
|---|---|---|---|---|---|---|$table_rows
"
if [ "$unhealthy" -gt 0 ]; then
  report="$report
### $unhealthy of $total repos unhealthy
$detail_lines

A quiet repo is not a flagged repo: runs that commit nothing count as
healthy. Every line above is a schedule that is off, silent past the
limit, or failing repeatedly."
else
  report="$report
All $total repos healthy."
fi

printf '%s\n' "$report"
[ -n "$REPORT_FILE" ] && printf '%s\n' "$report" > "$REPORT_FILE"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$report" >> "$GITHUB_STEP_SUMMARY"

[ "$unhealthy" -eq 0 ]
