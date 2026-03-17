// Temporal accumulation state — extracted here to avoid main.js ↔ input.js circular dependency.
// Both main.js (reads) and input.js (resets) need these; a shared module breaks the cycle.

export let temporalOn = true;
export let frameIdx = 0;

export function toggleTemporal() {
    temporalOn = !temporalOn;
}

export function resetFrameIdx() {
    frameIdx = 0;
}

export function tickFrameIdx() {
    frameIdx++;
}

// Halton low-discrepancy sequence for sub-pixel jitter
export function halton(index, base) {
    let f = 1, r = 0;
    let i = index;
    while (i > 0) {
        f /= base;
        r += f * (i % base);
        i = Math.floor(i / base);
    }
    return r;
}
