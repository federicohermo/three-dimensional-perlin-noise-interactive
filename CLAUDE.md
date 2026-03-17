# 3D Perlin Noise Raymarcher

Shadertoy-style 3D Perlin noise raymarcher ported to Three.js. Renders a noisy sphere and terrain with orbiting light and soft shadows.

## Files

- `index.html` — Self-contained app: vertex/fragment shaders + Three.js setup. Open in browser to run.
- `perlin3d_fixed.glsl` — Standalone copy of the fragment shader (kept in sync with index.html).
- `perlin3d.glsl` — Original shader before fixes (reference only).

## How to run

Open `index.html` in any modern browser. No build step or server required.

## Fix history

### Session 1: Noise fix
- Replaced broken value-noise `Noise()` with correct 3D Perlin gradient noise (`sNoise` + `Hash3` + trilinear interpolation).

### Session 2: Performance + lighting artifacts
- **CastShadow NaN**: `sqrt(h*h - y*y)` could go negative when `y > h` → clamped argument to 0.
- **Shadow self-intersection**: Increased ray offset from 1x to 2x `SURFACE_DIST`.
- **Shadow result clamping**: Added `clamp(res, 0.0, 1.0)` to guard against inf from near-zero division.
- **Hash3 normalize removal**: Removed costly `normalize()` call — gradient magnitude doesn't matter for Perlin noise.
- **Pixel ratio cap**: Set to 1x to avoid 4x pixel count on HiDPI screens.
- **Octave reduction**: 4 → 3 octaves (4th octave weight 0.0625 is sub-pixel detail).
- **Shadow tmax reduction**: 8.0 → 5.0 (light is ~5-6 units away).

### Session 3: Shadow quality + performance + temporal accumulation
- **Improved soft shadows**: Restored Quilez 2018 `ph`-tracking penumbra (from original Shadertoy) with proper guards: `max(0.0, h*h - y*y)` prevents NaN, `max(0.0001, t-y)` prevents div-by-zero. Loop reduced 80 → 64 (improved technique converges faster).
- **Lipschitz relaxation**: Sphere 0.8 → 0.85, plane 0.4 → 0.45 (~6-11% fewer ray steps).
- **Distance-based octave LOD**: Noise octaves reduced at distance (>30u: 1 oct, >15u: 2 oct, near: 3 oct). Saves ~15-25% Hash3 calls on shadow rays.
- **Temporal accumulation**: Ping-pong frame blending with Halton(2,3) sub-pixel jitter (8-frame cycle, blend factor 0.12). Effective ~8x supersampling. Toggle with 'T' key. Uses 3 WebGLRenderTargets.

### Session 4: Lighting & Artifact Fixes
- **Grid-aligned noise artifacts**: Replaced the `sin()`-based `Hash3` function with a sineless alternative (Dave Hoskins' `hash33` variant) to completely eliminate square grid patterns on the noise-displaced surfaces.
- **Shadow acne & banding**: Reverted `CastShadow` from the improved Quilez 2018 `ph`-tracking formula back to the classic `k * h / t` soft shadow formula. The 2018 formula mathematically assumes a true Euclidean SDF and breaks down (causing pitch-black bands and self-shadowing acne) on the non-Lipschitz, continuous noise-displaced surfaces used in this scene.
