#!/bin/sh
# Create feature worktrees for a specification.
#
# Usage: prepare-spec.sh <project-map.yaml> <spec-name> [--reuse-branches]
#
# Reads specs/<spec-name>/repos.txt, validates clones, fetches origin, and creates
# feature/<spec-name> worktrees under specs/<spec-name>/repos/.

set -e

SCRIPT=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
SHARED=$(dirname "$SCRIPT")/../../_shared
. "$SHARED/lib/common.sh"

MAP=$1
SPEC=$2
REUSE=0
shift 2 || true

for arg in "$@"; do
	case $arg in
	--reuse-branches) REUSE=1 ;;
	*) die "unknown argument: $arg" ;;
	esac
done

[ -n "$MAP" ] && [ -n "$SPEC" ] || die "usage: prepare-spec.sh <project-map.yaml> <spec-name> [--reuse-branches]"

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
mkdir -p "$WORKTREES_DIR"

for name in $NAMES; do
	record=$(run_extract_project_map "$SCRIPT" "$MAP" --get "$name")
	clone_url=$(printf '%s' "$record" | cut -f2)
	default_branch=$(printf '%s' "$record" | cut -f3)
	validate_branch_ref "$default_branch" "default_branch for $name"

	ref_clone=$(safe_child_path "$ROOT/repos" "$name" "reference clone")
	[ -d "$ref_clone/.git" ] || die "reference clone missing for $name at repos/$name (run setup-repositories)"
	verify_origin_url "$ref_clone" "$clone_url"

	worktree_path=$(safe_child_path "$WORKTREES_DIR" "$name" "worktree path")

	git -C "$ref_clone" fetch origin --prune || die "fetch failed for $name"
	upstream="origin/$default_branch"
	git -C "$ref_clone" show-ref --verify --quiet "refs/remotes/$upstream" || \
		die "remote ref $upstream not found for $name"

	existing=$(worktree_registered_at "$ref_clone" "$worktree_path")

	if [ -d "$worktree_path" ] && [ "$existing" = "yes" ]; then
		require_clean_worktree "$worktree_path" "specs/$SPEC/repos/$name"
		wt_branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null) || wt_branch=""
		if [ "$wt_branch" = "$BRANCH" ]; then
			printf 'ok existing worktree %s\n' "$name"
			continue
		fi
		die "worktree exists at specs/$SPEC/repos/$name on branch $wt_branch (expected $BRANCH)"
	fi

	if [ -e "$worktree_path" ]; then
		die "conflicting path exists: $worktree_path"
	fi

	# Branch collision checks in reference clone.
	if git -C "$ref_clone" show-ref --verify --quiet "refs/heads/$BRANCH"; then
		if [ "$REUSE" -eq 0 ]; then
			die "local branch $BRANCH already exists for $name; rerun with --reuse-branches to reuse"
		fi
	fi
	if git -C "$ref_clone" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
		if [ "$REUSE" -eq 0 ]; then
			die "remote branch origin/$BRANCH already exists for $name; rerun with --reuse-branches to reuse"
		fi
	fi

	if [ "$REUSE" -eq 1 ]; then
		if git -C "$ref_clone" show-ref --verify --quiet "refs/heads/$BRANCH"; then
			git -C "$ref_clone" worktree add "$worktree_path" "$BRANCH" || \
				die "failed to attach worktree for $name on existing $BRANCH"
		elif git -C "$ref_clone" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
			git -C "$ref_clone" worktree add -B "$BRANCH" "$worktree_path" "origin/$BRANCH" || \
				die "failed to attach worktree for $name from origin/$BRANCH"
		else
			git -C "$ref_clone" worktree add -B "$BRANCH" "$worktree_path" "$upstream" || \
				die "failed to create worktree for $name"
		fi
	else
		git -C "$ref_clone" worktree add -B "$BRANCH" "$worktree_path" "$upstream" || \
			die "failed to create worktree for $name"
	fi

	require_clean_worktree "$worktree_path" "specs/$SPEC/repos/$name"
	printf 'ok prepared %s\n' "$name"
done

printf 'prepare-spec complete for %s\n' "$SPEC"
