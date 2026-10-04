#version 300 es
precision highp float;
precision highp int;
in vec2 local;
in vec2 window_point;
flat in vec4 clip;
flat in vec2 size;
flat in vec4 color;
flat in float radius;
flat in float sigma;
flat in float border;
flat in vec4 uv;
uniform sampler2D image;
out vec4 pixel;
// Gaussian integral approximation; Evan Wallace, CC0:
// https://madebyevan.com/shaders/fast-rounded-rectangle-shadows/
vec2 shadow_erf(vec2 x) {
    vec2 s = sign(x), a = abs(x);
    x = 1.0 + (0.278393 + (0.230389 + 0.078108*a*a)*a)*a;
    x *= x;
    return s - s/(x*x);
}
float shadow_x(float x, float y, float sigma, float radius, vec2 half_size) {
    float delta = min(half_size.y - radius - abs(y), 0.0);
    float extent = half_size.x - radius + sqrt(max(0.0, radius*radius - delta*delta));
    vec2 integral = 0.5 + 0.5*shadow_erf(vec2(x+extent, x-extent)*(0.70710678/sigma));
    return integral.x - integral.y;
}
float shadow_mask(vec2 point, vec2 half_size, float radius, float sigma) {
    if (radius <= 0.0) {
        vec2 lo = 0.5 + 0.5*shadow_erf((point+half_size)*(0.70710678/sigma));
        vec2 hi = 0.5 + 0.5*shadow_erf((point-half_size)*(0.70710678/sigma));
        return (lo.x-hi.x)*(lo.y-hi.y);
    }
    float low = max(-3.0*sigma, point.y-half_size.y);
    float high = min(3.0*sigma, point.y+half_size.y);
    if (high <= low) return 0.0;
    float step = (high-low)/8.0;
    float sum = 0.0;
    for (int i=0; i<8; ++i) {
        float y = low+(float(i)+0.5)*step;
        sum += shadow_x(point.x, point.y-y, sigma, radius, half_size)*
            exp(-0.5*y*y/(sigma*sigma))*(0.39894228/sigma)*step;
    }
    return clamp(sum, 0.0, 1.0);
}

void main() {
    if (any(lessThan(window_point, clip.xy)) || any(greaterThanEqual(window_point, clip.zw))) discard;
    vec2 q = abs(local - size * 0.5) - (size * 0.5 - radius);
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float aa = max(fwidth(distance), 0.0001);
    float coverage = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, distance);
    if (border > 0.0) coverage *= smoothstep(-border-aa*0.5, -border+aa*0.5, distance);
    if (sigma > 0.0) {
        float alpha = color.a * shadow_mask(local-size*0.5, size*0.5, radius, sigma);
        pixel = vec4(color.rgb*alpha, alpha);
        return;
    }
    // Uploaded row zero is the image's top row; local coordinates also start at top.
    vec4 texel = texture(image, mix(uv.xy, uv.zw, clamp(local / size, 0.0, 1.0)));
    float opacity = color.a * coverage;
    pixel = vec4(texel.rgb * color.rgb * opacity, texel.a * opacity);
}
