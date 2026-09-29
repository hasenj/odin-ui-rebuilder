#include <metal_stdlib>
using namespace metal;

// Matches GPU_Surface in render_darwin.odin (80-byte stride).
struct Surface {
    float2 position;
    float2 size;
    float4 color;
    float radius;
    float padding[3];
    float4 uv;
    float4 clip;
};

struct Vertex_Out {
    float4 position [[position]];
    float2 local;
    float2 size [[flat]];
    float4 color [[flat]];
    float radius [[flat]];
    float4 uv [[flat]];
    float4 clip [[flat]];
    float2 point;
};

vertex Vertex_Out surface_vertex(
    uint vertex_id [[vertex_id]],
    uint instance_id [[instance_id]],
    constant Surface *surfaces [[buffer(0)]],
    constant float2 &viewport [[buffer(1)]])
{
    constexpr float2 corners[] = {{0, 0}, {1, 0}, {0, 1}, {1, 1}};
    Surface r = surfaces[instance_id];
    // Extend the quad for antialiasing outside the surface's boundary.
    float2 local = corners[vertex_id] * (r.size + 2.0) - 1.0;
    float2 point = r.position + local;
    Vertex_Out out;
    out.position = float4(point.x / viewport.x * 2.0 - 1.0,
                         1.0 - point.y / viewport.y * 2.0, 0.0, 1.0);
    out.local = local;
    out.size = r.size;
    out.color = r.color;
    out.radius = r.radius;
    out.uv = r.uv;
    out.clip = r.clip;
    out.point = point;
    return out;
}

fragment float4 surface_fragment(Vertex_Out in [[stage_in]], texture2d<float> image [[texture(0)]])
{
    if (any(in.point < in.clip.xy) || any(in.point >= in.clip.zw)) discard_fragment();
    float2 half_size = in.size * 0.5;
    float2 q = abs(in.local - half_size) - (half_size - in.radius);
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - in.radius;
    float aa = max(fwidth(distance), 0.0001);
    float coverage = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, distance);
    constexpr sampler image_sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 texel = image.sample(image_sampler, mix(in.uv.xy, in.uv.zw, clamp(in.local / in.size, 0.0, 1.0)));
    // Textures already contain premultiplied alpha. Tint and coverage preserve
    // that representation for source-over blending. Solids use a white texel.
    float opacity = in.color.a * coverage;
    return float4(texel.rgb * in.color.rgb * opacity, texel.a * opacity);
}
