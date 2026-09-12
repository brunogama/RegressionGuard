#!/usr/bin/env bash
# Poll a pull request for failed checks and newly visible review feedback.
set -euo pipefail

usage() {
  printf 'Usage: %s [PR_NUMBER] [--once]\n' "$0" >&2
}

pr_number=""
watch=false

for argument in "$@"; do
  case "$argument" in
  --once)
    ;;
  --watch)
    watch=true
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  [0-9]*)
    pr_number="$argument"
    ;;
  *)
    usage
    exit 2
    ;;
  esac
done

if [[ -z "$pr_number" ]]; then
  pr_number="$(gh pr view --json number --jq '.number')"
fi

repository="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"

report() {
  local head_sha
  head_sha="$(gh pr view "$pr_number" --json headRefOid --jq '.headRefOid')"

  printf '=== PR #%s (%s) ===\n' "$pr_number" "$repository"
  gh pr view "$pr_number" --json url,title,state --jq '"\(.state): \(.title)\n\(.url)"'

  printf '\n=== Failed workflow runs for %s ===\n' "$head_sha"
  local failed_run_ids
  failed_run_ids="$(gh run list --commit "$head_sha" --status failure --json databaseId --jq '.[].databaseId')"
  if [[ -z "$failed_run_ids" ]]; then
    printf 'None\n'
  else
    while IFS= read -r run_id; do
      [[ -z "$run_id" ]] && continue
      printf '\n--- Failed run %s ---\n' "$run_id"
      gh run view "$run_id" --log-failed || true
    done <<<"$failed_run_ids"
  fi

  printf '\n=== Reviews ===\n'
  gh api "repos/$repository/pulls/$pr_number/reviews?per_page=100" \
    --jq '.[] | "\(.user.login): \(.state) at \(.submitted_at // "pending")\n\(.body // "")"' ||
    true

  printf '\n=== Inline review comments ===\n'
  gh api "repos/$repository/pulls/$pr_number/comments?per_page=100" \
    --jq '.[] | "\(.user.login) on \(.path):\(.line // .original_line // 0)\n\(.body)"' ||
    true
}

if ! $watch; then
  report
  exit 0
fi

while true; do
  report
  printf '\nNext poll in 60 seconds. Stop with Ctrl-C.\n\n'
  sleep 60
done
