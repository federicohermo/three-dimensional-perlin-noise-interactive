// ============================================================================
// Shadertoy [Buffer A] Tab — Persistence Logic
// ============================================================================
//
// 1. CLEAR ALL PREVIOUS CODE in this tab.
// 2. Click "iChannel0" at the bottom and select "Buffer A" (Feedback loop).
// ============================================================================

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // Only store data in the first pixel
    if (fragCoord.x > 1.0 || fragCoord.y > 1.0) discard;

    // Load previous state from iChannel0 (Buffer A feedback)
    vec4 state = texelFetch(iChannel0, ivec2(0,0), 0);
    
    float yaw   = state.x;
    float pitch = state.y;
    vec2 lastM  = state.zw;

    // Initial state setup
    if (iFrame == 0 || iMouse.z < 0.0) {
        if (iFrame == 0) {
            yaw = -1.5707; 
            pitch = 0.4;
        }
        lastM = iMouse.xy;
    }

    // Dragging logic
    if (iMouse.z > 0.0) {
        if (iMouse.w > 0.0) {
            lastM = iMouse.xy; // Start of click reset
        }
        vec2 delta = (iMouse.xy - lastM) / iResolution.xy;
        yaw   -= delta.x * 4.0;
        pitch -= delta.y * 1.8;
        pitch = clamp(pitch, -0.6, 0.6); // Stable vertical bounds
        lastM = iMouse.xy;
    }

    fragColor = vec4(yaw, pitch, lastM.x, lastM.y);
}
