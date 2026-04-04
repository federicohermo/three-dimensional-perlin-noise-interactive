precision highp float;

uniform float iTime;
uniform vec3 iResolution;
uniform vec4 iMouse;
uniform vec2 iJitter;
uniform vec3 iCameraPos;
uniform vec3 uAttachedOffsets[10];
uniform float uAttachedRadii[10];
uniform vec2 uIgnoredCells[15];
uniform int uAttachedCount;
uniform int uIgnoredCount;
uniform vec3 uFallingPositions[5];
uniform float uFallingRadii[5];
uniform int uFallingCount;
uniform vec2 uWindowSize;
uniform vec2 uCharFacing;
uniform float uAnimPhase;
uniform float uVY;
uniform float uMoving;
uniform float uCamDist;
uniform vec3  uSunDir;   // normalized, points from ground toward sun

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

#include './terrain_funcs.glsl';

vec3 GetJitter(vec3 p) {
    p = fract(p * vec3(.1031, .1030, .0973));
    p += dot(p, p.yxz + 33.33);
    vec3 h = fract((p.xxy + p.yxx) * p.zyx);
    return normalize(-1.0 + 2.0 * h) * 3.5;
}



// ---- SDF Primitives ----
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// ---- Humanoid Character SDF ----
// Origin: iCameraPos (eye level). +Y = up, fwd = uCharFacing (XZ).
float sdCharacter(vec3 p) {
    vec3 lp = p - iCameraPos;

    vec3 fwd = normalize(vec3(uCharFacing.x, 0.0, uCharFacing.y));
    vec3 rt  = vec3(-fwd.z, 0.0, fwd.x); // 90-deg CW in XZ

    // Jump blend factors (JUMP_VEL=12, max fall speed ~12)
    float airFactor  = clamp(abs(uVY) / 12.0, 0.0, 1.0);
    float upFactor   = clamp( uVY / 12.0, 0.0, 1.0);   // 0→1 while ascending
    float downFactor = clamp(-uVY / 12.0, 0.0, 1.0);   // 0→1 while falling

    // Walk cycle fades out while airborne
    float swing = sin(uAnimPhase) * 0.18 * (1.0 - airFactor);
    float legSw = sin(uAnimPhase) * 0.22 * (1.0 - airFactor);

    // Jump arm blend factors
    float raiseBlend = upFactor * (1.0 - uMoving) * airFactor;  // stationary ascent
    float backBlend  = upFactor * uMoving          * airFactor;  // moving ascent
    float jumpArmSpread = 0.08 * downFactor * (1.0 - uMoving) * airFactor; // stationary descent spread
    // Jump legs: knees tuck up on ascent, extend slightly on descent
    float jumpKneeY   = ( 0.22 * upFactor - 0.05 * downFactor) * airFactor;
    float jumpKneeFwd = ( 0.15 * upFactor - 0.05 * downFactor) * airFactor;
    float jumpAnkleY  = ( 0.15 * upFactor - 0.08 * downFactor) * airFactor;

    // HEAD — smooth sphere at eye level
    float dHead = length(lp) - 0.28;

    // NECK
    float dNeck = sdCapsule(lp, vec3(0.0, -0.28, 0.0), vec3(0.0, -0.48, 0.0), 0.11);

    // TORSO — light noise for organic texture
    float dTorso = sdCapsule(lp, vec3(0.0, -0.48, 0.0), vec3(0.0, -1.05, 0.0), 0.22);
    dTorso = (dTorso + 0.05 * (Noise(lp, 1.0) - 0.5)) * 0.92;

    // ARMS — three complete poses blended by jump state
    vec3 lSh = rt * (-0.28) + vec3(0.0, -0.52, 0.0);
    vec3 rSh = rt * ( 0.28) + vec3(0.0, -0.52, 0.0);

    // Base pose (idle/walk)
    vec3 lElBase = lSh + rt*(-0.06)              + vec3(0.0,-0.42,0.0) + fwd*( swing);
    vec3 rElBase = rSh + rt*( 0.06)              + vec3(0.0,-0.42,0.0) + fwd*(-swing);
    vec3 lWrBase = lElBase + rt*(-0.04)          + vec3(0.0,-0.38,0.0) + fwd*( swing*0.5);
    vec3 rWrBase = rElBase + rt*( 0.04)          + vec3(0.0,-0.38,0.0) + fwd*(-swing*0.5);

    // Stationary-jump ascent pose (arms raised above head)
    vec3 lElRaise = lSh + rt*(-0.12 - jumpArmSpread) + vec3(0.0,+0.22,0.0);
    vec3 rElRaise = rSh + rt*( 0.12 + jumpArmSpread) + vec3(0.0,+0.22,0.0);
    vec3 lWrRaise = lElRaise + rt*(-0.06 - jumpArmSpread*0.5) + vec3(0.0,+0.28,0.0);
    vec3 rWrRaise = rElRaise + rt*( 0.06 + jumpArmSpread*0.5) + vec3(0.0,+0.28,0.0);

    // Moving-jump ascent pose (both arms swept back)
    vec3 lElBack = lSh + rt*(-0.06) + vec3(0.0,-0.42,0.0) + fwd*(-0.22);
    vec3 rElBack = rSh + rt*( 0.06) + vec3(0.0,-0.42,0.0) + fwd*(-0.22);
    vec3 lWrBack = lElBack + rt*(-0.04) + vec3(0.0,-0.38,0.0) + fwd*(-0.11);
    vec3 rWrBack = rElBack + rt*( 0.04) + vec3(0.0,-0.38,0.0) + fwd*(-0.11);

    vec3 lEl = mix(mix(lElBase, lElRaise, raiseBlend), lElBack, backBlend);
    vec3 rEl = mix(mix(rElBase, rElRaise, raiseBlend), rElBack, backBlend);
    vec3 lWr = mix(mix(lWrBase, lWrRaise, raiseBlend), lWrBack, backBlend);
    vec3 rWr = mix(mix(rWrBase, rWrRaise, raiseBlend), rWrBack, backBlend);
    float dLA = min(sdCapsule(lp, lSh, lEl, 0.09), sdCapsule(lp, lEl, lWr, 0.075));
    float dRA = min(sdCapsule(lp, rSh, rEl, 0.09), sdCapsule(lp, rEl, rWr, 0.075));

    // LEGS — tuck on ascent, extend on descent
    vec3 lHip = rt * (-0.12) + vec3(0.0, -1.05, 0.0);
    vec3 rHip = rt * ( 0.12) + vec3(0.0, -1.05, 0.0);
    vec3 lKn  = lHip + rt * (-0.04) + vec3(0.0, -0.38 + jumpKneeY, 0.0) + fwd * (-legSw + jumpKneeFwd);
    vec3 rKn  = rHip + rt * ( 0.04) + vec3(0.0, -0.38 + jumpKneeY, 0.0) + fwd * ( legSw + jumpKneeFwd);
    vec3 lAn  = lKn  + vec3(0.0, -0.38 + jumpAnkleY, 0.0) + fwd * (-legSw * 0.4);
    vec3 rAn  = rKn  + vec3(0.0, -0.38 + jumpAnkleY, 0.0) + fwd * ( legSw * 0.4);
    float dLL = min(sdCapsule(lp, lHip, lKn, 0.11), sdCapsule(lp, lKn, lAn, 0.085));
    float dRL = min(sdCapsule(lp, rHip, rKn, 0.11), sdCapsule(lp, rKn, rAn, 0.085));

    float d = dHead;
    d = min(d, dNeck);
    d = min(d, dTorso);
    d = min(d, dLA);
    d = min(d, dRA);
    d = min(d, dLL);
    d = min(d, dRL);
    return d;
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

    // Humanoid character — skip expensive SDF when point is clearly outside character bounds
    float sphereDist = (camDist > 3.5) ? 1e10 : sdCharacter(p);

    // Infinite Spheres — find nearest candidate, then apply noise once
    float repSphereDist = 1e10;
    vec3  repBestPos    = vec3(0.0);
    float repBestR      = 0.6;
    vec2 cell = floor((p.xz + 7.5) / 15.0);
    for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            vec2 curCell = cell + vec2(float(i), float(j));
            bool ignored = false;
            for(int k=0; k<15; k++) {
                if(k >= uIgnoredCount) break;
                if(length(curCell - uIgnoredCells[k]) < 0.1) { ignored = true; break; }
            }
            if(!ignored) {
                vec3 jitter = GetJitter(vec3(curCell, 0.0));
                vec3 spherePos = vec3(curCell.x * 15.0 + jitter.x, 7.5 + jitter.y * 0.5, curCell.y * 15.0 + jitter.z);
                float r = mix(0.08, 0.8, pow(Hash(vec3(curCell, 1.0)), 2.0));
                float rawDist = length(p - spherePos) - r;
                if(rawDist < repSphereDist) {
                    repSphereDist = rawDist;
                    repBestPos    = spherePos;
                    repBestR      = r;
                }
            }
        }
    }
    // Apply noise to nearest candidate only
    if(repSphereDist < 1e9) {
        float base = repSphereDist;
        repSphereDist = (base < repBestR + 3.0)
            ? (base + 0.8*Noise(p - repBestPos, oct) - 0.8) * 0.45
            : (base - 0.8) * 0.45;
    }
    // Biome blend — slow noise in XZ defines character of each region
    float biomeN  = sNoise(vec3(p.x * 0.018, 0.5, p.z * 0.018));
    float volcanic = smoothstep(0.60, 0.75, biomeN); // spiky, dramatic
    float flatland = smoothstep(0.35, 0.20, biomeN); // open plains
    // noiseAmp: 0.35 (flat) → 1.0 (normal) → 1.65 (volcanic)
    float noiseAmp = mix(mix(1.0, 0.35, flatland), 1.65, volcanic);

    float basePlaneDist = p.y - 8.0;
    float planeDist = (basePlaneDist < 12.0)
        ? basePlaneDist + noiseAmp * (8.1*Noise(p*.125, oct) - 1.1*Noise(p*.25, oct) + 0.15*Noise(p, oct)) + 0.1
        : basePlaneDist - 1.1;
    planeDist *= 0.4;

    // 2A: Water / lava fills deep valleys
    float waterDist = (p.y - 3.5) * 0.4;
    planeDist = min(planeDist, waterDist);

    // Merge attached spheres into domain sphere pool (before terrain blend)
    for(int i = 0; i < 10; i++) {
        if(i >= uAttachedCount) break;
        vec3 attachedCenter = iCameraPos + uAttachedOffsets[i];
        float baseA = length(p - attachedCenter) - uAttachedRadii[i];
        float dAttached = (baseA + 0.8*Noise(p - attachedCenter, oct) - 0.8) * 0.45;
        repSphereDist = smin(repSphereDist, dAttached, 0.4);
    }

    // Merge falling spheres into domain sphere pool (before terrain blend)
    for(int i = 0; i < 5; i++) {
        if(i >= uFallingCount) break;
        float r = uFallingRadii[i];
        if(r < 0.05) continue;  // skip near-zero radius — prevents dimple artifact
        vec3 fallingCenter = uFallingPositions[i];
        float baseF = length(p - fallingCenter) - r;
        float dFalling = (baseF + 0.8*Noise(p - fallingCenter, oct) - 0.8) * 0.45;
        repSphereDist = smin(repSphereDist, dFalling, 0.7); // 2C: larger k → dramatic merge
    }

    // All sphere types now share the same terrain blend (k=1.0)
    float repBlend = smin(repSphereDist, planeDist, 1.0);

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
// Sky without stars/moon — used for fog blending on surfaces
vec3 GetSkyFog(vec3 rd) {
    float sunEl  = uSunDir.y;
    float sunDot = max(0.0, dot(rd, uSunDir));
    float dayT   = clamp(sunEl * 4.0 + 0.5, 0.0, 1.0);
    // horizT: only non-zero near the actual horizon crossing, zero well into night
    float horizT = exp(-8.0 * abs(sunEl)) * smoothstep(-0.15, 0.05, sunEl);

    vec3 dayCol  = mix(vec3(0.3, 0.45, 0.6), vec3(0.05, 0.15, 0.3), rd.y * 0.5 + 0.5);
    vec3 nightCol = vec3(0.005, 0.005, 0.02);
    vec3 col = mix(nightCol, dayCol, dayT);

    // Sunset tint only while sun is near/above horizon
    vec3 sunsetCol = mix(vec3(0.9, 0.4, 0.1), vec3(0.85, 0.65, 0.25), clamp(sunEl * 4.0, 0.0, 1.0));
    col = mix(col, sunsetCol, horizT * smoothstep(0.3, 0.0, abs(rd.y)));

    float haze = exp(-10.0 * abs(rd.y));
    vec3 hazeCol = mix(mix(vec3(0.8, 0.85, 0.9), vec3(0.75, 0.5, 0.2), horizT), nightCol, 1.0 - dayT);
    col = mix(col, hazeCol, haze * 0.5);

    // Sun disc and glow — fade out as sun dips below horizon so it doesn't bleed
    // through fog onto terrain surfaces when the sun is underground.
    float sunVisible = smoothstep(-0.08, 0.04, sunEl);
    col += vec3(1.0, 0.8, 0.4) * pow(sunDot, 64.0) * sunVisible;
    col += vec3(1.0, 0.9, 0.7) * pow(sunDot, 8.0) * 0.2 * sunVisible;
    return col;
}

// Full sky with stars and moon — only for rays that miss geometry
vec3 GetSky(vec3 rd) {
    vec3 col = GetSkyFog(rd);
    float sunEl = uSunDir.y;
    float nightFactor = smoothstep(0.05, -0.1, sunEl);

    float starNoise = Hash(floor(rd * 180.0 + 0.5));
    col += step(0.997, starNoise) * nightFactor * 0.9;

    float moonDot = max(0.0, dot(rd, -uSunDir));
    col += vec3(0.8, 0.85, 1.0) * pow(moonDot, 2000.0) * 1.8 * nightFactor;
    col += vec3(0.5, 0.55, 0.7) * pow(moonDot, 120.0) * 0.08 * nightFactor;

    return col;
}

// ---- Shadows & AO ----
float CastShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k, float distToCam) {
    float res = 1.0; float t = tmin;
    int steps = (distToCam < 12.0) ? 32 : 16;
    tmax = (distToCam < 12.0) ? tmax : min(tmax, 6.0);
    for (int i = 0; i < 32; i++) {
        if(i >= steps || t >= tmax) break;
        float h = GetDist(ro + t*rd, 1.5);
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
    vec3 l = uSunDir;  // directional light (normalized in JS)
    float sunEl = uSunDir.y;

    // Light color: warm white at noon, orange at sunrise/sunset
    float horizT    = exp(-4.0 * abs(sunEl));
    vec3  sunColor  = mix(vec3(1.0, 0.9, 0.8), vec3(1.0, 0.45, 0.1), horizT);
    float sunIntens = clamp(sunEl * 3.0 + 0.15, 0.0, 1.0); // smooth day/night ramp
    float distToCam2 = length(p - iCameraPos);

    // 2A: Water / lava surface — detected by height
    if (p.y < 3.65) {
        float biomeN  = sNoise(vec3(p.x * 0.018, 0.5, p.z * 0.018));
        float volcanic = smoothstep(0.60, 0.75, biomeN);

        // Animated wave normals (water only; lava is viscous → less ripple)
        vec3 wn = vec3(0.0, 1.0, 0.0);
        wn.x += (sNoise(p * 2.2 + vec3(iTime * 0.55, 0.0, iTime * 0.32)) - 0.5) * 0.35 * (1.0 - volcanic);
        wn.z += (sNoise(p * 2.2 + vec3(iTime * 0.32, 0.0, -iTime * 0.5)) - 0.5) * 0.35 * (1.0 - volcanic);
        wn = normalize(wn);

        float diff   = clamp(dot(wn, l), 0.0, 1.0);
        float shadow = CastShadow(p + vec3(0.0, 0.1, 0.0), l, 0.02, 12.0, 8.0, distToCam2);
        vec3  hv     = normalize(l - rd);
        float specBase = pow(clamp(dot(wn, hv), 0.0, 1.0), 48.0) * sunIntens;
        float fresnel  = pow(1.0 - max(0.0, dot(wn, -rd)), 3.0);
        float spec     = mix(specBase, specBase * 2.5, fresnel);

        // Lava surface pattern
        float lavaN  = max(0.0, sNoise(p * 1.4 - vec3(0.0, iTime * 0.04, 0.0)));
        float lavaGlow = smoothstep(0.25, 0.7, lavaN);

        // Terrain depth below water: evaluate terrain SDF at surface without water plane
        // Same noise as GetDistID but oct=1 (cheap), no water min() → gives actual floor distance
        float flatland = smoothstep(0.35, 0.20, biomeN);
        float noiseAmp = mix(mix(1.0, 0.35, flatland), 1.65, volcanic);
        float basePD   = p.y - 8.0;  // ≈ -4.5 at water surface (y=3.5)
        float terrainPD = (basePD + noiseAmp * (8.1*Noise(p*0.125, 1.0) - 1.1*Noise(p*0.25, 1.0)) + 0.1) * 0.4;
        float waterDepth = max(0.0, -terrainPD);  // 0=very shallow, larger=deeper floor
        float depthT  = 1.0 - exp(-waterDepth * 0.8);
        vec3  shallow = vec3(0.10, 0.32, 0.28);
        vec3  deep    = vec3(0.01, 0.05, 0.17);
        vec3  waterBase = mix(shallow, deep, depthT);

        vec3 waterCol = waterBase * (diff * shadow * sunIntens * 0.4 + 0.08)
                      + vec3(0.65, 0.85, 1.0) * spec;
        vec3 lavaCol  = vec3(0.18, 0.03, 0.0)
                      + vec3(1.0, 0.42, 0.04) * lavaGlow * 1.2
                      + vec3(0.9, 0.25, 0.0)  * spec * 0.6;

        return mix(waterCol, lavaCol, volcanic);
    }

    vec3 n = GetNormal(p, organicDetail, rayDist);
    float diff = clamp(dot(n, l), 0., 1.);
    float shadow = CastShadow(p + n * 0.2, l, 0.02, 12.0, 8.0, distToCam2);
    vec3 col = sunColor * sunIntens * diff * shadow;

    // Sky ambient: blue by day, dark by night; moonlight adds a faint blue tint
    float dayT = clamp(sunEl * 4.0 + 0.5, 0.0, 1.0);
    float nightT = clamp(-sunEl * 4.0 + 0.3, 0.0, 1.0);
    float sca = clamp(0.5 + 0.5 * n.y, 0.0, 1.0);
    vec3 skyAmb    = mix(vec3(0.03, 0.03, 0.06), vec3(0.2, 0.5, 1.0), dayT);
    vec3 groundAmb = mix(vec3(0.01, 0.01, 0.02), vec3(0.1, 0.05, 0.02), dayT);
    col += mix(groundAmb, skyAmb, sca) * 0.2;
    col += vec3(0.05, 0.06, 0.12) * nightT * sca; // moonlight fill

    float ao = (distToCam2 < 18.0) ? GetAO(p, n) : 1.0;
    col *= ao;
    vec3 h = normalize(l - rd);
    float spec = pow(clamp(dot(n, h), 0.0, 1.0), 32.0);
    col += vec3(0.3) * spec * shadow * ao * sunIntens;
    return col;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
    vec2 uv  = (fragCoord + iJitter - .5*iResolution.xy)/iResolution.y;
    vec2 uv0 = (fragCoord            - .5*iResolution.xy)/iResolution.y; // unjittered
    vec3 col = vec3(0.01);
    vec2 m = iMouse.xy / uWindowSize;
    vec3 ta = iCameraPos;
    float camDist = uCamDist;
    float yaw = -m.x * 12.5662 - 1.5707;
    float pitch = (m.y - 0.5) * 4.0;
    vec3 ro = ta + vec3(camDist * cos(yaw) * cos(pitch), camDist * sin(pitch), camDist * sin(yaw) * cos(pitch));
    vec3 cw = normalize(ta - ro);
    vec3 cu = normalize(cross(vec3(0,1,0), cw));
    vec3 cv = normalize(cross(cw, cu));
    vec3 rd  = normalize(uv.x  * cu + uv.y  * cv + 0.5 * cw);
    vec3 rd0 = normalize(uv0.x * cu + uv0.y * cv + 0.5 * cw); // unjittered ray for sky
    float oD = sin(ro.x*0.13 + ro.z*0.21)*0.5 + sin(ro.z*0.17 - ro.x*0.11)*0.5;
    float organicDetail = clamp(oD + 0.5, 0.0, 1.0);
    float d = RayMarch(ro, rd, organicDetail, fragCoord);
    if(d > 0.0) {
        vec3 p = ro + rd * d;
        bool isWater = (p.y < 3.65);

        col = GetLight(p, organicDetail, rd, d);

        // Distance fog — applies to all surfaces including water/lava (fades horizon edge)
        float fog = 1.0 - exp(-0.05 * max(0.0, d - 6.0));
        col = mix(col, GetSkyFog(rd), fog);

    } else {
        col = GetSky(rd0);  // unjittered ray → stars don't wiggle with jitter
    }
    col = pow(col, vec3(0.4545));
    // alpha=1 terrain hit, alpha=0 sky — blit shader uses this to skip history on sky pixels
    fragColor = vec4(col, d > 0.0 ? 1.0 : 0.0);
}

void main() {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}
