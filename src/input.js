import { uniforms } from './uniforms.js';
import { toggleTemporal, resetFrameIdx, setMoving } from './temporal.js';
import { attachNearbySphere, detachLastSphere } from './sphereAttachment.js';
import { renderer, resizeRenderTargets, cycleRenderScale, renderScale } from './renderer.js';

export const keys = { w: false, a: false, s: false, d: false, space: false };

// Persistent accumulated virtual cursor position.
// Initially offset so the default shader camera angle faces +Z.
let accumulatedX = window.innerWidth  * 0.25;
let accumulatedY = window.innerHeight * 0.5;

let isDragging  = false;
let lastClientX = 0;
let lastClientY = 0;

export function registerInputHandlers(domElement) {
    // ---- Keyboard ----------------------------------------------------------
    window.addEventListener('keydown', (e) => {
        const k = e.key.toLowerCase();
        if (k in keys) keys[k] = true;
        if (e.key === ' ') { keys.space = true; e.preventDefault(); }
        if (k === 't') {
            toggleTemporal();
            resetFrameIdx();
            uniforms.iJitter.value.set(0, 0);
        }
        if (k === 'r') {
            const scale = cycleRenderScale();
            resetFrameIdx();
            console.log(`Render scale: ${(scale * 100).toFixed(0)}%`);
        }
        if (k === 'e') {
            attachNearbySphere();
        }
        if (k === 'q') {
            detachLastSphere();
            resetFrameIdx();
        }
    });

    window.addEventListener('keyup', (e) => {
        const k = e.key.toLowerCase();
        if (k in keys) keys[k] = false;
        if (e.key === ' ') keys.space = false;
    });

    // ---- Resize ------------------------------------------------------------
    window.addEventListener('resize', () => {
        const w = window.innerWidth, h = window.innerHeight;
        renderer.setSize(w, h);
        const rw = Math.max(1, Math.floor(w * renderScale));
        const rh = Math.max(1, Math.floor(h * renderScale));
        uniforms.iResolution.value.set(rw, rh, 1.0);
        uniforms.uWindowSize.value.set(w, h);
        resizeRenderTargets(w, h);
        resetFrameIdx();
    });

    // ---- Mouse -------------------------------------------------------------
    domElement.addEventListener('mousemove', (e) => {
        if (!isDragging) return;

        const dx = e.clientX - lastClientX;
        const dy = e.clientY - lastClientY;

        accumulatedX += dx;
        accumulatedY += dy;

        // Clamp pitch to prevent gimbal flip and floor clipping
        accumulatedY = Math.max(window.innerHeight * 0.45, Math.min(window.innerHeight * 0.85, accumulatedY));

        lastClientX = e.clientX;
        lastClientY = e.clientY;

        uniforms.iMouse.value.set(accumulatedX, accumulatedY, uniforms.iMouse.value.z, uniforms.iMouse.value.w);

        setMoving(true);  // higher blend factor during camera pan
    });

    domElement.addEventListener('mousedown', (e) => {
        isDragging  = true;
        lastClientX = e.clientX;
        lastClientY = e.clientY;
        uniforms.iMouse.value.set(accumulatedX, accumulatedY, e.clientX, window.innerHeight - e.clientY);
    });

    domElement.addEventListener('mouseup', () => {
        isDragging = false;
        uniforms.iMouse.value.z = -Math.abs(uniforms.iMouse.value.z);
        uniforms.iMouse.value.w = -Math.abs(uniforms.iMouse.value.w);
    });
}
