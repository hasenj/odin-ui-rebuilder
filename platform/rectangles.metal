#include <metal_stdlib>
using namespace metal;

// Matches GPU_Rectangle in render_darwin.odin (48-byte stride).
struct Rectangle {
    float2 position;
    float2 size;
    float4 color;
    float radius;
    float padding[3];
};

struct Vertex_Out {
    float4 position [[position]];
    float2 local;
    float2 size [[flat]];
    float4 color [[flat]];
    float radius [[flat]];
};

vertex Vertex_Out rectangle_vertex(
    uint vertex_id [[vertex_id]],
    uint instance_id [[instance_id]],
    constant Rectangle *rectangles [[buffer(0)]],
    constant float2 &viewport [[buffer(1)]])
{
    constexpr float2 corners[] = {{0, 0}, {1, 0}, {0, 1}, {1, 1}};
    Rectangle r = rectangles[instance_id];
    // Extend the quad for antialiasing outside the rectangle's boundary.
    float2 local = corners[vertex_id] * (r.size + 2.0) - 1.0;
    float2 point = r.position + local;
    Vertex_Out out;
    out.position = float4(point.x / viewport.x * 2.0 - 1.0,
                         1.0 - point.y / viewport.y * 2.0, 0.0, 1.0);
    out.local = local;
    out.size = r.size;
    out.color = r.color;
    out.radius = r.radius;
    return out;
}

fragment float4 rectangle_fragment(Vertex_Out in [[stage_in]])
{
    float2 half_size = in.size * 0.5;
    float2 q = abs(in.local - half_size) - (half_size - in.radius);
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - in.radius;
    float aa = max(fwidth(distance), 0.0001);
    float coverage = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, distance);
    float alpha = in.color.a * coverage;
    // Premultiplied output matches the pipeline's source-over blend factors.
    return float4(in.color.rgb * alpha, alpha);
}
