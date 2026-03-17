#!/usr/bin/env zsh
# test/test_with_pr.zsh — verify segment output formatting

PLUGIN="$(dirname $0)/../gh-pr-status.plugin.zsh"
source "$(dirname $0)/helpers.zsh"

# Fixture: PR #42, 3 ok, 1 fail, 2 running
_F_ALL='{"number":42,"url":"https://github.com/org/repo/pull/42","statusCheckRollup":[
  {"status":"COMPLETED","conclusion":"SUCCESS"},
  {"status":"COMPLETED","conclusion":"SUCCESS"},
  {"status":"COMPLETED","conclusion":"SUCCESS"},
  {"status":"COMPLETED","conclusion":"FAILURE"},
  {"status":"IN_PROGRESS","conclusion":null},
  {"status":"QUEUED","conclusion":null}
]}'

# Fixture: PR #7, no checks
_F_NONE='{"number":7,"url":"https://github.com/org/repo/pull/7","statusCheckRollup":[]}'

# Fixture: PR #1, only running
_F_RUN='{"number":1,"url":"u","statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":null}]}'

# Fixture: PR #2, only ok
_F_OK='{"number":2,"url":"u","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}'

# Standard git stub
git() {
  case "$*" in
    "rev-parse --abbrev-ref HEAD") print "my-feature" ;;
    "remote get-url origin")       print "https://github.com/org/repo.git" ;;
    *) command git "$@" ;;
  esac
}

# ── compact format ────────────────────────────────────────────────────────────
(
  gh() { print "$_F_ALL"; return 0; }
  GH_PR_STATUS_FORMAT="compact"; GH_PR_STATUS_HYPERLINKS="off"
  source "$PLUGIN" 2>/dev/null
  _ghprs_segment
  assert_contains "$_GHPRS_LAST_TEXT" "PR#42" "compact: PR number shown"
  assert_contains "$_GHPRS_LAST_TEXT" "✓3"    "compact: ok count shown"
  assert_contains "$_GHPRS_LAST_TEXT" "✗1"    "compact: fail count shown"
  assert_contains "$_GHPRS_LAST_TEXT" "⟳2"    "compact: running count shown"
  assert_equals   "$_GHPRS_LAST_COLOR" "red"  "compact: color is red when failures exist"
)

# ── verbose format ────────────────────────────────────────────────────────────
(
  gh() { print "$_F_ALL"; return 0; }
  GH_PR_STATUS_FORMAT="verbose"; GH_PR_STATUS_HYPERLINKS="off"
  source "$PLUGIN" 2>/dev/null
  _ghprs_segment
  assert_contains "$_GHPRS_LAST_TEXT" "PR #42"    "verbose: PR number shown"
  assert_contains "$_GHPRS_LAST_TEXT" "3 passing" "verbose: ok count shown"
  assert_contains "$_GHPRS_LAST_TEXT" "1 failing" "verbose: fail count shown"
  assert_contains "$_GHPRS_LAST_TEXT" "2 running" "verbose: running count shown"
)

# ── zero counts hidden ────────────────────────────────────────────────────────
(
  gh() { print "$_F_NONE"; return 0; }
  GH_PR_STATUS_FORMAT="compact"; GH_PR_STATUS_HYPERLINKS="off"
  source "$PLUGIN" 2>/dev/null
  _ghprs_segment
  assert_contains     "$_GHPRS_LAST_TEXT" "PR#7" "no checks: PR number shown"
  assert_not_contains "$_GHPRS_LAST_TEXT" "✓"    "no checks: ok icon hidden"
  assert_not_contains "$_GHPRS_LAST_TEXT" "✗"    "no checks: fail icon hidden"
  assert_equals       "$_GHPRS_LAST_COLOR" "cyan" "no checks: color is neutral"
)

# ── color: yellow when only running ──────────────────────────────────────────
(
  gh() { print "$_F_RUN"; return 0; }
  GH_PR_STATUS_HYPERLINKS="off"
  source "$PLUGIN" 2>/dev/null
  _ghprs_segment
  assert_equals "$_GHPRS_LAST_COLOR" "yellow" "color: yellow when only running"
)

# ── color: green when only ok ─────────────────────────────────────────────────
(
  gh() { print "$_F_OK"; return 0; }
  GH_PR_STATUS_HYPERLINKS="off"
  source "$PLUGIN" 2>/dev/null
  _ghprs_segment
  assert_equals "$_GHPRS_LAST_COLOR" "green" "color: green when only ok"
)

# ── hyperlinks: OSC 8 sequence included when enabled ─────────────────────────
# Note: plugin checks [[ -o interactive ]] for hyperlinks.
# We enable interactive mode explicitly to test this path.
(
  gh() { print "$_F_NONE"; return 0; }
  GH_PR_STATUS_FORMAT="compact"; GH_PR_STATUS_HYPERLINKS="on"; TERM="xterm-256color"
  _GHPRS_FORCE_HYPERLINKS=1
  source "$PLUGIN" 2>/dev/null
  _ghprs_segment
  assert_contains "$_GHPRS_LAST_TEXT" "]8;;"   "hyperlinks: OSC 8 sequence present"
  assert_contains "$_GHPRS_LAST_TEXT" "pull/7" "hyperlinks: URL contains PR path"
)

# ── hyperlinks: disabled when TERM=dumb ───────────────────────────────────────
(
  gh() { print "$_F_NONE"; return 0; }
  GH_PR_STATUS_HYPERLINKS="on"; TERM="dumb"
  source "$PLUGIN" 2>/dev/null
  _ghprs_segment
  assert_not_contains "$_GHPRS_LAST_TEXT" "]8;;" "hyperlinks: disabled for TERM=dumb"
)

summarize
