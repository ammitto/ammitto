#!/usr/bin/env bash
# Announce fleet-health STATE CHANGES on a single tracking issue.
#
# Called by .github/workflows/fleet-health.yml on every run, healthy or
# not. Idempotent by title: at most one open issue with the exact title
# exists at a time. Pull requests share the issues listing and could
# share the title, so anything carrying a pull_request key is ignored
# when matching.
#
# Only changes are announced
# --------------------------
# A daily job that comments every time the fleet is unhealthy trains
# everyone to ignore it, and the thing this monitor exists to prevent is
# exactly a signal nobody reads. So fleet_health.sh ends its report with
#
#   <!-- fleet-health-state: data-eu=UNHEALTHY data-ru=EXPIRED-ACK -->
#
# an order-independent signature of every PAGING repo (acknowledged
# repos are deliberately absent — acknowledging a repo must not open an
# issue about it). The same signature is stored in the tracking issue's
# body, so this script can compare today against the last announcement
# with no database, cache or artifact anywhere:
#
#   signature unchanged        -> say nothing, write nothing
#   new or different problems  -> comment the report, restore the body
#                                 to carry the new signature
#   signature now "healthy"    -> comment the recovery and CLOSE the
#                                 issue, because an open issue titled
#                                 "schedules unhealthy" over a healthy
#                                 fleet is the same kind of lie this
#                                 monitor was built to kill
#
# An acknowledgement expiring changes the signature (nothing ->
# repo=EXPIRED-ACK), so it announces itself through the same path.
#
# Guarded: outside GitHub Actions this script refuses to run unless
# FLEET_HEALTH_ALLOW_ISSUE_WRITE=1, so a local invocation of the monitor
# can never write to GitHub by accident.
#
# Usage: scripts/fleet_health_issue.sh <report.md>
# Environment:
#   FLEET_HEALTH_ISSUE_REPO   target repo (default $GITHUB_REPOSITORY)
#   FLEET_HEALTH_ISSUE_TITLE  match/create title (default below)
#   GH_TOKEN                  token with issues:write on the target repo
set -euo pipefail

REPORT="${1:?usage: fleet_health_issue.sh <report.md>}"
[ -f "$REPORT" ] || { echo "report file not found: $REPORT" >&2; exit 66; }
REPO="${FLEET_HEALTH_ISSUE_REPO:-${GITHUB_REPOSITORY:-}}"
TITLE="${FLEET_HEALTH_ISSUE_TITLE:-Fleet health: data-repo fetch schedules unhealthy}"

if [ "${GITHUB_ACTIONS:-}" != "true" ] &&
   [ "${FLEET_HEALTH_ALLOW_ISSUE_WRITE:-}" != "1" ]; then
  echo "refusing to write issues outside GitHub Actions" \
       "(set FLEET_HEALTH_ALLOW_ISSUE_WRITE=1 to override)" >&2
  exit 78
fi
[ -n "$REPO" ] || {
  echo "no target repo: set GITHUB_REPOSITORY or FLEET_HEALTH_ISSUE_REPO" >&2
  exit 64
}

marker_of() { # file
  sed -n 's/.*fleet-health-state:[[:space:]]*\(.*\)[[:space:]]*-->.*/\1/p' \
    "$1" | tail -n 1 | sed 's/[[:space:]]*$//'
}

new_state="$(marker_of "$REPORT")"
# No marker means the report did not come from this version of
# fleet_health.sh. Refusing loudly beats guessing "healthy".
[ -n "$new_state" ] || {
  echo "no fleet-health-state marker in $REPORT — is it a fleet_health.sh report?" >&2
  exit 65
}

open_json="$(gh api "repos/$REPO/issues?state=open&per_page=100")"
existing="$(jq -r --arg t "$TITLE" \
  '[.[] | select(has("pull_request") | not) | select(.title == $t)]
   | .[0].number // empty' <<<"$open_json")"
old_state=""
if [ -n "$existing" ]; then
  TMP_BODY="$(mktemp)"
  trap 'rm -f "$TMP_BODY"' EXIT
  jq -r --arg t "$TITLE" \
    '[.[] | select(has("pull_request") | not) | select(.title == $t)]
     | .[0].body // ""' <<<"$open_json" > "$TMP_BODY"
  old_state="$(marker_of "$TMP_BODY")"
fi

# The unchanged check comes FIRST, before the healthy/unhealthy split.
# Ordering it the other way makes a healthy fleet with an open issue
# comment "recovered" and close it on every single run.
if [ -z "$existing" ]; then
  if [ "$new_state" = "healthy" ]; then
    echo "fleet healthy, no open tracking issue — nothing to announce"
    exit 0
  fi
  gh issue create --repo "$REPO" --title "$TITLE" --body-file "$REPORT"
  echo "new tracking issue created for state: $new_state"
  exit 0
fi

if [ "$old_state" = "$new_state" ]; then
  echo "no state change since the last announcement ($new_state) — staying quiet"
  exit 0
fi

if [ "$new_state" = "healthy" ]; then
  RECOVERY="$(mktemp)"
  trap 'rm -f "$TMP_BODY" "$RECOVERY"' EXIT
  {
    printf '%s\n\n' "Recovered — every watched schedule is healthy again. Closing; a new incident opens a fresh issue."
    cat "$REPORT"
  } > "$RECOVERY"
  gh issue comment "$existing" --repo "$REPO" --body-file "$RECOVERY"
  gh issue close "$existing" --repo "$REPO"
  echo "fleet recovered — commented and closed tracking issue #$existing"
  exit 0
fi

gh issue comment "$existing" --repo "$REPO" --body-file "$REPORT"
gh issue edit "$existing" --repo "$REPO" --body-file "$REPORT"
echo "state changed on #$existing: '${old_state:-none}' -> '$new_state'"
