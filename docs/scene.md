# Scene SDF

`GetDistID(p, organicDetail)` returns `vec2(distance, materialID)`. materialID `0` = terrain/sphere, `1` = character.

## Terrain

```glsl
float basePlaneDist = p.y - 8.0;
float eH = erosionFBM(p.xz * 0.07, oct * 1.5);
float planeDist = (basePlaneDist + noiseAmp * (eH * 7.0 + 4.5) + 0.1) * 0.45;
```

The base plane is at `y=8.0`. The erosion FBM lifts and sculpts it. `noiseAmp` scales the displacement based on biome (see below). The `0.45` Lipschitz factor keeps the SDF valid for sphere tracing (noise-displaced surfaces are not true SDFs — the Lipschitz relaxation prevents over-stepping).

Optimization: the full erosion FBM is only evaluated when `basePlaneDist < 12.0`. Beyond that, `planeDist = basePlaneDist - 1.1` — a cheap conservative bound that keeps rays advancing until they're close enough to matter.

## Biome system

A single slow `sNoise` in XZ space drives two biome transitions:

```glsl
float biomeN  = sNoise(vec3(p.x * 0.018, 0.5, p.z * 0.018));
float volcanic = smoothstep(0.60, 0.75, biomeN);  // high noise → spiky terrain
float flatland = smoothstep(0.35, 0.20, biomeN);  // low noise → open plains
float noiseAmp = mix(mix(1.0, 0.35, flatland), 1.65, volcanic);
```

`noiseAmp` ranges from 0.35 (flat grassland) through 1.0 (default) to 1.65 (volcanic). The volcanic / flatland zones are also used in `GetLight` for lava vs. water coloring.

## Water / lava plane

`waterDist = (p.y - 2.8) * 0.4` is merged into terrain via `min()`, so deep valleys fill with a flat surface at `y=2.8`. The water/lava distinction is visual only (in `GetLight`): the same biome `volcanic` factor controls lava viscosity and wave amplitude.

## Infinite sphere grid

Spheres are placed on a `15×15` world-space grid with per-cell jitter:

```glsl
vec2 cell = floor((p.xz + 7.5) / 15.0);
// 3×3 neighborhood search → find nearest
vec3 spherePos = vec3(cell.x * 15.0 + jitter.x, 7.5 + jitter.y*0.5, cell.y * 15.0 + jitter.z);
float r = mix(0.08, 0.8, pow(Hash(vec3(curCell, 1.0)), 2.0));
```

Noise displacement is applied **only to the nearest candidate** to avoid evaluating it for all 9 cells:

```glsl
repSphereDist = (base < repBestR + 3.0)
    ? (base + 0.8*Noise(p - repBestPos, oct) - 0.8) * 0.45
    : (base - 0.8) * 0.45;
```

Cells listed in `uIgnoredCells` are skipped — this is how attached and falling spheres are removed from the scene grid while being rendered separately.

## Attached / falling spheres

Attached spheres are stored as character-relative offsets in `uAttachedOffsets`. They are converted back to world space each frame and added to the domain sphere pool via `smin(..., 0.4)`.

Falling spheres come from `uFallingPositions`. They use a wider blend radius (`k=0.7`) to produce dramatic merges on landing.

All sphere types share the same terrain blend (`smin(..., 1.0)`) so they naturally sink into the ground surface.

## Character SDF — `sdCharacter(p)`

A capsule-skeleton humanoid built from 9 `sdCapsule` calls (head sphere + neck + torso + 2 arms × 2 segments + 2 legs × 2 segments). Origin is `iCameraPos` (eye level).

Animation blends three arm poses (idle/walk, stationary jump ascent, running jump ascent) driven by `uVY`, `uMoving`, and `uAnimPhase`. Leg joints tuck on ascent and extend on descent.

The character SDF is skipped entirely when `camDist > 3.5` to avoid evaluating it on distant pixels.

## Smooth minimum variants

Two variants are available:

- `smin(a, b, k)` — polynomial (Quilez). Simple, fast. Used for most blends.
- `sminE(a, b, k)` — exponential. Gradient is always a convex combination of the input gradients, giving correct normals on Lipschitz-scaled SDFs. Available but not currently used in the main scene.

## SDF primitives

`sdCapsule(p, a, b, r)` — distance from p to the line segment [a,b] minus radius r. Used as the building block for the character skeleton.
