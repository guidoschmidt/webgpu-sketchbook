StructuredBuffer<int> input_buffer;
RWStructuredBuffer<int> output_buffer;

[shader("compute")]
[numthreads(16,1,1)]
void main(uint3 threadId : SV_DispatchThreadID)
{
    uint index = threadId.x;
    output_buffer[index] = input_buffer[index] * 2;
}