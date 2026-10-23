#!/usr/bin/env bash
# Fixture tests for decide.sh. Run: bash scripts/linked-issue/tests/decide.test.sh
set -uo pipefail

decide="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/decide.sh"
failures=0

# fixture <author-type> <login> <base> <default> <labels-json> <closing-nodes-json>
fixture() {
  jq -n --arg type "$1" --arg login "$2" --arg base "$3" --arg default "$4" \
    --argjson labels "$5" --argjson closing "$6" '{
      data: { repository: {
        defaultBranchRef: { name: $default },
        pullRequest: {
          baseRefName: $base,
          author: { __typename: $type, login: $login },
          labels: { nodes: ($labels | map({ name: . })) },
          closingIssuesReferences: { totalCount: ($closing | length), nodes: $closing }
        } } } }'
}

# expect <name> <exit-code> <output-prefix> <json>
expect() {
  local out code
  out="$("$decide" <<<"$4")"
  code=$?
  if [[ "$code" == "$2" && "$out" == "$3"* ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: exit=$code out='$out' (want exit=$2, '$3…')"
    failures=$((failures + 1))
  fi
}

issue='[{"number":208,"repository":{"nameWithOwner":"datarul/fe-app-v3"}}]'
cross='[{"number":1284,"repository":{"nameWithOwner":"datarul/be-net"}},{"number":5,"repository":{"nameWithOwner":"datarul/fe-app-v3"}}]'

expect "linked issue passes" 0 "pass linked datarul/fe-app-v3#208" \
  "$(fixture User dev develop develop '[]' "$issue")"
expect "cross-repo references are listed" 0 "pass linked datarul/be-net#1284,datarul/fe-app-v3#5" \
  "$(fixture User dev develop develop '[]' "$cross")"
expect "unlinked PR fails" 1 "fail unlinked" \
  "$(fixture User dev develop develop '[]' '[]')"
expect "unrelated labels do not exempt" 1 "fail unlinked" \
  "$(fixture User dev develop develop '["bug","no-issue-later"]' '[]')"
expect "no-issue label exempts" 0 "pass no-issue-label" \
  "$(fixture User dev develop develop '["security","no-issue"]' '[]')"
expect "bot author exempts" 0 "pass bot dependabot" \
  "$(fixture Bot dependabot develop develop '[]' '[]')"
expect "[bot] login exempts" 0 "pass bot renovate[bot]" \
  "$(fixture User 'renovate[bot]' develop develop '[]' '[]')"
expect "promotion to non-default branch exempts" 0 "pass non-default-base main" \
  "$(fixture User dev main develop '[]' '[]')"
expect "missing pull request fails" 1 "fail missing-pr" \
  '{"data":{"repository":{"defaultBranchRef":{"name":"develop"},"pullRequest":null}}}'

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
