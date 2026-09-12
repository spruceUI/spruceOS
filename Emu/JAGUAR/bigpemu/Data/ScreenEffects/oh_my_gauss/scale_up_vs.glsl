#version 430

#include "../util/common_ubo.h"

layout(location = 0) in vec4 inVertexPos;
layout(location = 1) in vec2 inVertexUV;

layout(location = 0) out vec2 ilUV;

//uniform vec4 sTargetAreaOffsets;
uniform vec4 sRatiosAndScales;

void main()
{
	//const float zoom = min(sTargetAreaOffsets.z, sTargetAreaOffsets.w);
	//ilUV = (inVertexUV * zoom) + (zoom * 0.25f);
	ilUV = inVertexUV * sRatiosAndScales.zw + (vec2(1.0f) - sRatiosAndScales.zw) * 0.5f;
	gl_Position = sUBOConstants.mMVP * inVertexPos;
}

