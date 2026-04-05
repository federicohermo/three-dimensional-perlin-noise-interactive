import { setReady, onEnter, hideOverlay } from './ui.js';
import { Vector3 } from 'three';
import { uniforms, getCameraAngles } from './uniforms.js';
import { renderer, render } from './renderer.js';
import { temporalOn, frameIdx, isMoving, tickFrameIdx, setMoving } from './temporal.js';
import { keys, registerInputHandlers } from './input.js';
import { tickFalling, hasActiveFalling, getSpherePos, cellRadius, worldToCell } from './sphereAttachment.js';
import { queryTerrainHeight } from './heightQuery.js';

registerInputHandlers(renderer.domElement);

let lastTime = performance.now();
let entered = false;

const GRAVITY = -22;
const JUMP_VEL = 12;
let vy = 0;
let charFacingX = 0, charFacingZ = 1;

onEnter().then(() => {
    entered = true;
    hideOverlay();
    uniforms.iCameraPos.value.y = queryTerrainHeight(uniforms.iCameraPos.value.x, uniforms.iCameraPos.value.z) + 2.0;
    lastTime = performance.now();
});

function animate() {
    requestAnimationFrame(animate);

    const now = performance.now();
    const dt = entered ? (now - lastTime) / 1000 : 0;
    lastTime = now;
    const elapsed = now / 1000;
    uniforms.iTime.value = elapsed;

    // Day/night cycle: sun orbits in a tilted plane (full cycle ≈ 2 min)
    const sunAngle = elapsed * 0.008;
    uniforms.uSunDir.value.set(
        -0.5,
        Math.sin(sunAngle),
        -Math.cos(sunAngle)
    ).normalize();

    // ---- Render (always — compiles shaders on first frame behind loading screen)
    render(temporalOn, frameIdx, isMoving);

    // Signal ready after the first render (shaders now compiled)
    if (!animate.ready) { animate.ready = true; setReady(); }

    if (!entered) return;

    // ---- WASD Movement -----------------------------------------------------
    const moveSpeed = 5.0 * dt;
    const { yaw } = getCameraAngles();

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
        if (keys.a) { fx -= right.x; fz -= right.z; }
        if (keys.d) { fx += right.x; fz += right.z; }
        const flen = Math.sqrt(fx * fx + fz * fz);
        if (flen > 0.001) {
            charFacingX = fx / flen;
            charFacingZ = fz / flen;
        }
        uniforms.uCharFacing.value.set(charFacingX, charFacingZ);
        // Advance walk cycle proportional to distance traveled (one full cycle ≈ 1.5 world units)
        if (onGround) uniforms.uAnimPhase.value += moveSpeed * (Math.PI * 2 / 1.5);
    }

    uniforms.uVY.value = vy;
    uniforms.uMoving.value = moved ? 1.0 : 0.0;

    // Camera collision: pull camera back if orbit position is inside a domain sphere
    {
        const MAX_CAM = 4.0;
        const MIN_CAM = 0.5;
        const { yaw: camYaw, pitch: camPitch } = getCameraAngles();
        const cosPitch = Math.cos(camPitch);
        const camDirX = Math.cos(camYaw) * cosPitch;
        const camDirY = Math.sin(camPitch);
        const camDirZ = Math.sin(camYaw) * cosPitch;
        let safeDist = MAX_CAM;
        const px = pos.x, py = pos.y, pz = pos.z;
        const { cellX, cellZ } = worldToCell(px, pz);
        for (let i = -1; i <= 1; i++) {
            for (let j = -1; j <= 1; j++) {
                const cx = cellX + i, cz = cellZ + j;
                const sp = getSpherePos(cx, cz);
                // Effective radius: geometric + max noise extension (0.8) + small margin
                const r = cellRadius(cx, cz) + 0.9;
                const dx = sp.x - px, dy = sp.y - py, dz = sp.z - pz;
                const cx2 = dx * camDirX + dy * camDirY + dz * camDirZ;
                const disc = cx2 * cx2 - (dx * dx + dy * dy + dz * dz - r * r);
                if (disc >= 0) {
                    const sqrtDisc = Math.sqrt(disc);
                    const entry = cx2 - sqrtDisc;
                    const exit  = cx2 + sqrtDisc;
                    // Only pull back if camera endpoint is actually inside the sphere
                    // (ray passes through AND camera sits between entry and exit)
                    if (entry > 0 && entry < safeDist && exit >= safeDist) {
                        safeDist = Math.max(MIN_CAM, entry - 0.15);
                    }
                }
            }
        }
        uniforms.uCamDist.value = safeDist;
    }

    setMoving(moved || !onGround || hasActiveFalling());

    tickFalling(dt, forward);

    setMoving(false);  // reset each frame; input handlers re-set it if still active
    if (temporalOn) tickFrameIdx();
}

animate();
