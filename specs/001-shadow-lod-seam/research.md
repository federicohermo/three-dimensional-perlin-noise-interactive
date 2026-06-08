# Research: Shadow LOD Seam

## Root cause

`CastShadow` in `src/glsl/fragment.glsl` (lines 321–322) applies a **hard binary LOD** based on the distance from the hit point to the camera:

```glsl
int steps = (distToCam < 12.0) ? 32 : 16;
tmax = (distToCam < 12.0) ? tmax : min(tmax, 6.0);
```

At `distToCam = 12.0` there is a discontinuous step:

| Region | steps | tmax |
|---|---|---|
| < 12 units from camera | 32 | 12.0 (full) |
| ≥ 12 units from camera | 16 | **6.0 (halved)** |

The `tmax` reduction is the visual offender. When `tmax` drops from 12 → 6, shadow rays on the far side of the boundary can no longer reach occluders that are between 6 and 12 units away in sun-ray space. Those terrain points appear incorrectly unshadowed, producing a bright band just beyond the 12-unit ring.

The seam is the intersection of this radius-12 sphere (centred on the camera) with the terrain plane. At typical camera elevation and angle it projects as a diagonal or curved line across the ground, which matches the artifact in the screenshot.

## Secondary candidates (investigated, not the primary cause)

**`GetAO` hard cutoff at 18 units** (`fragment.glsl:407`):
```glsl
float ao = (distToCam2 < 18.0) ? GetAO(p, n) : 1.0;
```
Could produce a faint brightness ring at 18 units, but AO contribution is small (≤30% variation) and the transition between full AO and AO=1 is at most a mild brightening — unlikely to produce the sharp seam visible in the screenshot.

**`GetDistID` octave LOD** (`fragment.glsl:160`):
```glsl
float oct = 1.0 + 2.0 * exp(-camDist * 0.05) + exp(-camDist * 0.12) * organicDetail;
```
Smooth exponential — no discontinuity, not a suspect.

**Height-based SDF branch** (`fragment.glsl:207`):
```glsl
if (basePlaneDist < 12.0) { /* full noise */ } else { planeDist = basePlaneDist - 1.1; }
```
This is `p.y - 8.0 < 12.0` (i.e. `p.y < 20.0`), a height check, not a camera-distance check. The terrain surface sits around `y ≈ 0–4`, so this branch is always taken at the surface and is not a seam source.

## Why the fix is non-trivial

Smoothing the `int steps` value is difficult in GLSL: the loop `for (int i = 0; i < 32; i++) { if (i >= steps) break; ... }` is still 32 iterations; the `break` is dynamic but the compiler may not reduce the work proportionally on all GPUs. The real gain comes from smoothing `tmax`.

## References

- Inigo Quilez — "Soft Shadows in Raymarched SDFs" (shadertoy.com/view/lsKcDD) — the `k * h / t` formula used here.
- Session 4 fix history in CLAUDE.md — previous revert from Quilez 2018 formula back to classic `k*h/t` due to banding on non-Lipschitz noise surfaces.
