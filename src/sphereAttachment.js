import { Vector2, Vector3 } from 'three';
import { uniforms, getCameraAngles } from './uniforms.js';
import { queryTerrainHeight } from './heightQuery.js';

const attachedSpheres = []; // { offset: Vector3, cell: Vector2 }
const fallingSpheres  = []; // { worldPos, vel, cell, age, radius, landed, groundY, groundQueryTimer }
const MAX_FALLING    = 5;
const FALL_LIFETIME  = 12.0; // fallback max lifetime

// ---- JS mirrors of the GLSL helper functions -------------------------------
function fract(v) { return v - Math.floor(v); }

function hashCell(cx, cz) {
    // Mirrors GLSL: Hash(vec3(curCell, 1.0)) where curCell = vec2(cx, cz)
    // Must use Math.fround throughout — fract() of large floats is catastrophically
    // sensitive to float32 vs float64 precision, causing radius diffs up to 0.64.
    const fr = Math.fround;
    function fract32(v) { const fv = fr(v); return fr(fv - Math.floor(fv)); }
    let ax = fract32(fr(cx) * fr(1741.124));
    let ay = fract32(fr(cz) * fr(7537.13));
    let az = fract32(fr(1.0) * fr(4157.47));
    const d = fr(fr(ax) * fr(fr(ax) + fr(71.13)))
            + fr(fr(ay) * fr(fr(ay) + fr(71.13)))
            + fr(fr(az) * fr(fr(az) + fr(71.13)));
    ax = fr(ax + d); ay = fr(ay + d); az = fr(az + d);
    return fract32(fr(fr(ax) + fr(ay)) * fr(az));
}
export function cellRadius(cx, cz) {
    // Mirrors GLSL: mix(0.08, 0.8, pow(Hash(vec3(curCell, 1.0)), 2.0))
    const h = hashCell(cx, cz);
    return 0.08 + (0.8 - 0.08) * h * h;
}
export function worldToCell(x, z) {
    return { cellX: Math.floor((x + 7.5) / 15.0), cellZ: Math.floor((z + 7.5) / 15.0) };
}
// Convert a world-space offset to character-local (rt, Y, fwd) space
function toLocalOffset(worldOffset) {
    const f = uniforms.uCharFacing.value;
    const fwd = { x: f.x, z: f.y };
    const rt  = { x: -fwd.z, z: fwd.x };
    return new Vector3(
        rt.x  * worldOffset.x + rt.z  * worldOffset.z,
        worldOffset.y,
        fwd.x * worldOffset.x + fwd.z * worldOffset.z
    );
}

// Convert a character-local offset back to world space
function toWorldOffset(localOffset) {
    const f = uniforms.uCharFacing.value;
    const fwd = { x: f.x, z: f.y };
    const rt  = { x: -fwd.z, z: fwd.x };
    return new Vector3(
        rt.x  * localOffset.x + fwd.x * localOffset.z,
        localOffset.y,
        rt.z  * localOffset.x + fwd.z * localOffset.z
    );
}

function getJitter(p) {
    let px = fract(p.x * 0.1031);
    let py = fract(p.y * 0.1030);
    let pz = fract(p.z * 0.0973);
    const d = px * (py + 33.33) + py * (px + 33.33) + pz * (py + 33.33);
    px += d; py += d; pz += d;
    const resX = fract((px + py) * pz);
    const resY = fract((px + px) * py);
    const resZ = fract((py + px) * px);
    return new Vector3(-1.0 + 2.0 * resX, -1.0 + 2.0 * resY, -1.0 + 2.0 * resZ)
        .normalize()
        .multiplyScalar(3.5);
}

export function getSpherePos(cellX, cellZ) {
    const curCell = new Vector3(cellX, cellZ, 0.0);
    const jitter = getJitter(curCell);
    return new Vector3(
        cellX * 15.0 + jitter.x,
        7.5 + jitter.y * 0.5,
        cellZ * 15.0 + jitter.z
    );
}

// ---- Public API ------------------------------------------------------------

export function attachNearbySphere() {
    if (attachedSpheres.length >= 10) return;

    const p = uniforms.iCameraPos.value;
    const { cellX, cellZ } = worldToCell(p.x, p.z);

    const CHAR_DOMAIN = 2.2;   // char_avg_noisy(1.2) + domain_smooth(0.6) + tolerance(0.4)
    const DOM_DOM = 2.0;   // attached_avg_noisy(1.0) + domain_smooth(0.6) + tolerance(0.4)

    let bestSdf = 0;        // ≤ 0 means collision; track deepest overlap
    let bestSphere = null;
    let sphereFound = false;

    for (let i = -1; i <= 1; i++) {
        for (let j = -1; j <= 1; j++) {
            const cx = cellX + i;
            const cz = cellZ + j;

            if (attachedSpheres.some(s => Math.abs(s.cell.x - cx) < 0.1 && Math.abs(s.cell.y - cz) < 0.1)) continue;

            const sPos = getSpherePos(cx, cz);
            const distToChar = p.distanceTo(sPos);
            if (distToChar < 10.0) sphereFound = true;

            // SDF of this domain sphere against the whole cluster
            let sdf = distToChar - CHAR_DOMAIN;
            for (const s of attachedSpheres) {
                const aPos = p.clone().add(toWorldOffset(s.offset));
                sdf = Math.min(sdf, aPos.distanceTo(sPos) - DOM_DOM);
            }

            if (sdf <= 0 && (bestSphere === null || sdf < bestSdf)) {
                bestSdf = sdf;
                bestSphere = { offset: toLocalOffset(sPos.clone().sub(p)), cell: new Vector2(cx, cz), radius: cellRadius(cx, cz) };
            }
        }
    }

    if (bestSphere) {
        console.log("SUCCESS: Attaching sphere at relative offset:", bestSphere.offset);
        attachedSpheres.push(bestSphere);
        updateAttachmentUniforms();
    } else {
        console.log(sphereFound
            ? "DEBUG: Spheres detected but not colliding with cluster."
            : "DEBUG: No spheres in 3x3 grid.");
    }
}

export function updateAttachmentUniforms() {
    const offsets = uniforms.uAttachedOffsets.value;
    const radii   = uniforms.uAttachedRadii.value;
    const ignored = uniforms.uIgnoredCells.value;

    uniforms.uAttachedCount.value = attachedSpheres.length;

    for (let i = 0; i < 10; i++) {
        if (i < attachedSpheres.length) {
            offsets[i].copy(toWorldOffset(attachedSpheres[i].offset));
            radii[i]  = attachedSpheres[i].radius;
        } else {
            radii[i]  = 0.0;
        }
    }

    // Pack all ignored cells contiguously so uIgnoredCount indexes them correctly
    let ignoredIdx = 0;
    for (const s of attachedSpheres) ignored[ignoredIdx++].copy(s.cell);
    for (const s of fallingSpheres)  ignored[ignoredIdx++].copy(s.cell);
    uniforms.uIgnoredCount.value = ignoredIdx;
}

function updateFallingUniforms() {
    const pos   = uniforms.uFallingPositions.value;
    const radii = uniforms.uFallingRadii.value;
    uniforms.uFallingCount.value = fallingSpheres.length;
    for (let i = 0; i < 5; i++) {
        if (i < fallingSpheres.length) {
            pos[i].copy(fallingSpheres[i].worldPos);
            radii[i] = fallingSpheres[i].radius;
        } else {
            radii[i] = 0;
        }
    }
}

export function detachLastSphere(launchVel) {
    if (attachedSpheres.length === 0) return;
    if (fallingSpheres.length >= MAX_FALLING) return;
    const s = attachedSpheres.pop();
    const worldPos = uniforms.iCameraPos.value.clone().add(toWorldOffset(s.offset));
    const vel = launchVel ? launchVel.clone() : new Vector3(0, 1.5, 0);
    fallingSpheres.push({ worldPos, vel, cell: s.cell, age: 0, radius: s.radius, landed: false, groundY: 0, groundQueryTimer: 0 });
    updateAttachmentUniforms();
}

export function hasActiveFalling() {
    return fallingSpheres.some(s => !s.landed);
}

export function tickFalling(dt, forward) {
    updateAttachmentUniforms(); // always re-project local→world offsets each frame
    if (fallingSpheres.length === 0) return;
    const GRAVITY = -8.0;

    // iCameraPos is the orbit look-at target (ta), not the eye.
    // Reconstruct actual eye position (ro) to correctly classify behind-camera.
    const ta = uniforms.iCameraPos.value;
    const { yaw, pitch } = getCameraAngles();
    const CAMDIST = uniforms.uCamDist.value;
    const ro = ta.clone().add(new Vector3(
        CAMDIST * Math.cos(yaw) * Math.cos(pitch),
        CAMDIST * Math.sin(pitch),
        CAMDIST * Math.sin(yaw) * Math.cos(pitch)
    ));

    for (const s of fallingSpheres) {
        s.age += dt;
        if (!s.landed) {
            // Air damping — slight resistance makes arc feel natural (Three.js FPS pattern)
            s.vel.addScaledVector(s.vel, Math.exp(-0.8 * dt) - 1);

            s.vel.y += GRAVITY * dt;
            s.worldPos.addScaledVector(s.vel, dt);

            // Query actual terrain height — only when descending and near ground
            s.groundQueryTimer -= dt;
            if (s.vel.y < 0 && s.worldPos.y < 15 && s.groundQueryTimer <= 0) {
                s.groundY = queryTerrainHeight(s.worldPos.x, s.worldPos.z) + s.radius * 0.5;
                s.groundQueryTimer = 0.1; // throttle: max once per 100ms
            }

            // Bounce on landing
            if (s.worldPos.y < s.groundY) {
                s.worldPos.y = s.groundY;
                s.vel.y = Math.abs(s.vel.y) * 0.55;  // restitution
                s.vel.x *= 0.75;
                s.vel.z *= 0.75;
                if (s.vel.y < 0.4) { s.vel.set(0, 0, 0); s.landed = true; }
            }
        }
    }

    // Remove when landed AND out of view, or after max lifetime
    for (let i = fallingSpheres.length - 1; i >= 0; i--) {
        const s = fallingSpheres[i];
        if (s.age >= FALL_LIFETIME) { fallingSpheres.splice(i, 1); continue; }
        if (s.landed) {
            const dir = s.worldPos.clone().sub(ro);
            const dist = dir.length();
            if (dist > 8.0 && dir.dot(forward) / dist < -0.2) {
                fallingSpheres.splice(i, 1);
            }
        }
    }

    updateFallingUniforms();
    updateAttachmentUniforms();
}
