# Architecture

## Module map

```
index.html
└── src/
    ├── main.js            — game loop, physics, input dispatch
    ├── renderer.js        — WebGL setup, render targets, ping-pong blit
    ├── uniforms.js        — shared Three.js uniform objects
    ├── shaders.js         — imports GLSL files, exports shader strings
    ├── temporal.js        — temporal accumulation state (shared between main/input)
    ├── input.js           — keyboard/mouse handlers
    ├── ui.js              — overlay / HUD DOM
    ├── ui.css
    ├── sphereAttachment.js — sphere pick-up, throw, fall simulation
    ├── heightQuery.js     — GPU terrain height query
    └── glsl/
        ├── vertex.glsl
        ├── fragment.glsl      — main raymarcher
        ├── terrain_funcs.glsl — noise + erosion FBM (shared between fragment & height_query)
        ├── height_query.glsl  — binary-search terrain height shader
        └── blit.glsl          — temporal blend / upscale pass
```

## Data flow

```
JS game loop (main.js)
    │
    ├─ updates uniforms (iCameraPos, iTime, uSunDir, uAttachedOffsets, …)
    │
    └─ calls render(temporalOn, frameIdx, isMoving)  ← renderer.js
           │
           ├─ [temporal ON]
           │     render scene → rtScene  (scaled resolution)
           │     blit rtScene + rtHistRead → rtHistWrite  (scaled)
           │     blit rtHistWrite → screen  (full resolution)
           │
           └─ [temporal OFF]
                 render scene → screen  (or rtScene + upscale blit)
```

## Uniform bus

All GPU state lives in `uniforms.js`. Every JS module that needs to push data to the GPU imports `uniforms` directly — there is no central update loop. Uniforms are Three.js objects (`{ value: ... }`), so writes are reflected on the next `renderer.render()` call.

Key uniforms:

| Uniform | Type | Source |
|---|---|---|
| `iTime` | float | `performance.now() / 1000` |
| `iResolution` | vec3 | viewport × renderScale |
| `iMouse` | vec4 | raw pixel coords |
| `iJitter` | vec2 | Halton(base 2,3) sub-pixel offset |
| `iCameraPos` | vec3 | character eye position (look-at target) |
| `uCamDist` | float | dynamic orbit distance (collision-aware) |
| `uSunDir` | vec3 | normalized, rotated each frame for day/night |
| `uCharFacing` | vec2 | XZ facing direction for character SDF |
| `uAnimPhase` | float | walk cycle accumulator |
| `uVY` | float | vertical velocity (jump/fall blend) |
| `uMoving` | float | 0/1 flag for arm swing suppression |
| `uAttachedOffsets[10]` | vec3[] | character-relative offsets of held spheres |
| `uAttachedRadii[10]` | float[] | radius of each held sphere |
| `uAttachedCount` | int | active held sphere count |
| `uIgnoredCells[15]` | vec2[] | grid cells to skip in sphere generation |
| `uIgnoredCount` | int | total ignored cells (attached + falling) |
| `uFallingPositions[5]` | vec3[] | world positions of in-flight spheres |
| `uFallingRadii[5]` | float[] | radii of in-flight spheres |
| `uFallingCount` | int | active falling sphere count |
| `uWindowSize` | vec2 | full (unscaled) window size for mouse math |

## Height query pipeline

`heightQuery.js` fires a 1×1 WebGL render pass using `height_query.glsl`. The fragment shader runs a 16-step binary search to find the y coordinate where `terrainSDF(vec3(x, y, z)) == 0`. The result is read back via `readRenderTargetPixels()` into a `Float32Array`. This is used by:
- `main.js` — initial spawn position + ground collision each frame
- `sphereAttachment.js` — where a falling sphere should land

## sphereAttachment.js precision note

`hashCell()` and `getJitter()` mirror the GLSL `Hash`/`GetJitter` functions using `Math.fround()` throughout. This is required because `fract()` of large float values is catastrophically sensitive to float32 vs float64 precision — without `fround`, sphere radii can differ by up to 0.64 from what the shader sees, causing collision mismatch.
