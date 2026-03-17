#!/usr/bin/env zsh
# test/test_rprompt.zsh — RPROMPT management and theme integration

PLUGIN="$(dirname $0)/../gh-pr-status.plugin.zsh"
source "$(dirname $0)/helpers.zsh"

_PR7='{"number":7,"url":"https://github.com/org/repo/pull/7","statusCheckRollup":[]}'
_MOCK_BRANCH="feature"

git() {
  case "$*" in
    "rev-parse --abbrev-ref HEAD") print "$_MOCK_BRANCH" ;;
    "remote get-url origin")       print "https://github.com/org/repo.git" ;;
    *) command git "$@" ;;
  esac
}
gh() { print "$_PR7"; return 0; }
GH_PR_STATUS_HYPERLINKS="off"

# ── segment prepended; base RPROMPT preserved ─────────────────────────────────
(
  RPROMPT="base-content"
  GH_PR_STATUS_MANAGE_RPROMPT="on"
  source "$PLUGIN" 2>/dev/null
  _ghprs_precmd
  assert_contains     "$RPROMPT" "PR#7"         "rprompt: segment prepended"
  assert_contains     "$RPROMPT" "base-content" "rprompt: base content preserved"
)

# ── segment cleared when no PR on branch ─────────────────────────────────────
(
  RPROMPT=""
  GH_PR_STATUS_MANAGE_RPROMPT="on"
  GH_PR_STATUS_CACHE_TTL=0
  source "$PLUGIN" 2>/dev/null
  _ghprs_precmd           # adds segment

  gh() { print "no pull requests found" >&2; return 1; }
  _ghprs_precmd           # removes segment (no PR)
  assert_empty "$RPROMPT" "rprompt: cleared when no PR and no base"
)

# ── MANAGE_RPROMPT=off: sets GHPRS_SEGMENT, not RPROMPT ─────────────────────
(
  RPROMPT="untouched"
  GH_PR_STATUS_MANAGE_RPROMPT="off"
  source "$PLUGIN" 2>/dev/null
  _ghprs_precmd
  assert_equals   "$RPROMPT"       "untouched" "manage_off: RPROMPT untouched"
  assert_contains "$GHPRS_SEGMENT" "PR#7"      "manage_off: GHPRS_SEGMENT set"
)

# ── EXCLUDE_REPOS: segment hidden, no gh call made ───────────────────────────
(
  GH_PR_STATUS_EXCLUDE_REPOS="org/repo"
  GH_PR_STATUS_CACHE_TTL=0
  integer _gh_called=0
  gh() { (( _gh_called++ )); print "$_PR7"; return 0; }
  source "$PLUGIN" 2>/dev/null
  _ghprs_segment
  assert_empty "$_GHPRS_LAST_TEXT"  "exclude: segment hidden"
  assert_equals "$_gh_called" "0"   "exclude: gh not called"
)

# ── detached HEAD: stale segment cleared from RPROMPT ─────────────────────────
(
  RPROMPT=""
  GH_PR_STATUS_MANAGE_RPROMPT="on"
  source "$PLUGIN" 2>/dev/null
  _ghprs_precmd   # adds segment

  # Simulate detached HEAD
  git() {
    case "$*" in
      "rev-parse --abbrev-ref HEAD") print "HEAD" ;;
      *) command git "$@" ;;
    esac
  }
  GH_PR_STATUS_CACHE_TTL=0
  _ghprs_precmd
  assert_not_contains "$RPROMPT" "PR#" "detached HEAD: stale segment cleared"
)

# ── three precmd cycles: segment does not accumulate ─────────────────────────
(
  RPROMPT=""
  GH_PR_STATUS_MANAGE_RPROMPT="on"
  GH_PR_STATUS_CACHE_TTL=0
  source "$PLUGIN" 2>/dev/null

  _ghprs_precmd; _ghprs_precmd; _ghprs_precmd
  # "PR#7" should appear exactly once, not three times
  local r="$RPROMPT"
  local stripped="${r//PR#7}"
  local removed=$(( ${#r} - ${#stripped} ))
  assert_equals "$removed" "4" "precmd cycles: segment not duplicated (PR#7 = 4 chars)"
)

# ── late-setting plugin: its RPROMPT contribution is preserved ───────────────
(
  RPROMPT=""
  GH_PR_STATUS_MANAGE_RPROMPT="on"
  source "$PLUGIN" 2>/dev/null

  # Simulate another plugin setting RPROMPT after gh-pr-status loaded
  RPROMPT="from-other-plugin"

  GH_PR_STATUS_CACHE_TTL=0
  _ghprs_precmd

  assert_contains "$RPROMPT" "PR#7"              "late plugin: our segment present"
  assert_contains "$RPROMPT" "from-other-plugin" "late plugin: other plugin's RPROMPT preserved"
)

summarize
