---
name: create-spec
description: Create a feature specification directory with requirements, design, tasks, and repos.txt. Use when the user asks to create a spec, start a feature specification, or run create-spec with a feature description.
---

# create-spec

Create `specs/<spec-name>/` with tracked specification documents and a confirmed `repos.txt`.

## When to use

- "Create a spec for …"
- `/create-spec <feature description>` or `$create-spec <feature description>`

## Spec naming

- Must match `^[a-z0-9][a-z0-9-]*$`.
- Reject if `specs/<spec-name>/` already exists.

## Workflow

1. **Gather requirements** from the user (or the provided feature description).
2. **Read** `project-repositories.yaml` and propose affected repositories using each entry's `description`, `selection.use_for`, and `selection.avoid_for`.
3. **Present the exact repository name list** and obtain explicit user confirmation. Do not guess after confirmation.
4. **Run the bundled helper** to create the spec directory (agents must not hand-author `repos.txt` or spec paths):

```sh
sh .claude/skills/create-spec/scripts/create-spec.sh project-repositories.yaml <spec-name> \
  --summary "<one-line summary>" repo-a repo-b
```

5. Edit the generated Markdown files with gathered requirements. Do not modify `repos.txt` after confirmation except through explicit user-directed correction reruns of the helper.

## repos.txt rules

- One `name` per line matching `project-repositories.yaml`.
- Blank lines and `#` comments allowed.
- No duplicate or unknown names.

## Next steps

Tell the user to run **setup-repositories** (if clones are missing) then **prepare-spec** `<spec-name>` to create feature worktrees.

Do **not** create worktrees or branches in this skill.

See [AGENTS.md](../../../AGENTS.md) for the specification lifecycle.
