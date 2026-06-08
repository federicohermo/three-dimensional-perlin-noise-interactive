# Tasks: Sparse Voxel Grid (BVH para SDF)

## Status legend
- `[ ]` todo
- `[~]` in progress
- `[x]` done
- `[-]` skipped / won't do

---

## Tasks

- [ ] Definir bounds del grid: rango de mundo cubierto, resolución (32×16×32 inicial)
- [ ] Crear `src/voxelGrid.js`: samplear SDF de terreno en CPU, restar margen de seguridad
- [ ] Subir como `DataTexture3D` (R16F) en `uniforms.js`
- [ ] En `RayMarch` GLSL: leer voxel y usar su valor como lower-bound del paso
- [ ] Verificar que el lower-bound nunca sobreestime (tests con rayos rasantes al terreno)
- [ ] Medir reducción de pasos promedio en escena abierta vs. baseline
- [ ] Verificar ausencia de artefactos a distintas distancias de cámara

## Notes

_El voxel grid sólo aplica al SDF de terreno. Las esferas de dominio y el personaje siguen evaluándose normalmente._
