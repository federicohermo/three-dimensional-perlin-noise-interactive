# Tasks: Shader Startup Latency

## Status legend
- `[ ]` todo
- `[~]` in progress
- `[x]` done
- `[-]` skipped / won't do

---

## Tasks

- [ ] Export `scene`, `blitScene`, and `camera` from `src/renderer.js`
- [ ] Wrap `main.js` startup in an async IIFE
- [ ] Call `await renderer.compileAsync(scene, camera)` and `await renderer.compileAsync(blitScene, camera)` before `animate()`
- [ ] Move `setReady()` to fire after `compileAsync` resolves (remove from inside `animate()`)
- [ ] Remove the now-stale comment about first-frame shader compilation in `animate()`
- [ ] Verify in browser: UI stays responsive during load, button enables correctly, first frame is clean

## Notes

_Anything discovered during implementation that future sessions should know._
