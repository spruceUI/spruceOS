/*
	Fragment shader based on "Improved texture interpolation" by Iñigo Quílez
	Original description: http://www.iquilezles.org/www/articles/texture/texture.htm
	Modified by DariusG for Miyoo A30.
*/

#pragma parameter bri "BRIGHTNESS" 1.0 0.0 2.0 0.05
#pragma parameter sat "SATURATION" 1.0 0.0 3.0 0.05
#pragma parameter gam "GAMMA" 1.0 0.0 3.0 0.05
#pragma parameter rr "RED" 1.0 0.0 2.0 0.01
#pragma parameter gg "GREEN" 1.0 0.0 2.0 0.01
#pragma parameter bb "BLUE" 1.0 0.0 2.0 0.01
 
#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying 
#define COMPAT_ATTRIBUTE attribute 
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 COL0;
COMPAT_VARYING vec4 TEX0;

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;

// vertex compatibility #defines
#define vTexCoord TEX0.xy
#define SourceSize vec4(TextureSize, 1.0 / TextureSize) //either TextureSize or InputSize
#define outsize vec4(OutputSize, 1.0 / OutputSize)

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    COL0 = COLOR;
    TEX0.xy = TexCoord.xy;
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;

// fragment compatibility #defines
#define Source Texture
#define vTexCoord TEX0.xy

#define SourceSize vec4(TextureSize, 1.0 / TextureSize) //either TextureSize or InputSize
#define outsize vec4(OutputSize, 1.0 / OutputSize)

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float bri;
uniform COMPAT_PRECISION float sat;
uniform COMPAT_PRECISION float gam;
uniform COMPAT_PRECISION float rr;
uniform COMPAT_PRECISION float gg;
uniform COMPAT_PRECISION float bb;

#else
#define bri 1.0
#define sat 1.0
#define gam 1.0
#define rr 1.0
#define gg 1.0
#define bb 1.0

#endif

void main()
{
	vec2 p = vTexCoord.xy;

	p = p * SourceSize.xy + vec2(0.5, 0.5);

	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * f * (f * (f * 6.0 - vec2(15.0, 15.0)) + vec2(10.0, 10.0));
	p = i + f;

	p = (p - vec2(0.5, 0.5)) * SourceSize.zw;
	vec4 res = vec4(COMPAT_TEXTURE(Source, p));
    res.rgb = pow(res.rgb, vec3(gam));

	float gray = dot(vec3(0.33),res.rgb);
	res.rgb = mix(vec3(gray), res.rgb, sat);
	res *= bri;
	res.rgb *= vec3(rr,gg,bb);

   // final sum and weight normalization
   FragColor = res;
} 
#endif
