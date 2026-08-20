#!/usr/bin/env bash
# Offline proof of the fleet-health monitor. No network, no writes.
#
# Generates synthetic API fixtures for the failure modes the monitor
# exists to catch, runs the real detection script against them, and
# asserts the verdicts. Also drives the real query builder through a
# stubbed gh (to prove only scheduled runs are counted) and the real
# issue script through a stubbed gh (to prove it writes on state changes
# and stays silent otherwise). The fleet-health workflow runs this before
# every live check: a monitor whose own parser silently broke would
# otherwise report "healthy" forever — the exact failure mode this whole
# feature exists to kill.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/fixtures"
mkdir -p "$FIX" "$TMP/bin"

failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

iso() { date -ud "$1" '+%Y-%m-%dT%H:%M:%SZ'; }

workflow_fixture() { # repo state
  printf '{"path":".github/workflows/fetch.yml","state":"%s"}' "$2" \
    > "$FIX/$1__workflow.json"
}
schedule_fixture() { # repo age conclusion
  printf '{"workflow_runs":[{"created_at":"%s","conclusion":"%s"}]}' \
    "$(iso "$2")" "$3" > "$FIX/$1__schedule_runs.json"
}
completed_fixture() { # repo conclusion... (newest first, as the caller reads)
  local repo="$1" runs="" c i=0
  shift
  # Timestamps descend with position, so a fixture written newest-first
  # still reads newest-first once the script orders by created_at. The
  # real endpoint always carries created_at; a fixture without one would
  # be testing a document the API does not produce.
  for c in "$@"; do
    runs="$runs{\"created_at\":\"$(iso "$((i + 1)) hours ago")\",\"conclusion\":\"$c\"},"
    i=$((i + 1))
  done
  printf '{"workflow_runs":[%s]}' "${runs%,}" \
    > "$FIX/${repo}__completed_runs.json"
}
healthy_fixture() { # repo — alive, recent, three clean runs
  workflow_fixture "$1" active
  schedule_fixture "$1" '5 hours ago' success
  completed_fixture "$1" success success success
}
# The acknowledgement tests freeze the clock weeks away from real "now",
# where a fixture written as "5 hours ago" would read as badly stale.
# These anchor the last run five hours before the frozen instant instead.
healthy_fixture_at() { # repo frozen-now-epoch
  workflow_fixture "$1" active
  printf '{"workflow_runs":[{"created_at":"%s","conclusion":"success"}]}' \
    "$(date -ud "@$(( $2 - 18000 ))" '+%Y-%m-%dT%H:%M:%SZ')" \
    > "$FIX/$1__schedule_runs.json"
  completed_fixture "$1" success success success
}

# Frozen instants for the acknowledgement tests, against a review-by of
# 2026-09-07. Verified with `date -ud <stamp> +%s`.
NOW_BEFORE=1786536000   # 2026-08-12 12:00 UTC — well before review-by
NOW_ONDAY=1788782400    # 2026-09-07 12:00 UTC — the review-by day itself
NOW_AFTER=1788868800    # 2026-09-08 12:00 UTC — the day after

# Case 1 — dead schedule: GitHub deactivated it 60 days after the last
# repo activity; the state field says so and the last run is ancient.
# This is the death the six repos died.
workflow_fixture data-dead disabled_inactively
schedule_fixture data-dead '70 days ago' success
completed_fixture data-dead success success success

# Case 1b — dead but lying state: workflow reads "active" yet the cron
# has not produced a run in 3 days (cron typo, renamed file, actor
# suspended). The recency check must catch what the state check misses.
workflow_fixture data-stale active
schedule_fixture data-stale '72 hours ago' success
completed_fixture data-stale success success success

# Case 2 — failure streak: schedule alive and recent, but three hard
# failures since the last success. A cancelled run in between must not
# reset the count.
workflow_fixture data-failing active
schedule_fixture data-failing '5 hours ago' failure
completed_fixture data-failing failure failure cancelled failure success success

# Case 3 — healthy but quiet: ran on schedule this morning, succeeded,
# committed nothing (invisible to run conclusions, which is the point).
# Must NOT be flagged. data-au has legitimate zero-delta days.
workflow_fixture data-quiet active
schedule_fixture data-quiet '6 hours ago' success
completed_fixture data-quiet success success success

# Boundary — two hard failures is below the limit and the schedule is
# alive: not flagged.
workflow_fixture data-two-fails active
schedule_fixture data-two-fails '4 hours ago' failure
completed_fixture data-two-fails failure failure success success

# Case 4 — cancelled forever: the cron fires daily and every run is
# cancelled. Recency looks perfect and there is not one failure, so the
# old "drop everything that is not success/failure" model called this
# healthy. A schedule that never finishes is not a working schedule.
workflow_fixture data-cancelled active
schedule_fixture data-cancelled '3 hours ago' cancelled
completed_fixture data-cancelled cancelled cancelled cancelled success

# Case 4b — mixed outcomes: two failures and two cancellations since the
# last success. Neither counter alone reaches the limit of 3, but four
# scheduled runs have gone by without a success.
workflow_fixture data-mixed active
schedule_fixture data-mixed '3 hours ago' failure
completed_fixture data-mixed failure cancelled failure cancelled success

# Unreadable — no fixtures at all for data-ghost: missing workflow or
# dead API must flag, not pass silently.

# Case 5 — each API document must validate on its own. Every repo below
# is perfectly healthy except for ONE unusable document. Before the
# monitor validated all three, an unreadable runs document produced an
# empty sequence, a zero streak and a confident "OK".
healthy_fixture data-badwf
printf '{"message":"Not Found","documentation_url":"https://docs.github.com"}' \
  > "$FIX/data-badwf__workflow.json"

healthy_fixture data-badsched
printf '{"message":"Server Error"}' > "$FIX/data-badsched__schedule_runs.json"

healthy_fixture data-badcompleted
printf '{"message":"Not Found","documentation_url":"https://docs.github.com"}' \
  > "$FIX/data-badcompleted__completed_runs.json"

healthy_fixture data-truncated
printf '{"workflow_runs":[{"conclu' > "$FIX/data-truncated__completed_runs.json"

# A runs array whose MEMBERS are unusable: validating only the array type
# let {"workflow_runs":[null]} read as "no scheduled run" -- indistinguishable
# from the silent death this monitor exists to catch.
healthy_fixture data-nullmember
printf '{"workflow_runs":[null]}' > "$FIX/data-nullmember__schedule_runs.json"

healthy_fixture data-scalarmember
printf '{"workflow_runs":["oops"]}' > "$FIX/data-scalarmember__completed_runs.json"

healthy_fixture data-blankdate
printf '{"workflow_runs":[{"created_at":"","conclusion":"success"}]}' \
  > "$FIX/data-blankdate__schedule_runs.json"

# An empty body is the trap that looks safest: `jq -e` exits 0 on empty
# input, so an unguarded validator would wave this through as healthy.
healthy_fixture data-empty
: > "$FIX/data-empty__completed_runs.json"

repos_all="$TMP/repos_all.txt"
printf '%s\n' data-dead data-stale data-failing data-quiet data-two-fails \
  data-cancelled data-mixed data-ghost data-badwf data-badsched \
  data-badcompleted data-truncated data-empty \
  data-nullmember data-scalarmember data-blankdate > "$repos_all"
repos_healthy="$TMP/repos_healthy.txt"
printf '%s\n' data-quiet data-two-fails > "$repos_healthy"

run_health() { # repos-file report-file [env assignments...]
  local repos="$1" report="$2"
  shift 2
  local rc=0
  env "$@" FLEET_HEALTH_FIXTURES="$FIX" FLEET_HEALTH_REPOS_FILE="$repos" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$report" > /dev/null || rc=$?
  echo "$rc"
}

echo "== detection: mixed fleet must exit 1 with exact verdicts =="
rc=$(run_health "$repos_all" "$TMP/report.md")
[ "$rc" -eq 1 ] && pass "mixed fleet exits 1" || fail "mixed fleet exit was $rc"

expect_status() { # repo status [report]
  local report="${3:-$TMP/report.md}"
  if grep -E "^\| $1 \| $2 " "$report" > /dev/null; then
    pass "$1 is $2"
  else
    fail "$1 is not $2: $(grep -E "^\| $1 \|" "$report" || echo 'no row')"
  fi
}
expect_reason() { # repo substring [report]
  if grep -F "**$1**" "${3:-$TMP/report.md}" | grep -qF "$2"; then
    pass "$1 reason mentions: $2"
  else
    fail "$1 reason missing: $2"
  fi
}

expect_status data-dead UNHEALTHY
expect_reason data-dead "disabled_inactively"
expect_status data-stale UNHEALTHY
expect_reason data-stale "72h ago (limit 48h)"
expect_status data-failing UNHEALTHY
expect_reason data-failing "3 hard failures since the last success"
expect_status data-quiet OK
expect_status data-two-fails OK
expect_status data-ghost UNREADABLE

echo "== detection: repeated cancellations must not read as healthy =="
expect_status data-cancelled UNHEALTHY
expect_reason data-cancelled "3 inconclusive scheduled runs"
expect_status data-mixed UNHEALTHY
expect_reason data-mixed "no successful scheduled run in the last 4 completed runs"

echo "== detection: every API document validates independently =="
expect_status data-badwf UNREADABLE
expect_reason data-badwf "workflow document unreadable"
expect_status data-badsched UNREADABLE
expect_reason data-badsched "schedule-runs document unreadable"
expect_status data-badcompleted UNREADABLE
expect_reason data-badcompleted "completed-runs document unreadable"
expect_status data-nullmember UNREADABLE
expect_reason data-nullmember "schedule-runs document unreadable"
expect_status data-scalarmember UNREADABLE
expect_reason data-scalarmember "completed-runs document unreadable"
expect_status data-blankdate UNREADABLE
expect_reason data-blankdate "schedule-runs document unreadable"
expect_status data-truncated UNREADABLE
expect_status data-empty UNREADABLE
for r in data-badwf data-badsched data-badcompleted data-truncated data-empty; do
  if grep -E "^\| $r \| OK " "$TMP/report.md" > /dev/null; then
    fail "$r reported OK with an unusable document"
  fi
done
pass "no repo with an unusable document reported OK"

echo "== detection: a total blackout is an outage, not fifteen deaths =="
# Observed live: a misfiring auth probe pushed a whole pass onto the
# anonymous API, the hourly budget ran out and every repo came back
# empty. Paging the entire fleet (and opening an incident) for one auth
# failure is worse than useless, so a full blackout leaves the 0/1
# health range and the workflow fails it as a monitor outage.
repos_blackout="$TMP/repos_blackout.txt"
printf '%s\n' data-ghost data-ghost2 data-ghost3 > "$repos_blackout"
rc=$(run_health "$repos_blackout" "$TMP/report_blackout.md")
[ "$rc" -eq 69 ] && pass "total blackout exits 69, outside the health range" \
  || fail "total blackout exit was $rc"
# One unreadable repo among readable ones is still an ordinary page.
repos_one_bad="$TMP/repos_one_bad.txt"
printf '%s\n' data-quiet data-ghost > "$repos_one_bad"
rc=$(run_health "$repos_one_bad" "$TMP/report_one_bad.md")
[ "$rc" -eq 1 ] && pass "a single unreadable repo still pages normally" \
  || fail "single unreadable exit was $rc"

echo "== detection: all-healthy fleet must exit 0 =="
rc=$(run_health "$repos_healthy" "$TMP/report_ok.md")
[ "$rc" -eq 0 ] && pass "healthy fleet exits 0" || fail "healthy exit was $rc"
grep -q 'All 2 repos healthy' "$TMP/report_ok.md" \
  && pass "healthy summary present" || fail "healthy summary missing"
grep -q '<!-- fleet-health-state: healthy -->' "$TMP/report_ok.md" \
  && pass "healthy state marker present" || fail "healthy state marker missing"

echo "== no-schedule: a designation, and one that can be wrong =="
# data-noschedule has an active workflow and no schedule-event runs at
# all, which is exactly what a repo with no cron looks like. Without the
# designation that is UNHEALTHY ("no schedule-event run on record"); with
# it, it is BY-DESIGN and silent.
workflow_fixture data-noschedule active
printf '{"workflow_runs":[]}' > "$FIX/data-noschedule__schedule_runs.json"
printf '{"workflow_runs":[]}' > "$FIX/data-noschedule__completed_runs.json"

repos_nosched="$TMP/repos_nosched.txt"
printf 'data-noschedule no-schedule:curated by its own scripts\n' > "$repos_nosched"
rc=$(run_health "$repos_nosched" "$TMP/report_nosched.md")
[ "$rc" -eq 0 ] && pass "a declared scheduleless repo exits 0" \
  || fail "no-schedule exit was $rc"
expect_status data-noschedule BY-DESIGN "$TMP/report_nosched.md"
expect_reason data-noschedule "no schedule expected" "$TMP/report_nosched.md"
grep -q '<!-- fleet-health-state: healthy -->' "$TMP/report_nosched.md" \
  && pass "BY-DESIGN stays out of the state signature" \
  || fail "BY-DESIGN leaked into the state signature"

# The half that makes it a designation rather than a mute button: an
# ACTIVE workflow that has produced scheduled runs means either the cron
# still fires or it is the dead schedule this monitor exists to catch.
# Either way the declaration is wrong and must page.
healthy_fixture data-noschedule
rc=$(run_health "$repos_nosched" "$TMP/report_nosched_stale.md")
[ "$rc" -eq 1 ] && pass "an active cron under no-schedule pages" \
  || fail "stale no-schedule designation exited $rc"
expect_reason data-noschedule "the workflow is active and has schedule-event runs" \
  "$TMP/report_nosched_stale.md"

# Run history OUTLIVES the workflow that produced it, and testing for
# its existence rather than for a live workflow is what paged on data-jp
# an hour after its cron was deliberately removed. A deleted workflow
# with weeks of history behind it is the designation working, not a
# stale declaration — and it must clear immediately, not wait for the
# history to age out of the API page.
workflow_fixture data-noschedule deleted
schedule_fixture data-noschedule '3 hours ago' success
completed_fixture data-noschedule success success success
rc=$(run_health "$repos_nosched" "$TMP/report_nosched_deleted.md")
[ "$rc" -eq 0 ] && pass "a deleted workflow with run history stays BY-DESIGN" \
  || fail "deleted workflow under no-schedule exited $rc"
expect_status data-noschedule BY-DESIGN "$TMP/report_nosched_deleted.md"

# And the deleted state must not itself be reported as a fault: for a
# declared-scheduleless repo it is the expected condition.
grep -q "workflow state is 'deleted'" "$TMP/report_nosched_deleted.md" \
  && fail "a deleted workflow was reported as a fault under no-schedule" \
  || pass "deleted state is not a fault under no-schedule"

# But `deleted` is the ONLY state it excuses. The disabled_* family means
# the workflow still exists WITH its schedule and is not running — the
# death this monitor was built for. A designation that swallowed those
# would hide the one thing it must never hide.
for dead_state in disabled_manually disabled_inactivity disabled_fork; do
  workflow_fixture data-noschedule "$dead_state"
  printf '{"workflow_runs":[]}' > "$FIX/data-noschedule__schedule_runs.json"
  printf '{"workflow_runs":[]}' > "$FIX/data-noschedule__completed_runs.json"
  rc=$(run_health "$repos_nosched" "$TMP/report_nosched_$dead_state.md")
  [ "$rc" -eq 1 ] \
    && pass "no-schedule does not excuse $dead_state" \
    || fail "$dead_state under no-schedule exited $rc"
done
# Put the fixture back: the cases below reuse this repo and expect an
# active workflow. Leaving it disabled_fork made them fail for a reason
# that had nothing to do with what they test.
workflow_fixture data-noschedule active

# Codex's gap: every fixture above has an empty completed_runs, so the
# streak bypass was never exercised. Give this one a history of failures
# and no success — a shape that would page loudly on a scheduled repo —
# and it must still read BY-DESIGN, because a repo with no cron cannot
# have a run of failures since its last success.
printf '{"workflow_runs":[]}' > "$FIX/data-noschedule__schedule_runs.json"
completed_fixture data-noschedule failure failure failure failure
rc=$(run_health "$repos_nosched" "$TMP/report_nosched_hist.md")
[ "$rc" -eq 0 ] && pass "old completed runs do not revive a streak under no-schedule" \
  || fail "no-schedule with failure history exited $rc"
expect_status data-noschedule BY-DESIGN "$TMP/report_nosched_hist.md"

# A line carrying both qualifiers must page, not suppress. Without the
# guard the whole remainder is one field and the ack is swallowed into
# the no-schedule reason.
repos_two_quals="$TMP/repos_two_quals.txt"
printf 'data-dead no-schedule:looks fine ack:parked:2099-01-01\n' > "$repos_two_quals"
rc=$(run_health "$repos_two_quals" "$TMP/report_two_quals.md")
[ "$rc" -eq 1 ] && pass "two qualifiers on one line pages" \
  || fail "doubled qualifier exited $rc"
expect_reason data-dead "one qualifier per line" "$TMP/report_two_quals.md"

# And it must not be usable as a dateless ack: a reasonless entry is
# malformed, and a malformed entry pages rather than suppresses.
repos_nosched_bad="$TMP/repos_nosched_bad.txt"
printf 'data-noschedule no-schedule:\n' > "$repos_nosched_bad"
rc=$(run_health "$repos_nosched_bad" "$TMP/report_nosched_bad.md")
[ "$rc" -eq 1 ] && pass "a reasonless no-schedule pages" \
  || fail "reasonless no-schedule exited $rc"

echo "== acknowledgement: suppresses paging until review-by =="
# data-dead is thoroughly broken (state disabled_inactively), so it is
# unhealthy at every frozen instant below; only the acknowledgement can
# keep it from paging. data-ackok is healthy at each instant, so when it
# pages, only the acknowledgement can be the cause.
healthy_fixture_at data-ackok "$NOW_AFTER"
healthy_fixture_at data-badack "$NOW_BEFORE"

repos_ack="$TMP/repos_ack.txt"
printf 'data-dead ack:parked for maintainer ruling:2026-09-07\n' > "$repos_ack"
rc=$(run_health "$repos_ack" "$TMP/report_ack.md" \
  FLEET_HEALTH_NOW_EPOCH="$NOW_BEFORE")
[ "$rc" -eq 0 ] && pass "acknowledged breakage exits 0" || fail "ack exit was $rc"
expect_status data-dead ACKNOWLEDGED "$TMP/report_ack.md"
grep -q '<!-- fleet-health-state: healthy -->' "$TMP/report_ack.md" \
  && pass "acknowledged repo stays out of the state signature" \
  || fail "acknowledged repo leaked into the state signature"
expect_reason data-dead "acknowledged until 2026-09-07" "$TMP/report_ack.md"
expect_reason data-dead "parked for maintainer ruling" "$TMP/report_ack.md"
grep -q '1 acknowledged and deliberately silent' "$TMP/report_ack.md" \
  && pass "acknowledged count reported" || fail "acknowledged count missing"

echo "== acknowledgement: still acknowledged ON the review-by date =="
rc=$(run_health "$repos_ack" "$TMP/report_ackday.md" \
  FLEET_HEALTH_NOW_EPOCH="$NOW_ONDAY")
[ "$rc" -eq 0 ] && pass "review-by day still exits 0" || fail "ack-day exit was $rc"
expect_status data-dead ACKNOWLEDGED "$TMP/report_ackday.md"

echo "== acknowledgement: expires into a page =="
rc=$(run_health "$repos_ack" "$TMP/report_exp.md" \
  FLEET_HEALTH_NOW_EPOCH="$NOW_AFTER")
[ "$rc" -eq 1 ] && pass "expired acknowledgement exits 1" || fail "expired exit was $rc"
expect_status data-dead EXPIRED-ACK "$TMP/report_exp.md"
expect_reason data-dead "acknowledgement expired (review-by 2026-09-07)" \
  "$TMP/report_exp.md"
grep -q '<!-- fleet-health-state: data-dead=EXPIRED-ACK -->' "$TMP/report_exp.md" \
  && pass "expiry shows up in the state signature" || fail "expiry not in signature"

echo "== acknowledgement: an expired ack on a HEALTHY repo still pages =="
# The date is a forcing function: the ruling is owed even if the repo
# fixed itself, otherwise the ack line lives forever.
repos_ack_ok="$TMP/repos_ack_ok.txt"
printf 'data-ackok ack:parked pending ruling:2026-09-07\n' > "$repos_ack_ok"
rc=$(run_health "$repos_ack_ok" "$TMP/report_expok.md" \
  FLEET_HEALTH_NOW_EPOCH="$NOW_AFTER")
[ "$rc" -eq 1 ] && pass "expired ack pages even when healthy" \
  || fail "expired-ack-on-healthy exit was $rc"
expect_status data-ackok EXPIRED-ACK "$TMP/report_expok.md"
expect_reason data-ackok "no outstanding health problem" "$TMP/report_expok.md"

echo "== acknowledgement: an unexpired ack on a healthy repo is quiet =="
repos_ack_quiet="$TMP/repos_ack_quiet.txt"
printf 'data-badack ack:parked pending ruling:2026-09-07\n' > "$repos_ack_quiet"
rc=$(run_health "$repos_ack_quiet" "$TMP/report_ackquiet.md" \
  FLEET_HEALTH_NOW_EPOCH="$NOW_BEFORE")
[ "$rc" -eq 0 ] && pass "healthy acknowledged repo exits 0" \
  || fail "healthy-acknowledged exit was $rc"

echo "== acknowledgement: a malformed one pages instead of muting =="
# data-badack is healthy at NOW_BEFORE, so any page here comes from the
# acknowledgement itself, not from the repo.
for bad in 'ack:no date here' 'ack:bad date:07-09-2026' 'ack:not real:2026-02-31' \
           'ack::2026-09-07' 'parked:2026-09-07'; do
  repos_bad="$TMP/repos_bad.txt"
  printf 'data-badack %s\n' "$bad" > "$repos_bad"
  rc=$(run_health "$repos_bad" "$TMP/report_bad.md" \
    FLEET_HEALTH_NOW_EPOCH="$NOW_BEFORE")
  if [ "$rc" -eq 1 ] &&
     grep -E "^\| data-badack \| UNHEALTHY " "$TMP/report_bad.md" > /dev/null; then
    pass "malformed ack pages: $bad"
  else
    fail "malformed ack was tolerated (exit $rc): $bad"
  fi
done

echo "== queries: only scheduled runs may reach the streak =="
# The fixture layer bypasses URL building entirely, so this drives the
# real query builder through a stubbed gh. The stub answers scheduled
# queries with successes and everything else with failures: if the
# monitor ever drops event=schedule, a red PR run pages the fleet.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
  echo "$2" >> "$GH_PATHS"
  case "$2" in
    *"/runs?"*"event=schedule"*"per_page=5") printf '{"workflow_runs":[{"created_at":"%s","conclusion":"success"}]}' "$SCHED_TS" ;;
    *"/runs?"*"event=schedule"*) printf '{"workflow_runs":[{"created_at":"%s","conclusion":"success"},{"created_at":"%s","conclusion":"success"},{"created_at":"%s","conclusion":"success"}]}' "$SCHED_TS" "$SCHED_TS" "$SCHED_TS" ;;
    *"/runs?"*) printf '{"workflow_runs":[{"created_at":"%s","conclusion":"failure"},{"created_at":"%s","conclusion":"failure"},{"created_at":"%s","conclusion":"failure"},{"created_at":"%s","conclusion":"failure"}]}' "$SCHED_TS" "$SCHED_TS" "$SCHED_TS" "$SCHED_TS" ;;
    *) printf '{"path":".github/workflows/fetch.yml","state":"active"}' ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$TMP/bin/gh"
printf 'data-prfail\n' > "$TMP/repos_q.txt"
: > "$TMP/paths.txt"
rc=0
PATH="$TMP/bin:$PATH" GH_TOKEN=stub-token GH_PATHS="$TMP/paths.txt" \
  SCHED_TS="$(iso '3 hours ago')" FLEET_HEALTH_FIXTURES= \
  FLEET_HEALTH_REPOS_FILE="$TMP/repos_q.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_q.md" > /dev/null || rc=$?
[ "$rc" -eq 0 ] && pass "PR/push failures do not page (exit 0)" \
  || fail "unscheduled runs leaked into the verdict (exit $rc)"
expect_status data-prfail OK "$TMP/report_q.md"
unscheduled="$(grep '/runs?' "$TMP/paths.txt" | grep -v 'event=schedule' || true)"
[ -z "$unscheduled" ] && pass "no run query is missing event=schedule" \
  || fail "run query without event=schedule: $unscheduled"
grep -q 'runs?event=schedule&status=completed' "$TMP/paths.txt" \
  && pass "streak query is scheduled runs, completed only" \
  || fail "streak query wrong: $(grep '/runs?' "$TMP/paths.txt" | tr '\n' ' ')"

echo "== auth: an older gh must not fall through to the anonymous API =="
# `gh auth token` arrived in gh 2.6. Probing with it alone made gh 2.4
# look logged-out, so a full pass went out over anonymous curl and died
# on the 60/hour limit. A logged-in gh must be used whichever probe
# answers.
mkdir -p "$TMP/bin2"
cat > "$TMP/bin2/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "auth token")  exit 1 ;;   # as on gh < 2.6
  "auth status") exit 0 ;;   # but the CLI is logged in
esac
if [ "$1" = "api" ]; then
  echo "$2" >> "$GH_PATHS"
  case "$2" in
    *"/runs?"*"per_page=5") printf '{"workflow_runs":[{"created_at":"%s","conclusion":"success"}]}' "$SCHED_TS" ;;
    *"/runs?"*) printf '{"workflow_runs":[{"created_at":"%s","conclusion":"success"},{"created_at":"%s","conclusion":"success"}]}' "$SCHED_TS" "$SCHED_TS" ;;
    *) printf '{"state":"active"}' ;;
  esac
fi
exit 0
STUB
cat > "$TMP/bin2/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$CURL_LOG"
STUB
chmod +x "$TMP/bin2/gh" "$TMP/bin2/curl"
: > "$TMP/paths2.txt"
: > "$TMP/curl.log"
rc=0
env -u GH_TOKEN -u GITHUB_TOKEN PATH="$TMP/bin2:$PATH" \
  GH_PATHS="$TMP/paths2.txt" CURL_LOG="$TMP/curl.log" \
  SCHED_TS="$(iso '3 hours ago')" FLEET_HEALTH_FIXTURES= \
  FLEET_HEALTH_REPOS_FILE="$TMP/repos_q.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_auth.md" > /dev/null || rc=$?
[ "$rc" -eq 0 ] && pass "logged-in gh 2.4-style CLI produces a verdict" \
  || fail "auth fallback exit was $rc"
[ -s "$TMP/paths2.txt" ] && pass "requests went through gh" \
  || fail "gh was never called"
[ -s "$TMP/curl.log" ] \
  && fail "fell through to anonymous curl: $(cat "$TMP/curl.log")" \
  || pass "did not fall through to anonymous curl"

echo "== streak: the page must be large enough to reach the threshold =="
# Recency must come from the newest run on the page, not from position
# zero. The endpoint has been observed serving a stale page: on
# 2026-08-18 it reported data-uk's last scheduled run as three weeks old
# while that repository was committing every morning, and the monitor
# paged on a healthy repo for it. This stub puts the OLD run first, so a
# reader that trusts position zero calls a healthy repo stale.
echo "== recency: the newest run on the page wins, whatever its position =="
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
  [ -n "${GH_PATHS:-}" ] && echo "$2" >> "$GH_PATHS"
  case "$2" in
    *"/runs?"*"event=schedule"*"status=completed"*)
      printf '{"workflow_runs":[{"created_at":"%s","conclusion":"success"}]}' "$SCHED_TS" ;;
    *"/runs?"*"event=schedule"*)
      printf '{"workflow_runs":[{"created_at":"%s","conclusion":"failure"},{"created_at":"%s","conclusion":"success"}]}' "$SCHED_OLD" "$SCHED_TS" ;;
    *) printf '{"path":".github/workflows/fetch.yml","state":"active"}' ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$TMP/bin/gh"
printf 'data-order\n' > "$TMP/repos_order.txt"
rc=0
PATH="$TMP/bin:$PATH" GH_TOKEN=stub-token \
  SCHED_TS="$(iso '3 hours ago')" SCHED_OLD="$(iso '30 days ago')" \
  FLEET_HEALTH_FIXTURES= FLEET_HEALTH_REPOS_FILE="$TMP/repos_order.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_order.md" > /dev/null || rc=$?
[ "$rc" -eq 0 ] \
  && pass "the newest run on the page decides recency, not position zero" \
  || fail "a stale entry ahead of the newest one paged a healthy repo (exit $rc)"
# The conclusion must come from the same run as the timestamp. It is
# display-only, so nothing about the verdict catches it: reading it from
# position zero reports the OLD run's conclusion beside the NEW run's
# time, which is a row that describes no run that ever happened.
if grep -q '(success)' "$TMP/report_order.md"; then
  pass "the reported conclusion belongs to the run reported beside it"
else
  fail "conclusion came from a different run than the timestamp: $(grep 'data-order' "$TMP/report_order.md" || true)"
fi

# The streak reads the same endpoint and had the same positional trust:
# `window` takes everything before the first S as "since the last
# success", so an old success served ahead of newer failures clears a
# real streak. This stub puts the OLD success first and three newer
# failures after it; ordered correctly the repo pages, ordered by
# position it reads clean.
echo "== streak: the newest completed runs decide it, not API position =="
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
  [ -n "${GH_PATHS:-}" ] && echo "$2" >> "$GH_PATHS"
  case "$2" in
    *"/runs?"*"event=schedule"*"status=completed"*)
      printf '{"workflow_runs":[{"created_at":"%s","conclusion":"success"},{"created_at":"%s","conclusion":"failure"},{"created_at":"%s","conclusion":"failure"},{"created_at":"%s","conclusion":"failure"}]}' "$SCHED_OLD" "$SCHED_MID" "$SCHED_NEWER" "$SCHED_TS" ;;
    *"/runs?"*"event=schedule"*)
      printf '{"workflow_runs":[{"created_at":"%s","conclusion":"failure"}]}' "$SCHED_TS" ;;
    *) printf '{"path":".github/workflows/fetch.yml","state":"active"}' ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$TMP/bin/gh"
rc=0
PATH="$TMP/bin:$PATH" GH_TOKEN=stub-token \
  SCHED_TS="$(iso '3 hours ago')" SCHED_NEWER="$(iso '4 hours ago')" \
  SCHED_MID="$(iso '5 hours ago')" SCHED_OLD="$(iso '30 days ago')" \
  FLEET_HEALTH_FIXTURES= FLEET_HEALTH_REPOS_FILE="$TMP/repos_order.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_streak_order.md" > /dev/null || rc=$?
[ "$rc" -eq 1 ] \
  && pass "an old success served first cannot clear a real failure streak" \
  || fail "the streak was cleared by API position (exit $rc)"

# per_page was pinned at 10 while FLEET_HEALTH_STREAK is configurable, so
# any threshold above 10 could never be reached: the streak stayed short
# of the limit forever and a dead repo read healthy — the silent OK this
# monitor exists to kill.
: > "$TMP/paths12.txt"
rc=0
PATH="$TMP/bin:$PATH" GH_TOKEN=stub-token GH_PATHS="$TMP/paths12.txt" \
  SCHED_TS="$(iso '3 hours ago')" FLEET_HEALTH_FIXTURES= \
  FLEET_HEALTH_STREAK=12 FLEET_HEALTH_REPOS_FILE="$TMP/repos_q.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_12q.md" > /dev/null || rc=$?
grep -q 'status=completed&per_page=13' "$TMP/paths12.txt" \
  && pass "threshold 12 asks the API for 13 completed runs" \
  || fail "streak page ignored the threshold: $(grep -o 'per_page=[0-9]*' "$TMP/paths12.txt" | tr '\n' ' ')"
grep -q 'status=completed&per_page=10' "$TMP/paths.txt" \
  && pass "the default threshold still asks for 10" \
  || fail "default page size changed: $(grep -o 'per_page=[0-9]*' "$TMP/paths.txt" | tr '\n' ' ')"

# The fixture layer bypasses URL building, so this proves the other half:
# with the runs in hand, a threshold above the old page size does reach a
# verdict instead of sitting one short of it forever.
printf 'data-streak12\n' > "$TMP/repos_12.txt"
workflow_fixture data-streak12 active
schedule_fixture data-streak12 '5 hours ago' failure
completed_fixture data-streak12 failure failure failure failure failure \
  failure failure failure failure failure failure failure
rc=0
FLEET_HEALTH_STREAK=12 FLEET_HEALTH_FIXTURES="$FIX" \
  FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_12.md" > /dev/null || rc=$?
expect_status data-streak12 UNHEALTHY "$TMP/report_12.md"
expect_reason data-streak12 "12 hard failures since the last success" \
  "$TMP/report_12.md"

# ...and that it stays a threshold, not a hair trigger: eleven is below it.
completed_fixture data-streak12 failure failure failure failure failure \
  failure failure failure failure failure failure
rc=0
FLEET_HEALTH_STREAK=12 FLEET_HEALTH_FIXTURES="$FIX" \
  FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_11.md" > /dev/null || rc=$?
expect_status data-streak12 OK "$TMP/report_11.md"

echo "== streak: a threshold the query cannot honour is refused =="
# 100 is the API per_page ceiling. A larger threshold, or a non-numeric
# one, is refused at startup rather than discovered as a quiet "OK".
for bad in 0 101 abc -1; do
  rc=0
  FLEET_HEALTH_STREAK="$bad" FLEET_HEALTH_FIXTURES="$FIX" \
    FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_bad.md" \
    > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 64 ] && pass "refuses FLEET_HEALTH_STREAK=$bad (exit 64)" \
    || fail "FLEET_HEALTH_STREAK=$bad exited $rc, wanted 64"
done
rc=0
FLEET_HEALTH_STREAK=100 FLEET_HEALTH_FIXTURES="$FIX" \
  FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_100.md" > /dev/null || rc=$?
[ "$rc" -ne 64 ] && pass "accepts the largest honourable threshold (100)" \
  || fail "threshold 100 was refused"

echo "== streak: a leading zero means the same number everywhere =="
# bash reads a leading zero as octal inside $((…)) but as decimal in
# [ … -lt … ]. Unnormalised, FLEET_HEALTH_STREAK=012 sized the page as 10
# while every comparison read 12 — a page one short of the threshold, the
# exact silent OK the block above exists to kill. 008 and 09 are not octal
# at all and aborted the run with an arithmetic error instead of exit 64.
: > "$TMP/paths012.txt"
rc=0
PATH="$TMP/bin:$PATH" GH_TOKEN=stub-token GH_PATHS="$TMP/paths012.txt" \
  SCHED_TS="$(iso '3 hours ago')" FLEET_HEALTH_FIXTURES= \
  FLEET_HEALTH_STREAK=012 FLEET_HEALTH_REPOS_FILE="$TMP/repos_q.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_012.md" > /dev/null || rc=$?
grep -q 'status=completed&per_page=13' "$TMP/paths012.txt" \
  && pass "threshold 012 asks for 13, the same as 12" \
  || fail "012 was read as octal: $(grep -o 'per_page=[0-9]*' "$TMP/paths012.txt" | tr '\n' ' ')"

# A padded threshold must be indistinguishable from its plain spelling —
# same exit code, same verdict — not merely "does not crash", since the
# fleet's own unhealthy exit code is easy to mistake for survival.
for pair in 008:8 09:9 0100:100; do
  zeroed=${pair%:*}; plain=${pair#*:}
  rc_z=0; rc_p=0
  FLEET_HEALTH_STREAK="$zeroed" FLEET_HEALTH_FIXTURES="$FIX" \
    FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_z.md" \
    > /dev/null 2>&1 || rc_z=$?
  FLEET_HEALTH_STREAK="$plain" FLEET_HEALTH_FIXTURES="$FIX" \
    FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_p.md" \
    > /dev/null 2>&1 || rc_p=$?
  if [ "$rc_z" = "$rc_p" ] && diff -q "$TMP/report_z.md" "$TMP/report_p.md" \
       > /dev/null 2>&1; then
    pass "FLEET_HEALTH_STREAK=$zeroed behaves exactly like $plain (exit $rc_p)"
  else
    fail "$zeroed exited $rc_z and $plain exited $rc_p, reports differ"
  fi
done

# Bash arithmetic wraps at 64 bits: 2^64+1 evaluates to 1, which is a
# perfectly valid threshold, so a range check performed after evaluation
# waves it through and the monitor silently runs at a threshold nobody
# configured.
for huge in 18446744073709551617 99999999999999999999999; do
  rc=0
  FLEET_HEALTH_STREAK="$huge" FLEET_HEALTH_FIXTURES="$FIX" \
    FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_huge.md" \
    > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 64 ] && pass "refuses FLEET_HEALTH_STREAK=$huge (exit 64)" \
    || fail "FLEET_HEALTH_STREAK=$huge exited $rc, wanted 64 — it wrapped"
done

echo "== the staleness limit is validated at startup too =="
# MAX_AGE_HOURS is only ever compared, never used in arithmetic, so octal
# cannot bite it — but an unvalidated non-numeric value used to abort the
# sweep partway through the fleet instead of refusing at startup.
for bad in abc 0 ''; do
  rc=0
  FLEET_HEALTH_MAX_AGE_HOURS="$bad" FLEET_HEALTH_FIXTURES="$FIX" \
    FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_age.md" \
    > /dev/null 2>&1 || rc=$?
  if [ -z "$bad" ]; then
    # An empty value is the shell's own "use the default" spelling, and
    # the default is the strict end of the range — it must not be refused.
    [ "$rc" -ne 64 ] && pass "an empty staleness limit falls back to the default" \
      || fail "empty FLEET_HEALTH_MAX_AGE_HOURS was refused"
  else
    [ "$rc" -eq 64 ] && pass "refuses FLEET_HEALTH_MAX_AGE_HOURS=$bad (exit 64)" \
      || fail "FLEET_HEALTH_MAX_AGE_HOURS=$bad exited $rc, wanted 64"
  fi
done

echo "== curl fallback presents the token the environment notes promise =="
# Without gh the token was dropped, so a tokened run quietly spent the
# anonymous 60/hour budget that one 45-call sweep nearly exhausts. gh is
# kept off PATH entirely here: with a token set the gh branch would win
# and the curl path would never be reached.
mkdir -p "$TMP/bin3"
for b in bash cat date dirname jq sort tr; do
  ln -sf "$(command -v "$b")" "$TMP/bin3/$b"
done
cat > "$TMP/bin3/curl" <<'STUB'
#!/usr/bin/env bash
# One argument per line so an assertion can match a header exactly.
{ for a in "$@"; do echo "$a"; done; } >> "$CURL_LOG"
case "$*" in
  *status=completed*) printf '{"workflow_runs":[{"created_at":"%s","conclusion":"success"}]}' "$SCHED_TS" ;;
  *event=schedule*) printf '{"workflow_runs":[{"created_at":"%s","conclusion":"success"}]}' "$SCHED_TS" ;;
  *) printf '{"path":".github/workflows/fetch.yml","state":"active"}' ;;
esac
STUB
chmod +x "$TMP/bin3/curl"

: > "$TMP/curl_tok.log"
rc=0
env PATH="$TMP/bin3" GH_TOKEN=stub-token CURL_LOG="$TMP/curl_tok.log" \
  SCHED_TS="$(iso '3 hours ago')" FLEET_HEALTH_FIXTURES= \
  FLEET_HEALTH_REPOS_FILE="$TMP/repos_q.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_curl.md" > /dev/null || rc=$?
[ "$rc" -eq 0 ] && pass "the curl path produces a verdict" \
  || fail "curl path exit was $rc"
grep -qx 'Authorization: Bearer stub-token' "$TMP/curl_tok.log" \
  && pass "curl sends Authorization when a token is set" \
  || fail "curl sent no Authorization header"
grep -q 'stub-token' "$TMP/report_curl.md" \
  && fail "the report leaked the token" \
  || pass "the token stays out of the report"

# GITHUB_TOKEN is the workflow's spelling; it must work the same.
: > "$TMP/curl_gt.log"
rc=0
env -u GH_TOKEN PATH="$TMP/bin3" GITHUB_TOKEN=stub-gt \
  CURL_LOG="$TMP/curl_gt.log" SCHED_TS="$(iso '3 hours ago')" \
  FLEET_HEALTH_FIXTURES= FLEET_HEALTH_REPOS_FILE="$TMP/repos_q.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_curl_gt.md" > /dev/null || rc=$?
grep -qx 'Authorization: Bearer stub-gt' "$TMP/curl_gt.log" \
  && pass "GITHUB_TOKEN reaches curl too" \
  || fail "GITHUB_TOKEN was dropped on the curl path"

# No token must stay anonymous — an empty header would be a 401, which is
# worse than the anonymous read the fleet's public repos allow.
: > "$TMP/curl_anon.log"
rc=0
env -u GH_TOKEN -u GITHUB_TOKEN PATH="$TMP/bin3" \
  CURL_LOG="$TMP/curl_anon.log" SCHED_TS="$(iso '3 hours ago')" \
  FLEET_HEALTH_FIXTURES= FLEET_HEALTH_REPOS_FILE="$TMP/repos_q.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_anon.md" > /dev/null || rc=$?
[ -s "$TMP/curl_anon.log" ] && pass "an untokened run still reaches curl" \
  || fail "curl was never called"
grep -q 'Authorization' "$TMP/curl_anon.log" \
  && fail "an untokened run sent an Authorization header" \
  || pass "no token, no Authorization header"

echo "== issue: announces state changes, and only state changes =="
# gh stub: logs every invocation; "gh api" answers with a canned issue
# list so the title match runs against realistic JSON.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
case "$1" in
  api) cat "$GH_ISSUES_JSON" ;;
esac
STUB
chmod +x "$TMP/bin/gh"

title='Fleet health: data-repo fetch schedules unhealthy'
state_now="$(sed -n 's/.*fleet-health-state:[[:space:]]*\(.*\)[[:space:]]*-->.*/\1/p' \
  "$TMP/report.md" | tail -n 1 | sed 's/[[:space:]]*$//')"
[ -n "$state_now" ] && pass "report carries a state signature" \
  || fail "report has no state signature"

issues_json() { # file body
  # An open PR with the exact title (must be ignored) plus the real
  # issue #42 (must be matched).
  jq -n --arg t "$title" --arg b "$2" \
    '[{number:7,title:$t,pull_request:{}},{number:42,title:$t,body:$b}]' > "$1"
}
echo '[]' > "$TMP/issues_none.json"
issues_json "$TMP/issues_same.json" \
  "stored report

<!-- fleet-health-state: $state_now -->"
issues_json "$TMP/issues_diff.json" \
  "stored report

<!-- fleet-health-state: data-somethingelse=UNHEALTHY -->"

run_upsert() { # issues-json log-file report
  : > "$2"
  PATH="$TMP/bin:$PATH" GH_LOG="$2" GH_ISSUES_JSON="$1" \
    FLEET_HEALTH_ALLOW_ISSUE_WRITE=1 \
    FLEET_HEALTH_ISSUE_REPO=ammitto/ammitto \
    "$SCRIPT_DIR/fleet_health_issue.sh" "$3" > /dev/null
}
wrote_nothing() { # log-file label
  if grep -qE '^gh issue ' "$1"; then
    fail "$2: wrote to GitHub ($(grep -E '^gh issue ' "$1" | tr '\n' ' '))"
  else
    pass "$2: no writes"
  fi
}

run_upsert "$TMP/issues_none.json" "$TMP/log1" "$TMP/report.md"
grep -q '^gh issue create ' "$TMP/log1" \
  && pass "unhealthy + no open issue -> creates" || fail "create path broken"
grep -q '^gh issue comment ' "$TMP/log1" \
  && fail "created AND commented" || pass "create path does not comment"

run_upsert "$TMP/issues_diff.json" "$TMP/log2" "$TMP/report.md"
grep -q '^gh issue comment 42 ' "$TMP/log2" \
  && pass "changed state -> comments on #42 (PR with same title ignored)" \
  || fail "comment path broken"
grep -q '^gh issue edit 42 ' "$TMP/log2" \
  && pass "changed state -> stores the new signature in the body" \
  || fail "signature not stored back"
grep -q '^gh issue create ' "$TMP/log2" \
  && fail "duplicate issue created" || pass "comment path does not create"

run_upsert "$TMP/issues_same.json" "$TMP/log3" "$TMP/report.md"
wrote_nothing "$TMP/log3" "unchanged state"

run_upsert "$TMP/issues_none.json" "$TMP/log4" "$TMP/report_ok.md"
wrote_nothing "$TMP/log4" "healthy with no open issue"

run_upsert "$TMP/issues_diff.json" "$TMP/log5" "$TMP/report_ok.md"
grep -q '^gh issue comment 42 ' "$TMP/log5" \
  && pass "recovery -> comments on #42" || fail "recovery comment missing"
grep -q '^gh issue close 42 ' "$TMP/log5" \
  && pass "recovery -> closes #42" || fail "recovery does not close"

echo "== issue: an expiring acknowledgement announces itself =="
# ACKNOWLEDGED is invisible to the signature, so the ack going stale is
# a plain none -> EXPIRED-ACK transition through the normal path.
issues_json "$TMP/issues_ackstate.json" \
  "stored report

<!-- fleet-health-state: healthy -->"
run_upsert "$TMP/issues_ackstate.json" "$TMP/log6" "$TMP/report_ack.md"
wrote_nothing "$TMP/log6" "acknowledged repo"
run_upsert "$TMP/issues_ackstate.json" "$TMP/log7" "$TMP/report_exp.md"
grep -q '^gh issue comment 42 ' "$TMP/log7" \
  && pass "expired acknowledgement -> comments" || fail "expiry not announced"

echo "== issue: refuses a report with no state marker =="
printf 'not a fleet report\n' > "$TMP/bogus.md"
rc=0
: > "$TMP/log8"
PATH="$TMP/bin:$PATH" GH_LOG="$TMP/log8" GH_ISSUES_JSON="$TMP/issues_none.json" \
  FLEET_HEALTH_ALLOW_ISSUE_WRITE=1 FLEET_HEALTH_ISSUE_REPO=ammitto/ammitto \
  "$SCRIPT_DIR/fleet_health_issue.sh" "$TMP/bogus.md" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 65 ] && pass "markerless report refused (exit 65)" \
  || fail "markerless report exit was $rc"
wrote_nothing "$TMP/log8" "markerless report"

echo "== issue: refuses to write outside Actions =="
rc=0
: > "$TMP/log9"
PATH="$TMP/bin:$PATH" GH_LOG="$TMP/log9" GH_ISSUES_JSON="$TMP/issues_none.json" \
  GITHUB_ACTIONS= FLEET_HEALTH_ALLOW_ISSUE_WRITE= \
  FLEET_HEALTH_ISSUE_REPO=ammitto/ammitto \
  "$SCRIPT_DIR/fleet_health_issue.sh" "$TMP/report.md" \
  > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 78 ] && pass "guard refuses (exit 78)" || fail "guard exit was $rc"
[ -s "$TMP/log9" ] && fail "guard still called gh" || pass "guard called no gh"

echo "== shipped repos file parses, and data-ru is acknowledged =="
if [ -f "$SCRIPT_DIR/fleet_repos.txt" ]; then
  ack_line="$(grep -E '^data-ru[[:space:]]' "$SCRIPT_DIR/fleet_repos.txt" || true)"
  case "$ack_line" in
    *"ack:parked for maintainer ruling on ru revival:2026-09-07")
      pass "data-ru ships acknowledged until 2026-09-07" ;;
    *)
      fail "data-ru acknowledgement missing or altered: ${ack_line:-no line}" ;;
  esac
  # Every non-comment line is either a bare repo or a well-formed ack.
  bad_lines="$(sed 's/#.*//' "$SCRIPT_DIR/fleet_repos.txt" |
    grep -vE '^[[:space:]]*$' |
    grep -vE '^[A-Za-z0-9._-]+([[:space:]]+(ack:[^:]+([^:]|:)*:[0-9]{4}-[0-9]{2}-[0-9]{2}|no-schedule:.+))?[[:space:]]*$' \
    || true)"
  # A line may carry at most one qualifier; "no-schedule:x ack:y:DATE"
  # would otherwise read as a no-schedule whose reason contains an ack.
  doubled_re='(ack:.*no-schedule:|no-schedule:.*ack:)'
  doubled="$(sed 's/#.*//' "$SCRIPT_DIR/fleet_repos.txt" |
    grep -E "$doubled_re" || true)"
  [ -z "$doubled" ] && pass "no shipped line carries two qualifiers" \
    || fail "lines with two qualifiers: $doubled"

  # The two checks above are one contract, and it has to match the
  # runtime parser: `ack:` and `no-schedule:` are reserved substrings
  # anywhere in a reason, not merely prefixes. Prove the pair rejects
  # what the parser rejects, in BOTH orders — the leading regex alone
  # accepts an ack whose reason contains "no-schedule:", and only the
  # doubled check catches it.
  for probe in \
    'data-x ack:contains no-schedule: prose:2026-09-07' \
    'data-x no-schedule:contains ack:bar:2026-09-07'; do
    if printf '%s\n' "$probe" |
       grep -qvE '^[A-Za-z0-9._-]+([[:space:]]+(ack:[^:]+([^:]|:)*:[0-9]{4}-[0-9]{2}-[0-9]{2}|no-schedule:.+))?[[:space:]]*$' ||
       printf '%s\n' "$probe" | grep -qE "$doubled_re"; then
      pass "validator rejects a doubled qualifier: ${probe#data-x }"
    else
      fail "validator accepted a line the parser rejects: $probe"
    fi
  done
  [ -z "$bad_lines" ] && pass "every repos-file line is well formed" \
    || fail "malformed repos-file lines: $bad_lines"
else
  fail "fleet_repos.txt missing"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "fleet_health_test: all checks passed"
else
  echo "fleet_health_test: $failures check(s) FAILED"
  exit 1
fi
