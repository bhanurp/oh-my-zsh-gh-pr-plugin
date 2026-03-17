#!/usr/bin/env zsh
# test/test_no_pr.zsh — segment is empty and silent for non-PR branches

PLUGIN="$(dirname $0)/../gh-pr-status.plugin.zsh"
source "$(dirname $0)/helpers.zsh"

git() {
  case "$*" in
    "rev-parse --abbrev-ref HEAD") print "main" ;;
    "remote get-url origin")       print "https://github.com/org/repo.git" ;;
    *) command git "$@" ;;
  esac
}
gh() { print "no pull requests found" >&2; return 1; }

GH_PR_STATUS_HYPERLINKS="off"
source "$PLUGIN" 2>/dev/null

# ── segment empty ─────────────────────────────────────────────────────────────
_ghprs_segment
assert_empty "$_GHPRS_LAST_TEXT"  "no PR: text is empty"
assert_empty "$_GHPRS_LAST_COLOR" "no PR: color is empty"

# ── failed flag NOT set ───────────────────────────────────────────────────────
local bkey="main_$(printf '%s' 'main' | cksum | cut -d' ' -f1)"
local fvar="_ghprs_cache_${bkey}_failed"
assert_equals "${(P)fvar:-0}" "0" "no PR: failed flag is 0"

# ── RPROMPT unmodified ────────────────────────────────────────────────────────
RPROMPT="existing-content"
_ghprs_precmd
assert_equals "$RPROMPT" "existing-content" "no PR: RPROMPT unchanged"

# ── result cached; second call skips gh ──────────────────────────────────────
integer _gh_calls=0
gh() { (( _gh_calls++ )); print "no pull requests found" >&2; return 1; }
GH_PR_STATUS_CACHE_TTL=9999
_ghprs_segment   # populate cache
_gh_calls=0
_ghprs_segment   # should use cache
assert_equals "$_gh_calls" "0" "no PR: second call uses cache"

summarize
