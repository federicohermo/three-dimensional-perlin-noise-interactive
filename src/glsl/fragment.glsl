precision highp float;

uniform float iTime;
uniform vec3 iResolution;
uniform vec4 iMouse;
uniform vec2 iJitter;
uniform vec3 iCameraPos;
uniform vec3 uAttachedOffsets[10];
uniform float uAttachedActive[10];
uniform vec2 uIgnoredCells[10];
uniform int uAttachedCount;
uniform vec2 uWindowSize;

// ============================================================================
// 3D Perlin Noise Raymarcher — Fragment Shader
// ============================================================================

#define MAX_STEPS 100
#define MAX_DIST 50.
#define SURFACE_DIST .001

// ---- Hashing ----
float Hash(vec3 p) {
    vec3 a  = fract(p.xyz * vec3(1741.124, 7537.13, 4157.47));
    a += dot(a, a + 71.13);
    return fract((a.x + a.y) * a.z);
}

vec3 Hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return -1.0 + 2.0 * fract((p.xxy + p.yxx) * p.zyx);
}

float HashV(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

vec4 vNoised(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u  = f * f * (3.0 - 2.0 * f);
    vec3 du = 6.0 * f * (1.0 - f);

    float n000 = HashV(i + vec3(0,0,0)); float n100 = HashV(i + vec3(1,0,0));
    float n010 = HashV(i + vec3(0,1,0)); float n110 = HashV(i + vec3(1,1,0));
    float n001 = HashV(i + vec3(0,0,1)); float n101 = HashV(i + vec3(1,0,1));
    float n011 = HashV(i + vec3(0,1,1)); float n111 = HashV(i + vec3(1,1,1));

    float b = n100-n000, c = n010-n000, d = n001-n000;
    float e = n110-n010-n100+n000, g = n101-n001-n100+n000;
    float h = n011-n001-n010+n000;
    float k = n111-n011-n101-n110+n100+n010+n001-n000;

    float n = n000 + b*u.x + c*u.y + d*u.z
            + e*u.x*u.y + g*u.x*u.z + h*u.y*u.z + k*u.x*u.y*u.z;

    vec3 deriv = du * vec3(
        b + e*u.y + g*u.z + k*u.y*u.z,
        c + e*u.x + h*u.z + k*u.x*u.z,
        d + g*u.x + h*u.y + k*u.x*u.y
    );
    return vec4(n, deriv);
}

vec3 GetJitter(vec3 p) {
    p = fract(p * vec3(.1031, .1030, .0973));
    p += dot(p, p.yxz + 33.33);
    vec3 h = fract((p.xxy + p.yxx) * p.zyx);
    return normalize(-1.0 + 2.0 * h) * 4.5;
}

// ---- 3D Perlin Gradient Noise ----
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

vec4 NoiseD(vec3 p, float octaves) {
    mat3 m3  = mat3( 0.00,  0.80,  0.60, -0.80,  0.36, -0.48, -0.60, -0.48,  0.64);
    mat3 m3T = mat3( 0.00, -0.80, -0.60,  0.80,  0.36, -0.48,  0.60, -0.48,  0.64);
    float value = 0.0, nf = 0.0, scale = 0.5, freq = 1.0;
    vec3 dsum = vec3(0.0), totalDeriv = vec3(0.0);
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        if (fi >= octaves) break;
        float weight = scale * min(1.0, octaves - fi);
        vec4 nd = vNoised(p);
        vec3 dWorld = (m3T * nd.yzw) / freq;
        float erosion = 1.0 / (1.0 + dot(dsum, dsum));
        float w = weight * erosion;
        value += nd.x * w;
        nf += w;
        dsum += weight * dWorld;
        totalDeriv += w * dWorld;
        p = m3 * p * 2.0;
        scale *= 0.5; freq *= 2.0;
    }
    float inv = 1.0 / max(0.0001, nf);
    return vec4(value * inv, totalDeriv * inv);
}

// ---- Smooth Minimum ----
float smin( float a, float b, float k ) {
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

// Exponential smooth minimum — gradient is always a convex blend of input
// gradients (no extra derivative terms), giving correct normals even on
// Lipschitz-scaled SDFs. Phantom depth at a==b==0 is 1/k in SDF units.
float sminE( float a, float b, float k ) {
    float ea = exp2(-k * a);
    float eb = exp2(-k * b);
    return -log2(ea + eb) / k;
}

// ---- Scene SDF ----
vec2 GetDistID(vec3 p, float organicDetail) {
    float camDist = length(p - iCameraPos);
    float oct = 1.0;
    oct += 2.0 * (1.0 - smoothstep(15.0, 40.0, camDist));
    oct += (1.0 - smoothstep(5.0, 15.0, camDist)) * organicDetail;

    // Sphere FOLLOWS iCameraPos
    float baseSphereDist = length(p - iCameraPos) - 0.8;
    float sphereDist = (baseSphereDist < 2.5) ? baseSphereDist + 1.1*Noise(p - iCameraPos, oct) - 1.1 : baseSphereDist - 1.1;
    sphereDist *= 0.45;

    // Infinite Spheres
    float repSphereDist = 1e10;
    vec2 cell = floor((p.xz + 7.5) / 15.0);
    for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            vec2 curCell = cell + vec2(float(i), float(j));
            bool ignored = false;
            for(int k=0; k<10; k++) {
                if(k >= uAttachedCount) break;
                if(length(curCell - uIgnoredCells[k]) < 0.1) { ignored = true; break; }
            }
            if(!ignored) {
                vec3 jitter = GetJitter(vec3(curCell, 0.0));
                vec3 spherePos = vec3(curCell.x * 15.0 + jitter.x, 7.5 + jitter.y * 0.5, curCell.y * 15.0 + jitter.z);
                repSphereDist = min(repSphereDist, length(p - spherePos) - 0.6);
            }
        }
    }
    float basePlaneDist = p.y - 8.0;
    float planeDist = (basePlaneDist < 12.0) ? basePlaneDist + 8.1*Noise(p*.125, oct) - 1.1*Noise(p*.25, oct) + 0.15*Noise(p, oct) + 0.1 : basePlaneDist - 1.1;
    planeDist *= 0.4;

    // Smooth blend: repeat spheres merge into terrain
    float repBlend = smin(repSphereDist, planeDist, 1.0);

    // Attached spheres also blend smoothly with rep+terrain
    for(int i = 0; i < 10; i++) {
        if(i >= uAttachedCount) break;
        float dAttached = length((p - iCameraPos) - uAttachedOffsets[i]) - 0.6;
        repBlend = smin(repBlend, dAttached, 1.0);
    }

    // Character sphere: smooth blend with rep spheres
    float d = smin(sphereDist, repBlend, 0.4);
    return vec2(d, step(sphereDist, repBlend));  // id: 0=terrain/rep, 1=char sphere
}

float GetDist(vec3 p, float organicDetail) {
    return GetDistID(p, organicDetail).x;
}

// ---- Raymarcher ----
float RayMarch (vec3 ro, vec3 rd, float organicDetail, vec2 fragCoord) {
    float dO = 0.001 * Hash(vec3(fragCoord, iTime));
    for(int i=0; i <MAX_STEPS; i++) {
        float ds = GetDist(ro + dO * rd, organicDetail);
        float threshold = SURFACE_DIST + dO * (dO < 10.0 ? 0.0005 : 0.001);
        if(ds < threshold || dO > MAX_DIST) break;
        dO += ds;
    }
    return (dO > MAX_DIST) ? -1. : dO;
}

// ---- Normal ----
vec3 GetNormal(vec3 p, float organicDetail, float rayDist) {
    float h = max(0.005, 0.0015 * rayDist);
    vec2 k = vec2(1, -1);
    return normalize(k.xyy*GetDist(p + k.xyy*h, organicDetail) + k.yxy*GetDist(p + k.yxy*h, organicDetail) + k.yyx*GetDist(p + k.yyx*h, organicDetail) + k.xxx*GetDist(p + k.xxx*h, organicDetail));
}

// ---- Aesthetics ----
vec3 GetSky(vec3 rd) {
    float sun = max(0.0, dot(rd, normalize(vec3(-5.0, 5.0, -1.0))));
    vec3 col = mix(vec3(0.3, 0.45, 0.6), vec3(0.05, 0.15, 0.3), rd.y * 0.5 + 0.5);
    float haze = exp(-10.0 * abs(rd.y));
    col = mix(col, vec3(0.8, 0.85, 0.9), haze * 0.5);
    col += vec3(1.0, 0.8, 0.4) * pow(sun, 64.0);
    col += vec3(1.0, 0.9, 0.7) * pow(sun, 8.0) * 0.2;
    return col;
}

// ---- Shadows & AO ----
float CastShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k, float distToCam) {
    float res = 1.0; float t = tmin;
    int steps = (distToCam < 12.0) ? 48 : 24;
    tmax = (distToCam < 12.0) ? tmax : min(tmax, 6.0);
    for (int i = 0; i < 48; i++) {
        if(i >= steps || t >= tmax) break;
        float h = GetDist(ro + t*rd, 4.0);
        if (h < SURFACE_DIST) {
            if (t < 0.25) { t += 0.1; continue; }  // escape LOD mismatch zone
            return 0.0;
        }
        res = min(res, k * h / t);
        if (res < 0.005) break; 
        t += clamp(h, (distToCam < 12.0 ? 0.005 : 0.01), 0.25);
    }
    return clamp(res, 0.0, 1.0);
}

float GetAO(vec3 p, vec3 n) {
    float occ = 0.0; float sca = 1.0;
    for (int i = 0; i < 3; i++) {
        float h = 0.01 + 0.15 * float(i) / 2.0;
        float d = GetDist(p + n * h, 4.0);
        occ += clamp(h - abs(d), 0.0, h) * sca;  // abs(d): phantom zone (d<0) → zero AO
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

vec3 GetLight(vec3 p, float organicDetail, vec3 rd, float rayDist) {
    vec3 lightPos = vec3(-5.0, 15.0, -1.0);
    vec3 l = normalize(lightPos - p);

    vec3 n = GetNormal(p, organicDetail, rayDist);
    float diff = clamp(dot(n, l), 0., 1.);
    float distToCam = length(p - iCameraPos);
    float shadow = CastShadow(p + n * 0.2, l, 0.02, 12.0, 8.0, distToCam);
    vec3 col = vec3(1.0, 0.9, 0.8) * diff * shadow;
    float sca = clamp(0.5 + 0.5 * n.y, 0.0, 1.0);
    col += (mix(vec3(0.2, 0.5, 1.0), vec3(0.1, 0.05, 0.02), 1.0-sca)) * 0.2;
    float ao = GetAO(p, n);
    col *= ao;
    vec3 h = normalize(l - rd);
    float spec = pow(clamp(dot(n, h), 0.0, 1.0), 32.0);
    col += vec3(0.3) * spec * shadow * ao;
    return col;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
    vec2 uv = (fragCoord + iJitter - .5*iResolution.xy)/iResolution.y;
    vec3 col = vec3(0.01);
    vec2 m = iMouse.xy / uWindowSize;
    vec3 ta = iCameraPos;
    float camDist = 4.0;
    float yaw = -m.x * 12.5662 - 1.5707;
    float pitch = (m.y - 0.5) * 4.0;
    vec3 ro = ta + vec3(camDist * cos(yaw) * cos(pitch), camDist * sin(pitch), camDist * sin(yaw) * cos(pitch));
    vec3 cw = normalize(ta - ro);
    vec3 cu = normalize(cross(vec3(0,1,0), cw));
    vec3 cv = normalize(cross(cw, cu));
    vec3 rd = normalize(uv.x * cu + uv.y * cv + 0.5 * cw);
    float oD = sin(ro.x*0.13 + ro.z*0.21)*0.5 + sin(ro.z*0.17 - ro.x*0.11)*0.5;
    float organicDetail = clamp(oD + 0.5, 0.0, 1.0);
    float d = RayMarch(ro, rd, organicDetail, fragCoord);
    if(d > 0.0) {
        vec3 p = ro + rd * d;
        col = GetLight(p, organicDetail, rd, d);
        float fog = 1.0 - exp(-0.05 * max(0.0, d - 6.0));
        col = mix(col, GetSky(rd), fog);
    } else {
        col = GetSky(rd);
    }
    col = pow(col, vec3(0.4545));
    fragColor = vec4(col, 1.0);
}

void main() {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}
