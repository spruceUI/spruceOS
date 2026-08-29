#version 430

layout(binding = 0) uniform sampler2D sTex;

layout(location = 0) in vec2 ilUV;

layout(location = 0) out vec4 outColor0;

void main()
{
	outColor0 = texture2D(sTex, ilUV);
}
