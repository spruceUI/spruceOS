#version 430

#include "util/common_ubo.h"

layout(location = 0) in vec4 inVertexPos;
layout(location = 1) in vec2 inVertexUV;

layout(location = 0) out vec2 ilUV;

void main()
{
	ilUV = inVertexUV;
	gl_Position = sUBOConstants.mMVP * inVertexPos;
}

