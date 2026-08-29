#version 430

#include "../util/common_ubo.h"

uniform vec4 sTargetAreaOffsets;

layout(location = 0) in vec4 inVertexPos;
layout(location = 1) in vec2 inVertexUV;

layout(location = 0) out vec2 ilUV;

void main()
{
	ilUV = inVertexUV;
	vec4 adjustedPos = inVertexPos;
	adjustedPos.xy = (adjustedPos.xy * sTargetAreaOffsets.zw) + sTargetAreaOffsets.xy;
	
	gl_Position = sUBOConstants.mMVP * adjustedPos;
}

