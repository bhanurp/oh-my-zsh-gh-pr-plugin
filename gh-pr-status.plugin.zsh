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
# 3. Core Segment
# ============================================================

# Output globals set by _ghprs_segment():
#   _GHPRS_LAST_TEXT  — formatted segment string (empty = no segment to show)
#   _GHPRS_LAST_COLOR — color name (empty = no segment to show)
_GHPRS_LAST_TEXT=""
_GHPRS_LAST_COLOR=""

_ghprs_segment() {
  _GHPRS_LAST_TEXT=""
  _GHPRS_LAST_COLOR=""

  # 1. Get branch
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ -z "$branch" || "$branch" == "HEAD" ]] && return

  # 2. Compute cache key: sanitize branch name + checksum to avoid collisions
  #    e.g., feat/foo and feat-foo both sanitize to feat_foo but have different checksums
  local branch_key checksum
  branch_key="${branch//[^a-zA-Z0-9]/_}"
  checksum=$(printf '%s' "$branch" | cksum | cut -d' ' -f1)
  branch_key="${branch_key}_${checksum}"

  # 3. Current time (EPOCHSECONDS builtin preferred; date +%s fallback for zsh < 5.8)
  local now
  if (( ${+EPOCHSECONDS} )); then
    now=$EPOCHSECONDS
  else
    now=$(date +%s)
  fi

  # 4. Cache hit: valid non-failed entry within TTL
  local tvar="_ghprs_cache_${branch_key}_text"
  local cvar="_ghprs_cache_${branch_key}_color"
  local timevar="_ghprs_cache_${branch_key}_time"
  local failvar="_ghprs_cache_${branch_key}_failed"

  local cache_time="${(P)timevar}"
  if [[ -n "$cache_time" ]] && (( now - cache_time < GH_PR_STATUS_CACHE_TTL )); then
    _GHPRS_LAST_TEXT="${(P)tvar}"
    _GHPRS_LAST_COLOR="${(P)cvar}"
    return
  fi

  # 5. Retry interval: suppress hammering gh after a genuine failure
  local cache_failed="${(P)failvar:-0}"
  if [[ "$cache_failed" == "1" ]] && (( now - ${cache_time:-0} < GH_PR_STATUS_RETRY_INTERVAL )); then
    return
  fi

  # 6. Parse repo slug locally (no network call needed)
  local remote_url repo_slug
  remote_url=$(git remote get-url origin 2>/dev/null)
  if [[ -n "$remote_url" ]]; then
    repo_slug=$(printf '%s' "$remote_url" \
      | sed 's|.*github\.com[:/]\(.*\)\.git$|\1|; s|.*github\.com[:/]\(.*\)$|\1|')
  fi

  # 7. EXCLUDE_REPOS: suppress segment without making any gh call
  if [[ -n "$repo_slug" && -n "$GH_PR_STATUS_EXCLUDE_REPOS" ]]; then
    local excl
    for excl in ${(z)GH_PR_STATUS_EXCLUDE_REPOS}; do
      [[ "$repo_slug" == "$excl" ]] && return
    done
  fi

  # 8. Fetch PR data (with timeout if available)
  local json exit_code
  if command -v timeout &>/dev/null; then
    json=$(timeout "$GH_PR_STATUS_TIMEOUT" gh pr view --json number,url,statusCheckRollup 2>&1)
  else
    json=$(gh pr view --json number,url,statusCheckRollup 2>&1)
  fi
  exit_code=$?

  # 9. "No PR" — normal case for most branches; cache result WITHOUT setting failed flag
  if (( exit_code != 0 )); then
    if [[ "$json" == *"no pull requests found"* ]]; then
      typeset -g "${tvar}"=""
      typeset -g "${cvar}"=""
      typeset -g "${timevar}"=$now
      typeset -g "${failvar}"=0
      return
    fi
    # 10. Genuine failure — set failed flag to trigger retry interval
    typeset -g "${failvar}"=1
    typeset -g "${timevar}"=$now
    return
  fi

  # 11. Parse with jq
  local pr_number pr_url ok fail run
  pr_number=$(printf '%s' "$json" | jq -r '.number // empty' 2>/dev/null)
  if [[ -z "$pr_number" ]]; then
    typeset -g "${failvar}"=1
    typeset -g "${timevar}"=$now
    return
  fi

  pr_url=$(printf '%s' "$json" | jq -r '.url // empty' 2>/dev/null)

  ok=$(printf '%s' "$json" | jq '[.statusCheckRollup[] |
    select(.conclusion == "SUCCESS" or .conclusion == "NEUTRAL" or .conclusion == "SKIPPED")
  ] | length' 2>/dev/null)

  fail=$(printf '%s' "$json" | jq '[.statusCheckRollup[] |
    select(.conclusion == "FAILURE" or .conclusion == "TIMED_OUT"
        or .conclusion == "ACTION_REQUIRED" or .conclusion == "CANCELLED")
  ] | length' 2>/dev/null)

  run=$(printf '%s' "$json" | jq '[.statusCheckRollup[] |
    select(.status != "COMPLETED")
  ] | length' 2>/dev/null)

  ok=${ok:-0}; fail=${fail:-0}; run=${run:-0}

  # 12. Build label string
  local label
  if [[ "$GH_PR_STATUS_FORMAT" == "verbose" ]]; then
    label="PR #${pr_number}"
    (( ok   > 0 )) && label+=" · ${ok} passing"
    (( fail > 0 )) && label+=" · ${fail} failing"
    (( run  > 0 )) && label+=" · ${run} running"
  else
    label="PR#${pr_number}"
    (( ok   > 0 )) && label+=" ${GH_PR_STATUS_ICON_OK}${ok}"
    (( fail > 0 )) && label+=" ${GH_PR_STATUS_ICON_FAIL}${fail}"
    (( run  > 0 )) && label+=" ${GH_PR_STATUS_ICON_RUNNING}${run}"
  fi

  # Wrap in OSC 8 hyperlink if enabled.
  # Guard: hyperlinks require a capable terminal. In production the shell is
  # interactive; tests can set _GHPRS_FORCE_HYPERLINKS=1 to exercise this path
  # since setopt INTERACTIVE cannot be enabled in a non-interactive script.
  local _hyper_ok=0
  if [[ -o interactive ]] || [[ "${_GHPRS_FORCE_HYPERLINKS:-0}" == "1" ]]; then
    _hyper_ok=1
  fi
  if [[ "$GH_PR_STATUS_HYPERLINKS" == "on" && "$TERM" != "dumb" && "$_hyper_ok" == "1" ]]; then
    label="%{\e]8;;${pr_url}\e\\%}${label}%{\e]8;;\e\\%}"
  fi

  # Pick color based on worst outcome
  local color
  if   (( fail > 0 )); then color="$GH_PR_STATUS_COLOR_FAIL"
  elif (( run  > 0 )); then color="$GH_PR_STATUS_COLOR_RUNNING"
  elif (( ok   > 0 )); then color="$GH_PR_STATUS_COLOR_OK"
  else                      color="$GH_PR_STATUS_COLOR_NEUTRAL"
  fi

  # 13. Store in cache and set output globals
  typeset -g "${tvar}"="$label"
  typeset -g "${cvar}"="$color"
  typeset -g "${timevar}"=$now
  typeset -g "${failvar}"=0

  _GHPRS_LAST_TEXT="$label"
  _GHPRS_LAST_COLOR="$color"
}

# ============================================================
# 4. Theme Integration
# ============================================================

# Run dep check; skip hook registration if required deps are missing
if ! _ghprs_check_deps; then
  return 0
fi

if [[ "$ZSH_THEME" == *powerlevel10k* || "$ZSH_THEME" == *p10k* ]]; then
  # ── PowerLevel10k ────────────────────────────────────────────────────────────
  # prompt_my_pr() is called by p10k on each render. A bare `return` (no args)
  # tells p10k to suppress the segment gap entirely when there is nothing to show.
  function prompt_my_pr() {
    _ghprs_segment
    [[ -n "$_GHPRS_LAST_TEXT" ]] || return
    p10k segment -b NONE -f "$_GHPRS_LAST_COLOR" -t "$_GHPRS_LAST_TEXT"
  }

else
  # ── Plain oh-my-zsh (any theme) ──────────────────────────────────────────────
  # _GHPRS_PREV_SEGMENT tracks the string we last prepended to RPROMPT.
  # Each precmd call strips the previous value and re-prepends the fresh one,
  # preserving any RPROMPT set by other plugins or the theme.
  _GHPRS_PREV_SEGMENT=""

  _ghprs_precmd() {
    _ghprs_segment  # sets _GHPRS_LAST_TEXT and _GHPRS_LAST_COLOR

    if [[ "$GH_PR_STATUS_MANAGE_RPROMPT" != "on" ]]; then
      # off mode: expose the colored segment for manual RPROMPT embedding
      if [[ -n "$_GHPRS_LAST_TEXT" ]]; then
        GHPRS_SEGMENT="%F{$_GHPRS_LAST_COLOR}$_GHPRS_LAST_TEXT%f"
      else
        GHPRS_SEGMENT=""
      fi
      return
    fi

    # Strip our previously injected segment from RPROMPT to recover base value.
    # This correctly handles other plugins that set RPROMPT after we loaded.
    local base="$RPROMPT"
    if [[ -n "$_GHPRS_PREV_SEGMENT" && "$base" == "$_GHPRS_PREV_SEGMENT"* ]]; then
      base="${base#"$_GHPRS_PREV_SEGMENT"}"
      base="${base# }"  # trim one leading space if present
    fi

    if [[ -n "$_GHPRS_LAST_TEXT" ]]; then
      local colored="%F{$_GHPRS_LAST_COLOR}$_GHPRS_LAST_TEXT%f"
      _GHPRS_PREV_SEGMENT="$colored"
      RPROMPT="${colored}${base:+ $base}"
    else
      _GHPRS_PREV_SEGMENT=""
      RPROMPT="$base"
    fi
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _ghprs_precmd
fi
