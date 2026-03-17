import { vertexShader, fragmentShader, blitFragmentShader } from './shaders.js';
import { uniforms } from './uniforms.js';
import { halton } from './temporal.js';

// ---- WebGL renderer --------------------------------------------------------
export const renderer = new THREE.WebGLRenderer();
renderer.setPixelRatio(1);  // Capped at 1x to avoid 4x pixel count on HiDPI screens
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

export const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);

// ---- Main scene (fullscreen raymarcher quad) --------------------------------
const scene = new THREE.Scene();
const material = new THREE.ShaderMaterial({ vertexShader, fragmentShader, uniforms });
scene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), material));

// ---- Render targets (ping-pong temporal accumulation) ----------------------
function makeRT(w, h) {
    return new THREE.WebGLRenderTarget(w, h, {
        minFilter: THREE.LinearFilter,
        magFilter: THREE.LinearFilter,
        format: THREE.RGBAFormat,
        type: THREE.UnsignedByteType,
    });
}

let rtScene = makeRT(window.innerWidth, window.innerHeight);  // current frame
let rtHistA = makeRT(window.innerWidth, window.innerHeight);  // history ping
let rtHistB = makeRT(window.innerWidth, window.innerHeight);  // history pong

// ---- Blit scene (blends current frame with history) ------------------------
const blitMaterial = new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader: blitFragmentShader,
    uniforms: {
        tCurrent:    { value: null },
        tHistory:    { value: null },
        uBlend:      { value: 0.12 },
        iResolution: uniforms.iResolution,  // shared reference
    },
});
const blitScene = new THREE.Scene();
blitScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), blitMaterial));

// ---- render() — encapsulates the full ping-pong blit logic -----------------
export function render(temporalOn, frameIdx) {
    if (temporalOn) {
        // Sub-pixel Halton jitter (8-frame cycle)
        const ji = (frameIdx % 8) + 1;
        uniforms.iJitter.value.set(halton(ji, 2) - 0.5, halton(ji, 3) - 0.5);

        // Ping-pong: read from histRead, write blended result to histWrite
        const histRead  = (frameIdx % 2 === 0) ? rtHistA : rtHistB;
        const histWrite = (frameIdx % 2 === 0) ? rtHistB : rtHistA;

        // 1. Render current frame to scene RT
        renderer.setRenderTarget(rtScene);
        renderer.render(scene, camera);

        // 2. Blend current + history → histWrite
        blitMaterial.uniforms.tCurrent.value = rtScene.texture;
        blitMaterial.uniforms.tHistory.value = histRead.texture;
        blitMaterial.uniforms.uBlend.value   = frameIdx === 0 ? 1.0 : 0.12;
        renderer.setRenderTarget(histWrite);
        renderer.render(blitScene, camera);

        // 3. Display histWrite to screen
        blitMaterial.uniforms.tCurrent.value = histWrite.texture;
        blitMaterial.uniforms.uBlend.value   = 1.0;  // passthrough
        renderer.setRenderTarget(null);
        renderer.render(blitScene, camera);
    } else {
        uniforms.iJitter.value.set(0, 0);
        renderer.setRenderTarget(null);
        renderer.render(scene, camera);
    }
}

// ---- resizeRenderTargets() -------------------------------------------------
export function resizeRenderTargets(w, h) {
    rtScene.setSize(w, h);
    rtHistA.setSize(w, h);
    rtHistB.setSize(w, h);
}
