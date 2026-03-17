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
