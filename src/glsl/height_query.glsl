precision highp float;
uniform vec2 uXZ;

#include './terrain_funcs.glsl';

float terrainSDF(vec3 p) {
    float base = p.y - 8.0;
    if (base >= 12.0) return base - 1.1;
    float biomeN  = sNoise(vec3(p.x * 0.018, 0.5, p.z * 0.018));
    float volcanic = smoothstep(0.60, 0.75, biomeN);
    float flatland = smoothstep(0.35, 0.20, biomeN);
    float noiseAmp = mix(mix(1.0, 0.35, flatland), 1.65, volcanic);
    float terrainH = base + noiseAmp * (8.1*Noise(p*0.125, 3.0) - 1.1*Noise(p*0.25, 3.0) + 0.15*Noise(p, 3.0)) + 0.1;
    float waterH   = p.y - 3.5;  // water plane — character stands on water surface in deep valleys
    return min(terrainH, waterH);
}

void main() {
    float lo = -5.0, hi = 25.0;
    for (int i = 0; i < 16; i++) {
        float mid = (lo + hi) * 0.5;
        if (terrainSDF(vec3(uXZ.x, mid, uXZ.y)) < 0.0) lo = mid; else hi = mid;
    }
    gl_FragColor = vec4((lo + hi) * 0.5, 0.0, 0.0, 1.0);
}
