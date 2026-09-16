#!/usr/bin/env bash
# Collect the tools to deploy: tools/ from the checked-out default branch, plus the
# tools changed by each open pull request deployed with /deploy (the "deployed" label
# and an approval status on its latest commit). Older pull requests win conflicts.
#
# Usage: collect_tools.sh STAGING_DIR
# Writes STAGING_DIR/sources, the source list for render_values.py.
set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${GITHUB_SERVER_URL:?}" "${GH_TOKEN:?}" "${DEFAULT_BRANCH:?}"
staging="${1:?usage: collect_tools.sh STAGING_DIR}"
status_context="testgalaxy/deploy"
status_creator="github-actions[bot]"

rm -rf "$staging"
mkdir -p "$staging/main"
if [ -d tools ]; then
  cp -R tools "$staging/main/tools"
else
  mkdir -p "$staging/main/tools"
fi
sources=("main=$staging/main/tools")

open_prs="$(gh pr list --repo "$GITHUB_REPOSITORY" --state open --label deployed --limit 500 \
  --json number,headRefOid --jq 'sort_by(.number) | .[] | "\(.number) \(.headRefOid)"')"

while read -r number sha; do
  [ -n "${number:-}" ] || continue

  approval="$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/statuses?per_page=100" \
    --jq "[.[] | select(.context == \"$status_context\")] | first | \"\(.state // \"\")\t\(.creator.login // \"\")\t\(.target_url // \"\")\"")"
  IFS=$'\t' read -r state creator target_url <<<"$approval"
  [ "$state" = "success" ] || continue
  if [ "$creator" != "$status_creator" ] || [ "$target_url" != "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/pull/$number" ]; then
    echo "::warning::Ignoring approval status on #$number that was not set by /deploy on that pull request"
    continue
  fi

  git fetch --no-tags --quiet origin "+refs/pull/$number/head:refs/remotes/pr/$number"
  if [ "$(git rev-parse "refs/remotes/pr/$number")" != "$sha" ]; then
    echo "::warning::#$number changed during the deploy; the next deploy will pick it up"
    continue
  fi
  if git ls-tree -r "$sha" -- tools | awk '$1 == "120000" { found = 1 } END { exit !found }'; then
    echo "::warning::Skipping #$number: symbolic links under tools/"
    continue
  fi

  # A pull request branch also holds older copies of tools it did not change, so only
  # take the tools it changed, and skip any that main has changed since it branched.
  changed_on_main="$(gh api "repos/$GITHUB_REPOSITORY/compare/$sha...$DEFAULT_BRANCH" \
    --jq '.files[].filename' | awk -F/ '$1 == "tools" && NF >= 3 { print $2 }' | sort -u)"
  changed_in_pr="$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$number/files" \
    --jq '.[] | select(.status != "removed") | .filename' \
    | awk -F/ '$1 == "tools" && NF >= 3 { print $2 }' | sort -u)"

  mkdir -p "$staging/pr-$number/tools"
  while read -r tool_id; do
    [ -n "$tool_id" ] || continue
    if ! [[ "$tool_id" =~ ^[a-z][a-z0-9_]{1,31}$ ]]; then
      echo "::warning::#$number: ignoring tools/$tool_id, not a valid tool id"
      continue
    fi
    if grep -qx "$tool_id" <<<"$changed_on_main"; then
      echo "::warning::#$number: skipping $tool_id, which changed on $DEFAULT_BRANCH after the pull request branched"
      continue
    fi
    if git cat-file -e "$sha:tools/$tool_id" 2>/dev/null; then
      git --literal-pathspecs archive "$sha" "tools/$tool_id" | tar -x --no-same-owner -C "$staging/pr-$number"
    fi
  done <<<"$changed_in_pr"

  sources+=("pr-$number=$staging/pr-$number/tools")
  echo "Including #$number at ${sha:0:12}"
done <<<"$open_prs"

printf '%s\n' "${sources[@]}" > "$staging/sources"
