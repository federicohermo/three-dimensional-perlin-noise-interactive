# Tasks: Shadow LOD Seam Fix

## Status legend
- `[ ]` todo
- `[~]` in progress
- `[x]` done
- `[-]` skipped / won't do

---

## Tasks

- [ ] In `CastShadow`, replace the hard ternary on `tmax` and `steps` with a `smoothstep(8.0, 16.0, distToCam)` transition
- [ ] Visual test: verify the seam line on the terrain is gone at multiple sun angles and camera distances
- [ ] Visual test: confirm no new shadow acne or banding appears in the 8–16 unit transition band
- [ ] Decide and act on the `GetAO` cutoff: smooth it (see plan) or defer
- [ ] Update `perlin3d_fixed.glsl` to match (kept in sync with `fragment.glsl` per CLAUDE.md)

## Notes

_Anything discovered during implementation that future sessions should know._
