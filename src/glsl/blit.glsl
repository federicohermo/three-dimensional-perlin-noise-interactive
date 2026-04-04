precision highp float;
uniform sampler2D tCurrent;
uniform sampler2D tHistory;
uniform float uBlend;
uniform vec3 iResolution;

void main() {
    vec2 uv = gl_FragCoord.xy / iResolution.xy;
    vec2 tx = 1.0 / iResolution.xy;

    vec4 curr = texture2D(tCurrent, uv);

    // Sky pixels (alpha=0) always use current frame — history is wrong after camera rotation.
    // Terrain pixels (alpha=1) use normal temporal blend.
    float isSky = 1.0 - curr.a;
    float effectiveBlend = mix(uBlend, 1.0, isSky);

    // 3x3 neighbourhood AABB — clamp history to prevent motion ghosting on terrain
    vec4 c00 = texture2D(tCurrent, uv + tx * vec2(-1.0, -1.0));
    vec4 c10 = texture2D(tCurrent, uv + tx * vec2( 0.0, -1.0));
    vec4 c20 = texture2D(tCurrent, uv + tx * vec2( 1.0, -1.0));
    vec4 c01 = texture2D(tCurrent, uv + tx * vec2(-1.0,  0.0));
    vec4 c21 = texture2D(tCurrent, uv + tx * vec2( 1.0,  0.0));
    vec4 c02 = texture2D(tCurrent, uv + tx * vec2(-1.0,  1.0));
    vec4 c12 = texture2D(tCurrent, uv + tx * vec2( 0.0,  1.0));
    vec4 c22 = texture2D(tCurrent, uv + tx * vec2( 1.0,  1.0));

    vec4 minC = min(curr, min(min(min(c00, c10), min(c20, c01)),
                              min(min(c21, c02), min(c12, c22))));
    vec4 maxC = max(curr, max(max(max(c00, c10), max(c20, c01)),
                              max(max(c21, c02), max(c12, c22))));

    vec4 hist = clamp(texture2D(tHistory, uv), minC, maxC);
    gl_FragColor = mix(hist, curr, effectiveBlend);
    gl_FragColor.a = curr.a;
}
