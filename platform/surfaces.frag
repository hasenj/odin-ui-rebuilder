#version 300 es
precision highp float;
precision highp int;
in vec2 local;
flat in vec2 size;
flat in vec4 color;
flat in float radius;
flat in vec4 uv;
uniform sampler2D image;
out vec4 pixel;
void main() {
    vec2 q = abs(local - size * 0.5) - (size * 0.5 - radius);
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float aa = max(fwidth(distance), 0.0001);
    float coverage = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, distance);
    // Uploaded row zero is the image's top row; local coordinates also start at top.
    vec4 texel = texture(image, mix(uv.xy, uv.zw, clamp(local / size, 0.0, 1.0)));
    float opacity = color.a * coverage;
    pixel = vec4(texel.rgb * color.rgb * opacity, texel.a * opacity);
}
