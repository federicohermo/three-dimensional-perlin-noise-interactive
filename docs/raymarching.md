# Raymarching

## Algorithm — `RayMarch()` (`fragment.glsl`)

Classic sphere tracing loop:

```glsl
#define MAX_STEPS 100
#define MAX_DIST  50.
#define SURFACE_DIST .001

float RayMarch(vec3 ro, vec3 rd, float organicDetail, vec2 fragCoord) {
    float dO = 0.001 * Hash(vec3(fragCoord, iTime));  // stochastic seed
    for (int i = 0; i < MAX_STEPS; i++) {
        float ds = GetDist(ro + dO * rd, organicDetail);
        float threshold = SURFACE_DIST + dO * (dO < 10.0 ? 0.0005 : 0.001);
        if (ds < threshold || dO > MAX_DIST) break;
        dO += ds;
    }
    return (dO > MAX_DIST) ? -1. : dO;
}
```

**Stochastic seed** — the initial offset `0.001 * Hash(fragCoord, iTime)` randomizes the first step per pixel per frame. Combined with temporal accumulation this eliminates banding on SDF features that are nearly co-planar with rays.

**Adaptive threshold** — the hit threshold grows with distance (`dO * 0.0005` near, `dO * 0.001` far). This prevents spending extra steps on sub-pixel detail in the distance without introducing visible acne up close.

**Miss signal** — returns `-1.0` so the caller can branch on sky vs. geometry.

## Camera

The camera is an orbit-style look-at setup computed in the shader from mouse position:

```glsl
vec3 ta = iCameraPos;           // look-at target (eye level)
float yaw   = -m.x * 12.5662 - 1.5707;
float pitch = (m.y - 0.5) * 4.0;
vec3 ro = ta + vec3(
    camDist * cos(yaw) * cos(pitch),
    camDist * sin(pitch),
    camDist * sin(yaw) * cos(pitch)
);
vec3 cw = normalize(ta - ro);
vec3 cu = normalize(cross(vec3(0,1,0), cw));
vec3 cv = normalize(cross(cw, cu));
vec3 rd  = normalize(uv.x * cu + uv.y * cv + 0.5 * cw);
```

`uCamDist` is updated each frame in JS with camera-sphere collision avoidance (pulls the camera back if the orbit position clips into a domain sphere).

The unjittered ray `rd0` is kept separate and used only for sky pixels to prevent stars from shimmering with sub-pixel offsets.

## Normal estimation

Tetrahedral 4-sample finite differences, epsilon scaled with ray distance to match pixel footprint:

```glsl
vec3 GetNormal(vec3 p, float organicDetail, float rayDist) {
    float h = max(0.005, 0.0015 * rayDist);
    vec2 k = vec2(1, -1);
    return normalize(
        k.xyy * GetDist(p + k.xyy*h, ...) +
        k.yxy * GetDist(p + k.yxy*h, ...) +
        k.yyx * GetDist(p + k.yyx*h, ...) +
        k.xxx * GetDist(p + k.xxx*h, ...)
    );
}
```

## Organic detail parameter

`organicDetail` is a per-pixel scalar derived from a low-frequency noise on the ray origin XZ position:

```glsl
float oD = sin(ro.x*0.13 + ro.z*0.21)*0.5 + sin(ro.z*0.17 - ro.x*0.11)*0.5;
float organicDetail = clamp(oD + 0.5, 0.0, 1.0);
```

It modulates the FBM octave count (see [noise.md](noise.md)) so that different patches of ground use slightly different detail levels, breaking the uniformity of the procedural surface.
