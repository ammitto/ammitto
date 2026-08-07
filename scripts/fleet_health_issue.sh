#!/usr/bin/env bash
# Create-or-update the SINGLE fleet-health tracking issue.
#
# Called by .github/workflows/fleet-health.yml only when the fleet is
# unhealthy. Idempotent by title: if an open issue with the exact title
# already exists, the fresh report is added as a comment; otherwise one
# issue is created. One alert channel, never fifteen, never a duplicate
# per day.
#
# Pull requests share the issues listing and could share the title, so
# anything carrying a pull_request key is ignored when matching.
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

existing="$(gh api "repos/$REPO/issues?state=open&per_page=100" |
  jq -r --arg t "$TITLE" \
    '[.[] | select(has("pull_request") | not) | select(.title == $t)]
     | .[0].number // empty')"

if [ -n "$existing" ]; then
  gh issue comment "$existing" --repo "$REPO" --body-file "$REPORT"
  echo "updated existing tracking issue #$existing"
else
  gh issue create --repo "$REPO" --title "$TITLE" --body-file "$REPORT"
  echo "created new tracking issue"
fi
