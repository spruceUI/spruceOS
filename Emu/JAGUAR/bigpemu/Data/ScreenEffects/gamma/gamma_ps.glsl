#version 430

#include "../util/colorspace.h"

uniform float sGamma;
uniform float sScale;

layout(binding = 0) uniform sampler2D sTex;

layout(location = 0) in vec2 ilUV;

layout(location = 0) out vec4 outColor0;

void main()
{
	vec4 screenColor = texture2D(sTex, ilUV);

	screenColor.rgb = pow(screenColor.rgb, sGamma.xxx);
	screenColor.rgb *= sScale.xxx;
	
	outColor0 = clamp(screenColor, 0.0f, 1.0f);
}
