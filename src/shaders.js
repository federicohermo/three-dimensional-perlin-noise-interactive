export const vertexShader = `
void main() {
    gl_Position = vec4(position, 1.0);
}
`;

export const fragmentShader = `
precision highp float;

uniform float iTime;
uniform vec3 iResolution;
uniform vec4 iMouse;
uniform vec2 iJitter;
uniform vec3 iCameraPos;
uniform vec3 uAttachedOffsets[10];
uniform float uAttachedActive[10];
uniform vec2 uIgnoredCells[10];

// ============================================================================
// 3D Perlin Noise Raymarcher — Fragment Shader
// ============================================================================
//
// Shadertoy-style fragment shader that raymarches a scene composed of two
// noise-displaced signed distance fields (a sphere and a ground plane),
// lit by an orbiting point light with soft shadows.
//
// References:
//   - Ken Perlin, "Improving Noise" (2002) — quintic fade + gradient noise
//   - Inigo Quilez, "Soft shadows in raymarched SDFs"
//     https://iquilezles.org/articles/rmshadows/
//   - Inigo Quilez, "Normals for an SDF"
//     https://iquilezles.org/articles/normalsSDF/
// ============================================================================


// ---- Rotation helpers ------------------------------------------------------
// Standard 3x3 rotation matrices around each axis pair.

vec3 rotateYZ(vec3 pos, float angle)
{
    return mat3(1,                    0,                    0,
                0,  cos(radians(angle)), -sin(radians(angle)),
                0,  sin(radians(angle)),  cos(radians(angle))) * pos;
}

vec3 rotateXZ(vec3 pos, float angle)
{
    return mat3(cos(radians(angle)),  0, -sin(radians(angle)),
                                  0,  1,                    0,
                sin(radians(angle)),  0,  cos(radians(angle))) * pos;
}

vec3 rotateXY(vec3 pos, float angle)
{
    return mat3(cos(radians(angle)), -sin(radians(angle)),  0,
                sin(radians(angle)),  cos(radians(angle)),  0,
                                  0,                    0,  1) * pos;
}


// ---- Raymarching constants -------------------------------------------------

#define MAX_STEPS 100
#define MAX_DIST 50.
#define SURFACE_DIST .001

// ---- Hashing ---------------------------------------------------------------

// Hash: scalar hash for a 3D lattice point. Returns float in [0, 1).
float Hash(vec3 p)
{
    vec3 a  = fract(p.xyz * vec3(1741.124, 7537.13, 4157.47));
         a += dot(a, a + 71.13);

    return fract((a.x + a.y) * a.z);
}

// Original Hash3 for Perlin Noise (Don't change!)
vec3 Hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return normalize(-1.0 + 2.0 * fract((p.xxy + p.yxx) * p.zyx));
}

// Sineless Jitter Hash for Grid Sync
vec3 GetJitter(vec3 p) {
    p = fract(p * vec3(.1031, .1030, .0973));
    p += dot(p, p.yxz + 33.33);
    vec3 h = fract((p.xxy + p.yxx) * p.zyx);
    return normalize(-1.0 + 2.0 * h) * 4.5;
}


// ---- 3D Perlin Gradient Noise (single octave) -----------------------------
//
// Classic gradient noise (Ken Perlin, "Improving Noise", 2002).
//
// Algorithm:
//   1. Decompose p into integer cell i and fractional position f.
//   2. At each of the 8 cube corners, compute dot(gradient, displacement).
//   3. Trilinear interpolation with quintic ease curve:
//      u(t) = 6t^5 - 15t^4 + 10t^3
//      This gives C2 continuity — zero 1st and 2nd derivatives at cell
//      boundaries — so normals are smooth (no "square" artifacts).
//      (Perlin's 1985 cubic 3t^2-2t^3 is only C1.)
//   4. Remap [-1,1] → [0,1] via *0.5 + 0.5.

float sNoise(vec3 p)
{
    vec3 i = floor(p);
    vec3 f = fract(p);

    // Quintic interpolation curve for C2 continuity
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    // Gradient dot products at all 8 cube corners
    float n000 = dot(Hash3(i + vec3(0, 0, 0)), f - vec3(0, 0, 0));
    float n100 = dot(Hash3(i + vec3(1, 0, 0)), f - vec3(1, 0, 0));
    float n010 = dot(Hash3(i + vec3(0, 1, 0)), f - vec3(0, 1, 0));
    float n110 = dot(Hash3(i + vec3(1, 1, 0)), f - vec3(1, 1, 0));
    float n001 = dot(Hash3(i + vec3(0, 0, 1)), f - vec3(0, 0, 1));
    float n101 = dot(Hash3(i + vec3(1, 0, 1)), f - vec3(1, 0, 1));
    float n011 = dot(Hash3(i + vec3(0, 1, 1)), f - vec3(0, 1, 1));
    float n111 = dot(Hash3(i + vec3(1, 1, 1)), f - vec3(1, 1, 1));

    // Trilinear interpolation along X → Y → Z
    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);

    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);

    return mix(nxy0, nxy1, u.z) * 0.5 + 0.5;
}


// ---- Fractal Brownian Motion (FBM) -----------------------------------------
//
// Sums multiple octaves of Perlin noise at doubling frequency / halving amplitude.
// Domain rotation matrix m3 decorrelates octave grid axes to prevent
// axis-aligned "square" patterns. The matrix is orthogonal (preserves distances).

float Noise(vec3 p, float octaves)
{
    float normalize_factor = 0.0;
    float value = 0.0;
    float scale = 0.5;

    mat3 m3 = mat3( 0.00,  0.80,  0.60,
                   -0.80,  0.36, -0.48,
                   -0.60, -0.48,  0.64 );

    for (int i = 0; i < 4; i++)
    {
        float fi = float(i);
        if (fi >= octaves) break;

        float weight = scale * min(1.0, octaves - fi);

        value            += sNoise(p) * weight;
        normalize_factor += weight;

        p     = m3 * p * 2.0;
        scale *= 0.5;
    }

    return value / max(0.0001, normalize_factor);
}


// ---- SDF primitives --------------------------------------------------------

float sdBox(vec3 p, vec3 r, float e)
{
    vec3 d = abs(p) - r;
    return length(max(d, 0.)) + min(max(d.x, max(d.y, d.z)), 0.) - e ;
}


// ---- Smooth Minimum ----
float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

// ---- Scene SDF -------------------------------------------------------------
float GetDist(vec3 p, float organicDetail) {
    float camDist = length(p - iCameraPos);
    float oct = 1.0;
    oct += 2.0 * (1.0 - smoothstep(15.0, 40.0, camDist));

    // Organic detail modulation using pre-calculated value
    float nearMask = (1.0 - smoothstep(5.0, 15.0, camDist));
    oct += nearMask * organicDetail;

    // Sphere FOLLOWS iCameraPos (Third-person character feel)
    vec4 sphere = vec4(iCameraPos, 0.8);
    float baseSphereDist = length(p - sphere.xyz) - sphere.w;

    // Noise is sampled in LOCAL SPACE (p - iCameraPos) to prevent displacement swimming
    float sphereDist = (baseSphereDist < 2.5) ? baseSphereDist + 1.1*Noise(p - iCameraPos, oct) - 1.1 : baseSphereDist - 1.1;
    sphereDist *= 0.45;

    // Infinite Spheres (Domain Repetition with Neighbor Search for SDF Continuity)
    float repSphereDist = 1e10;
    vec2 cell = floor((p.xz + 7.5) / 15.0);

    for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            vec2 curCell = cell + vec2(float(i), float(j));
            // Sphere center in world space: cell center + jitter
            vec3 jitter = GetJitter(vec3(curCell, 0.0));
            vec3 spherePos = vec3(curCell.x * 15.0 + jitter.x, 7.5 + jitter.y * 0.5, curCell.y * 15.0 + jitter.z);

            // Check if this cell is ignored (attached)
            bool ignored = false;
            for(int k=0; k<10; k++) {
                if(length(curCell - uIgnoredCells[k]) < 0.1 && uAttachedActive[k] > 0.5) {
                    ignored = true; break;
                }
            }
            if(!ignored) {
                repSphereDist = min(repSphereDist, length(p - spherePos) - 0.6);
            }
        }
    }

    // Smoothly combine character sphere with repeated spheres
    float spheres = smin(sphereDist, repSphereDist, 0.4);

    // Add attached spheres
    for(int i = 0; i < 10; i++) {
        if(uAttachedActive[i] > 0.5) {
            // Attached spheres are relative to camera, but we sample them in world space
            // p - iCameraPos is local coordinate. uAttachedOffsets is also local.
            float dAttached = length((p - iCameraPos) - uAttachedOffsets[i]) - 0.6;
            spheres = smin(spheres, dAttached, 0.4);
        }
    }

    float basePlaneDist = p.y - 6.0;
    // Plane noise remains in world space for a "traveling" effect
    float planeDist = (basePlaneDist < 12.0) ? basePlaneDist + 8.1*Noise(p*.125, oct) - 1.1*Noise(p*.25, oct) + 0.1 : basePlaneDist - 1.1;
    planeDist *= 0.4;

    return min(spheres, planeDist);
}

// ---- Raymarcher ----
float RayMarch (vec3 ro, vec3 rd, float organicDetail, vec2 fragCoord) {
    // Initial dither to break up banding
    float dO = 0.001 * Hash(vec3(fragCoord, iTime));

    for(int i=0; i <MAX_STEPS; i++) {
        float ds = GetDist(ro + dO * rd, organicDetail);
        // LOD: Relax threshold slightly with distance for faster convergence
        float threshold = SURFACE_DIST + dO * (dO < 10.0 ? 0.0005 : 0.001);
        if(ds < threshold || dO > MAX_DIST) break;
        dO += ds;
    }
    return (dO > MAX_DIST) ? -1. : dO;
}

// ---- Normal calculation ----
vec3 GetNormal(vec3 p, float organicDetail) {
    float h = 0.007; // Reverted for smoothness
    vec2 k = vec2(1, -1);
    return normalize(k.xyy*GetDist(p + k.xyy*h, organicDetail) + k.yxy*GetDist(p + k.yxy*h, organicDetail) + k.yyx*GetDist(p + k.yyx*h, organicDetail) + k.xxx*GetDist(p + k.xxx*h, organicDetail));
}

// ---- Aesthetics -----------------------------------------------------------
vec3 GetSky(vec3 rd) {
    float sun = max(0.0, dot(rd, normalize(vec3(-5.0, 5.0, -1.0))));
    vec3 col = mix(vec3(0.3, 0.45, 0.6), vec3(0.05, 0.15, 0.3), rd.y * 0.5 + 0.5); // Sky gradient

    // Horizon haze: whiten near rd.y = 0
    float haze = exp(-10.0 * abs(rd.y));
    col = mix(col, vec3(0.8, 0.85, 0.9), haze * 0.5);

    col += vec3(1.0, 0.8, 0.4) * pow(sun, 64.0); // Sun disk
    col += vec3(1.0, 0.9, 0.7) * pow(sun, 8.0) * 0.2; // Sun glow
    return col;
}

// ---- Soft shadows ----
float CastShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k, float organicDetail, float distToCam) {
    float res = 1.0; float t = tmin;
    // LOD: Fewer steps and shorter range for distant points
    int steps = (distToCam < 12.0) ? 48 : 24;
    tmax = (distToCam < 12.0) ? tmax : min(tmax, 6.0);

    for (int i = 0; i < 48; i++) { // Uniform loop for compiler; use 'steps' break
        if(i >= steps || t >= tmax) break;
        float h = GetDist(ro + t*rd, organicDetail);
        if (h < SURFACE_DIST) return 0.0;
        res = min(res, k * h / t);
        if (res < 0.005) break; // Aggressive early exit for performance
        // Relax min step for distant points
        t += clamp(h, (distToCam < 12.0 ? 0.005 : 0.01), 0.25);
    }
    return clamp(res, 0.0, 1.0);
}

float GetAO(vec3 p, vec3 n, float organicDetail) {
    float occ = 0.0;
    float sca = 1.0;
    for (int i = 0; i < 5; i++) {
        float h = 0.01 + 0.12 * float(i) / 4.0;
        float d = GetDist(p + n * h, organicDetail);
        occ += (h - d) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

// ---- Lighting ----
vec3 GetLight(vec3 p, float organicDetail, vec3 rd) {
    vec3 lightPos = vec3(-5.0, 15.0, -1.0);
    vec3 l = normalize(lightPos - p);
    vec3 n = GetNormal(p, organicDetail);

    // Direct lighting (diffuse + soft shadow)
    float diff = clamp(dot(n, l), 0., 1.);
    float distToCam = length(p - iCameraPos);
    float shadow = CastShadow(p + n * 0.1, l, 0.02, 12.0, 8.0, organicDetail, distToCam);
    vec3 col = vec3(1.0, 0.9, 0.8) * diff * shadow;

    // Cheap GI Approximation (Hemisphere Lighting)
    float sca = clamp(0.5 + 0.5 * n.y, 0.0, 1.0);
    vec3 skyCol = vec3(0.2, 0.5, 1.0) * sca; // Sky bounce
    vec3 gndCol = vec3(0.1, 0.05, 0.02) * (1.0 - sca); // Ground bounce
    col += (skyCol + gndCol) * 0.2;

    // Ambient Occlusion
    float ao = GetAO(p, n, organicDetail);
    col *= ao;

    // Specular (Roughness approximation)
    vec3 h = normalize(l - rd);
    float spec = pow(clamp(dot(n, h), 0.0, 1.0), 32.0);
    col += vec3(0.3) * spec * shadow * ao;

    return col;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = (fragCoord + iJitter - .5*iResolution.xy)/iResolution.y;
    vec3 col = vec3(0.01);

    vec2 m = iMouse.xy / iResolution.xy;
    vec3 ta = iCameraPos;             // Target: dynamic center from WASD
    float camDist = 4.0;              // Orbit radius

    // Convert mouse to spherical coordinates (yaw/pitch)
    float yaw = -m.x * 12.5662 - 1.5707;    // -PI/2 offset so default looks +Z
    float pitch = (m.y - 0.5) * 4.0;       // Elevation bounds to prevent flipping

    // Cartesian camera origin relative to dynamic target
    vec3 ro = ta + vec3(
        camDist * cos(yaw) * cos(pitch),
        camDist * sin(pitch),
        camDist * sin(yaw) * cos(pitch)
    );
    vec3 cw = normalize(ta - ro);
    vec3 cp = vec3(0.0, 1.0, 0.0);
    vec3 cu = normalize(cross(cp, cw));
    vec3 cv = normalize(cross(cw, cu));
    vec3 rd = normalize(uv.x * cu + uv.y * cv + 0.5 * cw);

    // Optimized & Simplified: Fast sine-based organic detail pre-calculation
    float oD = sin(ro.x*0.13 + ro.z*0.21)*0.5 + sin(ro.z*0.17 - ro.x*0.11)*0.5;
    float organicDetail = clamp(oD + 0.5, 0.0, 1.0);

    float d = RayMarch(ro, rd, organicDetail, fragCoord);
    if(d > 0.0) {
        vec3 p = ro + rd * d;
        col = GetLight(p, organicDetail, rd);

        // Aerial Perspective (Fog) - Distance masked to keep character clear
        float fog = 1.0 - exp(-0.05 * max(0.0, d - 6.0));
        col = mix(col, GetSky(rd), fog);
    } else {
        col = GetSky(rd);
    }

    // Grading
    col = pow(col, vec3(0.4545)); // Gamma correction
    fragColor = vec4(col, 1.0);
}

void main() {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}
`;

export const blitFragmentShader = `
precision highp float;
uniform sampler2D tCurrent;
uniform sampler2D tHistory;
uniform float uBlend;
uniform vec3 iResolution;
void main() {
    vec2 uv = gl_FragCoord.xy / iResolution.xy;
    vec4 curr = texture2D(tCurrent, uv);
    vec4 hist = texture2D(tHistory, uv);
    gl_FragColor = mix(hist, curr, uBlend);
}
`;
