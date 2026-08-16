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
# Only <consumer>/node_modules/ is ever modified. No Git state is touched, no
# package.json is rewritten, and the global npm prefix is not used. `npm install`
# or `npm ci` in a consumer restores the published version and drops the link.

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
trap 'rm -f "$REGISTRY" "$EDGES"' EXIT INT HUP TERM

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

# Absolute path of the node_modules entry for package $2 inside consumer dir $1.
dep_path() {
	consumer_dir=$1
	pkg=$2
	case $pkg in
	@*/*) printf '%s/node_modules/%s/%s\n' "$consumer_dir" "${pkg%%/*}" "${pkg#*/}" ;;
	*) printf '%s/node_modules/%s\n' "$consumer_dir" "$pkg" ;;
	esac
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

CHANGED=0

while IFS='	' read -r consumer consumer_dir dep dep_dir; do
	[ -n "$consumer" ] || continue
	validate_pkg_name "$dep"
	dest=$(dep_path "$consumer_dir" "$dep")

	# Defense in depth: never operate outside the consumer's node_modules.
	case $dest in
	"$consumer_dir"/node_modules/*) ;;
	*) die "refusing to touch path outside node_modules: $dest" ;;
	esac

	case $ACTION in
	status)
		if [ -L "$dest" ]; then
			target=$(readlink "$dest")
			if [ -d "$dest" ]; then
				printf 'ok linked      %s -> %s (%s)\n' "$consumer" "$dep" "$target"
			else
				printf 'ok dangling    %s -> %s (%s missing)\n' "$consumer" "$dep" "$target"
			fi
		elif [ -d "$dest" ]; then
			version=$(pkg_version "$dest/package.json")
			printf 'ok registry    %s -> %s (%s)\n' "$consumer" "$dep" "${version:-unknown}"
		else
			printf 'ok absent      %s -> %s (not installed)\n' "$consumer" "$dep"
		fi
		;;
	link)
		[ -d "$consumer_dir/node_modules" ] || \
			die "$consumer has no node_modules; run npm install there before linking"
		if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$dep_dir" ]; then
			printf 'ok already     %s -> %s\n' "$consumer" "$dep"
			continue
		fi
		if [ ! -d "$dep_dir/dist" ]; then
			printf 'warn no build  %s has no dist/; run its build before testing\n' "$dep"
		fi
		case $dep in
		@*/*)
			scope_dir="$consumer_dir/node_modules/${dep%%/*}"
			[ -d "$scope_dir" ] || mkdir -p "$scope_dir"
			;;
		esac
		rm -rf "$dest"
		ln -s "$dep_dir" "$dest"
		printf 'ok linked      %s -> %s (%s)\n' "$consumer" "$dep" "$dep_dir"
		CHANGED=$((CHANGED + 1))
		;;
	unlink)
		if [ -L "$dest" ]; then
			rm -f "$dest"
			printf 'ok unlinked    %s -> %s (run npm ci in %s to reinstall)\n' "$consumer" "$dep" "$consumer"
			CHANGED=$((CHANGED + 1))
		elif [ -d "$dest" ]; then
			printf 'ok registry    %s -> %s (not linked; left as-is)\n' "$consumer" "$dep"
		else
			printf 'ok absent      %s -> %s (not installed)\n' "$consumer" "$dep"
		fi
		;;
	esac
done <"$EDGES"

if [ "$ACTION" = "link" ] && [ "$CHANGED" -gt 0 ]; then
	printf 'note: npm install or npm ci in a consumer silently removes these links\n'
fi

printf 'link-local-packages complete\n'
