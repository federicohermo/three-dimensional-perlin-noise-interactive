// Single shared uniforms object — ES module singleton (all importers share the same reference).
export const uniforms = {
    iTime:             { value: 0.0 },
    iResolution:       { value: new THREE.Vector3(window.innerWidth, window.innerHeight, 1.0) },
    iMouse:            { value: new THREE.Vector4(window.innerWidth * 0.25, window.innerHeight * 0.5, 0, 0) },
    iJitter:           { value: new THREE.Vector2(0, 0) },
    iCameraPos:        { value: new THREE.Vector3(0.0, 8.0, 4.0) },
    uAttachedOffsets:  { value: Array.from({ length: 10 }, () => new THREE.Vector3()) },
    uAttachedActive:   { value: new Float32Array(10) },
    uIgnoredCells:     { value: Array.from({ length: 10 }, () => new THREE.Vector2()) },
};
