#version 430

#include "../util/colorspace.h"
#include "../util/convenience.h"

uniform float sTime;

uniform float sDesaturateAmount2;
uniform float sLizBias;
uniform float sLizScale;
uniform float sLizExponent;
uniform float sLizScriptBasedBias;

layout(binding = 0) uniform sampler2D sBloomTex;
layout(binding = 1) uniform sampler2D sScreenTex;
layout(binding = 2) uniform sampler2D sDeliciousDiamonds;

layout(location = 0) in vec2 ilUV;

layout(location = 0) out vec4 outColor0;

void main()
{
	vec4 bloomSample = texture2D(sBloomTex, ilUV);
	bloomSample.rgb = max(bloomSample.rgb - vec3(sLizBias + sLizScriptBasedBias), vec3(0.0f));
	bloomSample.rgb = pow(bloomSample.rgb, vec3(sLizExponent));
	bloomSample.rgb *= vec3(sLizScale);
	
	//we could just pass this over from the cpu already calculated, or even do it vertex-side, but we're all going to hell anyway
	float sT05 = sin(sTime * 0.5f);
	vec2 uvTime = vec2(sT05, cos(sTime * 1.0f)) * 0.025f;
	float lizFade = 2.0f + sT05 * 1.0f;
	vec4 diamondSample = to_linear_approx(texture2D(sDeliciousDiamonds, ilUV * vec2(0.9f + sT05 * 0.1f, 1.0f) + uvTime));
	diamondSample.rgb = diamondSample.rgb * lizFade;
	bloomSample.rgb *= diamondSample.rgb;
	
	vec4 srcSample = to_linear_approx(texture2D(sScreenTex, ilUV));
	
	float lStar = rgb_to_lightness(srcSample.rgb);
	lStar *= lStar; //square it for some contrast
	lStar *= lStar; //what the hell, let's do it again
	srcSample.rgb = lerp(srcSample.rgb, vec3(lStar, lStar, lStar), vec3(sDesaturateAmount2));
	
	srcSample.rgb = min(srcSample.rgb + bloomSample.rgb, vec3(1.0f));
	
	outColor0 = to_gamma_approx(srcSample);
}
