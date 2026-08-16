#!/bin/sh
# Link local package checkouts so cross-repo changes are testable without publishing.
#
# Usage:
#   link-local-packages.sh <project-map.yaml> status [options]
#   link-local-packages.sh <project-map.yaml> link   [options]
#   link-local-packages.sh <project-map.yaml> unlink [options]
#
# Options:
#   --spec <name>   Operate on specs/<name>/repos/ instead of repos/
#   --only <name>   Limit to this repository name (repeatable)
#
# Discovers which local checkouts depend on which other local checkouts by
# reading each package.json, then replaces the registry copy of that dependency
# inside the consumer's node_modules with a symlink to the local checkout.
#
# Safety model:
#   - Every edge is validated before any change is applied, so a failure on a
#     later consumer cannot leave earlier consumers half-linked.
#   - Destinations are anchored to the *physical* node_modules directory, so a
#     symlinked scope directory cannot redirect a write outside it.
#   - Only symlinks pointing at the expected local checkout are ever removed. A
#     symlink owned by something else (pnpm, a manual link) is reported and left
#     in place.
#
# No Git state is touched, no package.json is rewritten, and the global npm
# prefix is not used. `npm install` or `npm ci` in a consumer restores the
# published version and drops the link.

set -e

SCRIPT=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
. "$(dirname "$SCRIPT")/../../_shared/lib/common.sh"

MAP=$1
shift || true
ACTION=$1
shift || true

case $ACTION in
status | link | unlink) ;;
*) die "usage: link-local-packages.sh <project-map.yaml> status|link|unlink [--spec <name>] [--only <name> ...]" ;;
esac

SPEC=""
ONLY=""
while [ $# -gt 0 ]; do
	case $1 in
	--spec)
		shift
		[ $# -gt 0 ] || die "--spec requires a value"
		SPEC=$1
		;;
	--only)
		shift
		[ $# -gt 0 ] || die "--only requires a value"
		ONLY="$ONLY $1"
		;;
	*) die "unknown option: $1" ;;
	esac
	shift
done

command -v node >/dev/null 2>&1 || die "node is required but not found in PATH"

ROOT=$(meta_root_from_map "$MAP")

if [ -n "$SPEC" ]; then
	validate_spec_name "$SPEC"
	BASE="$ROOT/specs/$SPEC/repos"
	LABEL="specs/$SPEC/repos"
	[ -d "$BASE" ] || die "no feature worktrees at $LABEL (run prepare-spec first)"
else
	BASE="$ROOT/repos"
	LABEL="repos"
	[ -d "$BASE" ] || die "no reference clones at repos/ (run setup-repositories first)"
fi

if [ -n "$ONLY" ]; then
	NAMES=$ONLY
else
	NAMES=$(run_extract_project_map "$SCRIPT" "$MAP" --names)
fi

[ -n "$NAMES" ] || {
	printf 'no repositories configured in project map\n'
	exit 0
}

REGISTRY=$(mktemp)
EDGES=$(mktemp)
PLAN=$(mktemp)
PROBLEMS=$(mktemp)
trap 'rm -f "$REGISTRY" "$EDGES" "$PLAN" "$PROBLEMS"' EXIT INT HUP TERM

# Read the "name" field from a package.json. Never fails; prints nothing on error.
pkg_name() {
	node -e '
		const fs = require("fs");
		try {
			const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
			if (typeof j.name === "string") process.stdout.write(j.name);
		} catch (e) {}
	' "$1" 2>/dev/null || true
}

# Read the "version" field from a package.json. Never fails.
pkg_version() {
	node -e '
		const fs = require("fs");
		try {
			const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
			if (typeof j.version === "string") process.stdout.write(j.version);
		} catch (e) {}
	' "$1" 2>/dev/null || true
}

# List every declared dependency name, one per line. Never fails.
pkg_deps() {
	node -e '
		const fs = require("fs");
		try {
			const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
			const seen = new Set();
			for (const field of ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]) {
				const block = j[field];
				if (block && typeof block === "object") {
					for (const key of Object.keys(block)) seen.add(key);
				}
			}
			for (const key of seen) process.stdout.write(key + "\n");
		} catch (e) {}
	' "$1" 2>/dev/null || true
}

# npm package name: optional scope, no path separators beyond the scope slash.
validate_pkg_name() {
	printf '%s' "$1" | grep -qE '^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*$' || \
		die "unsafe package name: $1"
}

# Physical path a symlink resolves to, honouring relative targets. Needed because
# canonical_path() returns the link's own path when the target is missing.
symlink_target() {
	link=$1
	raw=$(readlink "$link")
	case $raw in
	/*) abs=$raw ;;
	*) abs=$(dirname "$link")/$raw ;;
	esac
	canonical_path "$abs"
}

# Resolve the node_modules entry for package $2 inside consumer $1, anchored to
# the physical node_modules directory so a symlinked ancestor cannot escape it.
# Prints "-" when node_modules does not exist. Exits 1 when a scope directory is
# a symlink resolving outside node_modules.
resolve_dest() {
	consumer_dir=$1
	pkg=$2
	nm="$consumer_dir/node_modules"
	if [ ! -d "$nm" ]; then
		printf '%s\n' '-'
		return 0
	fi
	nm_real=$(cd "$nm" && pwd -P)
	case $pkg in
	@*/*)
		scope_dir="$nm_real/${pkg%%/*}"
		if [ -e "$scope_dir" ] || [ -L "$scope_dir" ]; then
			[ "$(canonical_path "$scope_dir")" = "$scope_dir" ] || return 1
		fi
		printf '%s/%s\n' "$scope_dir" "${pkg#*/}"
		;;
	*)
		printf '%s/%s\n' "$nm_real" "$pkg"
		;;
	esac
}

# Classify the current state of a resolved destination.
edge_state() {
	dest=$1
	dep_dir=$2
	if [ "$dest" = "-" ]; then
		printf 'absent\n'
	elif [ -L "$dest" ]; then
		if [ "$(symlink_target "$dest")" = "$dep_dir" ]; then
			printf 'linked\n'
		else
			printf 'foreign\n'
		fi
	elif [ -d "$dest" ]; then
		printf 'registry\n'
	else
		printf 'absent\n'
	fi
}

# Index every local checkout that is an npm package: package-name<TAB>directory
for name in $NAMES; do
	validate_repo_name "$name"
	dir=$(safe_child_path "$BASE" "$name" "repository path")
	[ -d "$dir" ] || continue
	[ -f "$dir/package.json" ] || continue
	pkg=$(pkg_name "$dir/package.json")
	[ -n "$pkg" ] || continue
	validate_pkg_name "$pkg"
	printf '%s\t%s\n' "$pkg" "$dir" >>"$REGISTRY"
done

[ -s "$REGISTRY" ] || {
	printf 'no local npm packages found under %s\n' "$LABEL"
	exit 0
}

# Resolve each local package's declared deps against the index to find link edges:
# consumer-name<TAB>consumer-dir<TAB>dep-package<TAB>dep-dir
while IFS='	' read -r pkg dir; do
	[ -n "$pkg" ] || continue
	consumer=$(basename "$dir")
	pkg_deps "$dir/package.json" | while IFS= read -r dep; do
		[ -n "$dep" ] || continue
		[ "$dep" != "$pkg" ] || continue
		dep_dir=$(awk -F'\t' -v d="$dep" '$1 == d { print $2; exit }' "$REGISTRY")
		[ -n "$dep_dir" ] || continue
		printf '%s\t%s\t%s\t%s\n' "$consumer" "$dir" "$dep" "$dep_dir" >>"$EDGES"
	done
done <"$REGISTRY"

[ -s "$EDGES" ] || {
	printf 'no local package depends on another local package under %s\n' "$LABEL"
	printf 'link-local-packages complete\n'
	exit 0
}

# Phase 1 — preflight. Resolve and classify every edge, recording blocking
# problems, before any destructive operation runs.
while IFS='	' read -r consumer consumer_dir dep dep_dir; do
	[ -n "$consumer" ] || continue
	validate_pkg_name "$dep"

	if ! dest=$(resolve_dest "$consumer_dir" "$dep"); then
		if [ "$ACTION" = "status" ]; then
			printf 'ok unsafe      %s -> %s (node_modules/%s is a symlink outside node_modules)\n' \
				"$consumer" "$dep" "${dep%%/*}"
			continue
		fi
		printf '%s: node_modules/%s is a symlink resolving outside node_modules\n' \
			"$consumer" "${dep%%/*}" >>"$PROBLEMS"
		continue
	fi

	state=$(edge_state "$dest" "$dep_dir")

	if [ "$ACTION" = "link" ]; then
		if [ "$dest" = "-" ]; then
			printf '%s: no node_modules; run npm install there before linking\n' "$consumer" >>"$PROBLEMS"
			continue
		fi
		if [ "$state" = "foreign" ]; then
			printf '%s: %s is already a symlink to %s; remove it manually if you want it linked locally\n' \
				"$consumer" "$dep" "$(symlink_target "$dest")" >>"$PROBLEMS"
			continue
		fi
	fi

	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$consumer" "$consumer_dir" "$dep" "$dep_dir" "$dest" "$state" >>"$PLAN"
done <"$EDGES"

if [ -s "$PROBLEMS" ]; then
	while IFS= read -r problem; do
		printf 'error %s\n' "$problem" >&2
	done <"$PROBLEMS"
	die "preflight failed; no changes were made"
fi

# Phase 2 — apply. Every edge below has been validated.
CHANGED=0

while IFS='	' read -r consumer consumer_dir dep dep_dir dest state; do
	[ -n "$consumer" ] || continue

	case $ACTION in
	status)
		case $state in
		linked)
			if [ -d "$dest" ]; then
				printf 'ok linked      %s -> %s (%s)\n' "$consumer" "$dep" "$dep_dir"
			else
				printf 'ok dangling    %s -> %s (%s missing)\n' "$consumer" "$dep" "$dep_dir"
			fi
			;;
		foreign)
			printf 'ok foreign     %s -> %s (symlink to %s; not managed here)\n' \
				"$consumer" "$dep" "$(symlink_target "$dest")"
			;;
		registry)
			version=$(pkg_version "$dest/package.json")
			printf 'ok registry    %s -> %s (%s)\n' "$consumer" "$dep" "${version:-unknown}"
			;;
		*)
			printf 'ok absent      %s -> %s (not installed)\n' "$consumer" "$dep"
			;;
		esac
		;;
	link)
		if [ "$state" = "linked" ]; then
			printf 'ok already     %s -> %s\n' "$consumer" "$dep"
			continue
		fi
		if [ ! -d "$dep_dir/dist" ]; then
			printf 'warn no build  %s has no dist/; run its build before testing\n' "$dep"
		fi
		parent=$(dirname "$dest")
		[ -d "$parent" ] || mkdir -p "$parent"
		rm -rf "$dest"
		ln -s "$dep_dir" "$dest"
		printf 'ok linked      %s -> %s (%s)\n' "$consumer" "$dep" "$dep_dir"
		CHANGED=$((CHANGED + 1))
		;;
	unlink)
		case $state in
		linked)
			rm -f "$dest"
			printf 'ok unlinked    %s -> %s (run npm ci in %s to reinstall)\n' "$consumer" "$dep" "$consumer"
			CHANGED=$((CHANGED + 1))
			;;
		foreign)
			printf 'ok foreign     %s -> %s (symlink to %s; left as-is)\n' \
				"$consumer" "$dep" "$(symlink_target "$dest")"
			;;
		registry)
			printf 'ok registry    %s -> %s (not linked; left as-is)\n' "$consumer" "$dep"
			;;
		*)
			printf 'ok absent      %s -> %s (not installed)\n' "$consumer" "$dep"
			;;
		esac
		;;
	esac
done <"$PLAN"

if [ "$ACTION" = "link" ] && [ "$CHANGED" -gt 0 ]; then
	printf 'note: npm install or npm ci in a consumer silently removes these links\n'
fi

printf 'link-local-packages complete\n'
