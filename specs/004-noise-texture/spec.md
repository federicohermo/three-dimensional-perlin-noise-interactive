# Spec: Noise Texture Lookup

## Goal

Reemplazar el cómputo de Perlin noise en el fragment shader (hashing + interpolación trilineal) por lookups a una textura 3D pre-bakeada. El `sNoise` actual hace ~4 llamadas a `hash33` + 8 samples + mezcla trilineal por invocación; un texture fetch hace lo mismo en 1 instrucción aprovechando el hardware de interpolación del GPU. Estimación de ganancia: 30–50% menos tiempo por frame en escenas con mucho FBM.

## Scope

**Incluido:**
- Bakear `sNoise` a una `DataTexture3D` de Three.js (resolución 128³, formato `R8` o `R16F`).
- Reemplazar llamadas a `sNoise(p)` en el fragment shader por `texture(uNoiseTex, fract(p / NOISE_PERIOD)).r`.
- Mantener `erosionFBM` y `Noise` usando la textura (las octavas siguen siendo FBM sobre la textura).
- `Hash3` / `hash33` para propósitos no-noise (jitter de esferas, `GetJitter`) se mantienen — son baratos y no repetitivos.

**Fuera de scope:**
- Bake de `erosionFBM` completo (sería una textura 2D por configuración, costoso de actualizar).
- Noise 3D animado (el terreno no se mueve).
- Mipmapping de la textura de ruido (wrapping periódico hace mip artifacts en bordes).

## Acceptance criteria

- [ ] Resultado visual idéntico (o dentro de error de cuantización de 8 bits) al shader actual.
- [ ] FPS medible en DevTools GPU > 10% mejor que baseline en una escena estática.
- [ ] Sin artefactos de tiling visible en el terreno a ninguna distancia de cámara.
- [ ] La textura se genera en JS al arrancar (< 200 ms CPU, antes de `compileAsync`).

## Constraints

- Resolución mínima 64³ para evitar aliasing. 128³ = 2 MB en R8, aceptable.
- El periodo de repetición de la textura debe ser una potencia de 2 (por diseño del Perlin noise original). Usar `NOISE_PERIOD = 16.0` unidades de mundo.
- Precision: `R8` (0–1 normalizado) suficiente para el rango de `sNoise`. Si hay banding visible, subir a `R16F`.
- WebGL 2 requerido para `DataTexture3D` (Three.js requiere WebGL 2 de todas formas en r172).

## Open questions

- ¿Hay diferencia visible en el agua animada? El agua usa `sNoise(p * 2.2 + iTime * offset)` — el argumento varía con el tiempo, así que el tile se mueve dentro de la textura. Verificar que no haya discontinuidades en los bordes del tile.
