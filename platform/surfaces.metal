#include <metal_stdlib>
using namespace metal;

// Matches GPU_Surface in render_darwin.odin (80-byte stride).
struct Surface {
    float2 position;
    float2 size;
    float4 color;
    float radius;
    float sigma;
    float border;
    float padding;
    float4 uv;
    float4 clip;
};

struct Vertex_Out {
    float4 position [[position]];
    float2 local;
    float2 size [[flat]];
    float4 color [[flat]];
    float radius [[flat]];
    float sigma [[flat]];
    float border [[flat]];
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
    float extent = max(1.0, 3.0*r.sigma);
    float2 local = corners[vertex_id] * (r.size + 2.0*extent) - extent;
    float2 point = r.position + local;
    Vertex_Out out;
    out.position = float4(point.x / viewport.x * 2.0 - 1.0,
                         1.0 - point.y / viewport.y * 2.0, 0.0, 1.0);
    out.local = local;
    out.size = r.size;
    out.color = r.color;
    out.radius = r.radius;
    out.sigma = r.sigma;
    out.border = r.border;
    out.uv = r.uv;
    out.clip = r.clip;
    out.point = point;
    return out;
}

// Gaussian integral approximation; Evan Wallace, CC0:
// https://madebyevan.com/shaders/fast-rounded-rectangle-shadows/
float2 shadow_erf(float2 x) {
    float2 s = sign(x), a = abs(x);
    x = 1.0 + (0.278393 + (0.230389 + 0.078108*a*a)*a)*a;
    x *= x;
    return s - s/(x*x);
}
float shadow_x(float x, float y, float sigma, float radius, float2 half_size) {
    float delta = min(half_size.y - radius - abs(y), 0.0);
    float extent = half_size.x - radius + sqrt(max(0.0, radius*radius - delta*delta));
    float2 integral = 0.5 + 0.5*shadow_erf(float2(x+extent, x-extent)*(0.70710678/sigma));
    return integral.x - integral.y;
}
float shadow_mask(float2 point, float2 half_size, float radius, float sigma) {
    if (radius <= 0.0) {
        float2 lo = 0.5 + 0.5*shadow_erf((point+half_size)*(0.70710678/sigma));
        float2 hi = 0.5 + 0.5*shadow_erf((point-half_size)*(0.70710678/sigma));
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

fragment float4 surface_fragment(Vertex_Out in [[stage_in]], texture2d<float> image [[texture(0)]])
{
    if (any(in.point < in.clip.xy) || any(in.point >= in.clip.zw)) discard_fragment();
    float2 half_size = in.size * 0.5;
    float2 q = abs(in.local - half_size) - (half_size - in.radius);
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - in.radius;
    float aa = max(fwidth(distance), 0.0001);
    float coverage = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, distance);
    if (in.border > 0.0) coverage *= smoothstep(-in.border-aa*0.5, -in.border+aa*0.5, distance);
    if (in.sigma > 0.0) {
        float alpha = in.color.a * shadow_mask(in.local-half_size, half_size, in.radius, in.sigma);
        return float4(in.color.rgb*alpha, alpha);
    }
    constexpr sampler image_sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 texel = image.sample(image_sampler, mix(in.uv.xy, in.uv.zw, clamp(in.local / in.size, 0.0, 1.0)));
    // Textures already contain premultiplied alpha. Tint and coverage preserve
    // that representation for source-over blending. Solids use a white texel.
    float opacity = in.color.a * coverage;
    return float4(texel.rgb * in.color.rgb * opacity, texel.a * opacity);
}
