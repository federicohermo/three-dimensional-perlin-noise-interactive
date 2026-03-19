import { Clock, Vector3 } from 'three';
import { uniforms } from './uniforms.js';
import { renderer, render } from './renderer.js';
import { temporalOn, frameIdx, resetFrameIdx, tickFrameIdx } from './temporal.js';
import { keys, registerInputHandlers } from './input.js';

registerInputHandlers(renderer.domElement);

const clock = new Clock();

(function animate() {
    requestAnimationFrame(animate);

    const dt = clock.getDelta();
    uniforms.iTime.value = clock.getElapsedTime();

    // ---- WASD Movement -----------------------------------------------------
    const moveSpeed = 5.0 * dt;
    const m   = uniforms.iMouse.value;
    const yaw = -(m.x / window.innerWidth) * 12.5662 - 1.5707;

    // Forward = direction from camera to target (ta - ro); since ro = ta + offset, forward = -offset_dir
    const forward = new Vector3(-Math.cos(yaw), 0, -Math.sin(yaw));
    const right   = new Vector3().crossVectors(new Vector3(0, 1, 0), forward).normalize();

    let moved = false;
    if (keys.w) { uniforms.iCameraPos.value.addScaledVector(forward,  moveSpeed); moved = true; }
    if (keys.s) { uniforms.iCameraPos.value.addScaledVector(forward, -moveSpeed); moved = true; }
    if (keys.a) { uniforms.iCameraPos.value.addScaledVector(right,   -moveSpeed); moved = true; }
    if (keys.d) { uniforms.iCameraPos.value.addScaledVector(right,    moveSpeed); moved = true; }

    if (moved) resetFrameIdx();

    // ---- Render ------------------------------------------------------------
    render(temporalOn, frameIdx);
    if (temporalOn) tickFrameIdx();
})();
