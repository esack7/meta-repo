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

spec_branch() {
	if [ -f "$SPEC_DIR/delivery.json" ]; then
		python3 "$SHARED/delivery.py" "$MAP" "$SPEC" active-branch "$1"
	else
		printf 'feature/%s\n' "$SPEC"
	fi
}
mkdir -p "$WORKTREES_DIR"

PLAN_DIR=$(mktemp -d "$SPEC_DIR/.prepare-spec-plan-XXXXXX") || \
	die "unable to create prepare plan under specs/$SPEC"
APPLIED="$PLAN_DIR/applied"
APPLY_ACTIVE=0

rollback_prepare() {
	[ -s "$APPLIED" ] || return 0
	printf 'note: prepare-spec failed; rolling back worktrees created by this invocation\n' >&2
	while read -r applied_name applied_action; do
		[ -n "$applied_name" ] || continue
		applied_ref=$(safe_child_path "$ROOT/repos" "$applied_name" "reference clone")
		applied_path=$(safe_child_path "$WORKTREES_DIR" "$applied_name" "worktree path")
		removed=1
		if [ "$(worktree_registered_at "$applied_ref" "$applied_path")" = "yes" ]; then
			if ! git -C "$applied_ref" worktree remove "$applied_path" >/dev/null 2>&1; then
				printf 'warning: unable to roll back worktree for %s; it was left in place\n' "$applied_name" >&2
				removed=0
			fi
		fi
		case $applied_action in
		create | reuse-remote)
			BRANCH=$(spec_branch "$applied_name")
			planned_base=$(cat "$PLAN_DIR/$applied_name.base")
			current_head=$(git -C "$applied_ref" rev-parse "refs/heads/$BRANCH" 2>/dev/null || true)
			if [ "$removed" -eq 1 ] && [ -n "$current_head" ] && [ "$current_head" = "$planned_base" ]; then
				git -C "$applied_ref" branch -D "$BRANCH" >/dev/null 2>&1 || \
					printf 'warning: unable to remove newly created branch %s for %s\n' "$BRANCH" "$applied_name" >&2
			fi
			;;
		esac
	done < "$APPLIED"
}

cleanup_prepare() {
	status=$?
	trap - EXIT INT HUP TERM
	if [ "$APPLY_ACTIVE" -eq 1 ] && [ "$status" -ne 0 ]; then
		rollback_prepare
	fi
	rm -rf "$PLAN_DIR"
	exit "$status"
}

trap cleanup_prepare EXIT
trap 'exit 1' INT HUP TERM

# Phase 1: fetch and validate every repository before creating any worktree or branch.
for name in $NAMES; do
	BRANCH=$(spec_branch "$name")
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
		wt_branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null) || wt_branch=""
		if [ "$wt_branch" = "$BRANCH" ] || { [ -f "$SPEC_DIR/delivery.json" ] &&
			python3 "$SHARED/delivery.py" "$MAP" "$SPEC" branch "$name" "$wt_branch"; }; then
			if [ -n "$(git -C "$worktree_path" status --porcelain 2>/dev/null)" ]; then
				printf '%s\n' 'skip-dirty' > "$PLAN_DIR/$name.action"
			else
				printf '%s\n' 'skip' > "$PLAN_DIR/$name.action"
			fi
			continue
		fi
		die "worktree exists at specs/$SPEC/repos/$name on branch $wt_branch (expected $BRANCH)"
	fi
	if [ "$existing" = "yes" ]; then
		die "stale worktree registration exists for specs/$SPEC/repos/$name (run close-spec to prune it)"
	fi

	if [ -e "$worktree_path" ]; then
		die "conflicting path exists: $worktree_path"
	fi

	action=create
	if git -C "$ref_clone" show-ref --verify --quiet "refs/heads/$BRANCH"; then
		if [ "$REUSE" -eq 0 ]; then
			die "local branch $BRANCH already exists for $name; rerun with --reuse-branches to reuse"
		fi
		checked_out=$(git -C "$ref_clone" worktree list --porcelain | awk -v branch="refs/heads/$BRANCH" '
			/^worktree / { path = $0; sub(/^worktree /, "", path) }
			$0 == "branch " branch { print path; exit }
		')
		[ -z "$checked_out" ] || die "branch $BRANCH for $name is already checked out at $checked_out"
		action=reuse-local
	fi
	if git -C "$ref_clone" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
		if [ "$REUSE" -eq 0 ]; then
			die "remote branch origin/$BRANCH already exists for $name; rerun with --reuse-branches to reuse"
		fi
		if [ "$action" = "create" ]; then
			action=reuse-remote
		fi
	fi

	if [ "$BRANCH" != "feature/$SPEC" ] && [ "$action" = "create" ]; then
		die "registered branch $BRANCH is missing for $name; refusing to recreate its history"
	fi
	printf '%s\n' "$action" > "$PLAN_DIR/$name.action"
	case $action in
	create) git -C "$ref_clone" rev-parse "$upstream" > "$PLAN_DIR/$name.base" ;;
	reuse-remote) git -C "$ref_clone" rev-parse "origin/$BRANCH" > "$PLAN_DIR/$name.base" ;;
	esac
done

# Phase 2: apply the complete plan. The exit trap rolls back new worktrees on failure.
APPLY_ACTIVE=1
for name in $NAMES; do
	BRANCH=$(spec_branch "$name")
	action=$(cat "$PLAN_DIR/$name.action")
	case $action in
	skip)
		printf 'ok existing worktree %s\n' "$name"
		continue
		;;
	skip-dirty)
		printf 'ok existing worktree %s (dirty; left unchanged)\n' "$name"
		continue
		;;
	esac

	record=$(run_extract_project_map "$SCRIPT" "$MAP" --get "$name")
	default_branch=$(printf '%s' "$record" | cut -f3)
	ref_clone=$(safe_child_path "$ROOT/repos" "$name" "reference clone")
	worktree_path=$(safe_child_path "$WORKTREES_DIR" "$name" "worktree path")
	upstream="origin/$default_branch"

	case $action in
	reuse-local)
		git -C "$ref_clone" worktree add "$worktree_path" "$BRANCH" || \
			die "failed to attach worktree for $name on existing $BRANCH"
		;;
	reuse-remote)
		git -C "$ref_clone" worktree add -b "$BRANCH" "$worktree_path" "origin/$BRANCH" || \
			die "failed to attach worktree for $name from origin/$BRANCH"
		;;
	create)
		git -C "$ref_clone" worktree add -b "$BRANCH" "$worktree_path" "$upstream" || \
			die "failed to create worktree for $name"
		;;
	*) die "invalid prepare action for $name: $action" ;;
	esac
	printf '%s %s\n' "$name" "$action" >> "$APPLIED"

	require_clean_worktree "$worktree_path" "specs/$SPEC/repos/$name"
	printf 'ok prepared %s\n' "$name"
done

APPLY_ACTIVE=0
printf 'prepare-spec complete for %s\n' "$SPEC"
