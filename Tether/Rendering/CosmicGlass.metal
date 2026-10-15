#include <metal_stdlib>
using namespace metal;

struct CosmicSegment {
    float2 start;
    float2 end;
    float4 color;
    float4 style;
    float4 detail;
};
struct CosmicUniforms { float4 viewport; };
struct CosmicRaster {
    float4 position [[position]];
    float2 point;
    float2 start [[flat]];
    float2 end [[flat]];
    float4 color [[flat]];
    float4 style [[flat]];
    float4 detail [[flat]];
};

vertex CosmicRaster cosmicVertex(
    uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
    const device CosmicSegment *segments [[buffer(0)]],
    constant CosmicUniforms &uniforms [[buffer(1)]]
) {
    const CosmicSegment segment = segments[instanceID];
    const float2 corners[] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(0, 1), float2(1, 0), float2(1, 1)
    };
    float2 delta = segment.end - segment.start;
    float lineLength = length(delta);
    float2 tangent = lineLength > 0.0001 ? delta / lineLength : float2(1, 0);
    float2 normal = float2(-tangent.y, tangent.x);
    float padding = segment.style.x + 2 + segment.style.y * 9;
    float2 corner = corners[vertexID];
    float2 point = segment.start + tangent * mix(-padding, lineLength + padding, corner.x)
                    + normal * mix(-padding, padding, corner.y);
    CosmicRaster out;
    out.position = float4(point.x / uniforms.viewport.x * 2 - 1,
                          1 - point.y / uniforms.viewport.y * 2, 0, 1);
    out.point = point;
    out.start = segment.start;
    out.end = segment.end;
    out.color = segment.color;
    out.style = segment.style;
    out.detail = segment.detail;
    return out;
}

fragment half4 cosmicFragment(CosmicRaster in [[stage_in]], constant CosmicUniforms &uniforms [[buffer(1)]]) {
    float2 delta = in.end - in.start;
    float lengthSquared = dot(delta, delta);
    float t = lengthSquared > 0.0001 ? clamp(dot(in.point - in.start, delta) / lengthSquared, 0.0, 1.0) : 0;
    float distance = length(in.point - (in.start + t * delta));
    float edge = max(0.5 / uniforms.viewport.z, fwidth(distance) * 0.65);
    float radius = in.style.x;
    float core = 1 - smoothstep(radius - edge, radius + edge, distance);
    if (in.detail.x > 0) core *= smoothstep(in.detail.x - edge, in.detail.x + edge, distance);
    float outside = max(0.0, distance - radius);
    float spread = 1.2 + in.style.y * 3.1;
    float glow = exp(-outside * outside / (spread * spread)) * in.style.y * 0.28;
    if (in.detail.x > 0 && distance < in.detail.x)
        glow *= smoothstep(max(0.0, in.detail.x - 2), in.detail.x, distance);
    float alpha = (core + glow * (1 - core)) * in.color.a;
    if (in.style.z > 0) {
        float along = t * sqrt(lengthSquared) + in.style.w;
        float dash = fmod(along, in.style.z);
        alpha *= 1 - smoothstep(in.style.z * 0.60 - edge, in.style.z * 0.60 + edge, dash);
    }
    float3 color = in.color.rgb;
    if (lengthSquared < 0.0001 && in.detail.x == 0)
        color = mix(color, float3(1), 0.6 * (1 - smoothstep(0.0, radius, distance)));
    return half4(half3(color * alpha), half(alpha));
}

struct CosmicSkyRaster {
    float4 position [[position]];
    float2 uv;
};
vertex CosmicSkyRaster cosmicSkyVertex(uint vertexID [[vertex_id]]) {
    const float2 coordinates[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    CosmicSkyRaster out;
    out.position = float4(coordinates[vertexID], 0, 1);
    out.uv = coordinates[vertexID] * float2(0.5, -0.5) + 0.5;
    return out;
}
float cosmicHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}
fragment half4 cosmicSkyFragment(CosmicSkyRaster in [[stage_in]], constant CosmicUniforms &uniforms [[buffer(1)]]) {
    float2 center = in.uv - 0.5;
    float vignette = exp(-dot(center, center) * 2.1);
    float blue = exp(-dot(in.uv - float2(0.18, 0.3), in.uv - float2(0.18, 0.3)) * 7);
    float violet = exp(-dot(in.uv - float2(0.8, 0.7), in.uv - float2(0.8, 0.7)) * 6);
    float3 base = float3(0.014, 0.020, 0.046) + float3(0.007, 0.011, 0.022) * vignette;
    base += float3(0.005, 0.014, 0.029) * blue + float3(0.024, 0.009, 0.027) * violet;
    // A quiet, stable star field. The host does not keep a display link running
    // merely to animate decoration, and Reduce Motion requires no special path.
    float2 pixel = in.uv * uniforms.viewport.xy;
    float2 cell = floor(pixel / 38);
    float2 random = float2(cosmicHash(cell), cosmicHash(cell + 51.7));
    float2 star = (cell + 0.18 + random * 0.64) * 38;
    float distance = length(pixel - star);
    float brightness = step(0.76, cosmicHash(cell + 6.13));
    float starAlpha = (1 - smoothstep(0.12, 0.75, distance)) * brightness * 0.26;
    base += float3(0.58, 0.67, 1.0) * starAlpha;
    return half4(half3(base), 1);
}
