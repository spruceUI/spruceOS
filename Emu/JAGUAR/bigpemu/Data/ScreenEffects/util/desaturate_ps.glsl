#version 430

#include "colorspace.h"
#include "convenience.h"

uniform float sDesaturateAmount;
uniform float sDesaturateExponent;

layout(binding = 0) uniform sampler2D sTex;

layout(location = 0) in vec2 ilUV;

layout(location = 0) out vec4 outColor0;

void main()
{
	vec4 srcSample = texture2D(sTex, ilUV);

	float lStar = rgb_to_lightness(srcSample.rgb);
	lStar = pow(lStar, sDesaturateExponent);

	srcSample.rgb = lerp(srcSample.rgb, vec3(lStar, lStar, lStar), vec3(sDesaturateAmount));
	
	outColor0 = srcSample;
}
