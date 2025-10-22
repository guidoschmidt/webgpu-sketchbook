matrix<float, 2, 2> rotate2D(float angle)
{
    return matrix<float, 2, 2>(cos(angle), -sin(angle), sin(angle), cos(angle));
}

matrix<float, 3, 3> rotate3DY(float angle)
{
    return matrix<float, 3, 3>(
         cos(angle), 0, sin(angle),
         0,          1, 0,
        -sin(angle), 0, cos(angle),
    );
}

matrix<float, 3, 3> rotate3DZ(float angle)
{
    return matrix<float, 3, 3>(
        cos(angle), -sin(angle), 0,
        sin(angle),  cos(angle), 0,
                0,           0, 1,
    );
}