#!/usr/bin/env zsh
# test/helpers.zsh — shared assertion utilities and test setup helpers

integer _GHPRS_TEST_FAILURES=0

pass() { print -P "%F{green}PASS%f: $1"; }
fail() { print -P "%F{red}FAIL%f: $1"; (( _GHPRS_TEST_FAILURES++ )); }

assert_equals()       { [[ "$1" == "$2" ]] && pass "$3" || fail "$3 (expected '$2', got '$1')"; }
assert_empty()        { [[ -z "$1" ]]      && pass "$2" || fail "$2 (expected empty, got '$1')"; }
assert_not_empty()    { [[ -n "$1" ]]      && pass "$2" || fail "$2 (expected non-empty, got empty)"; }
assert_contains()     { [[ "$1" == *"$2"* ]] && pass "$3" || fail "$3 (expected to contain '$2', got '$1')"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] && pass "$3" || fail "$3 (expected NOT to contain '$2', got '$1')"; }

summarize() {
  print ""
  if (( _GHPRS_TEST_FAILURES == 0 )); then
    print -P "%F{green}All tests passed.%f"
    exit 0
  else
    print -P "%F{red}${_GHPRS_TEST_FAILURES} test(s) failed.%f"
    exit 1
  fi
}

# _ghprs_make_path_without <tool>
#
# Creates a temp directory containing symlinks to all tools required by the
# plugin EXCEPT the named tool. Returns the tmpdir path. The caller should
# set PATH="$tmpdir" and arrange cleanup via trap.
#
# This lets tests simulate a missing dependency using real PATH resolution
# (command -v) rather than shell function overrides, which do not affect
# command -v in zsh.
_ghprs_make_path_without() {
  local missing_tool="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  local tool
  for tool in gh jq timeout sed cksum date git zsh; do
    if [[ "$tool" != "$missing_tool" ]]; then
      local real
      real=$(command -v "$tool" 2>/dev/null)
      [[ -n "$real" ]] && ln -s "$real" "$tmpdir/$tool"
    fi
  done
  print "$tmpdir"
}
