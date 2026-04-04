import { Vector2, Vector3, Vector4 } from 'three';
const SUN_INITIAL = new Vector3(-0.5, 0.8, -0.6).normalize();
// Default render scale (must match renderer.js SCALES[0])
const INITIAL_RENDER_SCALE = 0.5;

// Single shared uniforms object — ES module singleton (all importers share the same reference).
export const uniforms = {
    iTime: { value: 0.0 },
    iResolution: {
        value: new Vector3(
            Math.floor(window.innerWidth * INITIAL_RENDER_SCALE),
            Math.floor(window.innerHeight * INITIAL_RENDER_SCALE), 1.0)
    },
    iMouse: { value: new Vector4(window.innerWidth * 0.25, window.innerHeight * 0.5, 0, 0) },
    iJitter: { value: new Vector2(0, 0) },
    iCameraPos: { value: new Vector3(0.0, 8.0, 4.0) },
    uAttachedOffsets: { value: Array.from({ length: 10 }, () => new Vector3()) },
    uAttachedRadii: { value: new Float32Array(10) },
    uIgnoredCells: { value: Array.from({ length: 15 }, () => new Vector2()) },
    uAttachedCount: { value: 0 },
    uIgnoredCount: { value: 0 },
    uFallingPositions: { value: Array.from({ length: 5 }, () => new Vector3()) },
    uFallingRadii: { value: new Float32Array(5) },
    uFallingCount: { value: 0 },
    uWindowSize: { value: new Vector2(window.innerWidth, window.innerHeight) },
    uCharFacing: { value: new Vector2(0, 1) },
    uAnimPhase: { value: 0.0 },
    uVY: { value: 0.0 },
    uMoving: { value: 0.0 },
    uCamDist: { value: 4.0 },
    uSunDir:  { value: SUN_INITIAL.clone() },
};

export function getCameraAngles() {
    const m = uniforms.iMouse.value;
    const yaw   = -(m.x / window.innerWidth)  * 12.5662 - 1.5707;
    const pitch =  (m.y / window.innerHeight - 0.5) * 4.0;
    return { yaw, pitch };
}
