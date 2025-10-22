vector<T,N> pillow<T,int N>(vector<T,N> a, vector<T,N> b, float2 gamma, float2 uv)
where T : __BuiltinFloatingPointType
{
  float2 tmp =
    (uv * 2.0 - 1.0) * 0.5 * float2(-1, 1) * // x
    (uv * 2.0 - 1.0) * 0.5 * float2(-1, 1) + 0.5; // y

  float fade =
    pow(smoothstep(-1.0, 1.0, 1.0 - 0.5 * (tmp.x - 0.5)), pow(2.0, gamma.x)) *
    pow(smoothstep(-1.0, 1.0, 1.0 - 0.5 * (tmp.y - 0.5)), pow(2.0, gamma.y));

    return lerp(a, b, T(fade));
}