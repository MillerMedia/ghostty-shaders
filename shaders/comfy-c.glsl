// Procedural Comfy "C" — slow rotating 3D logo, low-opacity background overlay.
// Approximates the comfy.org hero logo with a raymarched chunky-C SDF.

// --- Tunables ---
#define ROTATION_PERIOD 32.0          // seconds per full rotation
#define LOGO_OPACITY    0.16          // 0.0 (invisible) .. 1.0 (opaque)
#define LOGO_CENTER     vec2(0.50, 0.50)  // screen-fraction position (x: 0=left,1=right; y: 0=top,1=bottom)
#define LOGO_SIZE       0.22          // logo radius as fraction of shorter screen axis
// ----------------

#define PI 3.14159265359

mat3 rotY(float a) {
    float c = cos(a), s = sin(a);
    return mat3(c, 0.0, -s, 0.0, 1.0, 0.0, s, 0.0, c);
}

float sdRoundBox(vec3 p, vec3 b, float r) {
    vec3 q = abs(p) - b + vec3(r);
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// Smooth max — like max() but blends the two surfaces over radius k. Used for
// smooth SDF subtraction so the corners where the cut meets the C are rounded.
float smax(float a, float b, float k) {
    float h = clamp(0.5 - 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

// Block letter C with corner cuts at top-left and bottom-left (the comfy logo's
// signature stepped corners). Open mouth on the right — no hooks.
float sdLogoC(vec3 p) {
    // Lay back: rotate around X axis so the top tilts away from the camera.
    {
        float a = 0.15;
        float c = cos(a), s = sin(a);
        float ny = p.y * c + p.z * s;
        float nz = -p.y * s + p.z * c;
        p.y = ny; p.z = nz;
    }
    // Italic shear: lean to the right at the top. Sign accounts for Ghostty's
    // Y axis pointing down (so positive shear coefficient leans forward).
    p.x += 0.25 * p.y;

    // Spine + arms, all aligned to the same left edge (clean block C).
    // Spine and arms shortened to bring the mouth gap tighter.
    float spine    = sdRoundBox(p - vec3(-0.50,  0.00, 0.0), vec3(0.34, 0.90, 0.35), 0.14);
    float topArm   = sdRoundBox(p - vec3(-0.15,  0.60, 0.0), vec3(0.65, 0.30, 0.35), 0.14);
    float botArm   = sdRoundBox(p - vec3(-0.15, -0.60, 0.0), vec3(0.65, 0.30, 0.35), 0.14);
    float c = min(spine, min(topArm, botArm));

    // Subtract larger rounded boxes from the top-left and bottom-left corners
    // to create the stepped/cut-corner silhouette. Z extent is large so the
    // cut goes all the way through (front-to-back).
    float tlCut = sdRoundBox(p - vec3(-0.95,  1.00, 0.0), vec3(0.45, 0.45, 0.5), 0.06);
    float blCut = sdRoundBox(p - vec3(-0.95, -1.00, 0.0), vec3(0.45, 0.45, 0.5), 0.06);
    float cuts = min(tlCut, blCut);

    return smax(c, -cuts, 0.08);
}

vec3 sdNormal(vec3 p) {
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        sdLogoC(p + e.xyy) - sdLogoC(p - e.xyy),
        sdLogoC(p + e.yxy) - sdLogoC(p - e.yxy),
        sdLogoC(p + e.yyx) - sdLogoC(p - e.yyx)
    ));
}

// Iridescent gradient (pink → blue → green) keyed off normal + view angle.
vec3 iridescent(vec3 n, vec3 v) {
    float t = clamp(0.5 + 0.5 * dot(n, v) + 0.3 * n.y, 0.0, 1.0);
    vec3 pink  = vec3(1.00, 0.78, 0.88);
    vec3 blue  = vec3(0.72, 0.82, 1.00);
    vec3 green = vec3(0.82, 1.00, 0.86);
    return t < 0.5 ? mix(pink, blue, t * 2.0) : mix(blue, green, (t - 0.5) * 2.0);
}

vec4 renderLogo(vec2 uv) {
    // Cheap distance cull — skip raymarch if far from the logo bounds.
    if (length(uv) > 2.2) return vec4(0.0);

    vec3 ro = vec3(0.0, 0.0, 4.0);
    vec3 rd = normalize(vec3(uv, -2.5));

    float angle = -(iTime / ROTATION_PERIOD) * PI * 2.0;
    mat3 rot = rotY(angle);
    ro = rot * ro;
    rd = rot * rd;

    float t = 0.0;
    for (int i = 0; i < 64; i++) {
        vec3 p = ro + rd * t;
        float d = sdLogoC(p);
        if (d < 0.001) {
            vec3 n = sdNormal(p);
            vec3 v = normalize(-rd);

            // Front/back faces (z-aligned normal) get yellow; side faces get iridescent.
            float yellowMask = step(max(abs(n.x), abs(n.y)), abs(n.z));
            vec3 yellow = vec3(1.00, 0.95, 0.38);
            vec3 col = mix(iridescent(n, v), yellow, yellowMask);

            // Soft top-down light, plus a touch of fresnel rim.
            vec3 light = normalize(vec3(0.4, 0.9, 0.5));
            float lambert = max(dot(n, light), 0.0);
            float rim = pow(1.0 - max(dot(n, v), 0.0), 3.0);
            col *= 0.7 + 0.4 * lambert;
            col += rim * 0.15;

            return vec4(col, 1.0);
        }
        t += d;
        if (t > 20.0) break;
    }
    return vec4(0.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv01 = fragCoord / iResolution.xy;
    vec4 term = texture(iChannel0, uv01);

    float screenMin = min(iResolution.x, iResolution.y);
    vec2 logoUV = (fragCoord - LOGO_CENTER * iResolution.xy) / (screenMin * LOGO_SIZE);

    vec4 logo = renderLogo(logoUV);

    fragColor = vec4(mix(term.rgb, logo.rgb, logo.a * LOGO_OPACITY), term.a);
}
