import imports.structs;
import imports.uniforms;
import slanglib.math;
import slanglib.shapes;

struct Uniforms {
    float time;
    float colorshift;
};

ConstantBuffer<Uniforms> uniforms;

[shader("vertex")]
VertexStageOutput vs_main(AssembledVertex input) {
    VertexStageOutput output;
    output.position = float4(mul(rotate2D(uniforms.time), input.position.xy), 0, 1);
    output.color = input.color;
    output.uv = input.uv;
    return output;
}

[shader("fragment")]
Fragment fs_main(VertexStageOutput input) : SV_Target {
    Fragment output;
    float3 color_a = 0;
    float3 color_b = (sin(3.0 * (uniforms.time)) * 0.5) + 0.5;
    float2 gamma = (sin(uniforms.time) * 0.5) + 0.5;
    // output.color = pillow(float4(color_a, 1), float4(color_b, 1), 5 + gamma * 10, input.uv);
    // output.color = float4(sin(uniforms.time), cos(uniforms.time), tan(uniforms.time), 1);
    output.color.rgb = input.color;
    return output;
}