#!/usr/bin/env bash
# rs-fleet spawn.sh - launch Claude Code background sessions for git repositories.
set -u

usage() {
  cat <<'EOF'
Usage:
  spawn.sh scan [root] [--max-depth N] [--prefix NAME] [--dry-run] [--force-respawn]
  spawn.sh multi <repo> --count N [--prefix NAME] [--dry-run] [--force-respawn]
  spawn.sh cleanup [--prefix NAME] [--pattern REGEX] [--dry-run]

Examples:
  spawn.sh scan
  spawn.sh scan /Users/sakang/repo --max-depth 3
  spawn.sh scan /Users/sakang/repo --dry-run
  spawn.sh multi /Users/sakang/repo/webssh --count 4
  spawn.sh cleanup
  spawn.sh cleanup --prefix rvbox
  spawn.sh cleanup --pattern '^rsfleet-rvbox-st-' --dry-run
EOF
}

MODE="${1:-}"
[ -n "$MODE" ] || { usage; exit 1; }
shift || true

case "$MODE" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

die() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "git command not found"
command -v claude >/dev/null 2>&1 || die "claude CLI not found"

# svn is optional - only required when targeting an SVN working copy.
HAVE_SVN=0
command -v svn >/dev/null 2>&1 && HAVE_SVN=1

# Resolve the actual Claude Code binary. The `claude` on PATH may be a
# wrapper (e.g. cmux.app) that routes some hidden subcommands like `rm`
# into the model as a prompt instead of invoking them. We prefer the
# native binary under ~/.local/share/claude/versions/<version>/ when
# available, falling back to the wrapper for normal cases.
resolve_claude_native() {
  local versions_dir="$HOME/.local/share/claude/versions"
  [ -d "$versions_dir" ] || { command -v claude; return 0; }
  local latest
  latest="$(ls -1 "$versions_dir" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
  if [ -n "$latest" ] && [ -x "$versions_dir/$latest" ]; then
    printf '%s' "$versions_dir/$latest"
  else
    command -v claude
  fi
}
CLAUDE_NATIVE="$(resolve_claude_native)"

PREFIX="rsfleet"
FORCE_RESPAWN=0
MAX_DEPTH=""
COUNT=""
ROOT=""
TARGET_REPO=""
ROSTER="$HOME/.claude/daemon/roster.json"
WORKTREE_ROOT="$HOME/.claude/rs-fleet/worktrees"
DRY_RUN=0

sanitize_name() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

parse_common_arg() {
  case "$1" in
    --prefix)
      [ $# -ge 2 ] || die "--prefix requires a value"
      PREFIX="$2"
      return 2
      ;;
    --force-respawn)
      FORCE_RESPAWN=1
      return 1
      ;;
    --dry-run)
      DRY_RUN=1
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

roster_all_workers() {
  # Emit "short\tname" lines for every worker in roster.json that has a resolvable name.
  [ -f "$ROSTER" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '
    .workers // {}
    | to_entries[]
    | . as $e
    | ($e.value.dispatch.launch.args // []) as $a
    | (
        $e.value.dispatch.seed.name
        // (
          first(
            range(0; ($a | length))
            | select($a[.] == "--name" or $a[.] == "-n")
            | $a[. + 1]
          )
        )
      ) as $name
    | select($name != null and $name != "")
    | "\($e.key)\t\($name)"
  ' "$ROSTER" 2>/dev/null
}

roster_workers_by_name() {
  local name="$1"
  [ -f "$ROSTER" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r --arg n "$name" '
    .workers // {}
    | to_entries[]
    | select(
        .value.dispatch.seed.name == $n
        or .value.dispatch.launch.args[]? == $n
      )
    | "\(.value.pid // "")\t\(.value.startedAt // 0)\t\(.key)"
  ' "$ROSTER" 2>/dev/null
}

stop_session_short() {
  local short="$1"
  [ -n "$short" ] || return 1
  claude stop "$short" </dev/null >/dev/null 2>&1 || return 1
  if printf '%s' "$short" | grep -Eq '^[0-9a-f]{8}$'; then
    rm -rf "$HOME/.claude/jobs/$short"
  fi
}

# Remove a background session entirely using `claude rm`, which the official
# docs describe as cleaning up the session (and its worktree when clean).
# Some CLI builds interpret a bare `rm` as a prompt — to guard against that
# we run it in the background, give it a short window to complete, and verify
# via the roster.
remove_session_short() {
  local short="$1"
  [ -n "$short" ] || return 1

  "$CLAUDE_NATIVE" rm "$short" </dev/null >/dev/null 2>&1 || true
  sleep 0.5

  if jq -e --arg s "$short" '.workers[$s]' "$ROSTER" >/dev/null 2>&1; then
    return 1
  fi
  rm -rf "$HOME/.claude/jobs/$short" 2>/dev/null
  return 0
}

ensure_name_available() {
  local name="$1"
  local existing
  existing="$(roster_workers_by_name "$name")"
  [ -n "$existing" ] || return 0

  if [ "$FORCE_RESPAWN" = "1" ]; then
    while IFS=$'\t' read -r _ _ short; do
      [ -n "$short" ] || continue
      if stop_session_short "$short"; then
        echo "  [$name] stopped existing $short"
      else
        echo "  [$name] failed to stop existing $short" >&2
      fi
    done <<< "$existing"
    sleep 1
    return 0
  fi

  echo "  [$name] SKIP - already active"
  return 1
}

detect_vcs() {
  # Args: path. Echoes "git" or "svn"; returns non-zero if neither.
  local path="$1"
  if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'git'
    return 0
  fi
  if [ "$HAVE_SVN" = "1" ] && svn info "$path" >/dev/null 2>&1; then
    printf 'svn'
    return 0
  fi
  return 1
}

vcs_top() {
  # Args: path. Echoes working-copy root for git or svn; empty on failure.
  local path="$1"
  local top
  top="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$top" ] && { printf '%s' "$top"; return 0; }
  if [ "$HAVE_SVN" = "1" ]; then
    top="$(svn info --show-item wc-root "$path" 2>/dev/null)" && [ -n "$top" ] && { printf '%s' "$top"; return 0; }
  fi
  return 1
}

prepare_worktree() {
  # Args: repo session_name
  # Echoes: worktree path on success. Returns non-zero on failure.
  # Git: `git worktree add --detach`. SVN: fresh `svn checkout` of the working copy's URL.
  local repo="$1"
  local session_name="$2"
  local wt="$WORKTREE_ROOT/$session_name"
  local kind url

  kind="$(detect_vcs "$repo")" || return 1

  if [ -d "$wt" ]; then
    if [ "$FORCE_RESPAWN" = "1" ]; then
      case "$kind" in
        git) (cd "$wt" 2>/dev/null && git worktree remove --force "$wt") >/dev/null 2>&1 || true ;;
      esac
      rm -rf "$wt" 2>/dev/null
    else
      printf '%s' "$wt"
      return 0
    fi
  fi

  mkdir -p "$WORKTREE_ROOT" || return 1
  case "$kind" in
    git)
      git -C "$repo" worktree add --detach "$wt" HEAD >/dev/null 2>&1 || return 1
      ;;
    svn)
      url="$(svn info --show-item url "$repo" 2>/dev/null)" || return 1
      [ -n "$url" ] || return 1
      svn checkout "$url" "$wt" >/dev/null 2>&1 || return 1
      ;;
    *)
      return 1
      ;;
  esac
  printf '%s' "$wt"
  return 0
}

spawn_agent() {
  local repo="$1"
  local session_name="$2"
  local prompt="$3"
  local use_worktree="${4:-0}"
  local out cwd wt

  ensure_name_available "$session_name" || return 2

  cwd="$repo"
  if [ "$use_worktree" = "1" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "  [$session_name] DRY-RUN (worktree at $WORKTREE_ROOT/$session_name from $repo)"
      return 0
    fi
    if ! wt="$(prepare_worktree "$repo" "$session_name")"; then
      echo "  [$session_name] FAILED to create worktree"
      return 1
    fi
    cwd="$wt"
  elif [ "$DRY_RUN" = "1" ]; then
    echo "  [$session_name] DRY-RUN ($repo)"
    return 0
  fi

  out="$(
    cd "$cwd" && claude --bg --name "$session_name" --add-dir "$cwd" "$prompt" </dev/null 2>&1 | head -5
  )"
  status=$?

  if [ "$status" -ne 0 ]; then
    echo "  [$session_name] FAILED"
    printf '%s\n' "$out" | sed 's/^/      /'
    return 1
  fi

  if printf '%s\n' "$out" | grep -qiE 'backgrounded|started|spawned'; then
    echo "  [$session_name] spawned ($cwd)"
    return 0
  fi

  echo "  [$session_name] launched or returned unexpected output"
  printf '%s\n' "$out" | sed 's/^/      /'
  return 0
}

repo_top() {
  vcs_top "$1"
}

discover_repos() {
  local root="$1"
  local max_depth_args=()

  if [ -n "$MAX_DEPTH" ]; then
    max_depth_args=(-maxdepth "$MAX_DEPTH")
  fi

  {
    find "$root" "${max_depth_args[@]}" \
      \( -type d -name .git -prune -o -type f -name .git \) -print 2>/dev/null \
      | sed 's#/.git$##'
    if [ "$HAVE_SVN" = "1" ]; then
      find "$root" "${max_depth_args[@]}" \
        -type d -name .svn -prune -print 2>/dev/null \
        | sed 's#/.svn$##'
    fi
  } \
    | while IFS= read -r repo; do
        vcs_top "$repo"
      done \
    | awk 'NF' \
    | sort -u
}

spawned=0
skipped=0
failed=0

case "$MODE" in
  scan)
    if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then
      ROOT="$1"
      shift
    else
      ROOT="."
    fi

    while [ $# -gt 0 ]; do
      case "$1" in
        --max-depth)
          [ $# -ge 2 ] || die "--max-depth requires a value"
          MAX_DEPTH="$2"
          shift 2
          ;;
        --prefix|--force-respawn|--dry-run)
          parse_common_arg "$@" || consumed=$?
          consumed=${consumed:-0}
          [ "$consumed" -gt 0 ] || die "unknown argument: $1"
          shift "$consumed"
          unset consumed
          ;;
        *)
          die "unknown argument: $1"
          ;;
      esac
    done

    [ -d "$ROOT" ] || die "root directory not found: $ROOT"
    ROOT="$(cd "$ROOT" && pwd)"
    PREFIX="$(sanitize_name "$PREFIX")"
    [ -n "$PREFIX" ] || PREFIX="rsfleet"

    echo "rs-fleet scan: $ROOT"
    echo ""

    repos="$(discover_repos "$ROOT")"
    if [ -z "$repos" ]; then
      echo "No git repositories found."
      exit 0
    fi

    while IFS= read -r repo; do
      [ -n "$repo" ] || continue
      repo_name="$(basename "$repo")"
      if [ "$PREFIX" = "$repo_name" ]; then
        session_name="$(sanitize_name "$PREFIX")"
      else
        session_name="$(sanitize_name "$PREFIX-$repo_name")"
      fi
      prompt="Standby for repository '$repo_name' at '$repo'. Inspect the repository only when the user gives a concrete task. Do not modify files until asked."
      if spawn_agent "$repo" "$session_name" "$prompt"; then
        spawned=$((spawned + 1))
      else
        rc=$?
        if [ "$rc" = "2" ]; then
          skipped=$((skipped + 1))
        else
          failed=$((failed + 1))
        fi
      fi
    done <<< "$repos"
    ;;

  multi)
    [ $# -ge 1 ] || die "multi mode requires <repo>"
    TARGET_REPO="$1"
    shift

    while [ $# -gt 0 ]; do
      case "$1" in
        --count)
          [ $# -ge 2 ] || die "--count requires a value"
          COUNT="$2"
          shift 2
          ;;
        --prefix|--force-respawn|--dry-run)
          parse_common_arg "$@" || consumed=$?
          consumed=${consumed:-0}
          [ "$consumed" -gt 0 ] || die "unknown argument: $1"
          shift "$consumed"
          unset consumed
          ;;
        *)
          die "unknown argument: $1"
          ;;
      esac
    done

    [ -n "$COUNT" ] || die "multi mode requires --count N"
    printf '%s' "$COUNT" | grep -Eq '^[1-9][0-9]*$' || die "--count must be a positive integer"
    [ "$COUNT" -le 50 ] || die "--count is capped at 50"

    REPO="$(vcs_top "$TARGET_REPO")" || die "not a git/svn working copy: $TARGET_REPO"
    repo_name="$(basename "$REPO")"
    PREFIX="$(sanitize_name "$PREFIX")"
    [ -n "$PREFIX" ] || PREFIX="rsfleet"

    echo "rs-fleet multi: $REPO ($COUNT agents)"
    echo ""

    if [ "$PREFIX" = "$repo_name" ]; then
      base_name="$PREFIX"
    else
      base_name="$PREFIX-$repo_name"
    fi

    i=1
    while [ "$i" -le "$COUNT" ]; do
      suffix="$(printf '%02d' "$i")"
      session_name="$(sanitize_name "$base_name-$suffix")"
      prompt="Standby agent $suffix for repository '$repo_name'. You are operating in an isolated git worktree (detached HEAD). Coordinate through user instructions. Do not modify files until assigned a concrete task."
      if spawn_agent "$REPO" "$session_name" "$prompt" 1; then
        spawned=$((spawned + 1))
      else
        rc=$?
        if [ "$rc" = "2" ]; then
          skipped=$((skipped + 1))
        else
          failed=$((failed + 1))
        fi
      fi
      i=$((i + 1))
    done
    ;;

  cleanup)
    PATTERN=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --pattern)
          [ $# -ge 2 ] || die "--pattern requires a value"
          PATTERN="$2"
          shift 2
          ;;
        --prefix|--dry-run)
          parse_common_arg "$@" || consumed=$?
          consumed=${consumed:-0}
          [ "$consumed" -gt 0 ] || die "unknown argument: $1"
          shift "$consumed"
          unset consumed
          ;;
        *)
          die "unknown argument: $1"
          ;;
      esac
    done

    [ -f "$ROSTER" ] || die "roster not found: $ROSTER"
    command -v jq >/dev/null 2>&1 || die "jq is required for cleanup"

    PREFIX="$(sanitize_name "$PREFIX")"
    [ -n "$PREFIX" ] || PREFIX="rsfleet"

    if [ -n "$PATTERN" ]; then
      echo "rs-fleet cleanup: pattern='$PATTERN'"
    else
      echo "rs-fleet cleanup: prefix='$PREFIX-'"
    fi
    echo ""

    stopped=0
    cleanup_failed=0
    matches=""
    while IFS=$'\t' read -r short name; do
      [ -n "$short" ] && [ -n "$name" ] || continue
      if [ -n "$PATTERN" ]; then
        printf '%s' "$name" | grep -Eq -- "$PATTERN" || continue
      else
        case "$name" in
          "$PREFIX"-*) ;;
          *) continue ;;
        esac
      fi
      matches="${matches}${short}	${name}
"
    done < <(roster_all_workers)

    if [ -z "$matches" ]; then
      echo "No matching sessions found."
      echo ""
      echo "Result: stopped 0 / failed 0"
      exit 0
    fi

    stopped_shorts=""
    while IFS=$'\t' read -r short name; do
      [ -n "$short" ] && [ -n "$name" ] || continue
      if [ "$DRY_RUN" = "1" ]; then
        echo "  [$name] DRY-RUN (would stop $short and remove ~/.claude/jobs/$short)"
        stopped=$((stopped + 1))
        continue
      fi
      "$CLAUDE_NATIVE" stop "$short" </dev/null >/dev/null 2>&1 || true
      if remove_session_short "$short"; then
        wt="$WORKTREE_ROOT/$name"
        wt_msg=""
        if [ -d "$wt" ]; then
          if [ -e "$wt/.git" ]; then
            if (cd "$wt" && git worktree remove "$wt") >/dev/null 2>&1; then
              wt_msg=" + worktree"
            else
              wt_msg=" (worktree dirty, kept)"
            fi
          elif [ -d "$wt/.svn" ]; then
            if [ "$HAVE_SVN" = "1" ] && [ -z "$(svn status "$wt" 2>/dev/null)" ]; then
              rm -rf "$wt" && wt_msg=" + svn checkout"
            else
              wt_msg=" (svn checkout dirty, kept)"
            fi
          else
            rm -rf "$wt" 2>/dev/null && wt_msg=" + worktree"
          fi
        fi
        echo "  [$name] removed $short$wt_msg"
        stopped=$((stopped + 1))
      else
        echo "  [$name] failed to remove $short (still present in roster)" >&2
        cleanup_failed=$((cleanup_failed + 1))
      fi
    done <<< "$matches"

    echo ""
    if [ "$DRY_RUN" = "1" ]; then
      echo "Result: planned $stopped / failed $cleanup_failed"
    else
      echo "Result: stopped $stopped / failed $cleanup_failed"
    fi
    echo "Dashboard: claude agents"
    exit 0
    ;;

  *)
    usage
    exit 1
    ;;
esac

echo ""
if [ "$DRY_RUN" = "1" ]; then
  echo "Result: planned $spawned / skipped $skipped / failed $failed"
else
  echo "Result: spawned $spawned / skipped $skipped / failed $failed"
fi
echo "Dashboard: claude agents"
echo "Attach:    claude attach <session-name>"
