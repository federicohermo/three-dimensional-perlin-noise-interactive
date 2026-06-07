# Lighting

## Sun / day-night cycle

`uSunDir` is a normalized vec3 updated each frame in JS:

```js
const sunAngle = elapsed * 0.008;   // full cycle ≈ 785 s (~13 min)
uniforms.uSunDir.value.set(-0.5, Math.sin(sunAngle), -Math.cos(sunAngle)).normalize();
```

`uSunDir.y` (sun elevation) drives all day/night transitions: light color, intensity, sky gradient, star/moon visibility, ambient levels.

## `GetLight()` — surface shading

### Terrain / sphere surfaces

1. Diffuse: `clamp(dot(normal, sunDir), 0, 1)`
2. Soft shadow: `CastShadow(p + n*0.2, sunDir, ...)`
3. Sky ambient: interpolated between night dark (`0.03, 0.03, 0.06`) and day blue (`0.2, 0.5, 1.0`), scaled by hemisphere factor `0.5 + 0.5*n.y`
4. Moonlight fill: faint blue-white tint added at night
5. AO: 3-sample `GetAO()` (skipped for `camDist > 18` as an optimization)
6. Specular: Blinn-Phong, exponent 32

### Water / lava surfaces

Detected by `p.y < 2.95`. Uses animated wave normals computed from two `sNoise` samples with time offsets:

```glsl
wn.x += (sNoise(p * 2.2 + vec3(iTime * 0.55, 0.0, iTime * 0.32)) - 0.5) * 0.35 * (1.0 - volcanic);
```

Water depth is estimated by evaluating the terrain SDF at 1 octave (cheap) and computing how far below the water plane the floor sits. This drives a shallow→deep color blend (`#1a5248` → `#010d2b`).

Specular uses Fresnel weighting: `mix(specBase, specBase * 2.5, pow(1 - dot(wn, -rd), 3))`.

Lava (`volcanic > 0.6`) suppresses wave normals and uses warmer colors.

## `CastShadow()` — soft shadows

Classic `k * h / t` formula (Quilez):

```glsl
res = min(res, k * h / t);
t  += clamp(h, stepMin, 0.25);
```

**Important**: The Quilez 2018 `ph`-tracking formula was reverted in Session 4. The improved formula mathematically assumes a true Euclidean SDF and breaks down on the noise-displaced surfaces used here, producing pitch-black bands and self-shadowing acne. The classic formula is more forgiving with non-Lipschitz SDFs.

LOD: 32 steps within 12 world units of camera, 16 steps beyond. `tmax` is clamped to 6.0 at distance to skip rays that can't matter.

An early-exit guard `if (t < 0.25) { t += 0.1; continue; }` skips the LOD mismatch zone immediately around a surface hit.

## `GetAO()` — ambient occlusion

3 samples along the surface normal at `h = 0.01, 0.085, 0.16`:

```glsl
occ += clamp(h - abs(d), 0.0, h) * sca;
```

`abs(d)` handles the phantom zone where the SDF reports a small negative value due to noise displacement — without `abs()`, those samples would contribute negative occlusion.

## Sky — `GetSky()` / `GetSkyFog()`

Two variants share most logic:
- `GetSkyFog(rd)` — base sky color without stars/moon. Used for fog blending on surfaces.
- `GetSky(rd)` — adds stars (`step(0.997, Hash(floor(rd * 180)))`) and moon (high-exponent dot product with `-uSunDir`).

Sky layers (bottom to top):
1. Day/night base gradient (zenith → horizon)
2. Sunset/sunrise tint near horizon (only while `sunEl` near 0)
3. Haze layer near horizon
4. Sun disc + corona glow (fades when sun is underground to prevent bleed-through fog)

Sky pixels use the **unjittered** ray `rd0` so stars don't shimmer with sub-pixel jitter.

## Fog

Exponential distance fog applied after all surface shading:

```glsl
float fog = 1.0 - exp(-0.07 * max(0.0, d - 6.0));
col = mix(col, GetSkyFog(rd), fog);
```

Starts fading at 6 world units from the camera (the `max(0, d-6)` deadband).

## Gamma

Final output applies sRGB gamma correction: `col = pow(col, vec3(0.4545))`.
