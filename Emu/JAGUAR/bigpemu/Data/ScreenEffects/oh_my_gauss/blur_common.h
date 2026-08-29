
uniform vec4 sRTSize;

//generated with Noesis tool_pascals_triangle.py (def genGaussianWeights)
const float blurOffsets[13] = float[13](
	-11.071428571428571,
	-9.142857142857142,
	-7.214285714285714,
	-5.285714285714286,
	-3.357142857142857,
	-1.4285714285714286,
	0.0,
	1.4285714285714286,
	3.357142857142857,
	5.285714285714286,
	7.214285714285714,
	9.142857142857142,
	11.071428571428571
);
const float blurWeights[13] = float[13](
	3.311158905091201e-06,
	0.00017935444069244006,
	0.003300121708740897,
	0.027226004097112403,
	0.11495423952114125,
	0.26648482798082745,
	0.17570428218516096,
	0.26648482798082745,
	0.11495423952114125,
	0.027226004097112403,
	0.003300121708740897,
	0.00017935444069244006,
	3.311158905091201e-06
);

vec4 blur_taps(sampler2D tex, vec2 uv)
{
	vec4 samples = vec4(0.0f);

	for (int i = 0; i < 13; ++i)
	{
		float w = blurWeights[i];
#ifdef BLUR_H
		samples += texture2D(tex, uv + vec2(blurOffsets[i] * sRTSize.z, 0.0f)) * vec4(w);
#else
		samples += texture2D(tex, uv + vec2(0.0f, blurOffsets[i] * sRTSize.w)) * vec4(w);
#endif
	}
	return samples;
}