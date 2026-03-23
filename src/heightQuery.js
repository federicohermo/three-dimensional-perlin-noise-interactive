import {
    WebGLRenderTarget, FloatType, RGBAFormat,
    ShaderMaterial, PlaneGeometry, Mesh, Scene,
    OrthographicCamera, Vector2,
} from 'three';
import { renderer } from './renderer.js';
import heightFrag from './glsl/height_query.glsl';

const rt = new WebGLRenderTarget(1, 1, { type: FloatType, format: RGBAFormat });
const scene = new Scene();
const camera = new OrthographicCamera(-1, 1, 1, -1, 0, 1);
const uXZ = { value: new Vector2() };
const mat = new ShaderMaterial({
    uniforms: { uXZ },
    vertexShader: `void main() { gl_Position = vec4(position, 1.0); }`,
    fragmentShader: heightFrag,
});
scene.add(new Mesh(new PlaneGeometry(2, 2), mat));
const buf = new Float32Array(4);

export function queryTerrainHeight(x, z) {
    uXZ.value.set(x, z);
    renderer.setRenderTarget(rt);
    renderer.render(scene, camera);
    renderer.setRenderTarget(null);
    renderer.readRenderTargetPixels(rt, 0, 0, 1, 1, buf);
    return buf[0];
}
