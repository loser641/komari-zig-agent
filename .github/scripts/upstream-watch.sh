#!/bin/sh
# Compare this repository against the upstream project it was forked from.
#
# Two findings, because they mean different things:
#   diverged  - upstream has commits we have not reconciled yet. Normal.
#               Review the diff, then merge deliberately.
#   rewritten - a commit that used to be on upstream main is no longer an
#               ancestor of upstream main. That is what a force-push, rebase or
#               history scrub looks like, and it is also how a poisoned commit
#               gets erased after the fact. Reported as a failure, never merged.
#
# Exit status: 0 in sync, 1 history rewritten, 2 new upstream commits, 3 error.
set -eu

upstream="${UPSTREAM_REPO:?UPSTREAM_REPO is required}"
upstream_branch="${UPSTREAM_BRANCH:-main}"
baseline_file="${BASELINE_FILE:-.github/upstream-baseline}"

log() { printf '%s\n' "$*" >&2; }
fail() { printf 'status=error\nreason=%s\n' "$1"; exit 3; }

# Full history on purpose: the rewrite check needs to test ancestry against a
# commit that may no longer be on the upstream branch tip.
git fetch --no-tags --force "https://github.com/${upstream}.git" \
  "+refs/heads/${upstream_branch}:refs/remotes/upstream/${upstream_branch}" \
  || fail "upstream-fetch-failed"

upstream_ref="refs/remotes/upstream/${upstream_branch}"
upstream_sha="$(git rev-parse "$upstream_ref")"

if [ ! -f "$baseline_file" ]; then
  log "no baseline at ${baseline_file}; recording ${upstream_sha}"
  printf '%s\n' "$upstream_sha" > "$baseline_file"
  printf 'status=baseline-created\nupstream_sha=%s\n' "$upstream_sha"
  exit 0
fi

baseline_sha="$(tr -d '[:space:]' < "$baseline_file")"
[ -n "$baseline_sha" ] || fail "baseline-empty"

if ! git cat-file -e "${baseline_sha}^{commit}" 2>/dev/null; then
  log "baseline commit ${baseline_sha} is gone from upstream"
  printf 'status=rewritten\nreason=baseline-commit-deleted\nbaseline=%s\nupstream_sha=%s\n' \
    "$baseline_sha" "$upstream_sha"
  exit 1
fi

if ! git merge-base --is-ancestor "$baseline_sha" "$upstream_sha"; then
  log "baseline ${baseline_sha} is no longer an ancestor of ${upstream_sha}"
  printf 'status=rewritten\nreason=baseline-not-ancestor\nbaseline=%s\nupstream_sha=%s\n' \
    "$baseline_sha" "$upstream_sha"
  exit 1
fi

if [ "$upstream_sha" = "$baseline_sha" ]; then
  printf 'status=in-sync\nupstream_sha=%s\n' "$upstream_sha"
  exit 0
fi

log "upstream advanced ${baseline_sha}..${upstream_sha}"
printf 'status=diverged\nbaseline=%s\nupstream_sha=%s\ncommits=%s\nfiles=%s\n' \
  "$baseline_sha" "$upstream_sha" \
  "$(git rev-list --count "${baseline_sha}..${upstream_sha}")" \
  "$(git diff --name-only "${baseline_sha}" "${upstream_sha}" | wc -l | tr -d ' ')"
exit 2
