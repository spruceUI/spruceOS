#version 430

#include "../util/colorspace.h"

uniform vec4 sScreenSize;

uniform float sScanlineIntensity;
uniform float sInterpolatedIntensity;

layout(binding = 0) uniform sampler2D sTex;
layout(binding = 1) uniform sampler2D ScanPass;

layout(location = 0) in vec2 ilUV;

layout(location = 0) out vec4 outColor0;

void main()
{
	vec4 screenColor0 = texture2D(sTex, ilUV) * vec4(sInterpolatedIntensity);
	vec4 screenColor1 = texture2D(ScanPass, ilUV) * vec4(sScanlineIntensity);
	
	outColor0 = to_gamma_approx(clamp(max(screenColor0, screenColor1), 0.0f, 1.0f));
}
