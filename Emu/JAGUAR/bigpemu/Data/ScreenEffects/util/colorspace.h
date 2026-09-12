
vec3 to_gamma_approx(vec3 clr)
{
	float toGamma = 1.0f / 2.2f;
	return pow(clr.rgb, vec3(toGamma));
}
vec4 to_gamma_approx(vec4 clr)
{
	return vec4(to_gamma_approx(clr.rgb), clr.a);
}

vec3 to_linear_approx(vec3 clr)
{
	float toLinear = 2.2f;
	return pow(clr.rgb, vec3(toLinear));
}
vec4 to_linear_approx(vec4 clr)
{
	return vec4(to_linear_approx(clr.rgb), clr.a);
}

float rgb_to_lightness(vec3 rgb)
{
	//luminance to lightness, see https://en.wikipedia.org/wiki/Lightness#1976
	//(6 / 29) ^ 3 = 216 / 24389 = 0.00885645167903563081717167575546
	//(29 / 3) ^ 3 = 24389 / 27 = 903.2962962962962962962962962963
	float l = rgb.r * 0.2126f + rgb.g * 0.7152f + rgb.b * 0.0722f;
	float kTransitionPoint = 216.0f / 24389.0f;
	float kSlope = 24389.0f / 27.0f;
	float lStar = ((l > kTransitionPoint) ? 116.0f * pow(l, 1.0f / 3.0f) - 16.0f : l * kSlope) * 0.01f;
	return lStar;
}
