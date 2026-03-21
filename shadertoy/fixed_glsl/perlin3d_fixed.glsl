// ============================================================================
// 3D Perlin Noise Raymarcher — Fragment Shader
// ============================================================================
//
// Shadertoy-style fragment shader that raymarches a scene composed of two
// noise-displaced signed distance fields (a sphere and a ground plane),
// lit by an orbiting point light with soft shadows.
//
// Ported to Three.js via ShaderMaterial with Shadertoy-compatible uniforms
// (iTime, iResolution, iMouse). See index.html for the host setup.
//
// References:
//   - Ken Perlin, "Improving Noise" (2002) — quintic fade + gradient noise
//   - Inigo Quilez, "Soft shadows in raymarched SDFs"
//     https://iquilezles.org/articles/rmshadows/
//   - Inigo Quilez, "Normals for an SDF"
//     https://iquilezles.org/articles/normalsSDF/
// ============================================================================


// ---- Rotation helpers ------------------------------------------------------
// Standard 3×3 rotation matrices around each axis pair.
// Used if the camera or objects need to be rotated (currently unused in main).
/*
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
*/

// ---- Raymarching constants -------------------------------------------------

#define MAX_STEPS 80           // Reduced from 100 for performance boost
#define MAX_DIST 50.           // Maximum ray travel distance (world units)
#define SURFACE_DIST .001      // Hit threshold — ray is "on" the surface


// ---- Hashing ---------------------------------------------------------------
//
// Hash functions map integer lattice coordinates to pseudo-random values.
// They replace a lookup table (as in Perlin's original implementation) with
// arithmetic operations suitable for GPU execution.

// Hash: scalar hash for a 3D lattice point.
// Returns a single float in [0, 1). Used as a general-purpose random source.
// Technique: multiply by large primes, fold with dot product, extract fraction.
float Hash(vec3 p)
{
    vec3 a  = fract(p.xyz * vec3(1741.124, 7537.13, 4157.47));
         a += dot(a, a + 71.13);

    return fract((a.x + a.y) * a.z);
}

// Hash3: 3D gradient hash for Perlin noise.
// Maps an integer lattice point to a pseudo-random gradient vector.
//
// Uses a sineless "Hash without Sine" algorithm (adapted from Dave Hoskins' hash33)
// to avoid the grid-aligned "square" artifacts that occur with sin()-based hashes
// due to linear banding at certain coordinate ranges.
//
// normalize() is intentionally omitted — gradient magnitude doesn't affect
// Perlin noise correctness and the extra sqrt + 3 divides hurt performance.
vec3 Hash3(vec3 p)
{
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return -1.0 + 2.0 * fract((p.xxy + p.yxx) * p.zyx);
}

// HashV: scalar value hash for value noise. Cheaper than Hash3.
float HashV(vec3 p)
{
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

// vNoised: value noise with analytical derivatives.
// Returns vec4(n, dn/dx, dn/dy, dn/dz) at zero extra hash cost vs scalar value noise.
// Uses cubic kernel u=f²(3-2f) whose derivative du=6f(1-f) is trivial to compute.
vec4 vNoised(vec3 p)
{
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


// ---- 3D Perlin Gradient Noise (single octave) -----------------------------
//
// Classic gradient noise as described by Ken Perlin (improved version, 2002).
//
// How it works:
//   1. The input point p is decomposed into integer part i (lattice cell) and
//      fractional part f (position within the cell), both in [0,1)^3.
//
//   2. At each of the 8 corners of the unit cube surrounding p, a pseudo-
//      random gradient vector is generated via Hash3(corner).
//
//   3. For each corner, compute the dot product of its gradient with the
//      displacement vector from that corner to p. This gives a signed scalar
//      measuring how much p "agrees" with that corner's random direction.
//      Corners whose gradient points toward p contribute positively; those
//      pointing away contribute negatively.
//
//   4. These 8 corner values are blended via trilinear interpolation using a
//      quintic ease curve: u = 6t^5 - 15t^4 + 10t^3. This curve has zero
//      first AND second derivatives at t=0 and t=1, which means:
//        - First derivative continuity (C1): no visible seams at cell borders
//        - Second derivative continuity (C2): smooth normals when the noise
//          is used as a displacement in an SDF — without C2, normals show
//          piecewise-linear "square" artifacts at cell boundaries.
//      (Perlin's original 1985 noise used a cubic 3t^2 - 2t^3 which is only
//      C1, producing noticeable normal discontinuities.)
//
//   5. The raw result is in approximately [-1, 1]; it is remapped to [0, 1]
//      via `* 0.5 + 0.5` for convenient use as displacement or color.
//
// Output: float in [0, 1]

float sNoise(vec3 p)
{
    vec3 i = floor(p);    // Integer lattice coordinates (cell origin)
    vec3 f = fract(p);    // Fractional position within the cell [0,1)^3

    // Quintic interpolation curve: u(t) = 6t^5 - 15t^4 + 10t^3
    // Ensures C2 continuity across cell boundaries.
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    // Evaluate gradient dot products at all 8 corners of the unit cube.
    // Each nXYZ = dot(gradient_at_corner, displacement_from_corner_to_p)
    float n000 = dot(Hash3(i + vec3(0, 0, 0)), f - vec3(0, 0, 0));
    float n100 = dot(Hash3(i + vec3(1, 0, 0)), f - vec3(1, 0, 0));
    float n010 = dot(Hash3(i + vec3(0, 1, 0)), f - vec3(0, 1, 0));
    float n110 = dot(Hash3(i + vec3(1, 1, 0)), f - vec3(1, 1, 0));
    float n001 = dot(Hash3(i + vec3(0, 0, 1)), f - vec3(0, 0, 1));
    float n101 = dot(Hash3(i + vec3(1, 0, 1)), f - vec3(1, 0, 1));
    float n011 = dot(Hash3(i + vec3(0, 1, 1)), f - vec3(0, 1, 1));
    float n111 = dot(Hash3(i + vec3(1, 1, 1)), f - vec3(1, 1, 1));

    // Trilinear interpolation along X, then Y, then Z.
    // Uses the quintic-smoothed u so that transitions between cells are C2.
    float nx00 = mix(n000, n100, u.x);   // interpolate along X (y=0, z=0)
    float nx10 = mix(n010, n110, u.x);   // interpolate along X (y=1, z=0)
    float nx01 = mix(n001, n101, u.x);   // interpolate along X (y=0, z=1)
    float nx11 = mix(n011, n111, u.x);   // interpolate along X (y=1, z=1)

    float nxy0 = mix(nx00, nx10, u.y);   // interpolate along Y (z=0)
    float nxy1 = mix(nx01, nx11, u.y);   // interpolate along Y (z=1)

    // Final Z interpolation, then remap [-1,1] → [0,1]
    return mix(nxy0, nxy1, u.z) * 0.5 + 0.5;
}


// ---- Fractal Brownian Motion (FBM) -----------------------------------------
//
// Combines multiple octaves of Perlin noise at increasing frequencies and
// decreasing amplitudes to produce naturalistic detail at multiple scales.
//
// Each octave doubles the frequency (p * 2.0) and halves the amplitude
// (scale * 0.5). This is the standard "1/f" fractal noise.
//
// A key optimization is the domain rotation matrix m3: before each frequency
// doubling, the sample point is rotated by a fixed rotation. This prevents
// the grid axes of successive octaves from aligning, which would otherwise
// produce visible axis-aligned "square" patterns in the summed noise.
// The matrix is orthogonal (det ≈ 1) so it preserves distances.
//
// The final value is normalized by dividing by the sum of all weights,
// keeping the output in approximately [0, 1].
//
// Parameters:
//   p       — 3D sample position
//   octaves — number of noise layers (3 is used; 4th octave's weight of
//             0.0625 is sub-pixel detail at typical view distances)

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

        // Last octave is interpolated by the fractional part of octaves
        float weight = scale * min(1.0, octaves - fi);
        
        value            += sNoise(p) * weight;
        normalize_factor += weight;

        p     = m3 * p * 2.0;
        scale *= 0.5;
    }

    return value / max(0.0001, normalize_factor);
}

// NoiseD: erosion FBM with analytical derivatives (IQ "morenoise" technique).
// Returns vec4(value, gradient_x, gradient_y, gradient_z).
// The erosion weight 1/(1+dot(dsum,dsum)) suppresses octaves in high-gradient
// areas, making peaks sharp and valleys smooth.
vec4 NoiseD(vec3 p, float octaves)
{
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


// ---- SDF primitives --------------------------------------------------------

// Signed distance to a rounded box (unused in current scene, kept for reference).
float sdBox(vec3 p, vec3 r, float e)
{
    vec3 d = abs(p) - r;
    return length(max(d, 0.)) + min(max(d.x, max(d.y, d.z)), 0.) - e ;
}


// ---- Scene SDF -------------------------------------------------------------
//
// Returns the signed distance from point p to the nearest surface in the scene.
// The scene consists of:
//   1. A noise-displaced sphere (center [0,1,4], radius 1.1)
//   2. A noise-displaced ground plane (y=0)
//
// Both use bounding-volume early-out: if the point is far from the base
// primitive, skip the expensive Noise() evaluation and return a conservative
// (safe) lower-bound distance instead. This is critical for performance since
// Noise() involves 3 octaves × 8 hash evaluations = 24 Hash3 calls per sample.
//
// The SDF values are scaled down (sphere ×0.8, plane ×0.4) because noise
// displacement breaks the Lipschitz-1 property of true
// ---- Smooth Minimum ----
float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

// ---- Scene SDF -------------------------------------------------------------
float GetDist(vec3 p, float organicDetail) {
    float camDist = length(p - vec3(0., 6., 4.));
    float oct = 1.0;
    oct += 2.0 * (1.0 - smoothstep(15.0, 40.0, camDist)); 
    
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
    
    // Smoothly combine spheres
    // Reduced k from 1.2 to 0.4 for tighter blending
    float spheres = smin(sphereDist, repSphereDist, 0.4);

    float basePlaneDist = p.y - 4.0;
    float planeDist = (basePlaneDist < 12.0) ? basePlaneDist + 8.1*Noise(p*.125, oct) - 1.1*Noise(p*.25, oct) + 0.15*Noise(p, oct) + 0.1 : basePlaneDist - 1.1;
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

// ---- Normals ----
vec3 GetNormal(vec3 p, float organicDetail) {
    float h = 0.005; vec2 k = vec2(1, -1);
    return normalize(k.xyy*GetDist(p + k.xyy*h, organicDetail) + k.yxy*GetDist(p + k.yxy*h, organicDetail) + k.yyx*GetDist(p + k.yyx*h, organicDetail) + k.xxx*GetDist(p + k.xxx*h, organicDetail));
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


// ---- Lighting --------------------------------------------------------------
//
// Computes final illumination at surface point p:
//   - Diffuse: Lambert dot(N, L), scaled by 0.5 for softer falloff
//   - Soft shadows: CastShadow() toward the orbiting light
//   - Ambient: hemispherical ambient (dot with up vector)
//   - Aerial/rim: faint backlight term dot(N, -L) for atmospheric feel
//
// The light orbits in the XZ plane at radius 2 around (-5, 5, -1).
// Shadow ray is offset 0.05 along the normal to avoid self-intersection
// artifacts ("shadow acne") on the bumpy noise-displaced surface.

float GetLight(vec3 p, float organicDetail, vec3 ro)
{
    // Fixed light position
    vec3 lightPos = vec3(-5.0, 10.0, -1.0);
    vec3 l = normalize(lightPos - p);                   // Direction to light
    vec3 n = GetNormal(p, organicDetail);                // Surface normal

    float diff = clamp(dot(n, l), 0., 1.)*0.5;    // Half-Lambert diffuse
    
    float distToCam = length(p - ro); 
    
    // Shadow ray: offset origin along normal to clear the bumpy surface
    float shadow = CastShadow(p + n * 0.1, l, 0.02, 8.5, 8.0, organicDetail, distToCam);

    float amb = clamp(dot(n, vec3(0., 1., 0.)), 0., 1.);    // Hemispherical ambient
    float aer = clamp(dot(n, -l), 0., 1.);                   // Backlight / aerial
    shadow += amb*0.05;    // Lift shadows with ambient

    return diff*shadow+aer*.007;
}


// ---- Main image (Shadertoy entry point) ------------------------------------
//
// Sets up a fixed camera at the origin looking along +Z, fires a ray per
// pixel via the raymarcher, and applies gamma correction (pow 1/2.2 ≈ 0.4545).
//
// UV convention: centered, Y-normalized (aspect-correct), matching Shadertoy.

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = (fragCoord-.5*iResolution.xy)/iResolution.y;    // Centered, aspect-correct UVs

    vec3 col = vec3(0.01);    // Background (near-black)

    // Camera setup (orbital using iMouse)
    vec2 m = iMouse.xy / iResolution.xy;

    vec3 ta = vec3(0.0, 6.0, 4.0);    // Target: center of the sphere
    float camDist = 4.0;              // Orbit radius
    
    // Relaxed Clamping logic
    // We clamp m.y to [0.2, 0.8] for a more stable vertical range.
    m.y = clamp(m.y, 0.2, 0.8);

    // Further reduced sensitivity for premium feel and less jump on click
    float yaw = -m.x * 4.0 - 1.5707;        // Reduced from 6.28 to 4.0
    float pitch = (m.y - 0.5) * 1.8;        // Reduced from 2.5 to 1.8
    
    // Cartesian camera origin
    vec3 ro = ta + vec3(
        camDist * cos(yaw) * cos(pitch),
        camDist * sin(pitch),
        camDist * sin(yaw) * cos(pitch)
    ); 

    // Camera basis vectors (LookAt matrix)
    vec3 cw = normalize(ta - ro);               // Forward
    vec3 cp = vec3(0.0, 1.0, 0.0);              // World up
    vec3 cu = normalize(cross(cp, cw));         // Right
    vec3 cv = normalize(cross(cw, cu));         // Camera up
    
    // Ray direction (0.5 acts as zoom/FOV scalar matching original)
    vec3 rd = normalize(uv.x * cu + uv.y * cv + 0.5 * cw);

    // Optimized & Simplified: Fast sine-based organic detail pre-calculation
    float oD = sin(ro.x*0.13 + ro.z*0.21)*0.5 + sin(ro.z*0.17 - ro.x*0.11)*0.5;
    float organicDetail = clamp(oD + 0.5, 0.0, 1.0);

    float d = RayMarch(ro, rd, organicDetail, fragCoord);
    if(d > 0.0)
    {
        vec3 p = ro + rd * d;      // Surface hit point
        float diff = GetLight(p, organicDetail, ro);  // Compute illumination
        col = vec3(diff);          // Grayscale output
    }

    col = pow(col, vec3(0.4545));    // Gamma correction (linear → sRGB)

    fragColor = vec4(col,1.0);
}
