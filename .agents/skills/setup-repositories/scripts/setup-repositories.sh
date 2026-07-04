#!/bin/sh
# Clone missing reference repositories under repos/<name>/.
#
# Usage: setup-repositories.sh <project-map.yaml> [repository-name ...]
#
# With no repository names, processes every entry in the project map.
# Existing clones with matching origin are left unchanged.

set -e

SCRIPT=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
. "$(dirname "$SCRIPT")/../../_shared/lib/common.sh"

MAP=$1
shift || true

require_git_version
ROOT=$(meta_root_from_map "$MAP")
REPOS_DIR="$ROOT/repos"

cleanup_tmp() {
	for d in "$@"; do
		if [ -n "$d" ] && [ -d "$d" ]; then
			rm -rf "$d"
		fi
	done
}

# Build target name list.
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
	[ -d "$REPOS_DIR" ] || mkdir -p "$REPOS_DIR"
	record=$(run_extract_project_map "$SCRIPT" "$MAP" --get "$name")
	[ -n "$record" ] || die "repository not in project map: $name"
	clone_url=$(printf '%s' "$record" | cut -f2)
	default_branch=$(printf '%s' "$record" | cut -f3)
	validate_branch_ref "$default_branch" "default_branch for $name"

	target=$(safe_child_path "$REPOS_DIR" "$name" "repository path")
	tmp=""

	if [ -d "$target" ]; then
		if [ ! -d "$target/.git" ]; then
			die "conflicting non-git path exists: $target"
		fi
		verify_origin_url "$target" "$clone_url"
		printf 'ok existing %s\n' "$name"
		continue
	fi

	if [ -e "$target" ]; then
		die "conflicting path exists: $target"
	fi

	tmp=$(mktemp -d "$REPOS_DIR/.setup-tmp-XXXXXX") || \
		die "unable to create temporary clone directory under $REPOS_DIR"
	trap 'cleanup_tmp "$tmp"' EXIT INT HUP TERM

	printf 'cloning %s...\n' "$name"
	git clone --origin origin --branch "$default_branch" -- "$clone_url" "$tmp" || die "clone failed for $name"

	verify_origin_url "$tmp" "$clone_url"
	current_branch=$(git -C "$tmp" rev-parse --abbrev-ref HEAD)
	[ "$current_branch" = "$default_branch" ] || die "clone of $name is on $current_branch, expected $default_branch"

	if ! git -C "$tmp" show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
		die "configured default branch origin/$default_branch not found after cloning $name"
	fi

	mv "$tmp" "$target"
	tmp=""
	trap - EXIT INT HUP TERM
	printf 'ok cloned %s\n' "$name"
done

printf 'setup-repositories complete\n'
