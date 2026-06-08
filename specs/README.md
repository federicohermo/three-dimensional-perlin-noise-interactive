# Specs

Each feature or improvement gets its own subfolder. Use the `_template/` files as a starting point.

## Active specs

| #   | Spec | Estado |
|-----|------|--------|
| 001 | [shadow-lod-seam](001-shadow-lod-seam/spec.md) | Completado |
| 002 | [shader-startup-latency](002-shader-startup-latency/spec.md) | Completado |
| 003 | [progressive-quality](003-progressive-quality/spec.md) | Pendiente |
| 004 | [noise-texture](004-noise-texture/spec.md) | Pendiente |
| 005 | [sparse-voxel-bvh](005-sparse-voxel-bvh/spec.md) | Pendiente |

## Folder structure

```
specs/
├── _template/       — copy this for each new feature
│   ├── spec.md      — what and why
│   ├── research.md  — prior art, references, experiments
│   ├── plan.md      — implementation approach and decisions
│   └── tasks.md     — concrete steps with status
└── NNN-<feature-name>/   — prefix NNN = número de orden (001, 002, …)
    └── ...
```

## Workflow

1. Copy `_template/` to a new folder `NNN-<feature-name>` (número correlativo + kebab-case).
2. Fill `spec.md` first — define the goal and acceptance criteria before touching code.
3. Use `research.md` to collect references, benchmarks, or experiment results.
4. Draft `plan.md` once research is done — lock the approach before writing tasks.
5. Track progress in `tasks.md`. Check off tasks as they're completed.
