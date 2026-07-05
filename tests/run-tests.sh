#!/bin/sh
# Integration tests for meta-repo skill helpers.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
EXTRACT="$ROOT/.claude/skills/_shared/extract-project-map.sh"
PARSE="$ROOT/.claude/skills/_shared/parse-repos-txt.sh"
SETUP="$ROOT/.claude/skills/setup-repositories/scripts/setup-repositories.sh"
REFRESH="$ROOT/.claude/skills/refresh-repositories/scripts/refresh-repositories.sh"
PREPARE="$ROOT/.claude/skills/prepare-spec/scripts/prepare-spec.sh"
CLOSE="$ROOT/.claude/skills/close-spec/scripts/close-spec.sh"
CREATE="$ROOT/.claude/skills/create-spec/scripts/create-spec.sh"
COMMON="$ROOT/.claude/skills/_shared/lib/common.sh"

PASS=0
FAIL=0

pass() {
	PASS=$((PASS + 1))
	printf 'PASS: %s\n' "$1"
}

fail() {
	FAIL=$((FAIL + 1))
	printf 'FAIL: %s\n' "$1" >&2
}

assert_fail() {
	desc=$1
	shift
	if "$@" >/dev/null 2>&1; then
		fail "$desc (expected failure)"
	else
		pass "$desc"
	fi
}

assert_ok() {
	desc=$1
	shift
	if "$@"; then
		pass "$desc"
	else
		fail "$desc"
	fi
}

assert_lines() {
	desc=$1
	expected=$2
	shift 2
	count=$("$@" 2>/dev/null | wc -l | tr -d ' ')
	if [ "$count" = "$expected" ]; then
		pass "$desc"
	else
		fail "$desc (expected $expected lines, got $count)"
	fi
}

write_map() {
	file=$1
	shift
	printf '%s\n' "$@" > "$file"
}

# Syntax checks
for script in "$EXTRACT" "$PARSE" "$SETUP" "$REFRESH" "$PREPARE" "$CLOSE" "$CREATE"; do
	if sh -n "$script" 2>/dev/null; then
		pass "shell syntax: $(basename "$script")"
	else
		fail "shell syntax: $(basename "$script")"
	fi
done

# Skill metadata checks
for skill in setup-repositories refresh-repositories create-spec prepare-spec close-spec; do
	skill_file="$ROOT/.claude/skills/$skill/SKILL.md"
	if [ -f "$skill_file" ] && grep -q '^name: '"$skill" "$skill_file" && grep -q '^description:' "$skill_file"; then
		pass "skill metadata: $skill"
	else
		fail "skill metadata: $skill"
	fi
	ui_file="$ROOT/.claude/skills/$skill/agents/openai.yaml"
	if [ -f "$ui_file" ] && grep -q '^  display_name: "' "$ui_file" && \
		grep -q '^  short_description: "' "$ui_file" && \
		grep -Fq 'default_prompt: "Use $'"$skill" "$ui_file"; then
		pass "skill UI metadata: $skill"
	else
		fail "skill UI metadata: $skill"
	fi
done

# Codex symlinks
for skill in setup-repositories refresh-repositories create-spec prepare-spec close-spec; do
	link="$ROOT/.agents/skills/$skill"
	if [ -L "$link" ] && [ -f "$link/SKILL.md" ]; then
		pass "codex symlink: $skill"
	else
		fail "codex symlink: $skill"
	fi
done

# Propio symlinks
for skill in setup-repositories refresh-repositories create-spec prepare-spec close-spec; do
	link="$ROOT/.propio/skills/$skill"
	if [ -L "$link" ] && [ -f "$link/SKILL.md" ]; then
		pass "propio symlink: $skill"
	else
		fail "propio symlink: $skill"
	fi
done

# Branch refs with slash are valid when Git accepts them.
if . "$COMMON" && validate_branch_ref "release/1" "test branch"; then
	pass 'validate_branch_ref accepts release/1'
else
	fail 'validate_branch_ref accepts release/1'
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT INT HUP TERM

ORIGIN_A="$WORKDIR/origin-a.git"
ORIGIN_B="$WORKDIR/origin-b.git"
git init --bare "$ORIGIN_A" >/dev/null
git init --bare "$ORIGIN_B" >/dev/null

seed_repo() {
	origin=$1
	name=$2
	branch=${3:-main}
	seed="$WORKDIR/seed-$name-$branch"
	git init "$seed" >/dev/null
	(
		cd "$seed"
		git config user.email "test@example.com"
		git config user.name "Test"
		printf '# %s\n' "$name" > README.md
		git add README.md
		git commit -m "init" >/dev/null
		git branch -M "$branch"
		git remote add origin "$origin"
		git push -u origin "$branch" >/dev/null
	)
}

seed_repo "$ORIGIN_A" repo-a
seed_repo "$ORIGIN_B" repo-b

META="$WORKDIR/meta"
mkdir -p "$META/.claude/skills"
cp -R "$ROOT/.claude/skills/." "$META/.claude/skills/"
MAP="$META/project-repositories.yaml"

write_map "$MAP" \
	"version: 1" \
	"repositories:" \
	"  - name: repo-a" \
	"    description: Repository A" \
	"    git:" \
	"      clone_url: $ORIGIN_A" \
	"      default_branch: main" \
	"  - name: repo-b" \
	"    description: Repository B" \
	"    git:" \
	"      clone_url: $ORIGIN_B" \
	"      default_branch: main"

META_SETUP="$META/.claude/skills/setup-repositories/scripts/setup-repositories.sh"
META_REFRESH="$META/.claude/skills/refresh-repositories/scripts/refresh-repositories.sh"
META_PREPARE="$META/.claude/skills/prepare-spec/scripts/prepare-spec.sh"
META_CLOSE="$META/.claude/skills/close-spec/scripts/close-spec.sh"
META_CREATE="$META/.claude/skills/create-spec/scripts/create-spec.sh"
META_EXTRACT="$META/.claude/skills/_shared/extract-project-map.sh"

# Empty map no-op (no filesystem changes)
EMPTY="$WORKDIR/empty.yaml"
write_map "$EMPTY" "version: 1" "repositories: []"
EMPTY_META="$WORKDIR/empty-meta"
mkdir -p "$EMPTY_META/.claude/skills"
cp -R "$ROOT/.claude/skills/." "$EMPTY_META/.claude/skills/"
EMPTY_SETUP="$EMPTY_META/.claude/skills/setup-repositories/scripts/setup-repositories.sh"
if "$EMPTY_SETUP" "$EMPTY" 2>/dev/null | grep -q 'no repositories' && [ ! -d "$EMPTY_META/repos" ]; then
	pass 'repositories: [] is no-op'
else
	fail 'repositories: [] is no-op'
fi

write_map "$WORKDIR/no-version.yaml" "repositories: []"
no_version_err=$("$META_EXTRACT" "$WORKDIR/no-version.yaml" 2>&1 >/dev/null || true)
if printf '%s' "$no_version_err" | grep -q 'unsupported or missing version' && \
	! printf '%s' "$no_version_err" | grep -qx '0'; then
	pass 'missing version line has clean stderr'
else
	fail 'missing version line has clean stderr'
fi

# Extract validation (fixed file-based negative tests)
assert_lines 'extract lists two repos' 2 "$META_EXTRACT" "$MAP"

write_map "$WORKDIR/dup-names.yaml" \
	"version: 1" "repositories:" \
	"  - name: dup" "    git:" "      clone_url: u" "      default_branch: main" \
	"  - name: dup" "    git:" "      clone_url: u2" "      default_branch: main"
assert_fail 'reject duplicate names' "$META_EXTRACT" "$WORKDIR/dup-names.yaml"

write_map "$WORKDIR/anchor.yaml" \
	"version: 1" "repositories:" \
	"  - &x name: bad" "    git:" "      clone_url: u" "      default_branch: main"
assert_fail 'reject anchor in map' "$META_EXTRACT" "$WORKDIR/anchor.yaml"

write_map "$WORKDIR/inline-comment.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a  # sneaky" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: main"
assert_fail 'reject inline comment on name' "$META_EXTRACT" "$WORKDIR/inline-comment.yaml"

write_map "$WORKDIR/bad-indent.yaml" \
	"version: 1" "repositories:" \
	" - name: repo-a" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: main"
assert_fail 'reject incorrect name indentation' "$META_EXTRACT" "$WORKDIR/bad-indent.yaml"

write_map "$WORKDIR/dup-clone.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" \
	"      clone_url: $ORIGIN_A" \
	"      clone_url: $ORIGIN_B" \
	"      default_branch: main"
assert_fail 'reject duplicate clone_url' "$META_EXTRACT" "$WORKDIR/dup-clone.yaml"

write_map "$WORKDIR/dup-version.yaml" \
	"version: 1" "version: 1" "repositories: []"
assert_fail 'reject duplicate version declaration' "$META_EXTRACT" "$WORKDIR/dup-version.yaml"

write_map "$WORKDIR/dup-git.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: main" \
	"    git:" "      clone_url: $ORIGIN_B" "      default_branch: main"
assert_fail 'reject duplicate git block' "$META_EXTRACT" "$WORKDIR/dup-git.yaml"

write_map "$WORKDIR/dup-repos-header.yaml" \
	"version: 1" "repositories:" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: main"
assert_fail 'reject duplicate repositories header' "$META_EXTRACT" "$WORKDIR/dup-repos-header.yaml"

write_map "$WORKDIR/dup-empty-repos.yaml" \
	"version: 1" "repositories: []" "repositories: []"
assert_fail 'reject duplicate empty repositories declarations' "$META_EXTRACT" "$WORKDIR/dup-empty-repos.yaml"

write_map "$WORKDIR/traversal-name.yaml" \
	"version: 1" "repositories:" \
	"  - name: ../escape" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: main"
assert_fail 'reject traversal repository name' "$META_EXTRACT" "$WORKDIR/traversal-name.yaml"

write_map "$WORKDIR/punct-desc.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a" \
	"    description: Auth & sessions service handling *.json payloads" \
	"    git:" "      clone_url: $ORIGIN_A" "      default_branch: main" \
	"    selection:" \
	"      use_for: Billing & payments" \
	"      avoid_for: invalidates *.cache"
assert_lines 'extract accepts punctuation in descriptive fields' 1 "$META_EXTRACT" "$WORKDIR/punct-desc.yaml"

write_map "$WORKDIR/anchor-clone.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: &u $ORIGIN_A" "      default_branch: main"
assert_fail 'reject anchor on critical clone_url' "$META_EXTRACT" "$WORKDIR/anchor-clone.yaml"

write_map "$WORKDIR/quoted-clone.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: \"$ORIGIN_A\"" "      default_branch: main"
assert_fail 'reject quoted clone_url' "$META_EXTRACT" "$WORKDIR/quoted-clone.yaml"

write_map "$WORKDIR/option-clone.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: --upload-pack=/bin/evil" "      default_branch: main"
assert_fail 'reject option-like clone_url' "$META_EXTRACT" "$WORKDIR/option-clone.yaml"

write_map "$WORKDIR/phantom-section.yaml" \
	"version: 1" \
	"unrelated_section:" \
	"  - name: phantom" \
	"    git:" \
	"      clone_url: $ORIGIN_B" \
	"      default_branch: main" \
	"repositories:" \
	"  - name: repo-a" \
	"    git:" \
	"      clone_url: $ORIGIN_A" \
	"      default_branch: main"
assert_fail 'reject repository entry outside repositories block' "$META_EXTRACT" "$WORKDIR/phantom-section.yaml"

write_map "$WORKDIR/phantom-after.yaml" \
	"version: 1" \
	"repositories:" \
	"  - name: repo-a" \
	"    git:" \
	"      clone_url: $ORIGIN_A" \
	"      default_branch: main" \
	"trailing_section:" \
	"  - name: phantom" \
	"    git:" \
	"      clone_url: $ORIGIN_B" \
	"      default_branch: main"
assert_fail 'reject top-level section after repositories block' "$META_EXTRACT" "$WORKDIR/phantom-after.yaml"

write_map "$WORKDIR/partial-invalid.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: main" \
	"  - name: repo-b" "    git:" "      clone_url: $ORIGIN_B"
partial_out=$("$META_EXTRACT" "$WORKDIR/partial-invalid.yaml" 2>/dev/null || true)
if [ -z "$partial_out" ]; then
	pass 'extract emits no stdout on validation failure'
else
	fail 'extract emits no stdout on validation failure'
fi

write_map "$WORKDIR/invalid-branch.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: -invalid"
assert_fail 'reject invalid default_branch ref' "$META_EXTRACT" "$WORKDIR/invalid-branch.yaml"

# Setup clones
if "$META_SETUP" "$MAP" >/dev/null 2>&1; then
	pass 'setup clones missing repositories'
else
	fail 'setup clones missing repositories'
fi

[ -d "$META/repos/repo-a/.git" ] && pass 'repo-a clone exists' || fail 'repo-a clone exists'
[ -d "$META/repos/repo-b/.git" ] && pass 'repo-b clone exists' || fail 'repo-b clone exists'

# Setup must never remove a pre-existing path that merely resembles its temporary path.
COLLISION_META="$WORKDIR/setup-collision"
mkdir -p "$COLLISION_META/.claude/skills"
cp -R "$ROOT/.claude/skills/." "$COLLISION_META/.claude/skills/"
COLLISION_MAP="$COLLISION_META/project-repositories.yaml"
write_map "$COLLISION_MAP" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: main"
COLLISION_SETUP="$COLLISION_META/.claude/skills/setup-repositories/scripts/setup-repositories.sh"
if sh -c '
	root=$1
	setup=$2
	map=$3
	collision="$root/repos/.setup-tmp-$$-repo-a"
	mkdir -p "$collision"
	printf keep > "$collision/marker"
	exec "$setup" "$map" repo-a
' sh "$COLLISION_META" "$COLLISION_SETUP" "$COLLISION_MAP" >/dev/null 2>&1 && \
	find "$COLLISION_META/repos" -name marker -print -quit | grep -q .; then
	pass 'setup preserves pre-existing temp-like directories'
else
	fail 'setup preserves pre-existing temp-like directories'
fi

rm -rf "$META/repos/repo-a"
printf 'not a git repo\n' > "$META/repos/repo-a"
assert_fail 'setup refuses conflicting non-git path' "$META_SETUP" "$MAP" repo-a
rm -f "$META/repos/repo-a"
"$META_SETUP" "$MAP" repo-a >/dev/null 2>&1
[ -d "$META/repos/repo-a/.git" ] && pass 'setup restores repo-a after non-git conflict test' || \
	fail 'setup restores repo-a after non-git conflict test'
assert_fail 'setup aborts on invalid project map' "$META_SETUP" "$WORKDIR/partial-invalid.yaml"

write_map "$WORKDIR/missing-branch.yaml" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: release/1"
MISSING_BRANCH_SETUP="$WORKDIR/missing-branch-setup"
mkdir -p "$MISSING_BRANCH_SETUP/.claude/skills"
cp -R "$ROOT/.claude/skills/." "$MISSING_BRANCH_SETUP/.claude/skills/"
MISSING_SETUP="$MISSING_BRANCH_SETUP/.claude/skills/setup-repositories/scripts/setup-repositories.sh"
assert_fail 'setup refuses unavailable default branch' "$MISSING_SETUP" "$WORKDIR/missing-branch.yaml" repo-a

hash_before=$(git -C "$META/repos/repo-a" rev-parse HEAD)
if "$META_SETUP" "$MAP" >/dev/null 2>&1 && [ "$(git -C "$META/repos/repo-a" rev-parse HEAD)" = "$hash_before" ]; then
	pass 'setup does not modify existing clones'
else
	fail 'setup does not modify existing clones'
fi

saved_setup_origin=$(git -C "$META/repos/repo-a" remote get-url origin)
git -C "$META/repos/repo-a" remote set-url origin "$WORKDIR/wrong-existing.git"
assert_fail 'setup rejects existing clone origin mismatch' "$META_SETUP" "$MAP" repo-a
git -C "$META/repos/repo-a" remote set-url origin "$saved_setup_origin"

# Simulate a clone whose origin changes before post-clone validation.
POST_CLONE_META="$WORKDIR/post-clone-mismatch"
mkdir -p "$POST_CLONE_META/.claude/skills" "$WORKDIR/git-shim"
cp -R "$ROOT/.claude/skills/." "$POST_CLONE_META/.claude/skills/"
POST_CLONE_MAP="$POST_CLONE_META/project-repositories.yaml"
write_map "$POST_CLONE_MAP" \
	"version: 1" "repositories:" \
	"  - name: repo-a" "    git:" "      clone_url: $ORIGIN_A" "      default_branch: main"
REAL_GIT=$(command -v git)
printf '%s\n' \
	'#!/bin/sh' \
	'if [ "$1" = clone ]; then' \
	'  "$REAL_GIT" "$@" || exit $?' \
	'  for destination; do :; done' \
	'  "$REAL_GIT" -C "$destination" remote set-url origin "$POST_CLONE_WRONG"' \
	'  exit 0' \
	'fi' \
	'exec "$REAL_GIT" "$@"' > "$WORKDIR/git-shim/git"
chmod +x "$WORKDIR/git-shim/git"
POST_CLONE_SETUP="$POST_CLONE_META/.claude/skills/setup-repositories/scripts/setup-repositories.sh"
if PATH="$WORKDIR/git-shim:$PATH" REAL_GIT="$REAL_GIT" POST_CLONE_WRONG="$WORKDIR/wrong-post-clone.git" \
	"$POST_CLONE_SETUP" "$POST_CLONE_MAP" repo-a >/dev/null 2>&1; then
	fail 'setup rejects post-clone origin mismatch'
elif [ ! -e "$POST_CLONE_META/repos/repo-a" ]; then
	pass 'setup rejects post-clone origin mismatch'
else
	fail 'setup cleans target after post-clone origin mismatch'
fi

# Refresh up-to-date
if "$META_REFRESH" "$MAP" >/dev/null 2>&1; then
	pass 'refresh up-to-date clones'
else
	fail 'refresh up-to-date clones'
fi

# Refresh fast-forward
ff_seed="$WORKDIR/ff-seed"
git clone "$ORIGIN_A" "$ff_seed" >/dev/null 2>&1
(
	cd "$ff_seed"
	git config user.email "test@example.com"
	git config user.name "Test"
	printf 'ff\n' >> README.md
	git add README.md
	git commit -m "fast-forward" >/dev/null
	git push origin main >/dev/null
)
if "$META_REFRESH" "$MAP" repo-a >/dev/null 2>&1; then
	pass 'refresh fast-forwards behind clone'
else
	fail 'refresh fast-forwards behind clone'
fi

# Refresh refuses dirty
printf '\n' >> "$META/repos/repo-a/README.md"
assert_fail 'refresh refuses dirty clone' "$META_REFRESH" "$MAP" repo-a
git -C "$META/repos/repo-a" checkout -- README.md

# Refresh refuses locally-ahead
(
	cd "$META/repos/repo-a"
	printf 'ahead\n' > ahead.txt
	git add ahead.txt
	git commit -m "ahead" >/dev/null
)
assert_fail 'refresh refuses locally-ahead clone' "$META_REFRESH" "$MAP" repo-a
git -C "$META/repos/repo-a" reset --hard origin/main >/dev/null

# Refresh refuses wrong branch
git -C "$META/repos/repo-a" checkout -b side-branch >/dev/null 2>&1
assert_fail 'refresh refuses wrong-branch clone' "$META_REFRESH" "$MAP" repo-a
git -C "$META/repos/repo-a" checkout main >/dev/null 2>&1
git -C "$META/repos/repo-a" branch -D side-branch >/dev/null 2>&1 || true

# Refresh refuses diverged clone (ahead and behind)
git -C "$META/repos/repo-a" reset --hard origin/main >/dev/null 2>&1
(
	cd "$WORKDIR/ff-seed"
	git pull origin main >/dev/null 2>&1
	printf 'diverge-remote\n' >> README.md
	git add README.md
	git commit -m "remote advance" >/dev/null
	git push origin main >/dev/null
)
(
	cd "$META/repos/repo-a"
	printf 'diverge-local\n' > diverge-local.txt
	git add diverge-local.txt
	git commit -m "local diverge" >/dev/null
)
assert_fail 'refresh refuses diverged clone' "$META_REFRESH" "$MAP" repo-a
git -C "$META/repos/repo-a" fetch origin >/dev/null 2>&1
git -C "$META/repos/repo-a" reset --hard origin/main >/dev/null 2>&1

# create-spec helper
SPEC=feature-alpha
assert_fail 'create-spec rejects unknown repo before writing spec dir' \
	"$META_CREATE" "$MAP" partial-spec --summary 'noop' unknown-repo
[ ! -e "$META/specs/partial-spec" ] && pass 'create-spec leaves no partial spec on failure' || \
	fail 'create-spec leaves no partial spec on failure'

SPEC_PUNCT=feature-r-and-d
if "$META_CREATE" "$MAP" "$SPEC_PUNCT" --summary 'R&D / API' repo-a >/dev/null 2>&1; then
	pass 'create-spec accepts summary punctuation'
else
	fail 'create-spec accepts summary punctuation'
fi
grep -q 'R&D / API' "$META/specs/$SPEC_PUNCT/requirements.md" && \
	pass 'create-spec substitutes summary punctuation' || \
	fail 'create-spec substitutes summary punctuation'

SPEC_TOKEN=feature-token-summary
if "$META_CREATE" "$MAP" "$SPEC_TOKEN" --summary 'literal {{SUMMARY}} here' repo-a >/dev/null 2>&1; then
	pass 'create-spec handles literal template token in summary'
else
	fail 'create-spec handles literal template token in summary'
fi
grep -Fq 'literal {{SUMMARY}} here' "$META/specs/$SPEC_TOKEN/requirements.md" && \
	pass 'create-spec preserves literal template token text' || \
	fail 'create-spec preserves literal template token text'

if "$META_CREATE" "$MAP" "$SPEC" --summary "Alpha feature" repo-a repo-b >/dev/null 2>&1; then
	pass 'create-spec helper creates spec directory'
else
	fail 'create-spec helper creates spec directory'
fi
SPEC_DIR="$META/specs/$SPEC"
[ -f "$SPEC_DIR/requirements.md" ] && [ -f "$SPEC_DIR/design.md" ] && \
	[ -f "$SPEC_DIR/tasks.md" ] && [ -f "$SPEC_DIR/repos.txt" ] && \
	pass 'create-spec helper writes all spec files' || fail 'create-spec helper writes all spec files'
assert_fail 'create-spec rejects existing spec name' "$META_CREATE" "$MAP" "$SPEC" repo-a

# Prepare worktrees
if "$META_PREPARE" "$MAP" "$SPEC" >/dev/null 2>&1; then
	pass 'prepare-spec creates worktrees'
else
	fail 'prepare-spec creates worktrees'
fi

git -C "$SPEC_DIR/repos/repo-a" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
	pass 'worktree repo-a' || fail 'worktree repo-a'

branch_a=$(git -C "$SPEC_DIR/repos/repo-a" rev-parse --abbrev-ref HEAD)
[ "$branch_a" = "feature/$SPEC" ] && pass 'worktree branch repo-a' || fail 'worktree branch repo-a'

# Worktree registration checks must preserve paths containing spaces.
SPACE_WT="$WORKDIR/worktree with spaces"
if git -C "$META/repos/repo-a" worktree add -b feature/space-path "$SPACE_WT" origin/main >/dev/null 2>&1 && \
	[ "$(worktree_registered_at "$META/repos/repo-a" "$SPACE_WT")" = "yes" ]; then
	pass 'worktree registration supports paths with spaces'
else
	fail 'worktree registration supports paths with spaces'
fi
git -C "$META/repos/repo-a" worktree remove "$SPACE_WT" >/dev/null 2>&1 || true
git -C "$META/repos/repo-a" branch -D feature/space-path >/dev/null 2>&1 || true

if "$META_PREPARE" "$MAP" "$SPEC" >/dev/null 2>&1; then
	pass 'prepare-spec skips existing worktrees'
else
	fail 'prepare-spec skips existing worktrees'
fi

wt_before_refresh=$(git -C "$SPEC_DIR/repos/repo-a" rev-parse HEAD)
if "$META_REFRESH" "$MAP" >/dev/null 2>&1 && [ -d "$SPEC_DIR/repos/repo-a" ] && \
	[ "$(git -C "$SPEC_DIR/repos/repo-a" rev-parse HEAD)" = "$wt_before_refresh" ]; then
	pass 'refresh leaves feature worktrees untouched'
else
	fail 'refresh leaves feature worktrees untouched'
fi

# Origin mismatch blocks prepare-spec
saved_origin=$(git -C "$META/repos/repo-a" remote get-url origin)
git -C "$META/repos/repo-a" remote set-url origin "$WORKDIR/wrong.git"
assert_fail 'prepare-spec rejects origin mismatch' "$META_PREPARE" "$MAP" "$SPEC"
git -C "$META/repos/repo-a" remote set-url origin "$saved_origin"

# Unpushed commits without remote feature branch block close (isolated spec)
SPEC_UNPUSHED=feature-unpushed
"$META_CREATE" "$MAP" "$SPEC_UNPUSHED" --summary "Unpushed test" repo-a >/dev/null 2>&1
SPEC_UNPUSHED_DIR="$META/specs/$SPEC_UNPUSHED"
"$META_PREPARE" "$MAP" "$SPEC_UNPUSHED" >/dev/null 2>&1
(
	cd "$SPEC_UNPUSHED_DIR/repos/repo-a"
	printf 'feature\n' > feature.txt
	git add feature.txt
	git commit -m "feature work" >/dev/null
)
assert_fail 'close refuses unpushed commits without remote feature branch' "$META_CLOSE" "$MAP" "$SPEC_UNPUSHED"
if "$META_CLOSE" "$MAP" "$SPEC_UNPUSHED" --acknowledge-unpushed >/dev/null 2>&1; then
	pass 'close accepts unpushed commits when acknowledged'
else
	fail 'close accepts unpushed commits when acknowledged'
fi

# Remote-only branch reuse preserves pushed feature SHA (separate spec)
SPEC_REMOTE=feature-remote
"$META_CREATE" "$MAP" "$SPEC_REMOTE" --summary "Remote reuse" repo-a >/dev/null 2>&1
SPEC_REMOTE_DIR="$META/specs/$SPEC_REMOTE"
"$META_PREPARE" "$MAP" "$SPEC_REMOTE" >/dev/null 2>&1
(
	cd "$SPEC_REMOTE_DIR/repos/repo-a"
	printf 'remote-feature\n' > remote.txt
	git add remote.txt
	git commit -m "remote feature work" >/dev/null
)
FEATURE_SHA=$(git -C "$SPEC_REMOTE_DIR/repos/repo-a" rev-parse HEAD)
git -C "$META/repos/repo-a" push origin "feature/$SPEC_REMOTE" >/dev/null 2>&1
"$META_CLOSE" "$MAP" "$SPEC_REMOTE" >/dev/null 2>&1

# An unregistered Git directory must fail preflight before any valid worktree is removed.
SPEC_UNREGISTERED=feature-unregistered
"$META_CREATE" "$MAP" "$SPEC_UNREGISTERED" --summary "Unregistered path" repo-a repo-b >/dev/null 2>&1
SPEC_UNREGISTERED_DIR="$META/specs/$SPEC_UNREGISTERED"
"$META_PREPARE" "$MAP" "$SPEC_UNREGISTERED" >/dev/null 2>&1
git -C "$META/repos/repo-b" worktree remove "$SPEC_UNREGISTERED_DIR/repos/repo-b" >/dev/null 2>&1
git clone --branch main "$ORIGIN_B" "$SPEC_UNREGISTERED_DIR/repos/repo-b" >/dev/null 2>&1
git -C "$SPEC_UNREGISTERED_DIR/repos/repo-b" checkout -b "feature/$SPEC_UNREGISTERED" >/dev/null 2>&1
assert_fail 'close rejects unregistered Git directory during preflight' \
	"$META_CLOSE" "$MAP" "$SPEC_UNREGISTERED"
if [ -d "$SPEC_UNREGISTERED_DIR/repos/repo-a" ]; then
	pass 'close retains earlier worktrees on unregistered-directory failure'
else
	fail 'close retains earlier worktrees on unregistered-directory failure'
fi
rm -rf "$SPEC_UNREGISTERED_DIR/repos/repo-b"
git -C "$META/repos/repo-b" worktree add "$SPEC_UNREGISTERED_DIR/repos/repo-b" \
	"feature/$SPEC_UNREGISTERED" >/dev/null 2>&1
"$META_CLOSE" "$MAP" "$SPEC_UNREGISTERED" >/dev/null 2>&1

# Missing worktree directories must have their stale registration pruned.
SPEC_STALE=feature-stale
"$META_CREATE" "$MAP" "$SPEC_STALE" --summary "Stale metadata" repo-a >/dev/null 2>&1
SPEC_STALE_DIR="$META/specs/$SPEC_STALE"
"$META_PREPARE" "$MAP" "$SPEC_STALE" >/dev/null 2>&1
rm -rf "$SPEC_STALE_DIR/repos/repo-a"
if [ "$(worktree_registered_at "$META/repos/repo-a" "$SPEC_STALE_DIR/repos/repo-a")" = "yes" ]; then
	pass 'stale worktree registration fixture created'
else
	fail 'stale worktree registration fixture created'
fi
if "$META_CLOSE" "$MAP" "$SPEC_STALE" >/dev/null 2>&1 && \
	[ "$(worktree_registered_at "$META/repos/repo-a" "$SPEC_STALE_DIR/repos/repo-a")" != "yes" ]; then
	pass 'close prunes stale worktree registration'
else
	fail 'close prunes stale worktree registration'
fi
git -C "$META/repos/repo-a" branch -D "feature/$SPEC_REMOTE" >/dev/null 2>&1
if "$META_PREPARE" "$MAP" "$SPEC_REMOTE" --reuse-branches >/dev/null 2>&1; then
	reopened_sha=$(git -C "$SPEC_REMOTE_DIR/repos/repo-a" rev-parse HEAD)
	if [ "$reopened_sha" = "$FEATURE_SHA" ]; then
		pass 'prepare-spec reuses remote-only feature branch'
	else
		fail "prepare-spec reuses remote-only feature branch (expected $FEATURE_SHA, got $reopened_sha)"
	fi
else
	fail 'prepare-spec reuses remote-only feature branch'
fi
"$META_CLOSE" "$MAP" "$SPEC_REMOTE" >/dev/null 2>&1

# Two-repo atomic preflight: dirty repo-a must not remove any worktree
printf 'dirty\n' >> "$SPEC_DIR/repos/repo-a/local.txt"
assert_fail 'close refuses when any worktree dirty' "$META_CLOSE" "$MAP" "$SPEC"
[ -d "$SPEC_DIR/repos/repo-a" ] && [ -d "$SPEC_DIR/repos/repo-b" ] && \
	pass 'close retains all worktrees when preflight fails' || \
	fail 'close retains all worktrees when preflight fails'
git -C "$SPEC_DIR/repos/repo-a" checkout -- local.txt 2>/dev/null || rm -f "$SPEC_DIR/repos/repo-a/local.txt"

# Origin mismatch blocks close-spec
git -C "$META/repos/repo-a" remote set-url origin "$WORKDIR/wrong.git"
assert_fail 'close-spec rejects origin mismatch' "$META_CLOSE" "$MAP" "$SPEC"
git -C "$META/repos/repo-a" remote set-url origin "$saved_origin"

# Close removes worktrees
if "$META_CLOSE" "$MAP" "$SPEC" >/dev/null 2>&1; then
	pass 'close-spec removes worktrees'
else
	fail 'close-spec removes worktrees'
fi

[ ! -d "$SPEC_DIR/repos/repo-a" ] && pass 'worktree repo-a removed' || fail 'worktree repo-a removed'
git -C "$META/repos/repo-a" show-ref --verify --quiet "refs/heads/feature/$SPEC" && \
	pass 'feature branch retained after close' || fail 'feature branch retained after close'

assert_fail 'prepare refuses without reuse when local feature branch exists' "$META_PREPARE" "$MAP" "$SPEC"

if "$META_PREPARE" "$MAP" "$SPEC" --reuse-branches >/dev/null 2>&1; then
	pass 'prepare-spec reopens with local feature branch reuse'
else
	fail 'prepare-spec reopens with local feature branch reuse'
fi

git -C "$META/repos/repo-a" remote set-url origin "$WORKDIR/does-not-exist.git"
assert_fail 'close refuses on fetch failure' "$META_CLOSE" "$MAP" "$SPEC"
git -C "$META/repos/repo-a" remote set-url origin "$ORIGIN_A"
if "$META_CLOSE" "$MAP" "$SPEC" --offline --acknowledge-unpushed >/dev/null 2>&1; then
	pass 'offline close with clean worktrees'
else
	fail 'offline close with clean worktrees'
fi

rm -rf "$META/repos/repo-b"
assert_fail 'prepare refuses missing clone' "$META_PREPARE" "$MAP" "$SPEC"

write_map "$WORKDIR/bad-repos.txt" "unknown-repo"
assert_fail 'parse rejects unknown repo' "$PARSE" "$WORKDIR/bad-repos.txt" --validate-map "$MAP"

write_map "$WORKDIR/dup-repos.txt" "repo-a" "repo-a"
assert_fail 'parse rejects duplicate repos' "$PARSE" "$WORKDIR/dup-repos.txt"

if grep -qF '/repos/' "$ROOT/.gitignore" && grep -qF '/specs/*/repos/' "$ROOT/.gitignore" && \
	git -C "$ROOT" check-ignore -q --no-index repos/example && \
	git -C "$ROOT" check-ignore -q --no-index specs/example/repos/repository && \
	! git -C "$ROOT" check-ignore -q --no-index specs/example/requirements.md && \
	! git -C "$ROOT" check-ignore -q --no-index specs/example/repos.txt; then
	pass 'gitignore ignores clones and worktrees but not spec documents'
else
	fail 'gitignore ignores clones and worktrees but not spec documents'
fi

# Live validation harness availability (reported; not equivalent to passing tests above)
if command -v skill-validator >/dev/null 2>&1; then
	pass 'skill-validator CLI available'
else
	printf 'NOTE: skill-validator CLI unavailable; live skill validation unverified (see docs/VERIFICATION.md)\n'
fi
if command -v claude >/dev/null 2>&1; then
	printf 'NOTE: Claude Code native skill discovery smoke tests not run in CI (see docs/VERIFICATION.md)\n'
else
	printf 'NOTE: Claude Code CLI unavailable; native discovery unverified\n'
fi
if command -v codex >/dev/null 2>&1; then
	printf 'NOTE: Codex native skill discovery smoke tests not run in CI (see docs/VERIFICATION.md)\n'
else
	printf 'NOTE: Codex CLI unavailable; native discovery unverified\n'
fi
if command -v propio >/dev/null 2>&1; then
	printf 'NOTE: Propio native skill discovery smoke tests not run in CI (see docs/VERIFICATION.md)\n'
else
	printf 'NOTE: Propio CLI unavailable; native discovery unverified\n'
fi

printf '\nTests complete: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
