#!/bin/sh
# Remove feature worktrees for a specification (never deletes branches or spec docs).
#
# Usage: close-spec.sh <project-map.yaml> <spec-name> [--offline] [--acknowledge-unpushed]
#
# Two-phase safety: preflight across all repositories, then removal only if all pass.

set -e

SCRIPT=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
SHARED=$(dirname "$SCRIPT")/../../_shared
. "$SHARED/lib/common.sh"

MAP=$1
SPEC=$2
OFFLINE=0
ACK_UNPUSHED=0
shift 2 || true

for arg in "$@"; do
	case $arg in
	--offline) OFFLINE=1 ;;
	--acknowledge-unpushed) ACK_UNPUSHED=1 ;;
	*) die "unknown argument: $arg" ;;
	esac
done

[ -n "$MAP" ] && [ -n "$SPEC" ] || \
	die "usage: close-spec.sh <project-map.yaml> <spec-name> [--offline] [--acknowledge-unpushed]"

require_git_version
validate_spec_name "$SPEC"
ROOT=$(meta_root_from_map "$MAP")
SPEC_DIR="$ROOT/specs/$SPEC"
REPOS_TXT="$SPEC_DIR/repos.txt"
WORKTREES_DIR="$SPEC_DIR/repos"
PARSE="$SHARED/parse-repos-txt.sh"

[ -d "$SPEC_DIR" ] || die "spec directory not found: specs/$SPEC"
[ -f "$REPOS_TXT" ] || die "repos.txt not found: specs/$SPEC/repos.txt"
[ -x "$PARSE" ] || die "missing parse helper: $PARSE"

NAMES=$("$PARSE" "$REPOS_TXT" --validate-map "$MAP")
[ -n "$NAMES" ] || die "repos.txt has no repository entries"

BRANCH="feature/$SPEC"
STALE_NOTE=0
ORPHANED=""

# Phase 1: preflight (atomic — any failure aborts before removals).
for name in $NAMES; do
	record=$(run_extract_project_map "$SCRIPT" "$MAP" --get "$name")
	clone_url=$(printf '%s' "$record" | cut -f2)
	default_branch=$(printf '%s' "$record" | cut -f3)

	ref_clone=$(safe_child_path "$ROOT/repos" "$name" "reference clone")
	[ -d "$ref_clone/.git" ] || die "reference clone missing for $name"
	verify_origin_url "$ref_clone" "$clone_url"

	worktree_path=$(safe_child_path "$WORKTREES_DIR" "$name" "worktree path")

	if [ "$OFFLINE" -eq 0 ]; then
		if ! git -C "$ref_clone" fetch origin --prune; then
			die "fetch failed for $name; refusing close-spec (use --offline for acknowledged offline close)"
		fi
	else
		STALE_NOTE=1
	fi

	existing=$(worktree_registered_at "$ref_clone" "$worktree_path")
	if [ ! -d "$worktree_path" ]; then
		if [ "$existing" = "yes" ]; then
			printf 'ok stale worktree metadata %s (will prune)\n' "$name"
		else
			printf 'skip %s (no worktree)\n' "$name"
		fi
		continue
	fi

	[ "$existing" = "yes" ] || \
		die "directory exists at specs/$SPEC/repos/$name but is not a registered worktree"

	require_clean_worktree "$worktree_path" "specs/$SPEC/repos/$name"

	wt_branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null) || wt_branch=""
	[ "$wt_branch" = "$BRANCH" ] || die "worktree for $name is on $wt_branch, expected $BRANCH"

	unpushed=$(unpushed_feature_commits "$worktree_path" "$default_branch" "$BRANCH")
	if [ "$unpushed" -gt 0 ] && [ "$ACK_UNPUSHED" -eq 0 ]; then
		die "specs/$SPEC/repos/$name has unpushed commits on $BRANCH; use --acknowledge-unpushed to close anyway (branch is retained)"
	fi
	if [ "$OFFLINE" -eq 1 ]; then
		STALE_NOTE=1
	fi
done

if [ "$STALE_NOTE" -eq 1 ]; then
	printf 'note: remote reachability is stale (offline close); branches and commits retained\n'
fi

# Phase 2: remove worktrees.
for name in $NAMES; do
	ref_clone=$(safe_child_path "$ROOT/repos" "$name" "reference clone")
	worktree_path=$(safe_child_path "$WORKTREES_DIR" "$name" "worktree path")

	existing=$(worktree_registered_at "$ref_clone" "$worktree_path")

	if [ "$existing" = "yes" ]; then
		if [ -d "$worktree_path" ]; then
			git -C "$ref_clone" worktree remove "$worktree_path" || \
				die "failed to remove worktree for $name"
			git -C "$ref_clone" worktree prune
			printf 'ok removed worktree %s\n' "$name"
		else
			git -C "$ref_clone" worktree remove --force "$worktree_path" || \
				die "failed to remove stale worktree metadata for $name"
			if [ "$(worktree_registered_at "$ref_clone" "$worktree_path")" = "yes" ]; then
				die "failed to remove stale worktree metadata for $name"
			fi
			printf 'ok removed stale worktree metadata %s\n' "$name"
		fi
	elif [ -d "$worktree_path" ]; then
		ORPHANED="$ORPHANED $worktree_path"
	fi
done

if [ -n "$ORPHANED" ]; then
	die "close-spec incomplete: unregistered worktree directories remain:$ORPHANED"
fi

printf 'close-spec complete for %s (branches and specification documents retained)\n' "$SPEC"
