vec3 Hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return -1.0 + 2.0 * fract((p.xxy + p.yxx) * p.zyx);
}

float sNoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float n000 = dot(Hash3(i + vec3(0, 0, 0)), f - vec3(0, 0, 0));
    float n100 = dot(Hash3(i + vec3(1, 0, 0)), f - vec3(1, 0, 0));
    float n010 = dot(Hash3(i + vec3(0, 1, 0)), f - vec3(0, 1, 0));
    float n110 = dot(Hash3(i + vec3(1, 1, 0)), f - vec3(1, 1, 0));
    float n001 = dot(Hash3(i + vec3(0, 0, 1)), f - vec3(0, 0, 1));
    float n101 = dot(Hash3(i + vec3(1, 0, 1)), f - vec3(1, 0, 1));
    float n011 = dot(Hash3(i + vec3(0, 1, 1)), f - vec3(0, 1, 1));
    float n111 = dot(Hash3(i + vec3(1, 1, 1)), f - vec3(1, 1, 1));
    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z) * 0.5 + 0.5;
}

float Noise(vec3 p, float octaves) {
    float normalize_factor = 0.0;
    float value = 0.0;
    float scale = 0.5;
    mat3 m3 = mat3( 0.00,  0.80,  0.60, -0.80,  0.36, -0.48, -0.60, -0.48,  0.64 );
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        if (fi >= octaves) break;
        float weight = scale * min(1.0, octaves - fi);
        value += sNoise(p) * weight;
        normalize_factor += weight;
        p = m3 * p * 2.0;
        scale *= 0.5;
    }
    return value / max(0.0001, normalize_factor);
}

vec2 Hash2(vec2 p) {
    p = fract(p * vec2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return -1.0 + 2.0 * fract((p.xx + p.yx) * p.xy);
}

// 2D Perlin noise with analytical gradient: returns vec3(value, dvalue/dx, dvalue/dy)
vec3 sNoise2D_d(vec2 p) {
    vec2 i  = floor(p);
    vec2 f  = fract(p);
    vec2 u  = f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 du = f*f*(f*(f*30.0-60.0)+30.0);
    vec2 g00 = Hash2(i);
    vec2 g10 = Hash2(i + vec2(1,0));
    vec2 g01 = Hash2(i + vec2(0,1));
    vec2 g11 = Hash2(i + vec2(1,1));
    float v00 = dot(g00, f);
    float v10 = dot(g10, f - vec2(1,0));
    float v01 = dot(g01, f - vec2(0,1));
    float v11 = dot(g11, f - vec2(1,1));
    float val = v00 + u.x*(v10-v00) + u.y*(v01-v00) + u.x*u.y*(v00-v10-v01+v11);
    vec2 gInt = g00 + u.x*(g10-g00) + u.y*(g01-g00) + u.x*u.y*(g00-g10-g01+g11);
    float dx  = v10-v00 + u.y*(v00-v10-v01+v11);
    float dy  = v01-v00 + u.x*(v00-v10-v01+v11);
    return vec3(val, gInt + du * vec2(dx, dy));
}

// Erosion FBM (IQ technique): gradient accumulation suppresses octaves on steep slopes
float erosionFBM(vec2 p, float octaves) {
    float h = 0.0;
    vec2  d = vec2(0.0);
    float a = 0.5;
    mat2  rot = mat2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        if (fi >= octaves) break;
        float w = a * min(1.0, octaves - fi);
        vec3 n = sNoise2D_d(p);
        d += n.yz;
        h += w * n.x / (1.0 + dot(d, d));
        a *= 0.5;
        p = rot * p;
    }
    return h;
}
