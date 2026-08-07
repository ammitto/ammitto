#!/usr/bin/env bash
# Offline proof of the fleet-health monitor. No network, no writes.
#
# Generates synthetic API fixtures for the failure modes the monitor
# exists to catch, runs the real detection script against them, and
# asserts the verdicts. Also proves the tracking-issue upsert is
# idempotent using a stubbed gh. The fleet-health workflow runs this
# before every live check: a monitor whose own parser silently broke
# would otherwise report "healthy" forever — the exact failure mode
# this whole feature exists to kill.
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
completed_fixture() { # repo conclusion...
  local repo="$1" runs="" c
  shift
  for c in "$@"; do
    runs="$runs{\"conclusion\":\"$c\"},"
  done
  printf '{"workflow_runs":[%s]}' "${runs%,}" \
    > "$FIX/${repo}__completed_runs.json"
}

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

# Case 2 — failure streak: schedule alive and recent, but the last three
# completed runs all failed. A cancelled run in between must not break
# the streak.
workflow_fixture data-failing active
schedule_fixture data-failing '5 hours ago' failure
completed_fixture data-failing failure failure cancelled failure success success

# Case 3 — healthy but quiet: ran on schedule this morning, succeeded,
# committed nothing (invisible to run conclusions, which is the point).
# Must NOT be flagged. data-au has legitimate zero-delta days.
workflow_fixture data-quiet active
schedule_fixture data-quiet '6 hours ago' success
completed_fixture data-quiet success success success

# Boundary — two consecutive failures is below the streak limit and the
# schedule is alive: not flagged.
workflow_fixture data-two-fails active
schedule_fixture data-two-fails '4 hours ago' failure
completed_fixture data-two-fails failure failure success success

# Unreadable — no fixtures at all for data-ghost: missing workflow or
# dead API must flag, not pass silently.

repos_all="$TMP/repos_all.txt"
printf '%s\n' data-dead data-stale data-failing data-quiet \
  data-two-fails data-ghost > "$repos_all"
repos_healthy="$TMP/repos_healthy.txt"
printf '%s\n' data-quiet data-two-fails > "$repos_healthy"

echo "== detection: mixed fleet must exit 1 with exact verdicts =="
rc=0
FLEET_HEALTH_FIXTURES="$FIX" FLEET_HEALTH_REPOS_FILE="$repos_all" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report.md" \
  > /dev/null || rc=$?
[ "$rc" -eq 1 ] && pass "mixed fleet exits 1" || fail "mixed fleet exit was $rc"

expect_unhealthy() {
  if grep -E "^\| $1 \| UNHEALTHY " "$TMP/report.md" > /dev/null; then
    pass "$1 flagged"
  else
    fail "$1 not flagged"
  fi
}
expect_healthy() {
  if grep -E "^\| $1 \| OK " "$TMP/report.md" > /dev/null; then
    pass "$1 healthy"
  else
    fail "$1 wrongly flagged"
  fi
}
expect_reason() {
  if grep -F "**$1**" "$TMP/report.md" | grep -qF "$2"; then
    pass "$1 reason mentions: $2"
  else
    fail "$1 reason missing: $2"
  fi
}

expect_unhealthy data-dead
expect_reason data-dead "disabled_inactively"
expect_unhealthy data-stale
expect_reason data-stale "72h ago (limit 48h)"
expect_unhealthy data-failing
expect_reason data-failing "3 consecutive failed runs"
expect_unhealthy data-ghost
expect_reason data-ghost "missing or API unreadable"
expect_healthy data-quiet
expect_healthy data-two-fails
grep -qE '4 of 6 repos unhealthy' "$TMP/report.md" \
  && pass "summary counts 4 of 6" || fail "summary count wrong"

echo "== detection: all-healthy fleet must exit 0 =="
rc=0
FLEET_HEALTH_FIXTURES="$FIX" FLEET_HEALTH_REPOS_FILE="$repos_healthy" \
  "$SCRIPT_DIR/fleet_health.sh" --report "$TMP/report_ok.md" \
  > /dev/null || rc=$?
[ "$rc" -eq 0 ] && pass "healthy fleet exits 0" || fail "healthy exit was $rc"
grep -q 'All 2 repos healthy' "$TMP/report_ok.md" \
  && pass "healthy summary present" || fail "healthy summary missing"

echo "== issue upsert: create once, then comment, never duplicate =="
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
echo '[]' > "$TMP/issues_none.json"
# The open list holds a PR with the exact title (must be ignored) and
# the real issue #42 (must be matched).
printf '[{"number":7,"title":"%s","pull_request":{}},{"number":42,"title":"%s"}]' \
  "$title" "$title" > "$TMP/issues_open.json"

run_upsert() { # issues-json log-file
  PATH="$TMP/bin:$PATH" GH_LOG="$2" GH_ISSUES_JSON="$1" \
    FLEET_HEALTH_ALLOW_ISSUE_WRITE=1 \
    FLEET_HEALTH_ISSUE_REPO=ammitto/ammitto \
    "$SCRIPT_DIR/fleet_health_issue.sh" "$TMP/report.md" > /dev/null
}

: > "$TMP/log1"; run_upsert "$TMP/issues_none.json" "$TMP/log1"
grep -q '^gh issue create ' "$TMP/log1" \
  && pass "no open issue -> creates" || fail "create path broken"
grep -q '^gh issue comment ' "$TMP/log1" \
  && fail "created AND commented" || pass "create path does not comment"

: > "$TMP/log2"; run_upsert "$TMP/issues_open.json" "$TMP/log2"
grep -q '^gh issue comment 42 ' "$TMP/log2" \
  && pass "open issue #42 -> comments (PR with same title ignored)" \
  || fail "comment path broken"
grep -q '^gh issue create ' "$TMP/log2" \
  && fail "duplicate issue created" || pass "comment path does not create"

echo "== issue upsert: refuses to write outside Actions =="
rc=0
: > "$TMP/log3"
PATH="$TMP/bin:$PATH" GH_LOG="$TMP/log3" GH_ISSUES_JSON="$TMP/issues_none.json" \
  GITHUB_ACTIONS= FLEET_HEALTH_ALLOW_ISSUE_WRITE= \
  FLEET_HEALTH_ISSUE_REPO=ammitto/ammitto \
  "$SCRIPT_DIR/fleet_health_issue.sh" "$TMP/report.md" \
  > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 78 ] && pass "guard refuses (exit 78)" || fail "guard exit was $rc"
[ -s "$TMP/log3" ] && fail "guard still called gh" || pass "guard called no gh"

echo
if [ "$failures" -eq 0 ]; then
  echo "fleet_health_test: all checks passed"
else
  echo "fleet_health_test: $failures check(s) FAILED"
  exit 1
fi
