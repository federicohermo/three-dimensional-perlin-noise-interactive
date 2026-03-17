// ============================================================================
// Shadertoy [Common] Tab — Shared Math & SDF
// ============================================================================

// ---- Constants ----
#define MAX_STEPS 80
#define MAX_DIST 50.
#define SURFACE_DIST .001

// ---- Hashing ----
vec3 Hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return normalize(-1.0 + 2.0 * fract((p.xxy + p.yxx) * p.zyx));
}

// ---- 3D Perlin Gradient Noise ----
float sNoise(vec3 p) {
    vec3 i = floor(p); vec3 f = fract(p);
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float n000 = dot(Hash3(i + vec3(0, 0, 0)), f - vec3(0, 0, 0));
    float n100 = dot(Hash3(i + vec3(1, 0, 0)), f - vec3(1, 0, 0));
    float n010 = dot(Hash3(i + vec3(0, 1, 0)), f - vec3(0, 1, 0));
    float n110 = dot(Hash3(i + vec3(1, 1, 0)), f - vec3(1, 1, 0));
    float n001 = dot(Hash3(i + vec3(0, 0, 1)), f - vec3(0, 0, 1));
    float n101 = dot(Hash3(i + vec3(1, 0, 1)), f - vec3(1, 0, 1));
    float n011 = dot(Hash3(i + vec3(0, 1, 1)), f - vec3(0, 1, 1));
    float n111 = dot(Hash3(i + vec3(1, 1, 1)), f - vec3(1, 1, 1));
    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y), 
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z) * 0.5 + 0.5;
}

float Noise(vec3 p, float octaves) {
    float normalize_factor = 0.0; float value = 0.0; float scale = 0.5;
    mat3 m3 = mat3( 0.00,  0.80,  0.60, -0.80,  0.36, -0.48, -0.60, -0.48,  0.64 );
    for (int i = 0; i < 4; i++) {
        float fi = float(i); if (fi >= octaves) break;
        float weight = scale * min(1.0, octaves - fi);
        value += sNoise(p) * weight; normalize_factor += weight;
        p = m3 * p * 2.0; scale *= 0.5;
    }
    return value / max(0.0001, normalize_factor);
}

// ---- Smooth Minimum ----
float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

// ---- Scene SDF ----
float GetDist(vec3 p, float organicDetail) {
    float camDist = length(p - vec3(0., 6., 4.));
    float oct = 1.0;
    oct += 2.0 * (1.0 - smoothstep(15.0, 40.0, camDist)); // Transitions to 3 octaves
    
    // Organic detail modulation using pre-calculated value
    float nearMask = (1.0 - smoothstep(5.0, 15.0, camDist));
    oct += nearMask * organicDetail; 
    
    // Character Sphere
    vec4 sphere = vec4(0, 6, 4 ,1.1);
    float baseSphereDist = length(p - sphere.xyz) - sphere.w;
    float sphereDist = (baseSphereDist < 2.5) ? baseSphereDist + 1.1*Noise(p, oct) - 1.1 : baseSphereDist - 1.1;
    sphereDist *= 0.85;

    // Infinite Spheres (Domain Repetition with Neighbor Search for SDF Continuity)
    float repSphereDist = 1e10;
    vec2 cell = floor((p.xz + 7.5) / 15.0);
    
    for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            vec2 curCell = cell + vec2(float(i), float(j));
            // Unique jitter per cell
            vec3 curJit = (Hash3(vec3(curCell, 0.0)) - 0.5) * 8.0;
            // Sphere center in world space: cell center + jitter
            // Baseline y=7.5, jittered by 0.5 (tamer elevation)
            vec3 spherePos = vec3(curCell.x * 15.0 + curJit.x, 7.5 + curJit.y * 0.5, curCell.y * 15.0 + curJit.z);
            repSphereDist = min(repSphereDist, length(p - spherePos) - 0.6);
        }
    }
    
    // Smoothly combine character sphere with repeated spheres
    float spheres = smin(sphereDist, repSphereDist, 0.4);

    float basePlaneDist = p.y - 4.0;
    float planeDist = (basePlaneDist < 12.0) ? basePlaneDist + 8.1*Noise(p*.125, oct) - 1.1*Noise(p*.25, oct) + 0.1 : basePlaneDist - 1.1;
    planeDist *= 0.43;
    
    return min(spheres, planeDist);
}

// ---- Raymarcher ----
float RayMarch (vec3 ro, vec3 rd, float organicDetail) {
    float dO = 0.;
    for(int i=0; i <MAX_STEPS; i++) {
        float ds = GetDist(ro + dO * rd, organicDetail); dO += ds;
        if(ds < SURFACE_DIST + dO * 0.002 || dO > MAX_DIST) break;
    }
    return (dO > MAX_DIST) ? -1. : dO;
}

// ---- Normals ----
vec3 GetNormal(vec3 p, float organicDetail) {
    float h = 0.005; vec2 k = vec2(1, -1);
    return normalize(k.xyy*GetDist(p + k.xyy*h, organicDetail) + k.yxy*GetDist(p + k.yxy*h, organicDetail) + k.yyx*GetDist(p + k.yyx*h, organicDetail) + k.xxx*GetDist(p + k.xxx*h, organicDetail));
}

// ---- Soft Shadows ----
float CastShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k, float organicDetail) {
    float res = 1.0; float t = tmin;
    for (int i = 0; i < 32; i++) {
        if(t >= tmax) break;
        float h = GetDist(ro + t*rd, organicDetail);
        if (h < SURFACE_DIST) return 0.0;
        res = min(res, k * h / t);
        if (res < 0.001) break;
        t += clamp(h, 0.02, 0.25);
    }
    return clamp(res, 0.0, 1.0);
}

// ---- Lighting ----
float GetLight(vec3 p, float organicDetail) {
    vec3 lightPos = vec3(-5.0, 10.0, -1.0);
    vec3 l = normalize(lightPos - p); vec3 n = GetNormal(p, organicDetail);
    float diff = clamp(dot(n, l), 0., 1.)*0.5;
    float shadow = CastShadow(p + n * 0.1, l, 0.02, 8.5, 8.0, organicDetail);
    float amb = clamp(dot(n, vec3(0., 1., 0.)), 0., 1.);
    float aer = clamp(dot(n, -l), 0., 1.);
    return diff*(shadow + amb*0.05) + aer*.007;
}
