# Tasks: Noise Texture Lookup

## Status legend
- `[ ]` todo
- `[~]` in progress
- `[x]` done
- `[-]` skipped / won't do

---

## Tasks

- [ ] Crear `src/noiseTexture.js`: generar `DataTexture3D` (128³, R8) con `sNoise` sampleado en CPU
- [ ] Agregar `uNoiseTex` en `uniforms.js`
- [ ] Reemplazar `sNoise(p)` en `fragment.glsl` por `texture(uNoiseTex, fract(p / NOISE_PERIOD)).r`
- [ ] Reemplazar `sNoise(p)` en `terrain_funcs.glsl` ídem
- [ ] Ajustar rango: `sNoise` devuelve [0,1], verificar que el mapeo a [-0.5, 0.5] sea correcto en `erosionFBM`
- [ ] Verificar agua animada: sin discontinuidades en bordes de tile con `p * 2.2 + iTime * offset`
- [ ] Medir FPS antes/después con DevTools Performance

## Notes

_Nada aún._
