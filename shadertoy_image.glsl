// ============================================================================
// Shadertoy [Image] Tab — Rendering
// ============================================================================
//
// 1. CLEAR ALL PREVIOUS CODE in this tab.
// 2. Click "iChannel0" at the bottom and select "Buffer A".
// ============================================================================

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = (fragCoord - .5*iResolution.xy)/iResolution.y;
    vec3 col = vec3(0.01);

    // Read camera state from Buffer A
    vec4 state = texelFetch(iChannel0, ivec2(0,0), 0);
    float yaw = state.x;
    float pitch = state.y;
    
    vec3 ta = vec3(0.0, 1.0, 4.0);
    float camDist = 4.0;
    
    vec3 ro = ta + vec3(
        camDist * cos(yaw) * cos(pitch),
        camDist * sin(pitch),
        camDist * sin(yaw) * cos(pitch)
    ); 

    vec3 cw = normalize(ta - ro);
    vec3 cp = vec3(0.0, 1.0, 0.0);
    vec3 cu = normalize(cross(cp, cw));
    vec3 cv = normalize(cross(cw, cu));
    vec3 rd = normalize(uv.x * cu + uv.y * cv + 0.5 * cw);

    // Optimized & Simplified: Fast sine-based organic detail pre-calculation
    float oD = sin(ro.x*0.13 + ro.z*0.21)*0.5 + sin(ro.z*0.17 - ro.x*0.11)*0.5;
    float organicDetail = clamp(oD + 0.5, 0.0, 1.0);

    float d = RayMarch(ro, rd, organicDetail);
    if(d > 0.0) {
        vec3 p = ro + rd * d;
        col = vec3(GetLight(p, organicDetail));
    }

    fragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
