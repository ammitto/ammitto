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
# The script reads one run listing per repo, the workflow's unfiltered
# runs. The helpers below keep two parts of it per repo, the newest
# scheduled run (schedule_fixture) and the completed history
# (completed_fixture), and every write rebuilds the listing the way the
# API serves it: newest first, every run with an id, a run_number, an
# event and a status, and a total_count.
PARTS="$TMP/parts"
mkdir -p "$PARTS"
write_runs() { # repo
  # schedule_fixture's run and completed_fixture's first run are the same
  # run in these fixtures (completed_fixture starts at its timestamp), so
  # the scheduled one is folded into a completed run with its timestamp;
  # that is the only folding. Completed runs sharing a timestamp are all
  # kept. Ties are tested with hand-written pages in the listing cases.
  # Ids follow listing position, so a tie reads newest by id.
  { cat "$PARTS/$1.done" 2>/dev/null || echo '[]'
    cat "$PARTS/$1.sched" 2>/dev/null || echo '[]'; } | jq -c -s '
    .[0] as $done
    | ($done + [.[1][] | select(.created_at as $t
                                | [$done[].created_at] | index($t) | not)])
    | sort_by(.created_at) | reverse
    | length as $n
    | {total_count: $n,
       workflow_runs: [to_entries[] | .value
         + {id: (100000 + $n - .key), run_number: ($n - .key),
            event: "schedule"}]}' > "$FIX/$1__runs.json"
}
schedule_fixture() { # repo age conclusion
  printf '[{"created_at":"%s","status":"completed","conclusion":"%s"}]' \
    "$(iso "$2")" "$3" > "$PARTS/$1.sched"
  write_runs "$1"
}
no_runs_fixture() { # repo — a workflow that has never run
  echo '[]' > "$PARTS/$1.sched"
  echo '[]' > "$PARTS/$1.done"
  write_runs "$1"
}
completed_fixture() { # repo conclusion... (newest first, as the caller reads)
  local repo="$1" runs="" c i=0 newest base
  shift
  # Timestamps descend with position. They start at the newest scheduled
  # run when there is one: completed runs are scheduled runs, and one
  # newer than the newest scheduled run is a listing the API cannot
  # produce.
  newest="$(jq -r 'max_by(.created_at).created_at // empty' \
    "$PARTS/$repo.sched" 2>/dev/null || true)"
  if [ -n "$newest" ]; then
    base="$(date -ud "$newest" +%s)"
  else
    base=$(( $(date -u +%s) - 3600 ))
  fi
  for c in "$@"; do
    runs="$runs{\"created_at\":\"$(iso "@$((base - i * 3600))")\",\"status\":\"completed\",\"conclusion\":\"$c\"},"
    i=$((i + 1))
  done
  printf '[%s]' "${runs%,}" > "$PARTS/$repo.done"
  write_runs "$repo"
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
  printf '[{"created_at":"%s","status":"completed","conclusion":"success"}]' \
    "$(date -ud "@$(( $2 - 18000 ))" '+%Y-%m-%dT%H:%M:%SZ')" \
    > "$PARTS/$1.sched"
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
# monitor validated them all, an unreadable runs document produced an
# empty sequence, a zero streak and a confident "OK".
healthy_fixture data-badwf
printf '{"message":"Not Found","documentation_url":"https://docs.github.com"}' \
  > "$FIX/data-badwf__workflow.json"

healthy_fixture data-badsched
printf '{"message":"Server Error"}' > "$FIX/data-badsched__runs.json"

healthy_fixture data-badcompleted
printf '{"message":"Not Found","documentation_url":"https://docs.github.com"}' \
  > "$FIX/data-badcompleted__runs.json"

healthy_fixture data-truncated
printf '{"total_count":3,"workflow_runs":[{"conclu' > "$FIX/data-truncated__runs.json"

# A runs array whose MEMBERS are unusable: validating only the array type
# let {"workflow_runs":[null]} read as "no scheduled run" -- indistinguishable
# from the silent death this monitor exists to catch.
healthy_fixture data-nullmember
printf '{"total_count":1,"workflow_runs":[null]}' > "$FIX/data-nullmember__runs.json"

healthy_fixture data-scalarmember
printf '{"total_count":1,"workflow_runs":["oops"]}' > "$FIX/data-scalarmember__runs.json"

healthy_fixture data-blankdate
printf '{"total_count":1,"workflow_runs":[{"id":1,"created_at":"","event":"schedule","status":"completed","conclusion":"success"}]}' \
  > "$FIX/data-blankdate__runs.json"

# An empty body is the trap that looks safest: `jq -e` exits 0 on empty
# input, so an unguarded validator would wave this through as healthy.
healthy_fixture data-empty
: > "$FIX/data-empty__runs.json"

# Two JSON documents in one body. `jq -e` judges a stream by its last
# result, so a malformed document ahead of a valid one must still make
# the body unusable, for either document.
healthy_fixture data-twodocs
{ printf '[1,2]\n'; cat "$FIX/data-twodocs__runs.json"; } > "$TMP/twodocs.json"
mv "$TMP/twodocs.json" "$FIX/data-twodocs__runs.json"
healthy_fixture data-twowf
{ printf '"x"\n'; cat "$FIX/data-twowf__workflow.json"; } > "$TMP/twowf.json"
mv "$TMP/twowf.json" "$FIX/data-twowf__workflow.json"

repos_all="$TMP/repos_all.txt"
printf '%s\n' data-dead data-stale data-failing data-quiet data-two-fails \
  data-cancelled data-mixed data-ghost data-badwf data-badsched \
  data-badcompleted data-truncated data-empty \
  data-nullmember data-scalarmember data-blankdate data-twodocs \
  data-twowf > "$repos_all"
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
expect_reason data-stale "72h00m ago (limit 48h)"
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
expect_reason data-badsched "run listing unreadable"
expect_status data-badcompleted UNREADABLE
expect_reason data-badcompleted "run listing unreadable"
expect_status data-nullmember UNREADABLE
expect_reason data-nullmember "run listing unreadable"
expect_status data-scalarmember UNREADABLE
expect_reason data-scalarmember "run listing unreadable"
expect_status data-blankdate UNREADABLE
expect_reason data-blankdate "run listing unreadable"
expect_status data-truncated UNREADABLE
expect_status data-empty UNREADABLE
expect_status data-twodocs UNREADABLE
expect_reason data-twodocs "run listing unreadable"
expect_status data-twowf UNREADABLE
expect_reason data-twowf "workflow document unreadable"
for r in data-badwf data-badsched data-badcompleted data-truncated data-empty \
         data-twodocs data-twowf; do
  if grep -E "^\| $r \| OK " "$TMP/report.md" > /dev/null; then
    fail "$r reported OK with an unusable document"
  fi
done
pass "no repo with an unusable document reported OK"

echo "== listing: one page, judged only when it keeps its promises =="
# The runs come from one page of the workflow's unfiltered listing,
# because the API's event= filter answered with partial pages
# (2026-09-23: data-eu's newest scheduled run read as 09-18 while it ran
# daily to 09-22, paged as "117h ago"). The page is held to what it
# promises instead; each case below breaks one promise and must be
# UNREADABLE, never judged.
# runs_array: id-of-newest count event conclusion newest-epoch step
runs_array() {
  jq -n -c --argjson id "$1" --argjson n "$2" --arg ev "$3" --arg c "$4" \
    --argjson t "$5" --argjson step "$6" '
    [range(0; $n) | {id: ($id - .), run_number: ($id - .),
      created_at: (($t - . * $step) | todate), event: $ev,
      status: "completed", conclusion: $c}]'
}
listing_page() { # file total-count array...
  local file="$1" total="$2"
  shift 2
  printf '%s\n' "$@" | jq -c -s --argjson total "$total" \
    '{total_count: $total, workflow_runs: add}' > "$file"
}
now_s=$(date -u +%s)

# A short page: total_count 100 promises a full page and 99 arrive. The
# missing run is the newest, a failure; judged as served the streak
# reads FFSSSSSSSS, OK, with the newest failure never seen.
workflow_fixture data-shortpage active
listing_page "$FIX/data-shortpage__runs.json" 100 \
  "$(runs_array 99 2 schedule failure $((now_s - 7200)) 3600)" \
  "$(runs_array 97 97 schedule success $((now_s - 3 * 3600)) 3600)"

# The extreme of the same: an empty page whose total_count says a run
# exists. Judged as served it is a repo with no scheduled run on record.
workflow_fixture data-emptylist active
listing_page "$FIX/data-emptylist__runs.json" 1 '[]'

# History deeper than one page: 98 push runs crowd the page, the cron's
# own runs sit behind them, and total_count says there are 300 runs.
# Two scheduled failures are all the page shows of the streak.
workflow_fixture data-crowded active
listing_page "$FIX/data-crowded__runs.json" 300 \
  "$(runs_array 3000 98 push success $((now_s - 60)) 60)" \
  "$(runs_array 2902 2 schedule failure $((now_s - 7200)) 3600)"

# Not a fault: a history shorter than the streak's ten runs, whole on
# the page (total_count agrees), is judged as it stands.
workflow_fixture data-young active
listing_page "$FIX/data-young__runs.json" 3 \
  "$(runs_array 3 3 schedule success $((now_s - 7200)) 86400)"

# Duplicate ids: ten copies of one successful run would otherwise fill
# the streak's window and read as ten successes.
workflow_fixture data-dupids active
listing_page "$FIX/data-dupids__runs.json" 12 \
  "$(runs_array 12 2 schedule failure $((now_s - 3600)) 3600)" \
  "$(jq -c '[range(10)] | map({id: 10, run_number: 10,
      created_at: ("'"$(iso "@$((now_s - 3 * 3600))")"'"), event: "schedule",
      status: "completed", conclusion: "success"})' <<<'null')"

# total_count must be a whole number, not negative, below a billion (jq
# prints larger ones in exponent form, which aborts shell arithmetic),
# and must agree with the page; a fraction would also crash arithmetic.
bad_totals=()
for bad in -1 2.5 '"12"' 1 1e20; do
  case "$bad" in
    -1) name=data-totalneg ;;
    1e20) name=data-totalhuge ;;
    *) name="data-total$(printf '%s' "$bad" | tr -dc '0-9')" ;;
  esac
  workflow_fixture "$name" active
  runs_array 12 3 schedule success $((now_s - 3600)) 3600 |
    jq -c --argjson t "$bad" '{total_count: $t, workflow_runs: .}' \
    > "$FIX/${name}__runs.json"
  bad_totals+=("$name")
done

# A run without a conclusion key, and one whose timestamp is not the
# API's fixed form (string order would misplace it).
workflow_fixture data-noconclusion active
runs_array 3 3 schedule success $((now_s - 3600)) 3600 |
  jq -c '.[1] |= del(.conclusion) | {total_count: 3, workflow_runs: .}' \
  > "$FIX/data-noconclusion__runs.json"
workflow_fixture data-baddate active
runs_array 3 3 schedule success $((now_s - 3600)) 3600 |
  jq -c '.[1].created_at = "2026-09-23 10:00:00" | {total_count: 3, workflow_runs: .}' \
  > "$FIX/data-baddate__runs.json"

# Two scheduled runs created in the same second. Ties are broken by id,
# higher is newer: served that way the newer one (a failure) is read
# first; served the other way round the page is refused, because the
# order that decides the streak cannot be told from it.
tie_t="$(iso "@$((now_s - 3600))")"
tie_run() { printf '{"id":%s,"run_number":%s,"created_at":"%s","event":"schedule","status":"completed","conclusion":"%s"}' "$1" "$1" "$tie_t" "$2"; }
older="$(runs_array 18 8 schedule success $((now_s - 2 * 3600)) 3600)"
workflow_fixture data-tie active
listing_page "$FIX/data-tie__runs.json" 10 \
  "[$(tie_run 20 failure),$(tie_run 19 success)]" "$older"
workflow_fixture data-tieswapped active
listing_page "$FIX/data-tieswapped__runs.json" 10 \
  "[$(tie_run 19 success),$(tie_run 20 failure)]" "$older"

# Shapes the fleet serves every day, each judged as it stands. A full
# page whose total_count is exactly 100 is complete, not short.
workflow_fixture data-fullpage active
listing_page "$FIX/data-fullpage__runs.json" 100 \
  "$(runs_array 500 100 schedule success $((now_s - 3600)) 3600)"

# A cron run still queued or in progress at the top of the page is the
# cron having fired, so it is the newest scheduled run; it has no
# conclusion yet, so it is neither a success nor an inconclusive run in
# the streak.
workflow_fixture data-inflight active
listing_page "$FIX/data-inflight__runs.json" 13 \
  "$(runs_array 313 3 schedule x $((now_s - 60)) 60 |
     jq -c 'map(.conclusion = null) | .[0].status = "queued"
            | .[1].status = "in_progress" | .[2].status = "queued"')" \
  "$(runs_array 310 10 schedule success $((now_s - 3600)) 3600)"
inflight_t="$(iso "@$((now_s - 60))")"

# Manual dispatches at the top of the page, failing, are not the cron:
# they must neither set the recency nor enter the streak.
workflow_fixture data-dispatch active
listing_page "$FIX/data-dispatch__runs.json" 13 \
  "$(runs_array 413 3 workflow_dispatch failure $((now_s - 60)) 60)" \
  "$(runs_array 410 10 schedule success $((now_s - 3600)) 3600)"
dispatch_sched_t="$(iso "@$((now_s - 3600))")"

repos_listing="$TMP/repos_listing.txt"
printf '%s\n' data-shortpage data-emptylist data-crowded data-young \
  data-dupids "${bad_totals[@]}" data-noconclusion data-baddate data-tie \
  data-tieswapped data-fullpage data-inflight data-dispatch > "$repos_listing"
rc=$(run_health "$repos_listing" "$TMP/report_listing.md")
[ "$rc" -eq 1 ] && pass "broken listings page (exit 1)" \
  || fail "broken listings exit was $rc"
expect_status data-shortpage UNREADABLE "$TMP/report_listing.md"
expect_reason data-shortpage "99 runs where total_count 100 promises 100" \
  "$TMP/report_listing.md"
expect_status data-emptylist UNREADABLE "$TMP/report_listing.md"
expect_reason data-emptylist "0 runs where total_count 1 promises 1" \
  "$TMP/report_listing.md"
expect_status data-crowded UNREADABLE "$TMP/report_listing.md"
expect_reason data-crowded "history deeper than one page; not judged" \
  "$TMP/report_listing.md"
expect_status data-young OK "$TMP/report_listing.md"
for r in data-dupids data-totalneg data-total25 data-total12 \
         data-totalhuge data-noconclusion data-baddate; do
  expect_status "$r" UNREADABLE "$TMP/report_listing.md"
  expect_reason "$r" "run listing unreadable" "$TMP/report_listing.md"
done
expect_status data-total1 UNREADABLE "$TMP/report_listing.md"
expect_reason data-total1 "3 runs where total_count 1 promises 1" \
  "$TMP/report_listing.md"
expect_status data-tie OK "$TMP/report_listing.md"
grep -E '^\| data-tie \|' "$TMP/report_listing.md" | grep -qF "$tie_t (failure)" \
  && pass "a same-second tie reads the higher id as the newer run" \
  || fail "tie read wrong: $(grep -E '^\| data-tie \|' "$TMP/report_listing.md")"
grep -E '^\| data-tie \|' "$TMP/report_listing.md" | grep -qF '| FSSSSSSSSS |' \
  && pass "the tie is ordered the same way in the streak" \
  || fail "tie streak wrong: $(grep -E '^\| data-tie \|' "$TMP/report_listing.md")"
expect_status data-tieswapped UNREADABLE "$TMP/report_listing.md"
expect_reason data-tieswapped "not newest-first" "$TMP/report_listing.md"
expect_status data-fullpage OK "$TMP/report_listing.md"
grep -E '^\| data-fullpage \|' "$TMP/report_listing.md" | grep -qF '| SSSSSSSSSS |' \
  && pass "a full page with total_count exactly 100 is judged" \
  || fail "full page read wrong: $(grep -E '^\| data-fullpage \|' "$TMP/report_listing.md")"
expect_status data-inflight OK "$TMP/report_listing.md"
grep -E '^\| data-inflight \|' "$TMP/report_listing.md" \
  | grep -qF "$inflight_t (-) | 0h | SSSSSSSSSS | 0F/0C |" \
  && pass "queued and in-progress cron runs set recency but stay out of the streak" \
  || fail "in-flight runs read wrong: $(grep -E '^\| data-inflight \|' "$TMP/report_listing.md")"
expect_status data-dispatch OK "$TMP/report_listing.md"
grep -E '^\| data-dispatch \|' "$TMP/report_listing.md" \
  | grep -qF "$dispatch_sched_t (success) | 1h | SSSSSSSSSS | 0F/0C |" \
  && pass "failing manual dispatches set neither recency nor the streak" \
  || fail "dispatch runs read wrong: $(grep -E '^\| data-dispatch \|' "$TMP/report_listing.md")"
for r in data-shortpage data-emptylist data-crowded data-dupids \
         "${bad_totals[@]}" data-noconclusion data-baddate data-tieswapped; do
  grep -F "**$r**" "$TMP/report_listing.md" | grep -qF 'ago (limit' \
    && fail "$r: an age was computed from a page that broke a promise" \
    || pass "$r: no age computed from a broken page"
done

echo "== staleness: the limit is judged to the second =="
# Whole hours round down, so a run 48h59m59s old would read as 48h and
# pass a 48 hour limit. The clock is frozen so each age is exact.
age_now=1788782400
for spec in 172800:OK 172801:UNHEALTHY 176399:UNHEALTHY; do
  age=${spec%:*}; want=${spec#*:}
  workflow_fixture "data-age$age" active
  listing_page "$FIX/data-age${age}__runs.json" 3 \
    "$(runs_array 3 3 schedule success $((age_now - age)) 86400)"
  printf 'data-age%s\n' "$age" > "$TMP/repos_age.txt"
  rc=$(run_health "$TMP/repos_age.txt" "$TMP/report_age$age.md" \
    FLEET_HEALTH_NOW_EPOCH="$age_now")
  expect_status "data-age$age" "$want" "$TMP/report_age$age.md"
done
expect_reason data-age176399 "48h59m ago (limit 48h)" "$TMP/report_age176399.md"
# Under a minute past the limit, minutes alone would read as the limit.
expect_reason data-age172801 "48h00m01s ago (limit 48h)" "$TMP/report_age172801.md"

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
no_runs_fixture data-noschedule

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
  no_runs_fixture data-noschedule
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
#
# With one listing there is no longer a way to hold failures without a
# newest scheduled run, and an ACTIVE workflow with runs on record pages
# for its own reason (above). So the workflow is deleted, as data-jp's
# is, and its history ends in failures.
workflow_fixture data-noschedule deleted
schedule_fixture data-noschedule '3 hours ago' failure
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

# The two doubled-qualifier cases get their own blocks rather than a row
# in the loop above, because each needs a repo the doubled line would
# actually silence, and they do not agree on which repo that is. The
# parser is what decides whether a repository is watched, so proving it
# here matters more than the shipped-file validator's static check.
echo "== acknowledgement: a doubled ack pages instead of running to the later date =="
# On origin/main this exits 0 and reads ACKNOWLEDGED: the review-by comes
# from the LAST colon, so the second qualifier's 2099 wins and the repo
# goes quiet for decades. Measured both ways before this assertion was
# written.
repos_dblack="$TMP/repos_dblack.txt"
printf 'data-badack ack:first:2098-09-07 ack:second:2099-10-07\n' > "$repos_dblack"
rc=$(run_health "$repos_dblack" "$TMP/report_dblack.md" \
  FLEET_HEALTH_NOW_EPOCH="$NOW_BEFORE")
[ "$rc" -eq 1 ] && pass "a doubled ack pages" \
  || fail "doubled ack exited $rc"
expect_status data-badack UNHEALTHY "$TMP/report_dblack.md"
expect_reason data-badack "one qualifier per line" "$TMP/report_dblack.md"

echo "== acknowledgement: a doubled no-schedule pages on a repo it would silence =="
# This one needs its own fixture. data-badack has a live schedule, so it
# pages under EVERY no-schedule spelling, the single valid one included:
# asserting the doubled pair against it passed on unmodified main and
# proved nothing at all. data-dblnosched has no schedule-event run on
# record, so without the guard the second designator is swallowed into
# the reason, the line reads as one valid designation, and the repo goes
# BY-DESIGN and silent — which is the suppression the guard exists to
# refuse.
workflow_fixture data-dblnosched active
no_runs_fixture data-dblnosched
repos_dblnos="$TMP/repos_dblnos.txt"
printf 'data-dblnosched no-schedule:first no-schedule:second\n' > "$repos_dblnos"
rc=$(run_health "$repos_dblnos" "$TMP/report_dblnos.md")
[ "$rc" -eq 1 ] && pass "a doubled no-schedule pages" \
  || fail "doubled no-schedule exited $rc"
expect_status data-dblnosched UNHEALTHY "$TMP/report_dblnos.md"
expect_reason data-dblnosched "one qualifier per line" "$TMP/report_dblnos.md"

echo "== queries: only scheduled runs may reach the verdict =="
# The fixture layer bypasses URL building entirely, so this drives the
# real query builder through a stubbed gh. The listing mixes green
# scheduled runs with red push and PR runs, newer ones included: if the
# client-side event filter ever lapses, a red PR run pages the fleet.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
  echo "$2" >> "$GH_PATHS"
  case "$2" in
    *"/runs?"*)
      run() { printf '{"id":%s,"created_at":"%s","event":"%s","status":"completed","conclusion":"%s"}' "$@"; }
      printf '{"total_count":7,"workflow_runs":[%s,%s,%s,%s,%s,%s,%s]}' \
        "$(run 7 "$T1" pull_request failure)" "$(run 6 "$T2" schedule success)" \
        "$(run 5 "$T3" push failure)" "$(run 4 "$T4" push failure)" \
        "$(run 3 "$T5" schedule success)" "$(run 2 "$T6" push failure)" \
        "$(run 1 "$T7" schedule success)" ;;
    *) printf '{"path":".github/workflows/fetch.yml","state":"active"}' ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$TMP/bin/gh"
stub_times=(T1="$(iso '1 hours ago')" T2="$(iso '3 hours ago')"
  T3="$(iso '4 hours ago')" T4="$(iso '5 hours ago')"
  T5="$(iso '27 hours ago')" T6="$(iso '28 hours ago')"
  T7="$(iso '51 hours ago')")
printf 'data-prfail\n' > "$TMP/repos_q.txt"
: > "$TMP/paths.txt"
rc=0
env PATH="$TMP/bin:$PATH" GH_TOKEN=stub-token GH_PATHS="$TMP/paths.txt" \
  "${stub_times[@]}" FLEET_HEALTH_FIXTURES= \
  FLEET_HEALTH_REPOS_FILE="$TMP/repos_q.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_q.md" > /dev/null || rc=$?
[ "$rc" -eq 0 ] && pass "PR/push failures do not page (exit 0)" \
  || fail "unscheduled runs leaked into the verdict (exit $rc)"
expect_status data-prfail OK "$TMP/report_q.md"
grep -qF "${stub_times[1]#T2=} (success) | 3h | SSS |" "$TMP/report_q.md" \
  && pass "recency and streak are read from the scheduled runs only" \
  || fail "row read unscheduled runs: $(grep 'data-prfail' "$TMP/report_q.md" || true)"
# The API's own event= and status= filters serve partial pages (see
# "Where the runs come from" in the script), so no query may use them.
filtered="$(grep '/runs?' "$TMP/paths.txt" | grep -E 'event=|status=' || true)"
[ -z "$filtered" ] && pass "no run query uses the API's event or status filter" \
  || fail "filtered run query: $filtered"
[ "$(grep '/runs?' "$TMP/paths.txt")" = \
  "repos/ammitto/data-prfail/actions/workflows/fetch.yml/runs?per_page=100" ] \
  && pass "one listing page, 100 runs, is read when it is enough" \
  || fail "run queries: $(grep '/runs?' "$TMP/paths.txt" | tr '\n' ' ')"

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
    *"/runs?"*) printf '{"total_count":1,"workflow_runs":[{"id":1,"created_at":"%s","event":"schedule","status":"completed","conclusion":"success"}]}' "$SCHED_TS" ;;
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

echo "== order: a listing that is not newest-first is refused, not judged =="
# Recency is the first scheduled run on the listing and the streak is
# everything before the first success on it, so both trust the order.
# The endpoint has served stale pages before (2026-08-18: data-uk's last
# scheduled run read as three weeks old while it ran every morning), so
# the order is checked rather than assumed. An OLD run served ahead of
# newer ones would call a healthy repo stale, or put an old success
# ahead of newer failures and clear a real streak; either way the
# listing breaks its promise and the repo is UNREADABLE.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
  [ -n "${GH_PATHS:-}" ] && echo "$2" >> "$GH_PATHS"
  case "$2" in
    *"/runs?"*)
      run() { printf '{"id":%s,"created_at":"%s","event":"schedule","status":"completed","conclusion":"%s"}' "$@"; }
      if [ "$ORDER" = newest-first ]; then
        printf '{"total_count":4,"workflow_runs":[%s,%s,%s,%s]}' \
          "$(run 4 "$SCHED_TS" success)" "$(run 3 "$SCHED_NEWER" failure)" \
          "$(run 2 "$SCHED_MID" failure)" "$(run 1 "$SCHED_OLD" failure)"
      else
        printf '{"total_count":4,"workflow_runs":[%s,%s,%s,%s]}' \
          "$(run 1 "$SCHED_OLD" success)" "$(run 4 "$SCHED_TS" failure)" \
          "$(run 3 "$SCHED_NEWER" failure)" "$(run 2 "$SCHED_MID" failure)"
      fi ;;
    *) printf '{"path":".github/workflows/fetch.yml","state":"active"}' ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$TMP/bin/gh"
printf 'data-order\n' > "$TMP/repos_order.txt"
sched_ts="$(iso '3 hours ago')"
for order in newest-first old-first; do
  rc=0
  PATH="$TMP/bin:$PATH" GH_TOKEN=stub-token ORDER="$order" \
    SCHED_TS="$sched_ts" SCHED_NEWER="$(iso '4 hours ago')" \
    SCHED_MID="$(iso '5 hours ago')" SCHED_OLD="$(iso '30 days ago')" \
    FLEET_HEALTH_FIXTURES= FLEET_HEALTH_REPOS_FILE="$TMP/repos_order.txt" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_order_$order.md" > /dev/null || rc=$?
done
expect_status data-order OK "$TMP/report_order_newest-first.md"
# The conclusion must come from the same run as the timestamp. It is
# display-only, so nothing about the verdict catches it.
grep -qF "$sched_ts (success)" "$TMP/report_order_newest-first.md" \
  && pass "the reported conclusion belongs to the run reported beside it" \
  || fail "conclusion came from a different run than the timestamp: $(grep 'data-order' "$TMP/report_order_newest-first.md" || true)"
expect_status data-order UNREADABLE "$TMP/report_order_old-first.md"
expect_reason data-order "not newest-first" "$TMP/report_order_old-first.md"
grep -E '^\| data-order \| OK ' "$TMP/report_order_old-first.md" > /dev/null \
  && fail "an out-of-order listing was judged healthy" \
  || pass "an old success served first cannot clear a real failure streak"

echo "== streak: the one page is read far enough to reach the threshold =="
# The threshold is configurable, so the runs read must follow it: read
# one short of the threshold the streak stays short of the limit forever
# and a dead repo reads healthy. This page holds 30 scheduled runs, all
# the repo has; the default reads 10 of them, a threshold of 12 reads
# 13, and 012 must read exactly what 12 reads.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
  echo "$2" >> "$GH_PATHS"
  case "$2" in
    *"/runs?"*)
      runs=""
      for n in $(seq 0 29); do
        runs="$runs{\"id\":$((1000 - n)),\"created_at\":\"$(date -ud "@$(( BASE - n * 86400 ))" '+%Y-%m-%dT%H:%M:%SZ')\",\"event\":\"schedule\",\"status\":\"completed\",\"conclusion\":\"success\"},"
      done
      printf '{"total_count":30,"workflow_runs":[%s]}' "${runs%,}" ;;
    *) printf '{"path":".github/workflows/fetch.yml","state":"active"}' ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$TMP/bin/gh"
base_s="$(( $(date -u +%s) - 3600 ))"
frozen_s="$(date -u +%s)"
for streak in 3 12 012; do
  : > "$TMP/paths_s$streak.txt"
  rc=0
  PATH="$TMP/bin:$PATH" GH_TOKEN=stub-token GH_PATHS="$TMP/paths_s$streak.txt" \
    BASE="$base_s" FLEET_HEALTH_NOW_EPOCH="$frozen_s" FLEET_HEALTH_FIXTURES= \
    FLEET_HEALTH_STREAK="$streak" FLEET_HEALTH_REPOS_FILE="$TMP/repos_q.txt" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_s$streak.md" > /dev/null || rc=$?
done
grep -qF '| SSSSSSSSSS |' "$TMP/report_s3.md" \
  && pass "the default threshold reads ten completed runs" \
  || fail "default threshold read: $(grep 'data-prfail' "$TMP/report_s3.md")"
grep -qF '| SSSSSSSSSSSSS |' "$TMP/report_s12.md" \
  && pass "threshold 12 reads its 13 completed runs" \
  || fail "threshold 12 read: $(grep 'data-prfail' "$TMP/report_s12.md")"
diff -q "$TMP/report_s12.md" "$TMP/report_s012.md" > /dev/null \
  && pass "threshold 012 reads exactly what 12 reads" \
  || fail "012 was read as octal: $(grep 'data-prfail' "$TMP/report_s012.md")"
for streak in 3 12 012; do
  [ "$(grep -c '/runs?' "$TMP/paths_s$streak.txt")" -eq 1 ] \
    || fail "threshold $streak read more than one listing page"
done
pass "every threshold reads exactly one listing page"

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
# 99 is the ceiling. A larger threshold, or a non-numeric one, is
# refused at startup rather than discovered as a quiet "OK".
for bad in 0 100 abc -1; do
  rc=0
  FLEET_HEALTH_STREAK="$bad" FLEET_HEALTH_FIXTURES="$FIX" \
    FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_bad.md" \
    > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 64 ] && pass "refuses FLEET_HEALTH_STREAK=$bad (exit 64)" \
    || fail "FLEET_HEALTH_STREAK=$bad exited $rc, wanted 64"
done
rc=0
FLEET_HEALTH_STREAK=99 FLEET_HEALTH_FIXTURES="$FIX" \
  FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_99.md" > /dev/null || rc=$?
[ "$rc" -ne 64 ] && pass "accepts the largest honourable threshold (99)" \
  || fail "threshold 99 was refused"

echo "== streak: a leading zero means the same number everywhere =="
# bash reads a leading zero as octal inside $((…)) but as decimal in
# [ … -lt … ]. Unnormalised, FLEET_HEALTH_STREAK=012 sized the page as 10
# while every comparison read 12 — a page one short of the threshold, the
# exact silent OK the block above exists to kill. 008 and 09 are not octal
# at all and aborted the run with an arithmetic error instead of exit 64.
# A padded threshold must be indistinguishable from its plain spelling —
# same exit code, same verdict — not merely "does not crash", since the
# fleet's own unhealthy exit code is easy to mistake for survival.
# Both runs share one pinned clock. The report header is
# `date -ud @$NOW_EPOCH` where fleet_health.sh builds `$report`, and
# NOW_EPOCH defaults to now, so two runs either side of a minute boundary
# produced different headers and this assertion failed for a reason that
# has nothing to do with the streak spelling. It is a rare flake when the
# suite is run by hand and an intolerable one now that CI gates on it.
frozen="$(date -u +%s)"
for pair in 012:12 008:8 09:9 099:99; do
  zeroed=${pair%:*}; plain=${pair#*:}
  rc_z=0; rc_p=0
  FLEET_HEALTH_STREAK="$zeroed" FLEET_HEALTH_FIXTURES="$FIX" \
    FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
    FLEET_HEALTH_NOW_EPOCH="$frozen" \
    "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_z.md" \
    > /dev/null 2>&1 || rc_z=$?
  FLEET_HEALTH_STREAK="$plain" FLEET_HEALTH_FIXTURES="$FIX" \
    FLEET_HEALTH_REPOS_FILE="$TMP/repos_12.txt" \
    FLEET_HEALTH_NOW_EPOCH="$frozen" \
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
  */runs\?*) printf '{"total_count":1,"workflow_runs":[{"id":1,"created_at":"%s","event":"schedule","status":"completed","conclusion":"success"}]}' "$SCHED_TS" ;;
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

echo "== shipped repos file parses, and data-ru is listed =="
if [ -f "$SCRIPT_DIR/fleet_repos.txt" ]; then
  # Is data-ru still listed? That is the whole question here.
  #
  # An earlier version pinned the literal `ack:parked for maintainer ruling
  # on ru revival:2026-09-07`. That armed a trap: the acknowledgement exists
  # to force a ruling by a date, and once the date passed, both ways of
  # acting on the ruling -- renewing the date or dropping the line because ru
  # came back -- failed this test. The self-test gates every later step in
  # fleet-health.yml, so the monitor would have stopped watching all fifteen
  # repositories on the day someone did the right thing.
  #
  # Replacing the literal with a grammar was the same mistake in a longer
  # form: a grammar here is a THIRD parser of this file, and it disagreed
  # with the runtime's `${line%%#*}` and `read -r repo ack_spec` in
  # fleet_health.sh. `data-ru # revived` and
  # `data-ru` with trailing spaces both failed a test the monitor itself
  # accepts, which is the trap again, one notch along.
  #
  # So: normalise the line exactly as the runtime normalises it, and assert
  # only presence. Well-formedness is already the generic check below,
  # applied to every line by one grammar; acknowledgement behaviour is
  # proved end to end by the fixture tests against three frozen clocks.
  ru_listed=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    read -r repo _rest <<<"$line" || true
    [ "${repo:-}" = data-ru ] && ru_listed=$((ru_listed + 1))
  done < "$SCRIPT_DIR/fleet_repos.txt"
  case "$ru_listed" in
    1) pass "data-ru is listed, in whatever state the ruling leaves it" ;;
    0) fail "data-ru line missing from fleet_repos.txt" ;;
    *) fail "data-ru is listed $ru_listed times; the runtime would poll it twice" ;;
  esac
  # Every non-comment line is either a bare repo or a well-formed ack.
  # `no-schedule:.*[^[:space:]]`, not `no-schedule:.+`: the runtime splits
  # fields with `read`, which strips trailing whitespace, so a reason of
  # nothing but spaces reaches it empty and is rejected. `.+` counted those
  # spaces as a reason and passed a line the monitor pages on.
  # The lead is an explicit space or tab: those are the only characters
  # bash's `read` strips from the front of a line (its default IFS).
  # [[:space:]] also matches CR/VT/FF, and [[:blank:]] also matches other
  # Unicode blanks in a UTF-8 locale. A line opening with any of those would
  # pass this validator while reaching the runtime with that character stuck
  # to $repo.
  lead=$' \t'
  line_re='^['"$lead"']*[A-Za-z0-9._-]+([[:space:]]+(ack:[^:]+([^:]|:)*:[0-9]{4}-[0-9]{2}-[0-9]{2}|no-schedule:.*[^[:space:]]))?[[:space:]]*$'
  bad_lines="$(sed 's/#.*//' "$SCRIPT_DIR/fleet_repos.txt" |
    grep -vE '^[[:space:]]*$' |
    grep -vE "$line_re" \
    || true)"
  # A line may carry at most one qualifier; "no-schedule:x ack:y:DATE"
  # would otherwise read as a no-schedule whose reason contains an ack.
  # Repeats of the SAME qualifier count too: the runtime rejects
  # "no-schedule:first no-schedule:second" -- both designators are
  # reserved substrings anywhere in a reason, not merely prefixes --
  # and a check that caught only the mixed pair let that one through.
  doubled_re='(ack:.*no-schedule:|no-schedule:.*ack:|ack:.*ack:|no-schedule:.*no-schedule:)'
  doubled="$(sed 's/#.*//' "$SCRIPT_DIR/fleet_repos.txt" |
    grep -E "$doubled_re" || true)"
  [ -z "$doubled" ] && pass "no shipped line carries two qualifiers" \
    || fail "lines with two qualifiers: $doubled"

  # A date the regex accepts is not necessarily a date. The runtime settles
  # it with `date -ud` in its own `ack:` branch and pages on a failure, so
  # a shipped `ack:...:2026-02-31` would page while passing this file's own
  # validation. Ask the same question the runtime asks.
  unreal=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    read -r repo ack_spec <<<"$line" || true
    case "${ack_spec:-}" in
      ack:*) d="${ack_spec##*:}"
             date -ud "$d" +%s >/dev/null 2>&1 || unreal="$unreal $repo:$d" ;;
    esac
  done < "$SCRIPT_DIR/fleet_repos.txt"
  [ -z "$unreal" ] && pass "every shipped review-by date is a real date" \
    || fail "review-by dates that are not real dates:$unreal"

  # The two checks above are one contract, and it has to match the
  # runtime parser: `ack:` and `no-schedule:` are reserved substrings
  # anywhere in a reason, not merely prefixes. Prove the pair rejects
  # what the parser rejects, in BOTH orders — the leading regex alone
  # accepts an ack whose reason contains "no-schedule:", and only the
  # doubled check catches it.
  for probe in \
    'data-x ack:contains no-schedule: prose:2026-09-07' \
    'data-x no-schedule:contains ack:bar:2026-09-07' \
    'data-x no-schedule:first no-schedule:second' \
    'data-x ack:first:2026-09-07 ack:second:2026-10-07'; do
    if printf '%s\n' "$probe" | grep -qvE "$line_re" ||
       printf '%s\n' "$probe" | grep -qE "$doubled_re"; then
      pass "validator rejects a doubled qualifier: ${probe#data-x }"
    else
      fail "validator accepted a line the parser rejects: $probe"
    fi
  done
  [ -z "$bad_lines" ] && pass "every repos-file line is well formed" \
    || fail "malformed repos-file lines: $bad_lines"

  # The runtime parses a line with `read -r repo ack_spec <<<"$line"`,
  # which strips leading whitespace, so an indented line works fine at
  # runtime. `line_re` must accept the same lines the runtime accepts, or
  # a maintainer who indents a line gets a red self-test against a
  # monitor that would have worked.
  for indented in \
    '  data-x' \
    $'\tdata-x ack:parked pending ruling:2098-09-07' \
    '  data-x no-schedule:archived'; do
    read -r runtime_repo _ <<<"$indented"
    if printf '%s\n' "$indented" | grep -qE "$line_re" &&
       [ "$runtime_repo" = "data-x" ]; then
      pass "validator accepts an indented line the runtime parses the same way: ${indented#$'\t'}"
    else
      fail "validator and runtime disagree on an indented line: $indented"
    fi
  done

  # The other direction: a line whose first character `read` does not strip
  # must be rejected, in a UTF-8 locale too.
  for lead_name in CR VT FF U+3000 U+2003; do
    case "$lead_name" in
      CR)     lead_char=$'\r' ;;
      VT)     lead_char=$'\v' ;;
      FF)     lead_char=$'\f' ;;
      U+3000) lead_char=$'\xe3\x80\x80' ;;
      U+2003) lead_char=$'\xe2\x80\x83' ;;
    esac
    if printf '%s\n' "${lead_char}data-x" | LC_ALL=C.UTF-8 grep -qE "$line_re"; then
      fail "validator accepted a line opening with $lead_name, which read does not strip"
    else
      pass "validator rejects a line opening with $lead_name"
    fi
  done
else
  fail "fleet_repos.txt missing"
fi

echo "== a repos file with no trailing newline must not drop its last repo =="
# `while read; do ... done` exits WITHOUT running the loop body for a
# final line that has no trailing newline: `read` returns nonzero for it,
# and a bare `while read` treats that the same as "no more input". Both
# repos here are healthy, so a passing run with both rows present is the
# only way to tell the last one was not silently skipped.
healthy_fixture data-newline-a
healthy_fixture data-newline-b
repos_no_trailing_newline="$TMP/repos_no_trailing_newline.txt"
printf 'data-newline-a\ndata-newline-b' > "$repos_no_trailing_newline"
report_no_trailing_newline="$TMP/report_no_trailing_newline.md"
run_health "$repos_no_trailing_newline" "$report_no_trailing_newline" > /dev/null
expect_status data-newline-a OK "$report_no_trailing_newline"
expect_status data-newline-b OK "$report_no_trailing_newline"

echo
if [ "$failures" -eq 0 ]; then
  echo "fleet_health_test: all checks passed"
else
  echo "fleet_health_test: $failures check(s) FAILED"
  exit 1
fi
