#version 300 es
precision highp float;
precision highp int;
layout(location = 0) in vec2 rect_position;
layout(location = 1) in vec2 rect_size;
layout(location = 2) in vec4 rect_color;
layout(location = 3) in float rect_radius;
layout(location = 4) in vec4 rect_uv;
layout(location = 5) in vec4 rect_clip;
layout(location = 6) in float rect_sigma;
layout(location = 7) in float rect_border;
uniform vec2 viewport;
out vec2 local;
out vec2 window_point;
flat out vec4 clip;
flat out vec2 size;
flat out vec4 color;
flat out float radius;
flat out float sigma;
flat out float border;
flat out vec4 uv;
void main() {
    const vec2 corners[4] = vec2[4](vec2(0,0), vec2(1,0), vec2(0,1), vec2(1,1));
    float extent = max(1.0, 3.0*rect_sigma);
    local = corners[gl_VertexID] * (rect_size + 2.0*extent) - extent;
    vec2 point = rect_position + local;
    gl_Position = vec4(point.x / viewport.x * 2.0 - 1.0,
                       1.0 - point.y / viewport.y * 2.0, 0.0, 1.0);
    window_point = point;
    clip = rect_clip;
    size = rect_size;
    color = rect_color;
    radius = rect_radius;
    sigma = rect_sigma;
    border = rect_border;
    uv = rect_uv;
}
