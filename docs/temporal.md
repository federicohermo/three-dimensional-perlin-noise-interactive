# Temporal Accumulation

## Overview

Temporal anti-aliasing (TAA) blends the current frame with an accumulated history buffer to produce smooth edges without per-frame supersampling cost. Each frame contributes a sub-pixel jitter offset so successive frames sample different positions within the same pixel.

Toggled with the `T` key. State is in `src/temporal.js`.

## Render target layout

Three `WebGLRenderTarget`s at the current render scale:

| RT | Role |
|---|---|
| `rtScene` | Current frame (raymarched) |
| `rtHistA` | History buffer ping |
| `rtHistB` | History buffer pong |

## Ping-pong blit pipeline

Each frame with temporal ON:

1. **Render** scene → `rtScene` (scaled resolution)
2. **Blend** `rtScene` + `rtHistRead` → `rtHistWrite` (same scale)
3. **Display** `rtHistWrite` → screen (full resolution, upscale)

`histRead` and `histWrite` alternate between `rtHistA` / `rtHistB` based on `frameIdx % 2`.

## Blend factors

| Condition | `uBlend` | Effect |
|---|---|---|
| `frameIdx == 0` (first frame after movement) | 1.0 | Full current frame — no ghosting from stale history |
| Moving | 0.3 | Mostly current — less smearing during motion |
| Still | 0.12 | Mostly history — full accumulation, ~8× effective samples |

The blit shader blends as: `output = mix(history, current, uBlend)`.

## Sub-pixel jitter — Halton sequence

Frame 0 has zero jitter (always a clean, un-offset sample). Frames 1–7 use the Halton low-discrepancy sequence:

```js
export function halton(index, base) {
    let f = 1, r = 0;
    let i = index;
    while (i > 0) { f /= base; r += f * (i % base); i = Math.floor(i / base); }
    return r;
}
// Usage: halton(frameIdx % 8 + 1, 2) for X,  halton(..., 3) for Y
```

Jitter is applied in the shader as `uv = (fragCoord + iJitter - 0.5*res) / res.y`.

Halton(2,3) produces well-distributed samples in [0,1]² with low discrepancy (uniform coverage with no clustering), superior to random or regular-grid patterns.

## Frame counter

`frameIdx` resets to 0 on any camera movement or interaction. The reset ensures the history is not used after a discontinuous cut (which would cause ghosting). `temporal.js` is a shared module specifically to avoid a circular dependency between `main.js` (which reads `frameIdx`) and `input.js` (which resets it).

## Render scale

Three tiers: 0.5×, 0.75×, 1.0×. Cycled with the `R` key. The blit pass upscales to full resolution regardless of render scale, so at 0.5× the raymarcher runs at quarter pixel count with a linear upscale.

When temporal is ON with reduced render scale, the blend pass runs at scaled resolution and the final display blit runs at full resolution — two separate passes.
