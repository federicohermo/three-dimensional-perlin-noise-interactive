import {
    WebGLRenderer, OrthographicCamera, Scene, ShaderMaterial,
    PlaneGeometry, Mesh, WebGLRenderTarget,
    LinearFilter, RGBAFormat, UnsignedByteType, Vector3 as V3
} from 'three';
import { vertexShader, fragmentShader, blitFragmentShader } from './shaders.js';
import { uniforms } from './uniforms.js';
import { halton } from './temporal.js';

// ---- Resolution scale (Tier 3 optimization) --------------------------------
const SCALES = [0.5, 0.75, 1.0];
let scaleIdx = 0;
export let renderScale = SCALES[scaleIdx];

export function cycleRenderScale() {
    scaleIdx = (scaleIdx + 1) % SCALES.length;
    renderScale = SCALES[scaleIdx];
    const w = window.innerWidth, h = window.innerHeight;
    const rw = Math.max(1, Math.floor(w * renderScale));
    const rh = Math.max(1, Math.floor(h * renderScale));
    rtScene.setSize(rw, rh);
    rtHistA.setSize(rw, rh);
    rtHistB.setSize(rw, rh);
    uniforms.iResolution.value.set(rw, rh, 1.0);
    return renderScale;
}

// ---- WebGL renderer --------------------------------------------------------
export const renderer = new WebGLRenderer();
renderer.setPixelRatio(1);  // Capped at 1x to avoid 4x pixel count on HiDPI screens
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

export const camera = new OrthographicCamera(-1, 1, 1, -1, 0, 1);

// ---- Main scene (fullscreen raymarcher quad) --------------------------------
const scene = new Scene();
const material = new ShaderMaterial({ vertexShader, fragmentShader, uniforms });
scene.add(new Mesh(new PlaneGeometry(2, 2), material));

// ---- Render targets (ping-pong temporal accumulation) ----------------------
function makeRT(w, h) {
    return new WebGLRenderTarget(w, h, {
        minFilter: LinearFilter,
        magFilter: LinearFilter,
        format: RGBAFormat,
        type: UnsignedByteType,
    });
}

function scaledSize() {
    return [
        Math.max(1, Math.floor(window.innerWidth * renderScale)),
        Math.max(1, Math.floor(window.innerHeight * renderScale)),
    ];
}

const [initW, initH] = scaledSize();
let rtScene = makeRT(initW, initH);  // current frame
let rtHistA = makeRT(initW, initH);  // history ping
let rtHistB = makeRT(initW, initH);  // history pong

// ---- Blit scene (blends current frame with history) ------------------------
const blitResolution = new V3(initW, initH, 1.0); // own resolution, updated per-pass
const blitMaterial = new ShaderMaterial({
    vertexShader,
    fragmentShader: blitFragmentShader,
    uniforms: {
        tCurrent:    { value: null },
        tHistory:    { value: null },
        uBlend:      { value: 0.12 },
        iResolution: { value: blitResolution },  // decoupled from main shader
    },
});
const blitScene = new Scene();
blitScene.add(new Mesh(new PlaneGeometry(2, 2), blitMaterial));

// ---- render() — encapsulates the full ping-pong blit logic -----------------
export function render(temporalOn, frameIdx, moving = false) {
    // Pre-compute scaled and full resolutions for blit passes
    const rw = uniforms.iResolution.value.x;
    const rh = uniforms.iResolution.value.y;
    const fw = window.innerWidth;
    const fh = window.innerHeight;

    if (temporalOn) {
        // Sub-pixel Halton jitter (8-frame cycle). Zero on frame 0 (during/after movement)
        // so history-less frames aren't offset, which would cause visible aliasing.
        if (frameIdx === 0) {
            uniforms.iJitter.value.set(0, 0);
        } else {
            const ji = (frameIdx % 8) + 1;
            uniforms.iJitter.value.set(halton(ji, 2) - 0.5, halton(ji, 3) - 0.5);
        }

        // Ping-pong: read from histRead, write blended result to histWrite
        const histRead  = (frameIdx % 2 === 0) ? rtHistA : rtHistB;
        const histWrite = (frameIdx % 2 === 0) ? rtHistB : rtHistA;

        // 1. Render current frame to scene RT (scaled resolution)
        renderer.setRenderTarget(rtScene);
        renderer.render(scene, camera);

        // 2. Blend current + history → histWrite (scaled resolution)
        blitResolution.set(rw, rh, 1.0);
        blitMaterial.uniforms.tCurrent.value = rtScene.texture;
        blitMaterial.uniforms.tHistory.value = histRead.texture;
        // Higher blend (more current frame) during motion → less temporal smearing.
        // Lower blend when still → full 8-frame accumulation for smooth AA.
        blitMaterial.uniforms.uBlend.value   = frameIdx === 0 ? 1.0 : (moving ? 0.3 : 0.12);
        renderer.setRenderTarget(histWrite);
        renderer.render(blitScene, camera);

        // 3. Display histWrite to screen (full resolution)
        blitResolution.set(fw, fh, 1.0);
        blitMaterial.uniforms.tCurrent.value = histWrite.texture;
        blitMaterial.uniforms.uBlend.value   = 1.0;  // passthrough
        renderer.setRenderTarget(null);
        renderer.render(blitScene, camera);
    } else {
        uniforms.iJitter.value.set(0, 0);
        if (renderScale < 1.0) {
            // Render to scaled RT, then blit to screen
            renderer.setRenderTarget(rtScene);
            renderer.render(scene, camera);

            blitResolution.set(fw, fh, 1.0);
            blitMaterial.uniforms.tCurrent.value = rtScene.texture;
            blitMaterial.uniforms.tHistory.value = rtScene.texture;
            blitMaterial.uniforms.uBlend.value   = 1.0;
            renderer.setRenderTarget(null);
            renderer.render(blitScene, camera);
        } else {
            renderer.setRenderTarget(null);
            renderer.render(scene, camera);
        }
    }
}

// ---- resizeRenderTargets() -------------------------------------------------
export function resizeRenderTargets(w, h) {
    const rw = Math.max(1, Math.floor(w * renderScale));
    const rh = Math.max(1, Math.floor(h * renderScale));
    rtScene.setSize(rw, rh);
    rtHistA.setSize(rw, rh);
    rtHistB.setSize(rw, rh);
}
