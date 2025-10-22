import imports.structs;
import imports.uniforms;
import slanglib.math;

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
    output.color = float4(input.uv, 0, 1);
    return output;
}