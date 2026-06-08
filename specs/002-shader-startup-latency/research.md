# Research: Shader Startup Latency

## References

- [MDN — KHR_parallel_shader_compile](https://developer.mozilla.org/en-US/docs/Web/API/KHR_parallel_shader_compile) — extension spec and browser support
- [Three.js r143 changelog](https://github.com/mrdoob/three.js/blob/master/CHANGELOG.md) — `WebGLRenderer.compileAsync()` introduced
- [Three.js WebGLRenderer docs](https://threejs.org/docs/#api/en/renderers/WebGLRenderer.compileAsync) — API signature and semantics

## Prior art

**Shadertoy** compiles synchronously — no loading screen, browser freezes until done. Acceptable for demos but not product UX.

**Games/WebGL engines** typically use a dedicated "loading" step where they compile all shaders upfront before any game logic begins, often with a progress bar. The async compilation extension makes this non-blocking on modern browsers.

## Experiments / benchmarks

Current behavior (observed):
- The `animate()` loop starts immediately on page load.
- First call to `renderer.render(scene, camera)` triggers synchronous GPU shader compilation.
- On a complex 456-line fragment shader (Perlin FBM + SDF raymarching + soft shadows), this blocks the main thread for **2–5 seconds** depending on GPU driver.
- During this freeze the browser cannot paint, animate CSS, or respond to events — the "LOADING…" button itself appears frozen.
- The blit material (second `ShaderMaterial`) also compiles on first use, adding a second stall.

Root cause: WebGL's `glCompileShader()` + `glLinkProgram()` are synchronous. Without `KHR_parallel_shader_compile`, the driver holds the JS thread until done.

## Key findings

1. **`renderer.compileAsync(scene, camera)`** (Three.js r143+) uses `KHR_parallel_shader_compile` when available, returning a Promise that resolves once GPU compilation is done. The browser remains responsive throughout.

2. **Two scenes must be compiled**: the main raymarching scene and the blit scene (temporal accumulation). Both contain separate `ShaderMaterial` instances. A combined scene or two sequential `compileAsync` calls are needed.

3. **Browser support** for `KHR_parallel_shader_compile`: Chrome ✅, Edge ✅, Firefox ✅, Safari 16+ ⚠️ (partial). On unsupported browsers `compileAsync` falls back to synchronous with a console warning — the UX degrades to the current behavior but doesn't break.
