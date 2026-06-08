# Spec: Sparse Voxel Grid (BVH para SDF)

## Goal

Agregar una estructura de aceleración tipo BVH al raymarcher: un grid voxel grueso (32×16×32) pre-sampleado del SDF de terreno. Antes de invocar el SDF completo (con `erosionFBM`), el rayo consulta el voxel correspondiente para obtener un lower-bound de distancia y saltar en espacio claramente vacío. En zonas de cielo / lejos del terreno el raymarcher pasa de 80+ pasos a 5–10.

## Scope

**Incluido:**
- Grid 3D en CPU (`Float32Array`, 32×16×32 = 16k floats, ~64 KB) con el SDF de terreno sampleado a baja resolución.
- Subir el grid como `DataTexture3D` a GPU (formato `R16F`).
- En el raymarcher GLSL: antes de `GetDist`, leer el voxel — si la distancia voxelizada es > threshold usar ese valor como lower-bound para saltar más lejos.
- Regenerar el grid si cambia el terreno (actualmente el terreno es estático; el grid se genera una vez al arrancar).

**Fuera de scope:**
- Octree jerárquico multinivel (demasiado complejo para las ganancias en esta escena).
- Aceleración de sombras con el grid (las shadow rays tienen ángulo variable, el grid axial no ayuda tanto).
- Aceleración para las esferas de dominio (son objetos puntuales, ya tienen bounding check de 3×3 celdas).

## Acceptance criteria

- [ ] Rayos que apuntan al cielo (miss) reducen pasos de ~80 a < 15 en promedio.
- [ ] Sin artefactos visuales: el grid sólo se usa como lower-bound conservador, nunca sobreestima la distancia.
- [ ] FPS en escena abierta (mirando el horizonte) > 20% mejor que baseline.
- [ ] El grid se genera en CPU en < 500 ms al arrancar (puede solaparse con `compileAsync`).

## Constraints

- El grid **sólo puede subestimar** (o igualar) la distancia real — nunca sobreestimar. Un voxel que devuelve una distancia mayor que la real causaría que el rayo salte dentro de la superficie → artefactos negros.
- Resolución del grid: 32×16×32 cubre un rango de mundo de ±240 × [−5, 55] × ±240 unidades (celdas de 15 unidades). Si la escena requiere mayor precisión, subir a 64×32×64 (256 KB).
- El lower-bound conservador: tomar el valor sampleado y restarle un margen de seguridad `= cellSize * 0.5 * sqrt(3)` (radio de la esfera inscripta en el voxel).
- El grid de terreno no incluye esferas de dominio ni personaje — el SDF del rayo sigue evaluando esos por separado.

## Open questions

- ¿Vale la pena incluir también el SDF de agua en el grid? El agua es un plano `(p.y - 2.8) * 0.4`, trivial de evaluar, probablemente no.
- ¿Cómo manejar la regeneración del grid si en el futuro el terreno es dinámico (e.g., erosión en runtime)?
