#!/bin/sh
# Create a specification directory with templates and repos.txt.
#
# Usage: create-spec.sh <project-map.yaml> <spec-name> [--summary TEXT] [--amend] <repo-name>...

set -e

SCRIPT=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
SHARED=$(dirname "$SCRIPT")/../../_shared
. "$SHARED/lib/common.sh"

MAP=$1
SPEC=$2
shift 2 || true

SUMMARY=""
REPOS=""
AMEND=0

while [ $# -gt 0 ]; do
	case $1 in
	--summary)
		shift || die "create-spec: missing value for --summary"
		SUMMARY=${1:-}
		shift || true
		;;
	--amend)
		AMEND=1
		shift
		;;
	-*)
		die "unknown argument: $1"
		;;
	*)
		REPOS="$REPOS $1"
		shift
		;;
	esac
done

[ -n "$MAP" ] && [ -n "$SPEC" ] || \
	die "usage: create-spec.sh <project-map.yaml> <spec-name> [--summary TEXT] [--amend] <repo-name>..."

validate_spec_name "$SPEC"
ROOT=$(meta_root_from_map "$MAP")
SPEC_DIR="$ROOT/specs/$SPEC"
TEMPLATE_DIR=$(dirname "$SCRIPT")/../templates

[ -d "$TEMPLATE_DIR" ] || die "missing templates directory for create-spec"

REPOS=$(printf '%s\n' $REPOS | sed '/^$/d')
[ -n "$REPOS" ] || die "at least one repository name is required"

for name in $REPOS; do
	validate_repo_name "$name"
	run_extract_project_map "$SCRIPT" "$MAP" --get "$name" >/dev/null || \
		die "unknown repository in project map: $name"
done

if [ "$AMEND" -eq 1 ]; then
	[ -z "$SUMMARY" ] || die "--summary cannot be used with --amend; edit specification Markdown explicitly"
	[ -d "$SPEC_DIR" ] || die "spec directory not found: specs/$SPEC"
	[ -f "$SPEC_DIR/repos.txt" ] || die "repos.txt not found: specs/$SPEC/repos.txt"

	PARSE="$SHARED/parse-repos-txt.sh"
	[ -x "$PARSE" ] || die "missing parse helper: $PARSE"
	OLD_REPOS=$("$PARSE" "$SPEC_DIR/repos.txt")
	WORKTREES_DIR="$SPEC_DIR/repos"
	BRANCH="feature/$SPEC"

	if [ -d "$WORKTREES_DIR" ] && \
		[ -n "$(find "$WORKTREES_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
		die "cannot amend repos.txt while specs/$SPEC/repos contains worktrees or other entries; close the spec first"
	fi

	for old_name in $OLD_REPOS; do
		old_ref="$ROOT/repos/$old_name"
		old_worktree="$WORKTREES_DIR/$old_name"
		if [ -d "$old_ref/.git" ]; then
			if [ "$(worktree_registered_at "$old_ref" "$old_worktree")" = "yes" ]; then
				die "cannot amend repos.txt while a worktree remains registered for $old_name"
			fi
			if git -C "$old_ref" show-ref --verify --quiet "refs/heads/$BRANCH" || \
				git -C "$old_ref" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
				die "cannot amend repos.txt after $BRANCH has been created for $old_name; use a new spec name for a new repository selection"
			fi
		fi
	done

	TMP_REPOS=$(mktemp "$SPEC_DIR/.repos-txt-XXXXXX") || die "unable to create temporary repos.txt"
	cleanup_amend() {
		rm -f "$TMP_REPOS"
	}
	trap cleanup_amend EXIT INT HUP TERM
	for name in $REPOS; do
		if grep -qxF "$name" "$TMP_REPOS" 2>/dev/null; then
			die "duplicate repository name: $name"
		fi
		printf '%s\n' "$name" >> "$TMP_REPOS"
	done
	mv "$TMP_REPOS" "$SPEC_DIR/repos.txt"
	trap - EXIT INT HUP TERM
	printf 'ok amended specs/%s/repos.txt\n' "$SPEC"
	printf 'create-spec amend complete for %s\n' "$SPEC"
	exit 0
fi

[ ! -e "$SPEC_DIR" ] || die "spec directory already exists: specs/$SPEC"

mkdir -p "$ROOT/specs"

TMP_REPOS=$(mktemp)
TMP_SPEC=$(mktemp -d "$ROOT/specs/.create-spec-tmp-XXXXXX")
cleanup() {
	rm -f "$TMP_REPOS"
	rm -rf "$TMP_SPEC"
}
trap cleanup EXIT INT HUP TERM

for name in $REPOS; do
	if grep -qxF "$name" "$TMP_REPOS" 2>/dev/null; then
		die "duplicate repository name: $name"
	fi
	printf '%s\n' "$name" >> "$TMP_REPOS"
done

replace_token() {
	line=$1
	token=$2
	value=$3
	result=""
	while [ -n "$line" ]; do
		case $line in
		*"$token"*)
			prefix=${line%%"$token"*}
			suffix=${line#*"$token"}
			result=$result$prefix$value
			line=$suffix
			;;
		*)
			result=$result$line
			line=""
			;;
		esac
	done
	printf '%s' "$result"
}

substitute_template() {
	template=$1
	dest=$2
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(replace_token "$line" "{{SPEC_NAME}}" "$SPEC")
		line=$(replace_token "$line" "{{SUMMARY}}" "$SUMMARY")
		line=$(replace_token "$line" "{{OVERVIEW}}" "$SUMMARY")
		printf '%s\n' "$line"
	done < "$template" > "$dest"
}

substitute_template "$TEMPLATE_DIR/requirements.md" "$TMP_SPEC/requirements.md"
substitute_template "$TEMPLATE_DIR/design.md" "$TMP_SPEC/design.md"
substitute_template "$TEMPLATE_DIR/tasks.md" "$TMP_SPEC/tasks.md"
cp "$TMP_REPOS" "$TMP_SPEC/repos.txt"

mv "$TMP_SPEC" "$SPEC_DIR"
trap - EXIT INT HUP TERM
rm -f "$TMP_REPOS"

printf 'ok created specs/%s\n' "$SPEC"
printf 'create-spec complete for %s\n' "$SPEC"
