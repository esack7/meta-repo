#!/bin/sh
# Shared POSIX helpers for meta-repo skill scripts.

die() {
	printf '%s\n' "$*" >&2
	exit 1
}

# Resolve meta-repo root from project map path (directory containing the file).
meta_root_from_map() {
	map_path=$1
	if [ -z "$map_path" ]; then
		die "project map path is required"
	fi
	case $map_path in
	/*) ;;
	*) map_path=$(cd "$(dirname "$map_path")" && pwd)/$(basename "$map_path") ;;
	esac
	if [ ! -f "$map_path" ]; then
		die "project map not found: $map_path"
	fi
	dir=$(dirname "$map_path")
	printf '%s\n' "$dir"
}

# Require Git 2.17+ (the first supported version with `git worktree remove`).
require_git_version() {
	if ! command -v git >/dev/null 2>&1; then
		die "git is required but not found in PATH"
	fi
	major=$(git --version | sed -n 's/^git version \([0-9]*\)\..*/\1/p')
	minor=$(git --version | sed -n 's/^git version [0-9]*\.\([0-9]*\).*/\1/p')
	[ -n "$major" ] && [ -n "$minor" ] || die "unable to parse git version"
	if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 17 ]; }; then
		die "git 2.17 or newer is required (found $(git --version))"
	fi
}

# Repository name: single safe path component.
validate_repo_name() {
	name=$1
	label=${2:-repository name}
	printf '%s' "$name" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$' || \
		die "invalid $label: $name (must match ^[A-Za-z0-9][A-Za-z0-9._-]*$)"
	case $name in
	. | ..) die "invalid $label: $name" ;;
	esac
}

# Git ref safety for default branches.
validate_branch_ref() {
	ref=$1
	label=${2:-branch ref}
	[ -n "$ref" ] || die "missing $label"
	git check-ref-format --branch "$ref" >/dev/null 2>&1 || die "invalid $label: $ref"
}

# Spec name: lowercase slug.
validate_spec_name() {
	spec=$1
	printf '%s' "$spec" | grep -qE '^[a-z0-9][a-z0-9-]*$' || \
		die "invalid spec name: $spec (must match ^[a-z0-9][a-z0-9-]*$)"
}

# Resolve shared skill library directory relative to a skill script in .../scripts/.
shared_lib_dir() {
	script_dir=$(cd "$(dirname "$1")" && pwd)
	skills_dir=$(cd "$script_dir/../.." && pwd)
	printf '%s/_shared' "$skills_dir"
}

# Source shared extract helper path.
shared_extract_script() {
	lib=$(shared_lib_dir "$1")
	printf '%s/extract-project-map.sh' "$lib"
}

# Safe path under base directory; dies on traversal or escape.
safe_child_path() {
	base=$1
	name=$2
	label=${3:-path}
	validate_repo_name "$name" "$label"
	case $base in
	/*) ;;
	*) base=$(cd "$base" && pwd) ;;
	esac
	child="$base/$name"
	case $child in
	"$base"/*) ;;
	*) die "unsafe $label: $name" ;;
	esac
	real_base=$(cd "$base" && pwd -P)
	real_child=$(cd "$base" && cd "$name" 2>/dev/null && pwd -P) || real_child="$real_base/$name"
	case $real_child in
	"$real_base" | "$real_base"/*) printf '%s\n' "$real_child" ;;
	*) die "unsafe $label: $name (escapes $base)" ;;
	esac
}

# Canonical absolute path for stable comparisons (resolves symlinks like /tmp -> /private/tmp).
canonical_path() {
	p=$1
	if [ -d "$p" ]; then
		(cd "$p" && pwd -P)
	elif [ -e "$p" ]; then
		dir=$(dirname "$p")
		base=$(basename "$p")
		printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
	else
		parent=$(dirname "$p")
		base=$(basename "$p")
		if [ -d "$parent" ]; then
			printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
		else
			printf '%s\n' "$p"
		fi
	fi
}

# True when path is a registered worktree of repo_dir.
worktree_registered_at() {
	repo_dir=$1
	path=$2
	canonical=$(canonical_path "$path")
	git -C "$repo_dir" worktree list --porcelain 2>/dev/null | awk -v p="$canonical" '
		/^worktree / {
			wt = $0
			sub(/^worktree /, "", wt)
			if (wt == p) found = 1
		}
		END { if (found) print "yes" }
	'
}

# Count unpushed commits on a feature worktree (refuses-by-default input for close-spec).
# Requires fetch when online; uses last-known origin/* refs when offline.
unpushed_feature_commits() {
	worktree_dir=$1
	default_branch=$2
	feature_branch=$3
	if git -C "$worktree_dir" show-ref --verify --quiet "refs/remotes/origin/$feature_branch"; then
		git -C "$worktree_dir" rev-list --count "origin/$feature_branch..HEAD" 2>/dev/null || printf '0'
	elif git -C "$worktree_dir" show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
		git -C "$worktree_dir" rev-list --count "origin/$default_branch..HEAD" 2>/dev/null || printf '0'
	else
		git -C "$worktree_dir" rev-list --count HEAD 2>/dev/null || printf '0'
	fi
}

# Verify origin URL matches expected (exact string).
verify_origin_url() {
	repo_dir=$1
	expected=$2
	actual=$(git -C "$repo_dir" remote get-url origin 2>/dev/null) || die "no origin remote in $repo_dir"
	[ "$actual" = "$expected" ] || die "origin mismatch in $repo_dir: expected $expected, got $actual"
}

# Working tree must be clean.
require_clean_worktree() {
	repo_dir=$1
	label=${2:-$repo_dir}
	if [ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]; then
		die "working tree is not clean: $label"
	fi
}

# Locate this skill's shared extract script and run list mode.
# shellcheck disable=SC2039
run_extract_project_map() {
	script=$1
	map_path=$2
	shift 2
	extract=$(shared_extract_script "$script")
	[ -x "$extract" ] || die "missing extract helper: $extract"
	"$extract" "$map_path" "$@"
}
