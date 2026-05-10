// White Bear glyph — flat, slightly smaller, dialed-back opacity

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float whiteBear(vec2 p) {
    float s = 0.050;
    float d = sdBox(p - vec2(0.0,   1.3*s), vec2(s, 2.3*s));   // top stem
    d = min(d, sdBox(p,                    vec2(3.0*s, s)));   // middle bar
    d = min(d, sdBox(p - vec2(-2.0*s, -s), vec2(s, 2.0*s)));   // left column
    d = min(d, sdBox(p - vec2( 2.0*s, -s), vec2(s, 2.0*s)));   // right column
    return d;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / min(iResolution.x, iResolution.y);
    uv.y = -uv.y;

    float d = whiteBear(uv);
    float px = 1.0 / min(iResolution.x, iResolution.y);
    float mask = smoothstep(px, -px, d);

    float breathe = mix(0.30, 1.00, 0.5 + 0.5 * sin(iTime * 0.628));

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    vec3 symbol_color = vec3(1.0, 1.0, 1.0);
    float opacity = 0.14 * breathe;

    fragColor = vec4(mix(term.rgb, symbol_color, mask * opacity), term.a);
}
