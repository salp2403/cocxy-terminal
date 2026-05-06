#!/bin/bash
# smoke-github-pr-readonly.sh - Live read-only GitHub PR smoke.
#
# Usage:
#   ./scripts/smoke-github-pr-readonly.sh --repo owner/name --pr 123
#
# This script performs read-only `gh` operations only. It validates the
# repository, PR metadata, diff names, checks, and review-thread GraphQL shape.

set -euo pipefail

REPO=""
PR_NUMBER=""

usage() {
    sed -n '1,8p' "$0"
}

fail() {
    echo "error: $1" >&2
    exit 1
}

require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "required tool not found: $tool"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)
            REPO="${2:?missing repo}"
            shift 2
            ;;
        --pr)
            PR_NUMBER="${2:?missing PR number}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

require_tool gh
require_tool jq

case "$REPO" in
    */*) ;;
    *) fail "--repo must be in owner/name form" ;;
esac

case "$PR_NUMBER" in
    ''|*[!0-9]*) fail "--pr must be a positive integer" ;;
    0) fail "--pr must be a positive integer" ;;
esac

OWNER="${REPO%%/*}"
NAME="${REPO#*/}"

echo "==> Cocxy GitHub PR read-only smoke"
echo ""

echo "[Auth]"
gh auth status >/dev/null
echo "auth-ok"

echo ""
echo "[Repository]"
repo_json="$(gh repo view "$REPO" --json owner,name,url,defaultBranchRef,isPrivate)"
repo_full_name="$(jq -r '.owner.login + "/" + .name' <<<"$repo_json")"
if [ "$repo_full_name" != "$REPO" ]; then
    fail "repository mismatch: expected $REPO, got $repo_full_name"
fi
repo_url="$(jq -r '.url' <<<"$repo_json")"
echo "repo-ok $repo_full_name $repo_url"

echo ""
echo "[Open PR inventory]"
open_prs_json="$(gh pr list --repo "$REPO" --state open --limit 20 --json number,title,state,url)"
jq -e 'type == "array"' <<<"$open_prs_json" >/dev/null
echo "open-pr-count=$(jq 'length' <<<"$open_prs_json")"

echo ""
echo "[PR metadata]"
pr_json="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json number,title,state,author,url,headRefName,baseRefName,files,comments,reviews,reviewDecision,statusCheckRollup)"
jq -e --argjson pr "$PR_NUMBER" '
    .number == $pr
    and (.title | type == "string")
    and (.state | type == "string")
    and (.url | type == "string")
    and (.files | type == "array")
    and (.comments | type == "array")
    and (.reviews | type == "array")
' <<<"$pr_json" >/dev/null
pr_url="$(jq -r '.url' <<<"$pr_json")"
expected_prefix="https://github.com/$REPO/pull/$PR_NUMBER"
case "$pr_url" in
    "$expected_prefix") ;;
    "$expected_prefix"*) ;;
    *) fail "unexpected PR URL: $pr_url" ;;
esac
pr_state="$(jq -r '.state' <<<"$pr_json")"
file_count="$(jq '.files | length' <<<"$pr_json")"
if [ "$file_count" -eq 0 ]; then
    fail "PR has no changed files in gh metadata"
fi
echo "pr-view-ok #$PR_NUMBER state=$pr_state files=$file_count"

echo ""
echo "[PR diff]"
diff_names="$(gh pr diff "$PR_NUMBER" --repo "$REPO" --name-only)"
if [ -z "$diff_names" ]; then
    fail "PR diff returned no changed filenames"
fi
diff_count="$(printf '%s\n' "$diff_names" | sed '/^$/d' | wc -l | tr -d ' ')"
echo "pr-diff-ok files=$diff_count"

echo ""
echo "[Checks]"
checks_stderr="$(mktemp /tmp/cocxy-pr-checks.XXXXXX)"
trap 'rm -f "$checks_stderr"' EXIT
set +e
checks_json="$(gh pr checks "$PR_NUMBER" --repo "$REPO" --json name,state,bucket,link,startedAt,completedAt 2>"$checks_stderr")"
checks_status="$?"
set -e
if [ "$checks_status" -eq 0 ]; then
    jq -e 'type == "array"' <<<"$checks_json" >/dev/null
    echo "checks-ok count=$(jq 'length' <<<"$checks_json")"
elif [ "$checks_status" -eq 8 ] || grep -qi "no checks" "$checks_stderr"; then
    echo "checks-ok count=0"
else
    cat "$checks_stderr" >&2
    fail "gh pr checks failed"
fi

echo ""
echo "[Review threads]"
review_threads_query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){number reviewThreads(first:50){totalCount nodes{id isResolved isOutdated viewerCanResolve viewerCanUnresolve path line startLine comments(first:10){nodes{id body author{login} createdAt url}}}}}}}'
threads_json="$(
    gh api graphql \
        -F "owner=$OWNER" \
        -F "name=$NAME" \
        -F "number=$PR_NUMBER" \
        -f "query=$review_threads_query"
)"
jq -e --argjson pr "$PR_NUMBER" '
    .data.repository.pullRequest.number == $pr
    and (.data.repository.pullRequest.reviewThreads.nodes | type == "array")
' <<<"$threads_json" >/dev/null
thread_count="$(jq '.data.repository.pullRequest.reviewThreads.totalCount' <<<"$threads_json")"
echo "review-threads-ok count=$thread_count"

echo ""
echo "GitHub PR read-only smoke passed"
