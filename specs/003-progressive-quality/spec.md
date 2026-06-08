# Spec: Progressive Quality Ramp

## Goal

Al arrancar, el shader renderiza con calidad reducida (pocos pasos, pocas octavas, shadow simplificado) y la va subiendo suavemente hasta calidad completa en ~2 segundos. El usuario ve el escenario casi de inmediato en vez de esperar la compilación del shader. Complementa `compileAsync`: la compilación ya no congela el browser, y ahora tampoco hay que esperar a que el primer frame "pesado" termine.

## Scope

**Incluido:**
- Uniform `uQuality` (0.0 → 1.0) que controla en el fragment shader:
  - Octavas del `erosionFBM` (1 → 4)
  - `MAX_STEPS` efectivo (40 → 100)
  - Pasos de shadow (`CastShadow`: 8 → 32)
  - Muestras de AO (0 → 3)
- Ramp en JS: interpolación lineal durante los primeros N segundos post-enter.
- El ramp sólo corre después de que el usuario presionó ENTER (durante la pantalla de loading el shader no corre).

**Fuera de scope:**
- Cambios de resolución de render (ya existe `cycleRenderScale`).
- Checkerboard rendering.
- Noise texture (spec separado).

## Acceptance criteria

- [ ] El primer frame después de ENTER renderiza en < 16 ms (60 fps) con calidad baja.
- [ ] La transición de calidad baja a alta es imperceptible al ojo (no hay salto brusco de calidad).
- [ ] Con `uQuality = 1.0` el resultado visual es idéntico al shader actual.
- [ ] No hay regresión en el modo de temporal accumulation.

## Constraints

- El uniform debe ser un `float` para evitar recompilación del shader (no `#define`).
- La interpolación de octavas en GLSL debe hacerse con `floor()` o `ceil()` desde el float — no con branches por octava (el GPU predice mal branches no uniformes).
- Tiempo del ramp: configurable en JS, default 2.0 s.

## Open questions

- ¿El ramp debe pausarse si el usuario está en movimiento (temporal blend alto) y continuar cuando para? O simplemente siempre avanzar con el tiempo.
