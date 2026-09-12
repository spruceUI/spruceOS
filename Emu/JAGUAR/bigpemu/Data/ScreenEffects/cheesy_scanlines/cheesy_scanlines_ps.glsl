#version 430

#include "../util/colorspace.h"

uniform vec4 sScreenSize;

layout(binding = 0) uniform sampler2D sTex;

layout(location = 0) in vec2 ilUV;

layout(location = 0) out vec4 outColor0;

void main()
{
	vec4 screenColor = to_linear_approx(texture2D(sTex, ilUV));

	float y = sScreenSize.y * ilUV.y;
	float f = round(fract(y) + 0.001f);
	screenColor.rgb *= f;
	
	outColor0 = screenColor;
}
