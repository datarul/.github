#!/usr/bin/env bash
# Decides whether a pull request satisfies "every PR closes an issue".
#
# Input (stdin): the GraphQL response of query.graphql.
# Output: one line "<pass|fail> <reason> [detail]"; exit 0 on pass, 1 on fail.
# Kept free of network calls so the decision is testable from fixtures.
set -euo pipefail

NO_ISSUE_LABEL="${NO_ISSUE_LABEL:-no-issue}"

json="$(cat)"
pr() { jq -r ".data.repository.pullRequest$1" <<<"$json"; }

if [[ "$(jq -r '.data.repository.pullRequest == null' <<<"$json")" == "true" ]]; then
  echo "fail missing-pr pull request not found"
  exit 1
fi

author_type="$(pr '.author.__typename // ""')"
author_login="$(pr '.author.login // ""')"
if [[ "$author_type" == "Bot" || "$author_login" == *"[bot]" ]]; then
  echo "pass bot ${author_login}"
  exit 0
fi

base="$(pr '.baseRefName')"
default_branch="$(jq -r '.data.repository.defaultBranchRef.name // ""' <<<"$json")"
if [[ -n "$default_branch" && "$base" != "$default_branch" ]]; then
  echo "pass non-default-base ${base}"
  exit 0
fi

if [[ "$(jq -r --arg l "$NO_ISSUE_LABEL" '.data.repository.pullRequest.labels.nodes | any(.name == $l)' <<<"$json")" == "true" ]]; then
  echo "pass no-issue-label ${NO_ISSUE_LABEL}"
  exit 0
fi

count="$(pr '.closingIssuesReferences.totalCount // 0')"
if (( count > 0 )); then
  refs="$(pr '.closingIssuesReferences.nodes | map("\(.repository.nameWithOwner)#\(.number)") | join(",")')"
  echo "pass linked ${refs}"
  exit 0
fi

echo "fail unlinked no closing issue reference"
exit 1
