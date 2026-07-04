#!/bin/sh
# Fast-forward reference clones on their configured default branch.
#
# Usage: refresh-repositories.sh <project-map.yaml> [repository-name ...]
#
# Requires clean working trees, matching origin, checked-out default branch,
# and no local-only commits or divergence. Never stashes, resets, or merges.

set -e

SCRIPT=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
. "$(dirname "$SCRIPT")/../../_shared/lib/common.sh"

MAP=$1
shift || true

require_git_version
ROOT=$(meta_root_from_map "$MAP")
REPOS_DIR="$ROOT/repos"

if [ $# -gt 0 ]; then
	NAMES=$*
else
	NAMES=$(run_extract_project_map "$SCRIPT" "$MAP" --names)
fi

[ -n "$NAMES" ] || {
	printf 'no repositories configured in project map\n'
	exit 0
}

for name in $NAMES; do
	validate_repo_name "$name"
	record=$(run_extract_project_map "$SCRIPT" "$MAP" --get "$name")
	clone_url=$(printf '%s' "$record" | cut -f2)
	default_branch=$(printf '%s' "$record" | cut -f3)
	validate_branch_ref "$default_branch" "default_branch for $name"

	target=$(safe_child_path "$REPOS_DIR" "$name" "repository path")
	[ -d "$target/.git" ] || die "reference clone missing for $name (run setup-repositories)"

	verify_origin_url "$target" "$clone_url"
	require_clean_worktree "$target" "repos/$name"

	current_branch=$(git -C "$target" rev-parse --abbrev-ref HEAD)
	[ "$current_branch" = "$default_branch" ] || \
		die "repos/$name is on branch $current_branch, expected $default_branch"

	git -C "$target" fetch origin --prune || die "fetch failed for $name"

	if ! git -C "$target" show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
		die "origin/$default_branch not found for $name"
	fi

	upstream="origin/$default_branch"
	counts=$(git -C "$target" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null) || \
		die "unable to compare HEAD with $upstream for $name"
	ahead=$(printf '%s' "$counts" | awk '{print $1}')
	behind=$(printf '%s' "$counts" | awk '{print $2}')

	if [ "$ahead" -gt 0 ]; then
		if [ "$behind" -gt 0 ]; then
			die "repos/$name has diverged from $upstream; refusing to refresh"
		fi
		die "repos/$name has local commits ahead of $upstream; refusing to refresh"
	fi

	if [ "$behind" -gt 0 ]; then
		git -C "$target" merge --ff-only "$upstream" || die "fast-forward failed for $name"
		printf 'ok refreshed %s (fast-forward)\n' "$name"
	else
		printf 'ok up-to-date %s\n' "$name"
	fi
done

printf 'refresh-repositories complete\n'
