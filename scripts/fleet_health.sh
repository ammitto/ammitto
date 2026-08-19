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
#   FAILING FLEET_HEALTH_STREAK (default 3) or more hard failures since
#           the last success — see "The streak model" below.
#   UNREADABLE any of the three API documents missing, empty, or not
#           shaped like the API contract. Deliberately unhealthy: a repo
#           we cannot read is not a repo we can call healthy.
#
# A run that commits nothing is HEALTHY: only run conclusions are read,
# never commit deltas, so zero-delta days (data-au has them legitimately)
# are never flagged.
#
# Scheduled runs only
# -------------------
# Every run query filters event=schedule. The monitor watches the cron,
# not the repo: a failing PR or a broken push run says nothing about
# whether the daily fetch still works, and letting those into the streak
# both raises false alarms (red PR run pages the fleet) and hides real
# ones (a green push run would reset a streak of dead cron runs).
#
# The streak model
# ----------------
# Conclusions are read newest-first and mapped to one letter each:
#   S  success
#   F  hard failure — failure, timed_out, startup_failure
#   C  inconclusive — cancelled, skipped, neutral, action_required,
#      stale, or a null/unknown conclusion
# The window under judgement is everything before the most recent S (the
# whole sequence when there is no S at all). Within that window:
#   * FLEET_HEALTH_STREAK or more F  -> failing.
#   * FLEET_HEALTH_STREAK or more C  -> flagged too. Inconclusive runs
#     used to be dropped outright, which let a repo whose cron fires
#     daily and is cancelled every time look perfectly healthy: recent
#     run, no failures, no page. A schedule that never finishes is not a
#     working schedule, so repeated cancellations are surfaced, not
#     swallowed.
#   * Neither count reaching the limit but no S anywhere in the window
#     and at least FLEET_HEALTH_STREAK runs in it -> flagged as well.
#     This is the mixed-outcome catch-all (2 failures + 2 cancellations
#     is four scheduled runs since the last success, and no single
#     counter would notice).
#
# Acknowledgements
# ----------------
# A line in the repos file may carry an acknowledgement:
#
#   data-ru ack:parked for maintainer ruling on ru revival:2026-09-07
#
# meaning "this one is known-broken, do not page me about it until
# 2026-09-07". Acknowledged repos report ACKNOWLEDGED, are excluded from
# the unhealthy count and never reach the tracking issue. The date is a
# deadline, not a mute button: from the day AFTER review-by the repo
# reports EXPIRED-ACK and pages like any other failure — including when
# it has since recovered, because an expired acknowledgement is an
# unmade decision and the point of the date is to force the ruling. A
# malformed acknowledgement pages immediately rather than suppressing
# anything, so a typo in the date can never mute a repo forever.
#
# Usage: scripts/fleet_health.sh [--report FILE]
#   Prints a Markdown report (also appended to GITHUB_STEP_SUMMARY when
#   set, and written to FILE with --report). The report ends with an
#   HTML-comment state marker that fleet_health_issue.sh diffs to decide
#   whether anything actually changed.
#   Exit 0: nothing paging. Exit 1: at least one repo pages.
#   Exit 69: every repo was unreadable — the monitor's own view is down
#   (auth, rate limit, network), which is an outage to fix, not fifteen
#   dead repositories to page about.
#   Any other exit code is a bug in this script, not a health verdict.
#
# Environment:
#   FLEET_HEALTH_ORG            owner org (default ammitto)
#   FLEET_HEALTH_WORKFLOW       workflow file name (default fetch.yml)
#   FLEET_HEALTH_MAX_AGE_HOURS  staleness limit (default 48)
#   FLEET_HEALTH_STREAK         failure/inconclusive limit (default 3);
#                               1-100, and the streak query asks for
#                               enough runs to reach whatever is set
#   FLEET_HEALTH_REPOS_FILE     repo list (default scripts/fleet_repos.txt)
#   FLEET_HEALTH_FIXTURES       dir of fixture JSON; no network at all
#   FLEET_HEALTH_NOW_EPOCH      freeze "now" for tests
#   GH_TOKEN / GITHUB_TOKEN     optional; raises the API rate limit from
#                               60/h to 1000/h, on the gh path and the
#                               curl path alike. The fleet is public, so
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

# A threshold the streak query cannot reach would report every repo
# healthy forever — the silent "OK" this monitor exists to kill. It is
# refused at startup rather than discovered in a quiet report. 100 is the
# API's per_page ceiling, so a larger threshold cannot be judged from the
# single page the streak query fetches.
#
# The value is re-emitted in base 10 because bash reads a leading zero as
# octal in $((…)) but not in [ … -lt … ]: FLEET_HEALTH_STREAK=012 would
# size the query as 10 while every comparison read it as 12, restoring the
# short page this check exists to prevent. 008 and 09 are not octal at all
# and abort the script mid-run.
# Called directly, never in $(…): a subshell's exit would only end the
# subshell and let the script run on with an unvalidated threshold.
check_whole_number() {
  # name value min max
  local digits
  case "$2" in
    ''|*[!0-9]*)
      echo "$1 must be a whole number: $2" >&2
      exit 64 ;;
  esac
  # Bash arithmetic wraps at 64 bits, so 18446744073709551617 evaluates to
  # 1 and would pass the range check below as a valid threshold. Measure
  # the digit count instead — with the leading zeros stripped first, so
  # 0000012 counts as two digits and not seven — and refuse anything
  # longer than the ceiling before it is ever evaluated.
  digits=${2#"${2%%[!0]*}"}
  [ -n "$digits" ] || digits=0
  if [ "${#digits}" -gt "${#4}" ]; then
    echo "$1 must be between $3 and $4: $2" >&2
    exit 64
  fi
  if [ "$digits" -lt "$3" ] || [ "$digits" -gt "$4" ]; then
    echo "$1 must be between $3 and $4: $2" >&2
    exit 64
  fi
}

# The staleness limit is checked too — not for the octal split (it is only
# ever compared, never used in arithmetic) but because a non-numeric value
# aborts the run mid-report instead of at startup. A ceiling of one year
# keeps it from silently meaning "never stale".
check_whole_number FLEET_HEALTH_STREAK "$STREAK_LIMIT" 1 100
check_whole_number FLEET_HEALTH_MAX_AGE_HOURS "$MAX_AGE_HOURS" 1 8760
STREAK_LIMIT=$((10#$STREAK_LIMIT))
MAX_AGE_HOURS=$((10#$MAX_AGE_HOURS))

# The streak window is every run before the most recent success, so a
# page shorter than the threshold can never show a streak that long. Ask
# for one more than the threshold — the extra run is the success that
# closes the window — and never fewer than the 10 this has always used.
COMPLETED_PER_PAGE=$((STREAK_LIMIT + 1))
if [ "$COMPLETED_PER_PAGE" -lt 10 ]; then COMPLETED_PER_PAGE=10; fi
# Recency is judged over a page rather than a single item, so one stale
# entry cannot decide it. Five is enough: the newest of five is right
# unless the endpoint is stale about all five, and a page this small
# costs the same one request the one-item page did.
SCHEDULE_PER_PAGE=5
if [ "$COMPLETED_PER_PAGE" -gt 100 ]; then COMPLETED_PER_PAGE=100; fi

# Fetch one API document. kind: workflow | schedule_runs | completed_runs.
# Prints the JSON body, or nothing on any failure — the caller validates
# the body and treats anything unexpected as UNREADABLE rather than
# crashing, so one repo's outage cannot hide the other fourteen.
api_get() {
  local kind="$1" repo="$2" path base token
  local -a auth
  if [ -n "$FIXTURES" ]; then
    cat "$FIXTURES/${repo}__${kind}.json" 2>/dev/null || true
    return 0
  fi
  base="repos/$ORG/$repo/actions/workflows/$WORKFLOW_FILE"
  case "$kind" in
    workflow)
      path="$base" ;;
    # Recency: newest scheduled run of any status, so a run still in
    # progress still counts as the cron having fired.
    #
    # Several are fetched and the newest is chosen by created_at rather
    # than taking position zero of a one-item page. This endpoint has
    # been observed serving a stale page: on 2026-08-18 it reported
    # data-uk's last scheduled run as 2026-07-22 while that repository
    # had in fact run and committed every morning, and the monitor paged
    # on a healthy repo for it. The same query was seen returning three
    # different answers inside two minutes on 2026-08-19. A false page
    # trains everyone to ignore the channel, and the identical mechanism
    # can hand back a recent run for a repository whose cron has died,
    # which is the failure this monitor exists to prevent.
    schedule_runs)
      path="$base/runs?event=schedule&per_page=$SCHEDULE_PER_PAGE" ;;
    # Streak: scheduled runs only. A red PR run must never page the
    # fleet, and a green push run must never clear a real streak.
    completed_runs)
      path="$base/runs?event=schedule&status=completed&per_page=$COMPLETED_PER_PAGE" ;;
    *)
      return 1 ;;
  esac
  # `gh auth token` only exists from gh 2.6; probing with it alone made
  # gh 2.4 look logged-out and silently dropped the whole run onto the
  # anonymous curl path, whose 60/hour budget one 45-call pass nearly
  # exhausts. The second pass then returned nothing for every repo and
  # the monitor reported fifteen dead repositories. `gh auth status` has
  # been there far longer, so try both.
  if command -v gh >/dev/null 2>&1 &&
     { [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ] ||
       gh auth token >/dev/null 2>&1 ||
       gh auth status >/dev/null 2>&1; }; then
    gh api "$path" 2>/dev/null || true
  else
    # Without gh, the token has to be presented by hand or it buys
    # nothing and the pass runs on the anonymous 60/hour budget that one
    # 45-call sweep nearly exhausts — which the environment notes above
    # promise it does not. Built as an argument array so the token is
    # never interpolated into a logged string, and left empty when no
    # token is set so an anonymous read stays anonymous.
    auth=()
    token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [ -n "$token" ]; then
      auth=(-H "Authorization: Bearer $token")
    fi
    curl -sS --max-time 30 -H 'Accept: application/vnd.github+json' \
      ${auth[@]+"${auth[@]}"} \
      "https://api.github.com/$path" 2>/dev/null || true
  fi
}

# Every document is validated on its own. Before this existed only the
# workflow document was checked, so a 404 or a truncated body on the
# runs endpoints produced an empty sequence, a zero streak and a
# confident "OK" — the monitor's own version of the silence it exists to
# detect.
#
# An empty body must be rejected before jq sees it: `jq -e` exits 0 on
# empty input (verified with jq 1.6), so an unchecked empty response
# would validate.
doc_valid() { # kind json
  local kind="$1" json="$2"
  [ -n "${json//[[:space:]]/}" ] || return 1
  case "$kind" in
    workflow)
      jq -e 'type == "object" and (.state | type == "string")
             and (.state | length > 0)' >/dev/null 2>&1 <<<"$json" ;;
    schedule_runs)
      # Members must be objects with a usable created_at: a runs array
      # holding null or a scalar would otherwise validate and read as
      # "no scheduled run" -- which is the silent-death signal itself.
      jq -e 'type == "object" and (.workflow_runs | type == "array")
             and (.workflow_runs | all(type == "object"
                   and (.created_at | type == "string")
                   and (.created_at | length > 0)
                   and ((.conclusion == null) or (.conclusion | type == "string"))))' \
        >/dev/null 2>&1 <<<"$json" ;;
    *)
      # created_at is required here too, because the streak is ordered by
      # it rather than by the position the API returned.
      jq -e 'type == "object" and (.workflow_runs | type == "array")
             and (.workflow_runs | all(type == "object"
                   and (.created_at | type == "string")
                   and (.created_at | length > 0)
                   and ((.conclusion == null) or (.conclusion | type == "string"))))' \
        >/dev/null 2>&1 <<<"$json" ;;
  esac
}

table_rows=""
detail_lines=""
state_pairs=""
paging=0
acknowledged=0
unreadable_total=0
total=0

# The loop reads the repos file on FD 3 so gh/curl inside the loop can
# never swallow the remaining lines from stdin.
while IFS= read -r line <&3; do
  line="${line%%#*}"
  # First field is the repo, the rest (if any) is the acknowledgement.
  read -r repo ack_spec <<<"$line" || true
  repo="${repo:-}"
  ack_spec="${ack_spec:-}"
  [ -n "$repo" ] || continue
  total=$((total + 1))

  # --- acknowledgement --------------------------------------------------
  # "ack:<reason>:<review-by YYYY-MM-DD>". The reason may itself contain
  # colons, so the date is taken from the last colon and the reason is
  # everything before it.
  ack_reason=""
  ack_until=""
  ack_bad=""
  ack_epoch=0
  if [ -n "$ack_spec" ]; then
    case "$ack_spec" in
      ack:*)
        ack_body="${ack_spec#ack:}"
        ack_until="${ack_body##*:}"
        ack_reason="${ack_body%:*}"
        if [ -z "$ack_reason" ] || [ "$ack_reason" = "$ack_until" ]; then
          ack_bad="acknowledgement needs 'ack:<reason>:<YYYY-MM-DD>'"
        elif ! [[ "$ack_until" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
          ack_bad="acknowledgement review-by '$ack_until' is not YYYY-MM-DD"
        elif ! ack_epoch="$(date -ud "$ack_until" +%s 2>/dev/null)"; then
          ack_bad="acknowledgement review-by '$ack_until' is not a real date"
        fi
        ;;
      *)
        ack_bad="unknown entry '$ack_spec' (expected 'ack:<reason>:<YYYY-MM-DD>')"
        ;;
    esac
  fi

  # --- read and validate the three documents ---------------------------
  workflow_json="$(api_get workflow "$repo")"
  schedule_json="$(api_get schedule_runs "$repo")"
  completed_json="$(api_get completed_runs "$repo")"

  reasons=()
  unreadable=0
  doc_valid workflow "$workflow_json" || {
    reasons+=("workflow document unreadable — $WORKFLOW_FILE missing, or the API returned no usable body")
    unreadable=1
  }
  doc_valid schedule_runs "$schedule_json" || {
    reasons+=("schedule-runs document unreadable — no usable workflow_runs array")
    unreadable=1
  }
  doc_valid completed_runs "$completed_json" || {
    reasons+=("completed-runs document unreadable — no usable workflow_runs array, so the failure streak is unknown")
    unreadable=1
  }

  state="(unreadable)"
  last_sched=""
  last_sched_conclusion=""
  age_display="-"
  seq=""
  hard=0
  inconc=0

  if [ "$unreadable" -eq 0 ]; then
    state="$(jq -r '.state' <<<"$workflow_json")"
    newest_sched="$(jq -c '[.workflow_runs[]?
          | select(.created_at != null)]
          | sort_by(.created_at) | last // {}' <<<"$schedule_json")"
    last_sched="$(jq -r '.created_at // empty' <<<"$newest_sched")"
    last_sched_conclusion="$(jq -r '.conclusion // empty' \
      <<<"$newest_sched")"
    # Newest first, by created_at rather than by the order the API
    # returned. `window` below takes everything before the first S as
    # "since the last success", so a stale success ahead of newer
    # failures clears a real streak, and stale failures ahead of a newer
    # success invent one. Same reason the recency read was changed: this
    # endpoint promises filters and paging, not an order.
    seq="$(jq -r '[.workflow_runs[]? | {created_at, conclusion}]
          | sort_by(.created_at) | reverse
          | map(if .conclusion == "success" then "S"
                elif .conclusion == "failure" or .conclusion == "timed_out"
                     or .conclusion == "startup_failure" then "F"
                else "C" end)
          | join("")' <<<"$completed_json")"

    if [ "$state" != "active" ]; then
      reasons+=("workflow state is '$state' — the schedule is not running")
    fi

    if [ -n "$last_sched" ]; then
      if run_epoch="$(date -ud "$last_sched" +%s 2>/dev/null)" &&
         [ "$run_epoch" -gt 0 ]; then
        age_hours=$(( (NOW_EPOCH - run_epoch) / 3600 ))
        age_display="${age_hours}h"
        if [ "$age_hours" -gt "$MAX_AGE_HOURS" ]; then
          reasons+=("last schedule run was ${age_hours}h ago (limit ${MAX_AGE_HOURS}h)")
        fi
      else
        reasons+=("unparseable schedule run timestamp: $last_sched")
        unreadable=1
      fi
    else
      reasons+=("no schedule-event run on record")
    fi

    # Window = everything newer than the most recent success.
    window="${seq%%S*}"
    only_f="${window//[^F]/}"
    only_c="${window//[^C]/}"
    hard="${#only_f}"
    inconc="${#only_c}"
    if [ "$hard" -ge "$STREAK_LIMIT" ]; then
      reasons+=("$hard hard failures since the last success (limit $STREAK_LIMIT)")
    fi
    if [ "$inconc" -ge "$STREAK_LIMIT" ]; then
      reasons+=("$inconc inconclusive scheduled runs (cancelled/skipped) since the last success (limit $STREAK_LIMIT) — the cron fires but never finishes, so recency alone looks healthy")
    elif [ "$hard" -lt "$STREAK_LIMIT" ] &&
         [ "${#window}" -ge "$STREAK_LIMIT" ]; then
      reasons+=("no successful scheduled run in the last ${#window} completed runs ($hard failed, $inconc inconclusive)")
    fi
  fi

  # --- verdict ----------------------------------------------------------
  if [ -n "$ack_bad" ]; then
    reasons+=("$ack_bad — refusing to suppress anything until it is fixed")
    status="UNHEALTHY"
  elif [ -n "$ack_reason" ] && [ "$NOW_EPOCH" -ge "$((ack_epoch + 86400))" ]; then
    status="EXPIRED-ACK"
    reasons+=("acknowledgement expired (review-by $ack_until): $ack_reason")
    if [ "${#reasons[@]}" -eq 1 ]; then
      reasons+=("no outstanding health problem — either renew the acknowledgement or drop it from the repos file")
    fi
  elif [ -n "$ack_reason" ]; then
    status="ACKNOWLEDGED"
    reasons+=("acknowledged until $ack_until: $ack_reason")
  elif [ "$unreadable" -eq 1 ]; then
    status="UNREADABLE"
  elif [ "${#reasons[@]}" -eq 0 ]; then
    status="OK"
  else
    status="UNHEALTHY"
  fi

  # Counted from the raw documents, not the verdict: an acknowledged
  # repo is still one the API could not answer for.
  if [ "$unreadable" -eq 1 ]; then
    unreadable_total=$((unreadable_total + 1))
  fi

  case "$status" in
    OK) ;;
    ACKNOWLEDGED)
      acknowledged=$((acknowledged + 1)) ;;
    *)
      paging=$((paging + 1)) ;;
  esac

  if [ "$status" != "OK" ]; then
    joined=""
    for r in "${reasons[@]}"; do joined="$joined; $r"; done
    detail_lines="$detail_lines
- **$repo** ($status) — ${joined#; }"
  fi
  # Only paging statuses enter the signature. An acknowledged repo stays
  # visible in the report but must not move the signature, or the very
  # act of acknowledging it would open a tracking issue about it.
  if [ "$status" != "OK" ] && [ "$status" != "ACKNOWLEDGED" ]; then
    state_pairs="$state_pairs$repo=$status
"
  fi

  table_rows="$table_rows
| $repo | $status | $state | ${last_sched:-none} (${last_sched_conclusion:--}) | $age_display | ${seq:-none} | ${hard}F/${inconc}C |"
done 3< "$REPOS_FILE"

[ "$total" -gt 0 ] || { echo "repos file lists no repositories" >&2; exit 65; }

# Order-independent one-line signature of everything that is not OK.
# fleet_health_issue.sh compares it against the signature stored in the
# tracking issue so the fleet is announced when it CHANGES, not once per
# scheduled run.
if [ -n "$state_pairs" ]; then
  state_marker="$(printf '%s' "$state_pairs" | sort | tr '\n' ' ')"
  state_marker="${state_marker% }"
else
  state_marker="healthy"
fi

report="## Fleet health — $(date -ud "@$NOW_EPOCH" '+%Y-%m-%d %H:%M UTC')

Watching \`$WORKFLOW_FILE\` in $total repos under \`$ORG\`, scheduled runs
only. Limits: schedule gap > ${MAX_AGE_HOURS}h, ${STREAK_LIMIT}+ hard
failures or inconclusive runs since the last success. Recent runs are
newest-first (S success, F hard failure, C inconclusive); the last column
counts both within the window since that success.

| Repo | Status | Workflow state | Last schedule run | Age | Recent scheduled runs | Since success |
|---|---|---|---|---|---|---|$table_rows
"
if [ -n "$detail_lines" ]; then
  # "0" is a non-empty string, so ${acknowledged:+...} would print
  # ", 0 acknowledged" — spell the conditional out instead.
  ack_note=""
  if [ "$acknowledged" -gt 0 ]; then
    ack_note=", $acknowledged acknowledged and deliberately silent"
  fi
  report="$report
### $paging of $total repos paging$ack_note
$detail_lines

A quiet repo is not a flagged repo: runs that commit nothing count as
healthy. ACKNOWLEDGED lines are known-broken and deliberately silent
until their review-by date; every other line is a schedule that is off,
silent past the limit, failing, or unreadable."
else
  report="$report
All $total repos healthy."
fi
report="$report

<!-- fleet-health-state: $state_marker -->"

printf '%s\n' "$report"
if [ -n "$REPORT_FILE" ]; then
  printf '%s\n' "$report" > "$REPORT_FILE"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "$report" >> "$GITHUB_STEP_SUMMARY"
fi

# Every single repo unreadable is an outage of the monitor's own view,
# not fifteen simultaneous deaths. Observed for real: an auth probe that
# misfired sent a whole pass down the anonymous curl path, the 60/hour
# budget ran out and the fleet "died" in one step. Exiting outside the
# 0/1 health range makes the workflow fail as a monitor outage and skip
# the tracking issue entirely, so a blackout cannot manufacture fifteen
# pages and a bogus incident.
if [ "$total" -gt 1 ] && [ "$unreadable_total" -eq "$total" ]; then
  echo "monitor outage: all $total repos unreadable — treating as an API/auth" \
       "failure, not a health verdict" >&2
  exit 69
fi

[ "$paging" -eq 0 ]
