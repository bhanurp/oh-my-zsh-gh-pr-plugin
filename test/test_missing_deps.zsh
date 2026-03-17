#!/usr/bin/env zsh
# test/test_missing_deps.zsh — verify startup warnings for missing dependencies

PLUGIN="$(dirname $0)/../gh-pr-status.plugin.zsh"
source "$(dirname $0)/helpers.zsh"

# ── missing gh ────────────────────────────────────────────────────────────────
(
  local tmpdir
  tmpdir=$(_ghprs_make_path_without gh)
  trap "rm -rf $tmpdir" EXIT
  local output
  output=$(PATH="$tmpdir" ZSH_THEME="robbyrussell" zsh -c "source $PLUGIN" 2>&1)
  assert_contains "$output" "'gh' CLI not found"  "missing gh: warning printed"
  assert_contains "$output" "cli.github.com"      "missing gh: install URL shown"
)

# ── missing jq ────────────────────────────────────────────────────────────────
(
  local tmpdir
  tmpdir=$(_ghprs_make_path_without jq)
  trap "rm -rf $tmpdir" EXIT
  local output
  output=$(PATH="$tmpdir" ZSH_THEME="robbyrussell" zsh -c "source $PLUGIN" 2>&1)
  assert_contains "$output" "'jq' not found"  "missing jq: warning printed"
  assert_contains "$output" "brew install jq" "missing jq: install hint shown"
)

# ── missing timeout (non-fatal, plugin still loads) ───────────────────────────
(
  local tmpdir
  tmpdir=$(_ghprs_make_path_without timeout)
  trap "rm -rf $tmpdir" EXIT
  local output
  output=$(PATH="$tmpdir" ZSH_THEME="robbyrussell" zsh -c "source $PLUGIN && echo LOADED" 2>&1)
  assert_contains "$output" "'timeout' not found"    "missing timeout: warning printed"
  assert_contains "$output" "brew install coreutils" "missing timeout: install hint shown"
  assert_contains "$output" "LOADED"                 "missing timeout: plugin still loads"
)

# ── invalid FORMAT falls back to compact ─────────────────────────────────────
(
  local output
  output=$(ZSH_THEME="robbyrussell" zsh -c "
    GH_PR_STATUS_FORMAT=banana
    source $PLUGIN
    print \$GH_PR_STATUS_FORMAT
  " 2>&1)
  assert_contains "$output" "Unknown GH_PR_STATUS_FORMAT" "invalid format: warning printed"
  assert_contains "$output" "compact"                     "invalid format: falls back to compact"
)

# ── gh and jq missing: hooks are NOT registered ──────────────────────────────
(
  local tmpdir
  tmpdir=$(_ghprs_make_path_without gh)
  # also remove jq from this dir
  rm -f "$tmpdir/jq" 2>/dev/null
  trap "rm -rf $tmpdir" EXIT
  local output
  output=$(PATH="$tmpdir" ZSH_THEME="robbyrussell" zsh -c "
    source $PLUGIN
    typeset -f _ghprs_precmd
  " 2>&1)
  assert_not_contains "$output" "_ghprs_precmd" "missing deps: precmd hook not registered"
)

summarize
