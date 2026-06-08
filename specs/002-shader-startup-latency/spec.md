# Spec: Shader Startup Latency

## Goal

Eliminate the browser freeze that occurs while the GPU compiles the raymarching shader on first load. Currently the page appears completely locked for 2–5 seconds because `renderer.render()` triggers synchronous shader compilation. The fix is to compile shaders asynchronously before the animation loop starts, keeping the UI responsive and the "LOADING…" button visually alive throughout.

## Scope

**Included:**
- Replace the implicit first-frame shader compile with an explicit `renderer.compileAsync()` call before `animate()`.
- Compile both the main scene (raymarching material) and the blit scene (temporal accumulation material).
- Wire `setReady()` to fire after async compilation completes instead of after the first render frame.

**Out of scope:**
- GLSL source simplification or shader complexity reduction.
- Client-side binary shader caching (WEBGL_get_program_binary) — GPU-specific and low payoff.
- Progress percentage reporting (compilation is opaque; only done/not-done is knowable).

## Acceptance criteria

- [ ] Browser main thread is NOT blocked during shader compilation — CSS animations and layout remain responsive.
- [ ] "LOADING…" button is visually alive (no freeze) from page load until "ENTER" appears.
- [ ] "ENTER" button appears within ~100 ms of GPU compilation finishing (no extra latency introduced).
- [ ] First rendered frame is artifact-free (no one-frame flash of an unlit/wrong state).
- [ ] Works on Chrome, Firefox, Edge; degrades gracefully (falls back to sync) on Safari.

## Constraints

- No new dependencies.
- The animation loop must not start before shaders are ready (would render corrupt first frames).
- `setReady()` must still be called exactly once and only after compilation.
- The existing "render behind loading screen to warm up" pattern is superseded by `compileAsync` — the first `animate()` frame should be a normal frame, not a compile trigger.
