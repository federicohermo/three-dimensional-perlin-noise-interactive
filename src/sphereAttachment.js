import { Vector2, Vector3 } from 'three';
import { uniforms } from './uniforms.js';

const attachedSpheres = []; // { offset: Vector3, cell: Vector2 }

// ---- JS mirrors of the GLSL helper functions -------------------------------
function fract(v) { return v - Math.floor(v); }
function dot3(a, b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

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
        .multiplyScalar(4.5);
}

function getSpherePos(cellX, cellZ) {
    const curCell = new Vector3(cellX, cellZ, 0.0);
    const jitter  = getJitter(curCell);
    return new Vector3(
        cellX * 15.0 + jitter.x,
        7.5 + jitter.y * 0.5,
        cellZ * 15.0 + jitter.z
    );
}

// ---- Public API ------------------------------------------------------------

export function attachNearbySphere() {
    if (attachedSpheres.length >= 10) return;

    const p     = uniforms.iCameraPos.value;
    const cellX = Math.floor((p.x + 7.5) / 15.0);
    const cellZ = Math.floor((p.z + 7.5) / 15.0);

    let bestDist   = 4.0;
    let bestSphere = null;
    let sphereFound = false;

    for (let i = -1; i <= 1; i++) {
        for (let j = -1; j <= 1; j++) {
            const cx = cellX + i;
            const cz = cellZ + j;

            if (attachedSpheres.some(s => Math.abs(s.cell.x - cx) < 0.1 && Math.abs(s.cell.y - cz) < 0.1)) continue;

            const sPos = getSpherePos(cx, cz);
            const dist = p.distanceTo(sPos);

            if (dist < 10.0) sphereFound = true;

            if (dist < bestDist) {
                bestDist   = dist;
                bestSphere = { offset: sPos.clone().sub(p), cell: new Vector2(cx, cz) };
            }
        }
    }

    if (bestSphere) {
        console.log("SUCCESS: Attaching sphere at relative offset:", bestSphere.offset);
        attachedSpheres.push(bestSphere);
        updateAttachmentUniforms();
    } else {
        console.log(sphereFound
            ? "DEBUG: Spheres detected but too far (>4.0 units)."
            : "DEBUG: No spheres in 3x3 grid.");
    }
}

export function updateAttachmentUniforms() {
    const offsets = uniforms.uAttachedOffsets.value;
    const active  = uniforms.uAttachedActive.value;
    const ignored = uniforms.uIgnoredCells.value;

    uniforms.uAttachedCount.value = attachedSpheres.length;

    for (let i = 0; i < 10; i++) {
        if (i < attachedSpheres.length) {
            offsets[i].copy(attachedSpheres[i].offset);
            active[i]  = 1.0;
            ignored[i].copy(attachedSpheres[i].cell);
        } else {
            active[i] = 0.0;
        }
    }
}
