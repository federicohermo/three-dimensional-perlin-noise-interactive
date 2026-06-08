# Plan: Noise Texture Lookup

## Approach

_Por definir_

## Alternatives considered

| Option | Pro | Con | Decision |
|---|---|---|---|
| | | | |

## Files to change

| File | Change |
|---|---|
| `src/glsl/fragment.glsl` | Reemplazar `sNoise()` por `texture(uNoiseTex, ...)` |
| `src/glsl/terrain_funcs.glsl` | Ídem |
| `src/uniforms.js` | Agregar `uNoiseTex` |
| `src/noiseTexture.js` (nuevo) | Generar `DataTexture3D` en CPU |

## Risks / gotchas

_Por definir_
