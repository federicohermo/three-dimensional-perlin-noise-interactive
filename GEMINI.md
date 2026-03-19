# 3D Perlin Noise Raymarcher (Gemini Tracking)

Shadertoy-style 3D Perlin noise raymarcher ported to Three.js. 

## Files
- `index.html` — Self-contained app: vertex/fragment shaders + Three.js setup. Open in browser to run.
- `perlin3d_fixed.glsl` — Standalone copy of the fragment shader (synced with index.html).
- `shadertoy_common.glsl` — [NEW] Shared math & SDF functions for Shadertoy [Common] tab.
- `shadertoy_bufferA.glsl` — [NEW] Persistence logic for Shadertoy [Buffer A] tab.
- `shadertoy_image.glsl` — [NEW] Main rendering entry point for Shadertoy [Image] tab.
- `perlin3d.glsl` — Original shader before fixes (reference only).

## Fix History

### Session 1: Noise fix
- Replaced broken value-noise `Noise()` with correct 3D Perlin gradient noise (`sNoise` + `Hash3` + trilinear interpolation).

### Session 2: Performance + lighting artifacts
- Fixed NaN issues with the initial shadow implementation.
- Adjusted shadow step limits for the light configuration.

### Session 3: Shadow quality + performance + temporal accumulation
- **Improved soft shadows**: Implemented limits for `ph` tracking in shadows.
- **Lipschitz relaxation**: Relaxed early-out bounds on the sphere and plane to prevent ray overreach. 
- **Temporal accumulation**: Ping-pong frame blending with Halton(2,3) sub-pixel jitter.

### Session 4: Lighting & Artifact Fixes
- **Grid-aligned noise artifacts**: Replaced `sin()`-based `Hash3` gradient noise with a sineless Dave Hoskins variant. 
- **Shadow Adaptation**: Restored the classic `k * h / t` soft shadow formula since the 2018 Inigo Quilez formula breaks for heavily displaced non-Lipschitz surfaces. Attempted to adapt the 2018 formula mathematically, but it was visually unstable and reverted.

### Session 5: Orbital Camera
- **Sperhical Coordinates**: Translated the `iMouse` Shadertoy uniform drag vector into Spherical Coordinates ($Yaw$, $Pitch$).
- **Calculated LookAt Matrix**: Constructed a dynamic orthonormal frame (Forward, Right, and Up vectors) to generate responsive, non-flipping orbital rays wrapping around the central noise-displaced sphere.
- **Continuous Rotation**: Rather than feeding raw pixel locations to `iMouse`, the `index.html` Javascript captures the active drag delta on `mousemove` and adds it to persistent `accumulatedX`/`accumulatedY` trackers. This prevents the camera from destructively snapping to the cursor upon mouse click.

### Session 6: Camera Persistence and Control Refinement
- **Removed Persistence Bug**: Deleted the `iMouse.z` condition in `perlin3d_fixed.glsl` that reset the camera upon mouse release.
- **Initial Interaction Guard Removal**: Removed all checks for uninitialized `iMouse` input that were causing the camera to snap back to a "beauty shot" default view. The shader now respects the host's persistent cursor values unconditionally.
- **Improved Sensitivity & range**: Narrowed the `m.y` clamping to `[0.2, 0.8]` and significantly reduced rotation sensitivity for smoother, more premium-feeling orbital exploration.

### Session 7: Shadertoy Persistence (Buffer A)
- **Implemented Buffer A Logic**: Split the shader into three parts to overcome Shadertoy's stateless `iMouse` behavior.
- **Persistent State Storage**: Created `shadertoy_bufferA.glsl` to accumulate mouse deltas and store yaw/pitch in a feedback loop.
- **Integrated Mathematical Common**: Extracted all SDF and Raymarching logic into `shadertoy_common.glsl` to avoid duplication across tabs.
- **Final Cleanup**: Removed redundant intermediate files and verified cross-platform consistency.

### Session 8: Vertical Layout Adjustment
- **Elevated Sphere & Camera**: Shifted the primary sphere and camera baseline from $y=1$ to $y=6$ to provide a clearer view of the terrain.
- **Synchronized Plane Height**: Unified the ground plane baseline at $y=4$ across the Three.js host and all Shadertoy tabs for visual consistency.
- **Fixed Standalone Shader**: Corrected parameter mismatches in `perlin3d_fixed.glsl` that were causing compilation errors in the "fixed" reference file.

### Session 9: Infinite Spheres & Smoothmin
- **Smooth Minimum Implementation**: Added a polynomial `smin` function to `shadertoy_common.glsl`, `index.html`, and `perlin3d_fixed.glsl` for organic blending between surfaces.
- **Domain Repetition & Randomization**: Implemented XZ-plane domain repetition for infinite spheres. Added hash-based jittering using cell IDs to randomize X, Z, and Y positions within each cell territory.
- **Blobby Interaction & Refinement**: Combined the character sphere with repeated spheres using `smin`. Tuned $k=0.4$ and baseline height $y=7.5$ for a tight, premium-feeling interaction that clears the terrain.

### Session 10: Performance Optimizations
- **`GetDistCheap` for shadows & AO**: Created a lightweight SDF variant using 2 noise octaves and a 3x3 neighbor search (no attachment spheres). Wired into `CastShadow` and `GetAO`. Restoring the 3x3 search was necessary to maintain SDF continuity and prevent terrain holes at cell boundaries. 
- **`uAttachedCount` early-exit**: Added an integer uniform so the ignore-cell and attached-sphere inner loops can `break` at the actual count instead of always iterating 10.
- **Reduced AO samples**: Decreased from 5 to 3 samples using `GetDistCheap`.
- **Distance-adaptive normal epsilon**: Normal offset `h` now scales with ray distance ($\max(0.005, 0.0015 \cdot d)$) for faster convergence on distant surfaces.
- **Removed unused rotation helpers**: Deleted `rotateYZ`, `rotateXZ`, `rotateXY` (dead code).
- **Half-resolution rendering**: Render targets default to 50% resolution; blit pass upscales to full window size. Press **R** to cycle through 50% → 75% → 100%. Blit shader uses its own decoupled resolution uniform to handle per-pass resolution switching.
- **WASD yaw sync**: JS yaw calculation uses `iResolution.x` (scaled resolution) instead of `window.innerWidth` to match the shader's normalization.
