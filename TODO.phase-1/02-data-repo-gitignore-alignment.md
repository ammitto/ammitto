= Align data-repo gitignores with fetch output
Defect: 14/15 data repos gitignore processed/* — fetched data discarded for weeks.
Fix: PRs to each affected data repo unignoring the output dir (USER authorizes writes).
Accept: fetch output commits in a canary run. Size S per repo, mechanical.
