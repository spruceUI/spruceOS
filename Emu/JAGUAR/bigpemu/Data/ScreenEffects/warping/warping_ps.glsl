#version 430

#include "../util/convenience.h"

uniform vec4 sScreenSize;
uniform float sHCurve;
uniform float sHBias;
uniform float sVCurve;
uniform float sVBias;
uniform float sBoundaryFade;

layout(binding = 0) uniform sampler2D sTex;

layout(location = 0) in vec2 ilUV;

layout(location = 0) out vec4 outColor0;

void main()
{
	vec2 uv = ilUV;
	vec2 uvc = (uv - 0.5f) * 2.0f;

	//pulled this whole formula out of my ass! there's nothing consistent to go on anyway in terms of electromagnetic distortion.
	//most crt displays get it fairly right, and if they don't, the distortion is probably non-uniform and might be better approximated with a custom geometry lens. (see my Sega VR emulation work!)
	float ax = pow(abs(uvc.x), sVCurve);
	float ay = pow(abs(uvc.y), sHCurve);
	vec2 uvcScale = vec2(
		1.0f / max((1.0f - ay) + sHBias * ay, sScreenSize.z),
		1.0f / max((1.0f - ax) + sVBias * ax, sScreenSize.w)
	);
	uvc *= uvcScale;
	
	uv = (uvc + 1.0f) * 0.5f;
	
	vec2 d = vec2(abs(round(uv) - uv)) * 12.0f;
	
	float fc = uv_clip_mask(uv);
	
	outColor0 = vec4(texture2D(sTex, uv).rgb * fc, fc * lerp(1.0f, min(min(d.x, d.y), 1.0f), sBoundaryFade));
}
