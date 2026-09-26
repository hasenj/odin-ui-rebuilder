#version 330 core
layout(location = 0) in vec2 rect_position;
layout(location = 1) in vec2 rect_size;
layout(location = 2) in vec4 rect_color;
layout(location = 3) in float rect_radius;
uniform vec2 viewport;
out vec2 local;
flat out vec2 size;
flat out vec4 color;
flat out float radius;
void main() {
    const vec2 corners[4] = vec2[4](vec2(0,0), vec2(1,0), vec2(0,1), vec2(1,1));
    local = corners[gl_VertexID] * (rect_size + 2.0) - 1.0;
    vec2 point = rect_position + local;
    gl_Position = vec4(point.x / viewport.x * 2.0 - 1.0,
                       1.0 - point.y / viewport.y * 2.0, 0.0, 1.0);
    size = rect_size;
    color = rect_color;
    radius = rect_radius;
}
