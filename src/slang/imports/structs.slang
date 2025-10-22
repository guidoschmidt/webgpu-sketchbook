struct AssembledVertex {
    int index: SV_VertexID;
    float3 position: POSITION;
    float2 uv: TEXCOORD0;
    float3 color: COLOR;
};

struct VertexStageOutput {
    float4 position: SV_POSITION;
    float3 color: COLOR;
    float2 uv: TEXCOORD0;
};

struct Fragment {
    float4 color;
};
