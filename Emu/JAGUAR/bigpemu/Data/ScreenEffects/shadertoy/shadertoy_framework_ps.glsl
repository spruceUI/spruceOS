#version 430

uniform float iTime;
uniform vec4 iResolution;
uniform vec4 iChannel0Resolution;
uniform uint iFrame;

layout(binding = 0) uniform sampler2D iChannel0;

#include "../shadertoy.glsl"

layout(location = 0) in vec2 shadertoy_framework_ilUV;

layout(location = 0) out vec4 shadertoy_framework_outColor0;

void main()
{
	mainImage(shadertoy_framework_outColor0, shadertoy_framework_ilUV * iResolution.xy);
}
