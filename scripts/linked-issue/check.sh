#!/usr/bin/env bash
# Reads the pull request's live state and applies decide.sh.
#
# Live, not from the event payload: a ruleset-required workflow only runs on
# opened/synchronize/reopened, so after "Closes #n" is added to the body (or the
# no-issue label is set) a plain "Re-run" must see the new state.
#
# Env: GH_TOKEN, REPOSITORY (owner/name), PR_NUMBER; GITHUB_STEP_SUMMARY optional.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
owner="${REPOSITORY%%/*}"
name="${REPOSITORY#*/}"

response="$(gh api graphql \
  -F owner="$owner" -F name="$name" -F number="$PR_NUMBER" \
  -f query="$(cat "$here/query.graphql")")"

set +e
decision="$("$here/decide.sh" <<<"$response")"
status=$?
set -e

echo "$decision"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
if (( status == 0 )); then
  echo "Linked issue check passed: \`$decision\`" >>"$summary"
  exit 0
fi

message="Bu PR hiçbir issue'yu kapatmıyor. PR açıklamasına 'Closes #<n>' (başka repo için 'Closes datarul/<repo>#<n>') yazın ya da issue'yu Development bölümünden bağlayın, sonra bu kontrolü Re-run ile yeniden çalıştırın. Issue gerektirmeyen PR'da gerekçeyi açıklamaya yazıp 'no-issue' etiketini ekleyin. / This PR closes no issue: add 'Closes #<n>' to the description, then re-run this check."
echo "::error title=No linked issue::$message"
{
  echo "### No linked issue"
  echo
  echo "$message"
} >>"$summary"
exit 1
