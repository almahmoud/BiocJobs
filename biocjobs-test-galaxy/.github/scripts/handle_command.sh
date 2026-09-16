#!/usr/bin/env bash
# Handle /deploy, /undeploy and /help comments on pull requests.
#
# A pull request is deployed while it has the "deployed" label and its latest commit has
# a "testgalaxy/deploy" success status linked to it.
set -euo pipefail

: "${COMMENT_BODY?}" "${COMMENT_ID:?}" "${ACTOR:?}" "${PR_NUMBER:?}" "${GITHUB_REPOSITORY:?}" \
  "${GITHUB_SERVER_URL:?}" "${GH_TOKEN:?}" "${DEFAULT_BRANCH:?}"
output="${GITHUB_OUTPUT:-/dev/null}"
status_context="testgalaxy/deploy"
galaxy_url="https://testgalaxy.bioconductor.org"
pr_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/pull/$PR_NUMBER"
label="deployed"

first_line="$(printf '%s\n' "$COMMENT_BODY" | head -n 1 | tr -d '\r')"
read -r command argument extra <<<"$first_line" || true

reply() { gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$1" >/dev/null; }
react() { gh api -X POST "repos/$GITHUB_REPOSITORY/issues/comments/$COMMENT_ID/reactions" -f content="$1" >/dev/null 2>&1 || true; }
tool_ids() { awk -F/ '$1 == "tools" && NF >= 3 { print $2 }' | sort -u; }
pr_tools() {
  gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$1/files" \
    --jq '.[] | select(.status != "removed") | .filename' | tool_ids
}
# shellcheck disable=SC2016 # Markdown code spans
code_list() { sed 's/`//g; s/.*/`&`/' | paste -sd ',' - | sed 's/,/, /g'; }

case "${command:-}" in
  /help)
    reply "| Command | |
|---|---|
| \`/deploy <sha>\` | Deploy this pull request at commit \`<sha>\` to $galaxy_url. \`<sha>\` must be the current head. |
| \`/undeploy\` | Remove this pull request's tools from the test instance. |
| \`/help\` | Show this list. |

\`/deploy\` and \`/undeploy\` need write access. Pushing new commits removes the pull request from the test instance."
    exit 0
    ;;
  /deploy|/undeploy) ;;
  *) exit 0 ;;
esac

permission="$(gh api "repos/$GITHUB_REPOSITORY/collaborators/$ACTOR/permission" --jq .permission 2>/dev/null || echo none)"
case "$permission" in
  admin|maintain|write) ;;
  *)
    react "-1"
    reply "@$ACTOR \`$command\` needs write access to this repository."
    exit 0
    ;;
esac

state_and_head="$(gh pr view "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --json state,headRefOid --jq '"\(.state) \(.headRefOid)"')"
state="${state_and_head%% *}"
head="${state_and_head##* }"
if [ "$state" != "OPEN" ]; then
  reply "\`$command\` only works on open pull requests."
  exit 0
fi

if [ "$command" = "/undeploy" ]; then
  gh api -X POST "repos/$GITHUB_REPOSITORY/statuses/$head" \
    -f state=pending -f context="$status_context" -f target_url="$pr_url" \
    -f description="Removed by @$ACTOR" >/dev/null
  gh pr edit "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --remove-label "$label" >/dev/null 2>&1 || true
  react "+1"
  { echo "reconcile=true"; echo "action=undeploy"; } >> "$output"
  exit 0
fi

if [ -n "${extra:-}" ] || ! [[ "${argument:-}" =~ ^[0-9a-f]{7,40}$ ]]; then
  react "confused"
  reply "Usage: \`/deploy <sha>\`. The head of this pull request is \`${head:0:12}\`."
  exit 0
fi
if [[ "$head" != "$argument"* ]]; then
  react "confused"
  reply "\`$argument\` is not the head of this pull request. The head is \`${head:0:12}\`."
  exit 0
fi

outside="$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/files" \
  --jq '.[] | .filename, (.previous_filename // empty)' | grep -v '^tools/' | sort -u || true)"
if [ -n "$outside" ]; then
  react "-1"
  reply "Only pull requests that change nothing outside \`tools/\` can be deployed. This one also changes $(code_list <<<"$outside")."
  exit 0
fi

mine="$(pr_tools "$PR_NUMBER")"
if [ -z "$mine" ]; then
  react "confused"
  reply "This pull request does not add or change a tool."
  exit 0
fi

stale="$(comm -12 <(printf '%s\n' "$mine") <(gh api "repos/$GITHUB_REPOSITORY/compare/$head...$DEFAULT_BRANCH" --jq '.files[].filename' | tool_ids))"
if [ -n "$stale" ]; then
  react "-1"
  reply "$(code_list <<<"$stale") changed on \`$DEFAULT_BRANCH\` after this pull request branched. Rebase or merge \`$DEFAULT_BRANCH\` first."
  exit 0
fi

for other in $(gh pr list --repo "$GITHUB_REPOSITORY" --state open --label "$label" --limit 500 --json number --jq '.[].number'); do
  [ "$other" != "$PR_NUMBER" ] || continue
  shared="$(comm -12 <(printf '%s\n' "$mine") <(pr_tools "$other"))"
  if [ -n "$shared" ]; then
    react "-1"
    reply "#$other already deploys $(code_list <<<"$shared"). Run \`/undeploy\` there first."
    exit 0
  fi
done

validation="$(gh api "repos/$GITHUB_REPOSITORY/commits/$head/check-runs?check_name=Validate%20tools&per_page=100" \
  --jq '[.check_runs[] | select(.app.slug == "github-actions")] | sort_by(.started_at) | last | .conclusion // ""')"
if [ "$validation" != "success" ]; then
  react "-1"
  reply "**Validate tools** has not passed on \`${head:0:12}\` (${validation:-not run yet})."
  exit 0
fi

gh api -X POST "repos/$GITHUB_REPOSITORY/statuses/$head" \
  -f state=success -f context="$status_context" -f target_url="$pr_url" \
  -f description="Deployed by @$ACTOR" >/dev/null
gh label create "$label" --repo "$GITHUB_REPOSITORY" --color 0E8A16 \
  --description "On the test instance" >/dev/null 2>&1 || true
gh pr edit "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --add-label "$label" >/dev/null
react "rocket"
{ echo "reconcile=true"; echo "action=deploy"; } >> "$output"
