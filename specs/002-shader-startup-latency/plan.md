# Plan: Shader Startup Latency

## Approach

Move shader compilation out of the first animation frame and into an explicit `await renderer.compileAsync()` call before the loop starts. Three.js uses `KHR_parallel_shader_compile` under the hood, so the GPU compiles asynchronously and the browser main thread stays responsive.

The entry point `main.js` becomes an async function (or uses a top-level async IIFE). Compilation is awaited, `setReady()` fires immediately after, and only then does `animate()` begin.

## Alternatives considered

| Option | Pro | Con | Decision |
|---|---|---|---|
| Current approach (first-frame compile behind loading screen) | Zero setup, shaders warm on first frame | JS thread blocks 2–5s; UI freezes; CSS/button animations stop | Replaced |
| `renderer.compileAsync()` before loop | Non-blocking; browser stays responsive; supported on all major browsers | Requires making startup async; must compile both scenes explicitly | Chosen |
| Reduce shader complexity (fewer octaves, simpler hash) | Less to compile; faster runtime | Degrades visual quality; addresses symptom not root cause | Out of scope |
| WEBGL_get_program_binary caching | Zero recompile after first visit | GPU-specific binary; breaks across driver updates; near-zero browser support | Rejected |

## Files to change

| File | Change |
|---|---|
| `src/renderer.js` | Export `scene` and `blitScene` so `main.js` can pass them to `compileAsync` |
| `src/main.js` | Wrap startup in async IIFE; call `await renderer.compileAsync(scene, camera)` + `await renderer.compileAsync(blitScene, camera)` before `animate()`; move `setReady()` here |

## Risks / gotchas

- **`compileAsync` needs the camera**: The orthographic camera from `renderer.js` must be exported or a dummy camera passed. The camera only affects view frustum culling, not shader compilation — passing the existing `camera` object works fine.
- **Both ShaderMaterials must be compiled**: The main raymarcher (`fragmentShader`) and the blit material (`blitFragmentShader`) are in separate Three.js scenes. Both must pass through `compileAsync` or the blit material will still compile synchronously on first temporal-accumulation render.
- **`setReady()` timing shift**: Currently fires after the first rendered frame. After this change it fires after `compileAsync` resolves, which is before `animate()` starts. This is correct — the button becomes clickable the moment the GPU is ready, not one frame later.
- **Safari fallback**: If `KHR_parallel_shader_compile` is absent, `compileAsync` may still block. The UI will freeze on Safari the same as today — no regression, just no improvement. Consider documenting this in `ui.js` as a known limitation.
- **No first-frame corrupt render**: Because shaders are fully compiled before `animate()` runs, there's no risk of a corrupt first frame. Remove the comment `// Render (always — compiles shaders on first frame behind loading screen)` as it's no longer accurate.
