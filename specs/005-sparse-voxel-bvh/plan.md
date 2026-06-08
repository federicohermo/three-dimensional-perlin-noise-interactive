# Plan: Sparse Voxel Grid (BVH para SDF)

## Approach

_Por definir_

## Alternatives considered

| Option | Pro | Con | Decision |
|---|---|---|---|
| | | | |

## Files to change

| File | Change |
|---|---|
| `src/glsl/fragment.glsl` | Leer grid voxel como lower-bound antes de `GetDist` |
| `src/uniforms.js` | Agregar `uVoxelGrid` (DataTexture3D) |
| `src/voxelGrid.js` (nuevo) | Generar grid en CPU sampleando SDF de terreno |

## Risks / gotchas

_Por definir — el riesgo principal es sobreestimar la distancia y producir artefactos superficiales._
