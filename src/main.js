import './ui.js';
import { Clock, Vector3 } from 'three';
import { uniforms } from './uniforms.js';
import { renderer, render } from './renderer.js';
import { temporalOn, frameIdx, resetFrameIdx, tickFrameIdx } from './temporal.js';
import { keys, registerInputHandlers } from './input.js';
import { tickFalling, hasActiveFalling } from './sphereAttachment.js';
import { queryTerrainHeight } from './heightQuery.js';

registerInputHandlers(renderer.domElement);

const clock = new Clock();

const GRAVITY = -22;
const JUMP_VEL = 12;
let vy = 0;
let charFacingX = 0, charFacingZ = 1;

(function animate() {
    requestAnimationFrame(animate);

    const dt = clock.getDelta();
    uniforms.iTime.value = clock.getElapsedTime();

    // ---- WASD Movement -----------------------------------------------------
    const moveSpeed = 5.0 * dt;
    const m = uniforms.iMouse.value;
    const yaw = -(m.x / window.innerWidth) * 12.5662 - 1.5707;

    // Forward = direction from camera to target (ta - ro); since ro = ta + offset, forward = -offset_dir
    const forward = new Vector3(-Math.cos(yaw), 0, -Math.sin(yaw));
    const right = new Vector3().crossVectors(new Vector3(0, 1, 0), forward).normalize();

    let moved = false;
    if (keys.w) { uniforms.iCameraPos.value.addScaledVector(forward, moveSpeed); moved = true; }
    if (keys.s) { uniforms.iCameraPos.value.addScaledVector(forward, -moveSpeed); moved = true; }
    if (keys.a) { uniforms.iCameraPos.value.addScaledVector(right, -moveSpeed); moved = true; }
    if (keys.d) { uniforms.iCameraPos.value.addScaledVector(right, moveSpeed); moved = true; }

    // Jump & gravity
    const pos = uniforms.iCameraPos.value;
    const groundY = queryTerrainHeight(pos.x, pos.z) + 2.0;
    const onGround = pos.y <= groundY + 0.05;

    if (keys.space && onGround) vy = JUMP_VEL;
    vy += GRAVITY * dt;
    pos.y += vy * dt;

    if (pos.y <= groundY) {
        pos.y = groundY;
        vy = 0;
    }

    // Update character facing and animation phase from current movement direction
    if (moved) {
        let fx = 0, fz = 0;
        if (keys.w) { fx += forward.x; fz += forward.z; }
        if (keys.s) { fx -= forward.x; fz -= forward.z; }
        if (keys.a) { fx -= right.x;   fz -= right.z; }
        if (keys.d) { fx += right.x;   fz += right.z; }
        const flen = Math.sqrt(fx * fx + fz * fz);
        if (flen > 0.001) {
            charFacingX = fx / flen;
            charFacingZ = fz / flen;
        }
        uniforms.uCharFacing.value.set(charFacingX, charFacingZ);
        // Advance walk cycle proportional to distance traveled (one full cycle ≈ 1.5 world units)
        uniforms.uAnimPhase.value += moveSpeed * (Math.PI * 2 / 1.5);
    }

    if (moved || !onGround || hasActiveFalling()) resetFrameIdx();

    tickFalling(dt, forward);

    // ---- Render ------------------------------------------------------------
    render(temporalOn, frameIdx);
    if (temporalOn) tickFrameIdx();
})();
