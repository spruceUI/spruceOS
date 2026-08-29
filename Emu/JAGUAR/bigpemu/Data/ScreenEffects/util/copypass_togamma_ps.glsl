#version 430

#include "colorspace.h"

layout(binding = 0) uniform sampler2D sTex;

layout(location = 0) in vec2 ilUV;

layout(location = 0) out vec4 outColor0;

void main()
{
	outColor0 = to_gamma_approx(texture2D(sTex, ilUV));
}
