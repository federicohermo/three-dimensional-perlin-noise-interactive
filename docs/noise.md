# Noise

All noise functions live in `src/glsl/terrain_funcs.glsl`, included by both `fragment.glsl` and `height_query.glsl`.

## Hash3 — 3D gradient hash

Dave Hoskins' sineless `hash33` variant. Returns a vec3 in [-1, 1]³:

```glsl
vec3 Hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return -1.0 + 2.0 * fract((p.xxy + p.yxx) * p.zyx);
}
```

The sineless design is intentional — `sin()`-based hashes produce visible square grid artifacts on noise-displaced surfaces (fixed in Session 4). The arithmetic hash has uniform-enough distribution without the grid-alignment failure mode.

## sNoise — 3D Perlin noise

Standard gradient noise with quintic interpolation (`6t⁵ − 15t⁴ + 10t³`):

```glsl
float sNoise(vec3 p) {
    vec3 i = floor(p); vec3 f = fract(p);
    vec3 u = f*f*f*(f*(f*6.0 - 15.0) + 10.0);   // quintic — zero first and second derivative at cell edges
    // 8 corner dot products + trilinear mix
    return mix(...) * 0.5 + 0.5;  // remapped to [0, 1]
}
```

Output is in [0, 1].

## Noise — fractal Brownian motion (3D)

Multi-octave FBM with domain rotation between octaves:

```glsl
float Noise(vec3 p, float octaves) {
    mat3 m3 = mat3(0.00, 0.80, 0.60, -0.80, 0.36, -0.48, -0.60, -0.48, 0.64);
    // Up to 4 octaves; fractional last octave for smooth LOD
    for (int i = 0; i < 4; i++) {
        float weight = scale * min(1.0, octaves - fi);
        value += sNoise(p) * weight;
        p = m3 * p * 2.0;   // rotate + double frequency
        scale *= 0.5;
    }
    return value / normalize_factor;
}
```

The rotation matrix `m3` decorrelates successive octaves so the summed noise doesn't align to any axis. Fractional `octaves` blends the last octave's weight to `0.0` for smooth LOD transitions.

Used for: sphere surface displacement, attached/falling sphere displacement, torso organic texture.

## Distance-based LOD

The octave count passed to `Noise()` in `GetDistID` is:

```glsl
float oct = 1.0 + 2.0 * exp(-camDist * 0.05) + exp(-camDist * 0.12) * organicDetail;
```

| Distance | ~octaves |
|---|---|
| 0 (eye) | ~4 (with `organicDetail=1`) |
| 15 u | ~2 |
| 30 u | ~1.2 |
| 50 u | ~1 |

Saves ~15–25% Hash3 calls on shadow rays, which dominate the total sample count.

## Hash2 — 2D gradient hash

```glsl
vec2 Hash2(vec2 p) {
    p = fract(p * vec2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return -1.0 + 2.0 * fract((p.xx + p.yx) * p.xy);
}
```

Used internally by `sNoise2D_d`.

## sNoise2D_d — 2D Perlin with analytical gradient

Returns `vec3(value, dvalue/dx, dvalue/dy)`. The gradient is computed analytically during the same bilinear interpolation used for the value — no extra SDF evaluations.

Used by `erosionFBM` for gradient accumulation.

## erosionFBM — terrain FBM with erosion

IQ's gradient-accumulation technique: gradients from previous octaves suppress detail on steep slopes, simulating hydraulic erosion:

```glsl
float erosionFBM(vec2 p, float octaves) {
    vec2 d = vec2(0.0);
    mat2 rot = mat2(1.6, 1.2, -1.2, 1.6);
    for (...) {
        vec3 n = sNoise2D_d(p);
        d += n.yz * 0.4;                             // accumulate gradient
        h += w * n.x / (1.0 + dot(d, d) * 0.25);   // suppress by gradient magnitude
        p = rot * p;
    }
}
```

`0.25` and `0.4` are tuned for "mild suppression — preserve detail". Stronger values (0.5+) produce crisper ridgelines but lose mid-frequency variation.

Used for terrain height and water depth calculation.
