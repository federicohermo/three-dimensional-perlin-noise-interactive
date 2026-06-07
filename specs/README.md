# Specs

Each feature or improvement gets its own subfolder. Use the `_template/` files as a starting point.

## Active specs

_(none yet)_

## Folder structure

```
specs/
├── _template/       — copy this for each new feature
│   ├── spec.md      — what and why
│   ├── research.md  — prior art, references, experiments
│   ├── plan.md      — implementation approach and decisions
│   └── tasks.md     — concrete steps with status
└── <feature-name>/
    └── ...
```

## Workflow

1. Copy `_template/` to a new folder named after the feature (kebab-case).
2. Fill `spec.md` first — define the goal and acceptance criteria before touching code.
3. Use `research.md` to collect references, benchmarks, or experiment results.
4. Draft `plan.md` once research is done — lock the approach before writing tasks.
5. Track progress in `tasks.md`. Check off tasks as they're completed.
