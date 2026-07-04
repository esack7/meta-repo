#!/bin/sh
# Create a specification directory with templates and repos.txt.
#
# Usage: create-spec.sh <project-map.yaml> <spec-name> [--summary TEXT] <repo-name>...

set -e

SCRIPT=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
SHARED=$(dirname "$SCRIPT")/../../_shared
. "$SHARED/lib/common.sh"

MAP=$1
SPEC=$2
shift 2 || true

SUMMARY=""
REPOS=""

while [ $# -gt 0 ]; do
	case $1 in
	--summary)
		shift || die "create-spec: missing value for --summary"
		SUMMARY=${1:-}
		shift || true
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

[ -n "$MAP" ] && [ -n "$SPEC" ] || die "usage: create-spec.sh <project-map.yaml> <spec-name> [--summary TEXT] <repo-name>..."

validate_spec_name "$SPEC"
ROOT=$(meta_root_from_map "$MAP")
SPEC_DIR="$ROOT/specs/$SPEC"
TEMPLATE_DIR=$(dirname "$SCRIPT")/../templates

[ ! -e "$SPEC_DIR" ] || die "spec directory already exists: specs/$SPEC"
[ -d "$TEMPLATE_DIR" ] || die "missing templates directory for create-spec"

REPOS=$(printf '%s\n' $REPOS | sed '/^$/d')
[ -n "$REPOS" ] || die "at least one repository name is required"

for name in $REPOS; do
	validate_repo_name "$name"
	run_extract_project_map "$SCRIPT" "$MAP" --get "$name" >/dev/null || \
		die "unknown repository in project map: $name"
done

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
