# gh-pr-status.plugin.zsh
# Displays GitHub PR number and CI check status in the shell prompt.
# Works with any oh-my-zsh theme via RPROMPT; exports prompt_my_pr() for p10k.
# https://github.com/bhanurp/oh-my-zsh-gh-pr-plugin

# ============================================================
# 1. Dependency Check
# ============================================================

_ghprs_check_deps() {
  local missing=0

  if ! command -v gh &>/dev/null; then
    print -u2 "[gh-pr-status] 'gh' CLI not found. PR status will not be shown."
    print -u2 "               Install: https://cli.github.com"
    missing=1
  fi

  if ! command -v jq &>/dev/null; then
    print -u2 "[gh-pr-status] 'jq' not found. PR status will not be shown."
    print -u2 "               Install: brew install jq  (macOS)  |  sudo apt install jq  (Debian/Ubuntu)"
    missing=1
  fi

  if ! command -v timeout &>/dev/null; then
    print -u2 "[gh-pr-status] 'timeout' not found. 'gh' calls will not have a time limit and may hang."
    print -u2 "               Install: brew install coreutils  (macOS)"
    # Not fatal — plugin continues without timeout guard
  fi

  return $missing
}

# ============================================================
# 2. Config Defaults (only set if not already defined by user)
# ============================================================

: ${GH_PR_STATUS_CACHE_TTL:=60}
: ${GH_PR_STATUS_RETRY_INTERVAL:=10}
: ${GH_PR_STATUS_TIMEOUT:=5}
: ${GH_PR_STATUS_ICON_OK:="✓"}
: ${GH_PR_STATUS_ICON_FAIL:="✗"}
: ${GH_PR_STATUS_ICON_RUNNING:="⟳"}
: ${GH_PR_STATUS_COLOR_FAIL:="red"}
: ${GH_PR_STATUS_COLOR_RUNNING:="yellow"}
: ${GH_PR_STATUS_COLOR_OK:="green"}
: ${GH_PR_STATUS_COLOR_NEUTRAL:="cyan"}
: ${GH_PR_STATUS_FORMAT:="compact"}
: ${GH_PR_STATUS_HYPERLINKS:="on"}
: ${GH_PR_STATUS_EXCLUDE_REPOS:=""}
: ${GH_PR_STATUS_MANAGE_RPROMPT:="on"}

# Validate FORMAT
if [[ "$GH_PR_STATUS_FORMAT" != "compact" && "$GH_PR_STATUS_FORMAT" != "verbose" ]]; then
  print -u2 "[gh-pr-status] Unknown GH_PR_STATUS_FORMAT=\"$GH_PR_STATUS_FORMAT\". Using \"compact\"."
  GH_PR_STATUS_FORMAT="compact"
fi

# ============================================================
# 3. Core Segment (placeholder — implemented in Task 5)
# ============================================================

_GHPRS_LAST_TEXT=""
_GHPRS_LAST_COLOR=""

_ghprs_segment() {
  _GHPRS_LAST_TEXT=""
  _GHPRS_LAST_COLOR=""
}

# ============================================================
# 4. Theme Integration (placeholder — implemented in Task 8)
# ============================================================

# Run dep check; skip hook registration if required deps are missing
if ! _ghprs_check_deps; then
  return 0
fi
