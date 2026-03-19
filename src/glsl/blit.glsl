precision highp float;
uniform sampler2D tCurrent;
uniform sampler2D tHistory;
uniform float uBlend;
uniform vec3 iResolution;
void main() {
    vec2 uv = gl_FragCoord.xy / iResolution.xy;
    vec4 curr = texture2D(tCurrent, uv);
    vec4 hist = texture2D(tHistory, uv);
    gl_FragColor = mix(hist, curr, uBlend);
}
