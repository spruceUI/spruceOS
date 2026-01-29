/*
   Author: rsn8887 (modified by ChatGPT)
   License: Public domain

   4-tone colorization shader for RetroArch
   Originally designed to simulate a Virtual Boy with Super Game Boy–style coloring
*/

// === Palette Parameters ===
#pragma parameter COLOR1_R "Color 1 - R" 0.95 0.0 1.0 0.01
#pragma parameter COLOR1_G "Color 1 - G" 0.75 0.0 1.0 0.01
#pragma parameter COLOR1_B "Color 1 - B" 0.2  0.0 1.0 0.01

#pragma parameter COLOR2_R "Color 2 - R" 0.8  0.0 1.0 0.01
#pragma parameter COLOR2_G "Color 2 - G" 0.1  0.0 1.0 0.01
#pragma parameter COLOR2_B "Color 2 - B" 0.1  0.0 1.0 0.01

#pragma parameter COLOR3_R "Color 3 - R" 0.1  0.0 1.0 0.01
#pragma parameter COLOR3_G "Color 3 - G" 0.2  0.0 1.0 0.01
#pragma parameter COLOR3_B "Color 3 - B" 0.8  0.0 1.0 0.01

#pragma parameter COLOR4_R "Color 4 - R" 0.0  0.0 1.0 0.01
#pragma parameter COLOR4_G "Color 4 - G" 0.0  0.0 1.0 0.01
#pragma parameter COLOR4_B "Color 4 - B" 0.0  0.0 1.0 0.01

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

COMPAT_VARYING vec2 precalc_texel;
COMPAT_VARYING vec2 precalc_scale;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    COL0 = COLOR;
    TEX0.xy = TexCoord.xy;

    vec2 SourceSize = TextureSize;
    vec2 outsize = OutputSize;

    precalc_texel = TEX0.xy * SourceSize;
    precalc_scale = max(floor(outsize / InputSize), vec2(1.0, 1.0));
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

uniform sampler2D Texture;
uniform COMPAT_PRECISION int FrameDirection;
uniform COMPAT_PRECISION int FrameCount;
uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;

uniform float COLOR1_R, COLOR1_G, COLOR1_B;
uniform float COLOR2_R, COLOR2_G, COLOR2_B;
uniform float COLOR3_R, COLOR3_G, COLOR3_B;
uniform float COLOR4_R, COLOR4_G, COLOR4_B;

COMPAT_VARYING vec4 TEX0;
COMPAT_VARYING vec2 precalc_texel;
COMPAT_VARYING vec2 precalc_scale;

void main()
{
    vec2 texel = precalc_texel;
    vec2 scale = precalc_scale;

    vec2 texel_floored = floor(texel);
    vec2 s = fract(texel);
    vec2 region_range = 0.5 - 0.5 / scale;

    vec2 center_dist = s - 0.5;
    vec2 f = (center_dist - clamp(center_dist, -region_range, region_range)) * scale + 0.5;

    vec2 mod_texel = texel_floored + f;

    vec4 res = vec4(COMPAT_TEXTURE(Texture, mod_texel / TextureSize).rgb, 1.0);

    vec3 color1 = vec3(COLOR1_R, COLOR1_G, COLOR1_B);
    vec3 color2 = vec3(COLOR2_R, COLOR2_G, COLOR2_B);
    vec3 color3 = vec3(COLOR3_R, COLOR3_G, COLOR3_B);
    vec3 color4 = vec3(COLOR4_R, COLOR4_G, COLOR4_B);

    if (res.x > 0.85)
        res.rgb = color1;
    else if (res.x > 0.6)
        res.rgb = color2;
    else if (res.x > 0.3)
        res.rgb = color3;
    else
        res.rgb = color4;

    FragColor = res;
}

#endif
