# gh-pr-status

An oh-my-zsh plugin that shows your current branch's GitHub PR number and CI
check status in the shell prompt. Works with **any oh-my-zsh theme** via
`RPROMPT`, and supports **PowerLevel10k** as a native segment.

```
PR#42 ✓8 ✗1 ⟳2
```

## Requirements

- [gh CLI](https://cli.github.com) ≥ 2.0 (authenticated with `gh auth login`)
- [jq](https://stedolan.github.io/jq/)
- `timeout` (recommended — `brew install coreutils` on macOS)
- zsh 5.1+

## Installation

```zsh
git clone https://github.com/bhanurp/oh-my-zsh-gh-pr-plugin.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/gh-pr-status
```

Add to your `~/.zshrc`:

```zsh
plugins=(... gh-pr-status)
```

## PowerLevel10k

Add `my_pr` to your right prompt elements in `~/.p10k.zsh`:

```zsh
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(my_pr status ...)
```

The plugin defines `prompt_my_pr()` before p10k initializes — no special ordering needed.

## Configuration

Set these in `~/.zshrc` **before** `plugins=(...)`:

| Variable | Default | Description |
|---|---|---|
| `GH_PR_STATUS_CACHE_TTL` | `60` | Seconds before re-fetching PR data |
| `GH_PR_STATUS_RETRY_INTERVAL` | `10` | Seconds to wait before retrying after a `gh` failure |
| `GH_PR_STATUS_TIMEOUT` | `5` | Seconds before `gh` call is killed |
| `GH_PR_STATUS_ICON_OK` | `✓` | Icon for passing checks |
| `GH_PR_STATUS_ICON_FAIL` | `✗` | Icon for failed checks |
| `GH_PR_STATUS_ICON_RUNNING` | `⟳` | Icon for running checks |
| `GH_PR_STATUS_COLOR_FAIL` | `red` | Color when checks fail |
| `GH_PR_STATUS_COLOR_RUNNING` | `yellow` | Color when checks are running |
| `GH_PR_STATUS_COLOR_OK` | `green` | Color when all checks pass |
| `GH_PR_STATUS_COLOR_NEUTRAL` | `cyan` | Color when there are no checks |
| `GH_PR_STATUS_FORMAT` | `compact` | `compact` or `verbose` |
| `GH_PR_STATUS_HYPERLINKS` | `on` | `on`/`off` — clickable OSC 8 terminal links |
| `GH_PR_STATUS_EXCLUDE_REPOS` | | Space-separated `org/repo` slugs to suppress |
| `GH_PR_STATUS_MANAGE_RPROMPT` | `on` | `off` to use `$GHPRS_SEGMENT` manually |

### Format examples

**compact** (default):
```
PR#42 ✓8 ✗1 ⟳2
```

**verbose**:
```
PR #42 · 8 passing · 1 failing · 2 running
```

### Suppress for specific repos

```zsh
GH_PR_STATUS_EXCLUDE_REPOS="my-org/noisy-repo another-org/other-repo"
```

### Manual RPROMPT

```zsh
GH_PR_STATUS_MANAGE_RPROMPT="off"
RPROMPT='$GHPRS_SEGMENT %~'
```

## Testing locally

```bash
# Run all tests
for f in test/test_*.zsh; do echo "=== $f ==="; zsh "$f"; echo ""; done

# Run a single file
zsh test/test_with_pr.zsh
```

## How it works

1. On each prompt render, reads the current branch via `git rev-parse`
2. Checks a per-branch in-memory cache (TTL: `GH_PR_STATUS_CACHE_TTL` seconds)
3. On cache miss, calls `gh pr view --json number,url,statusCheckRollup`
4. Parses check results with `jq` and builds the formatted segment
5. Injects into `$RPROMPT` via a `precmd` hook (or via `p10k segment` for p10k users)
