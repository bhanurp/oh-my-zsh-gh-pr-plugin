#!/usr/bin/env zsh
# test/test_cache.zsh — cache hit/miss, TTL, retry interval, collision, fallback

PLUGIN="$(dirname $0)/../gh-pr-status.plugin.zsh"
source "$(dirname $0)/helpers.zsh"

_PR42='{"number":42,"url":"https://github.com/org/repo/pull/42","statusCheckRollup":[]}'
_MOCK_BRANCH="feature-a"

git() {
  case "$*" in
    "rev-parse --abbrev-ref HEAD") print "$_MOCK_BRANCH" ;;
    "remote get-url origin")       print "https://github.com/org/repo.git" ;;
    *) command git "$@" ;;
  esac
}

GH_PR_STATUS_HYPERLINKS="off"
source "$PLUGIN" 2>/dev/null

# Helper: gh() is called inside $(...) in the plugin, so integer counters in the
# parent shell are invisible to it.  Use a temp-file counter (same approach as
# helpers.zsh failure tracking) so increments survive the subshell boundary.
_counter_file() { local f=$(mktemp); print 0 > "$f"; print "$f"; }
_counter_read() { <"$1"; }
_counter_inc()  { local c; c=$(<"$1"); print $(( c + 1 )) > "$1"; }

# ── cache hit: second call does not invoke gh ────────────────────────────────
(
  _MOCK_BRANCH="cache-hit-test"
  local _cf=$(_counter_file)
  trap "rm -f $_cf" EXIT
  gh() { _counter_inc "$_cf"; print "$_PR42"; return 0; }
  GH_PR_STATUS_CACHE_TTL=9999

  _ghprs_segment
  assert_equals "$(_counter_read $_cf)" "1" "cache hit: first call fetches"
  _ghprs_segment
  assert_equals "$(_counter_read $_cf)" "1" "cache hit: second call uses cache"
)

# ── TTL=0: every call re-fetches ─────────────────────────────────────────────
(
  _MOCK_BRANCH="ttl-test"
  local _cf=$(_counter_file)
  trap "rm -f $_cf" EXIT
  gh() { _counter_inc "$_cf"; print "$_PR42"; return 0; }
  GH_PR_STATUS_CACHE_TTL=0

  _ghprs_segment
  _ghprs_segment
  assert_equals "$(_counter_read $_cf)" "2" "TTL=0: both calls fetch from gh"
)

# ── genuine failure: retry interval suppresses gh ────────────────────────────
(
  _MOCK_BRANCH="fail-test"
  local _cf=$(_counter_file)
  trap "rm -f $_cf" EXIT
  gh() { _counter_inc "$_cf"; print "some error" >&2; return 1; }
  GH_PR_STATUS_RETRY_INTERVAL=9999

  _ghprs_segment          # fails, sets failed flag
  print 0 > "$_cf"        # reset counter
  _ghprs_segment          # suppressed by retry interval
  assert_equals "$(_counter_read $_cf)" "0" "retry: gh suppressed within interval"
  assert_empty "$_GHPRS_LAST_TEXT" "retry: segment empty during interval"
)

# ── after RETRY_INTERVAL expires, gh is called again ────────────────────────
(
  _MOCK_BRANCH="retry-expiry"
  local _cf=$(_counter_file)
  trap "rm -f $_cf" EXIT
  gh() { _counter_inc "$_cf"; print "some error" >&2; return 1; }
  GH_PR_STATUS_CACHE_TTL=0        # ensure cache TTL doesn't short-circuit
  GH_PR_STATUS_RETRY_INTERVAL=0   # expire immediately

  _ghprs_segment          # fails, sets failed flag
  print 0 > "$_cf"        # reset counter
  _ghprs_segment          # interval expired: should retry
  assert_equals "$(_counter_read $_cf)" "1" "retry expiry: gh called again after interval"
)

# ── branch collision: feat/foo and feat-foo get separate entries ──────────────
(
  local _cf_foo=$(_counter_file) _cf_bar=$(_counter_file)
  trap "rm -f $_cf_foo $_cf_bar" EXIT

  _MOCK_BRANCH="feat/foo"
  gh() { _counter_inc "$_cf_foo"; print "$_PR42"; return 0; }
  _ghprs_segment

  _MOCK_BRANCH="feat-foo"
  gh() { _counter_inc "$_cf_bar"; print "$_PR42"; return 0; }
  _ghprs_segment

  assert_equals "$(_counter_read $_cf_bar)" "1" "collision: feat-foo fetches separately from feat/foo"
)

# ── no-PR does NOT set failed flag ───────────────────────────────────────────
(
  _MOCK_BRANCH="no-pr-branch"
  gh() { print "no pull requests found" >&2; return 1; }
  _ghprs_segment

  local bkey="no_pr_branch_$(printf '%s' 'no-pr-branch' | cksum | cut -d' ' -f1)"
  local fvar="_ghprs_cache_${bkey}_failed"
  assert_equals "${(P)fvar:-0}" "0" "no-PR: failed flag stays 0"
)

# ── EPOCHSECONDS fallback: force date +%s path ───────────────────────────────
(
  _MOCK_BRANCH="epoch-fallback"
  local _cf=$(_counter_file)
  trap "rm -f $_cf" EXIT
  gh() { _counter_inc "$_cf"; print "$_PR42"; return 0; }
  GH_PR_STATUS_CACHE_TTL=9999

  date() { print "1000000000"; }   # fixed epoch
  _ghprs_segment
  print 0 > "$_cf"
  _ghprs_segment
  assert_equals "$(_counter_read $_cf)" "0" "EPOCHSECONDS fallback: cache works with date +%s"
)

summarize
