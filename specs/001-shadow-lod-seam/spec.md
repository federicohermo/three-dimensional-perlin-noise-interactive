# Spec: Shadow LOD Seam Fix

## Goal

Remove the visible shading seam on the terrain that appears as a sharp line separating a shadowed region from an unshadowed region. The seam is caused by a hard binary LOD switch inside `CastShadow` that abruptly reduces the shadow ray's `tmax` from 12 to 6 units at exactly 12 units of camera distance, making distant terrain miss occluders that are between 6 and 12 units away in sun-ray space.

## Scope

**Included:**
- Replace the hard binary `distToCam < 12.0` switch in `CastShadow` with a smooth `smoothstep` transition.
- Smooth both `tmax` and `steps` across a transition band (8–16 units) so neither jumps discontinuously.
- Optionally smooth the `GetAO` cutoff at 18 units for the same reason.

**Out of scope:**
- Changing the shadow algorithm (keep classic `k * h / t`).
- Increasing baseline shadow quality or step counts beyond current near budget.
- Fixing other LOD effects (noise octaves, etc.) — those are smooth already.

## Acceptance criteria

- [ ] The diagonal seam line on the terrain is no longer visible at any time of day or camera position.
- [ ] The transition from higher to lower shadow quality is gradual enough to be imperceptible.
- [ ] Frame rate is not measurably reduced (the transition band runs at most `~24` steps, same average as before).
- [ ] No new shadow acne or banding introduced.

## Constraints

- Must stay within the existing `CastShadow` function signature — no new uniforms or textures.
- The fix is a pure shader change (`src/glsl/fragment.glsl`); no JS changes required.
- Must not increase the worst-case step count above 32 (near quality budget).

## Open questions

- Should the `GetAO` cutoff at 18 units be smoothed in the same PR, or deferred?
- Is a transition band of 8–16 units wide enough, or should it be wider (e.g. 6–18)?
