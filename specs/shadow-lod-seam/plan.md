# Plan: Shadow LOD Seam Fix

## Approach

Replace both hard ternary expressions in `CastShadow` with `smoothstep`-based transitions across a band from 8 to 16 units of camera distance. The `tmax` change is the primary visual fix; the `steps` change is a secondary performance-quality balance.

**Current code** (`fragment.glsl:321–322`):
```glsl
int steps = (distToCam < 12.0) ? 32 : 16;
tmax = (distToCam < 12.0) ? tmax : min(tmax, 6.0);
```

**Proposed code:**
```glsl
float lodT = smoothstep(8.0, 16.0, distToCam);
tmax      = mix(tmax, min(tmax, 6.0), lodT);
int steps = (lodT < 0.5) ? 32 : 16;
```

The `tmax` now transitions smoothly from its full value to 6.0 across the 8–16 unit band. The `steps` cutover remains a hard switch but is moved to 12 units (midpoint) — this is acceptable because the step count difference doesn't cause a visible shading discontinuity, only a minor quality variation.

An alternative for `steps` that avoids even the midpoint snap:
```glsl
int steps = int(mix(32.0, 16.0, lodT) + 0.5);
```
This rounds to the nearest integer as the transition progresses. Note: on most GLSL implementations the loop `for (int i=0; i<32; i++) { if (i>=steps) break; }` still compiles to 32 iterations; the dynamic break may or may not be optimized out. Keep the existing `(lodT < 0.5) ? 32 : 16` form unless profiling shows a problem.

**Optional: smooth the `GetAO` cutoff**

```glsl
// Current:
float ao = (distToCam2 < 18.0) ? GetAO(p, n) : 1.0;

// Proposed:
float aoFade = smoothstep(14.0, 20.0, distToCam2);
float ao = mix(GetAO(p, n), 1.0, aoFade);
```
Note: `GetAO` is called unconditionally when using `mix`, which is a small perf cost. Can guard with `(distToCam2 < 20.0) ? mix(GetAO(p, n), 1.0, aoFade) : 1.0` to skip the AO call beyond 20 units.

## Alternatives considered

| Option | Pro | Con | Decision |
|---|---|---|---|
| Smooth `tmax` only, keep hard steps ternary | Minimal change, fixes the primary artifact | Steps cutover at 12.0 may still cause a subtle step — but probably imperceptible since step count doesn't directly change shading value | Acceptable fallback |
| Remove the far LOD entirely (32 steps, full tmax everywhere) | Completely eliminates all seams | ~2× shadow ray cost at distance; may drop framerate on mid-range hardware | Rejected |
| Move the boundary farther (e.g. 20 units) | Seam pushed out of typical view | Still a hard seam, just less visible | Rejected — smooth is strictly better |
| Per-pixel dithered LOD (blue noise on boundary) | Seam diffused into noise | Complex, adds texture lookup or hash call | Overkill for this case |

## Files to change

| File | Change |
|---|---|
| `src/glsl/fragment.glsl` | Replace lines 321–322 in `CastShadow`; optionally update `GetAO` call on line 407 |

## Risks / gotchas

- **Shadow acne in transition zone**: if `tmax` is reduced, rays still march into the surface within the LOD zone. The existing `t < 0.25` skip guard on line 327 should cover this, but test around the 8–16 unit band at low sun angles.
- **Temporal accumulation ghosting**: the seam fix changes per-pixel shadow values across frames during camera movement. The blending factor is 0.12, so residual ghosting should fade within ~8 frames. No special handling needed.
- **`int steps` GLSL compatibility**: `int(mix(...))` requires GLSL 1.30+. The `(lodT < 0.5) ? 32 : 16` form is universally safe.
