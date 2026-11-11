#!/usr/bin/env bash
# Reads the pull request's live state and applies decide.sh.
#
# Live, not from the event payload: a ruleset-required workflow only runs on
# opened/synchronize/reopened, so after "Closes #n" is added to the body (or the
# no-issue label is set) a plain "Re-run" must see the new state.
#
# Env: GH_TOKEN, REPOSITORY (owner/name), PR_NUMBER; GITHUB_STEP_SUMMARY optional.
#   DOCS_EXEMPT_EXCLUDED_REPOS: space-separated repo names that never take the
#   docs-only exemption (their product is the document itself).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
owner="${REPOSITORY%%/*}"
name="${REPOSITORY#*/}"

response="$(gh api graphql \
  -F owner="$owner" -F name="$name" -F number="$PR_NUMBER" \
  -f query="$(cat "$here/query.graphql")")"

# Changed paths for the docs-only exemption. The list is handed to decide.sh only
# when it is complete: the files API caps a listing, so the number of listed files
# must equal the PR's changedFiles. Anything else leaves it empty = no exemption.
changed="$(mktemp)"
listing="$(mktemp)"
trap 'rm -f "$changed" "$listing"' EXIT
excluded=" ${DOCS_EXEMPT_EXCLUDED_REPOS:-} "
if [[ "$excluded" != *" $name "* ]]; then
  expected="$(jq -r '.data.repository.pullRequest.changedFiles // empty' <<<"$response")"
  if gh api --paginate "repos/$REPOSITORY/pulls/$PR_NUMBER/files?per_page=100" \
    --jq '.[] | [.filename, (.previous_filename // "")] | @tsv' >"$listing" 2>/dev/null; then
    listed="$(wc -l <"$listing" | tr -d ' ')"
    if [[ -n "$expected" && "$listed" == "$expected" ]]; then
      tr '\t' '\n' <"$listing" | sed '/^$/d' >"$changed"
    fi
  fi
fi
export CHANGED_FILES_FILE="$changed"

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

message="Bu PR hiçbir issue'yu kapatmıyor. PR açıklamasına 'Closes #<n>' (başka repo için 'Closes datarul/<repo>#<n>') yazın ya da issue'yu Development bölümünden bağlayın, sonra bu kontrolü Re-run ile yeniden çalıştırın. Yalnız Markdown dosyası değiştiren PR'lar issue gerektirmez (doküman repoları hariç). Başka bir nedenle issue gerektirmeyen PR'da gerekçeyi açıklamaya yazıp 'no-issue' etiketini ekleyin. / This PR closes no issue: add 'Closes #<n>' to the description, then re-run this check."
echo "::error title=No linked issue::$message"
{
  echo "### No linked issue"
  echo
  echo "$message"
} >>"$summary"
exit 1
