// crt-mini v5 - scanlines and an RGB mask.
// -----------------------------------------------------------------------------
// Author:  sinedied
// Licence: MIT - Copyright (c) 2026 sinedied
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions: the above copyright
// notice and this permission notice shall be included in all copies or
// substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
// WITHOUT WARRANTY OF ANY KIND.
// -----------------------------------------------------------------------------
// PARAMETERS
//
//   cp_scanlines   0.00 - 1.00  Scanline visibility. 0 disables them.
//   cp_rgb_mask    0.00 - 1.00  RGB mask visibility. 0 disables it.
//   cp_mask_type   0 / 1 / 2    Off, aperture grille, slot grille.
//   cp_mask_size   0.25 - 2.00  Mask triads per source pixel.
//   cp_min_pitch   2.00 - 6.00  Smallest pattern pitch, in output pixels.
//   cp_brightness  0.25 - 4.00  Output gain. 1.00 disables it.
//   cp_gamma       0.50 - 2.00  Output gamma. 1.00 disables it.
// -----------------------------------------------------------------------------
// A CRT look: soft scanlines and an RGB shadow mask. Reads like a small tube
// TV, and neither pattern beats against the pixel grid at any scale.
//
// Notes:
// - At min. pitch 2.00 the mask becomes 2 colours: use 2.50 or more to keep
//   the triads visible.
// - Brightness above 1.00 clips, may create pattern artifacts against the
//   pixel grid unless the output is an integer scale.
// - For screen curvature, add unflat-mini after this one.

#pragma parameter cp_scanlines  "Scanline visibility"        0.60 0.00 1.00 0.05
#pragma parameter cp_rgb_mask   "RGB mask visibility"        0.20 0.00 1.00 0.05
#pragma parameter cp_mask_type  "Mask 0=off 1=grille 2=slot" 1.00 0.00 2.00 1.00
#pragma parameter cp_mask_size  "Mask triads per pixel"      1.00 0.25 2.00 0.25
#pragma parameter cp_min_pitch  "Min. pitch in px"           3.00 2.00 6.00 0.25
#pragma parameter cp_brightness "Brightness"                 1.25 0.25 4.00 0.05
#pragma parameter cp_gamma      "Gamma"                      1.00 0.50 2.00 0.05

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
#define COMPAT_PRECISION highp
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

#define Source Texture
#define vTexCoord TEX0.xy

#define PI  3.141592654
#define TAU 6.283185307

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float cp_scanlines;
uniform COMPAT_PRECISION float cp_rgb_mask;
uniform COMPAT_PRECISION float cp_mask_type;
uniform COMPAT_PRECISION float cp_mask_size;
uniform COMPAT_PRECISION float cp_brightness;
uniform COMPAT_PRECISION float cp_min_pitch;
uniform COMPAT_PRECISION float cp_gamma;
#else
#define cp_scanlines 0.60
#define cp_rgb_mask 0.20
#define cp_mask_type 1.00
#define cp_mask_size 1.00
#define cp_brightness 1.25
#define cp_min_pitch 3.00
#define cp_gamma 1.00
#endif

// Average of a unit sinusoid of frequency f, in cycles per output pixel, over
// one pixel-wide box. Reaches zero at one cycle per pixel.
float boxSinc(float f)
{
    float x = PI * max(f, 1e-4);
    return sin(x) / x;
}

// Nothing above Nyquist can be drawn, so fade the pattern out entirely there -
// amplitude and darkening together, leaving no uniform dimming behind.
float nyquistFade(float f)
{
    return 1.0 - smoothstep(0.34, 0.5, f);
}

void main()
{
    vec2 uv = vTexCoord;

    // Straight through: behind a scaler this is 1:1 and exact.
    vec3 color = COMPAT_TEXTURE(Source, uv).rgb;

    // The base is clamped because pow(0, g) is undefined and returns NaN on
    // real drivers. 1e-8, not 1e-5, which would lift pure black to 1/255.
    if (abs(cp_gamma - 1.0) > 0.001) {
        color = pow(max(color, 1e-8), vec3(cp_gamma));
    }

    float scanSrcPitch = OutputSize.y / max(InputSize.y, 1.0);
    float scanPitch    = max(scanSrcPitch, cp_min_pitch);
    float scanLocked   = (1.0 - smoothstep(cp_min_pitch * 1.001, cp_min_pitch * 1.02, scanSrcPitch)) ;
    float scanFreq     = 1.0 / scanPitch;

    // Holds the pattern to one cycle per source line, and keeps this uniform
    // across the draw.
    float scanLocal    = scanFreq;

    float scanAmp = cp_scanlines * mix(nyquistFade(scanLocal), 1.0, scanLocked);
    float scanAC  = 0.5 * scanAmp * mix(boxSinc(scanLocal), 1.0, scanLocked);

    float scan = 1.0;
    if (scanAmp > 0.0) {
        float y = uv.y * OutputSize.y - 0.5 * scanLocked;
        scan = (1.0 - 0.5 * scanAmp) - scanAC * cos(TAU * fract(y * scanFreq));
    }

    float maskSrcPitch = OutputSize.x / max(InputSize.x * cp_mask_size, 1.0);
    float maskPitch    = max(maskSrcPitch, cp_min_pitch);
    float maskLocked   = (1.0 - smoothstep(cp_min_pitch * 1.001, cp_min_pitch * 1.02, maskSrcPitch)) ;
    float maskFreq     = 1.0 / maskPitch;
    float maskLocal    = maskFreq;

    float maskAmp = cp_rgb_mask * mix(nyquistFade(maskLocal), 1.0, maskLocked);

    vec3 mask = vec3(1.0);
    if (maskAmp > 0.0 && cp_mask_type >= 0.5) {
        float x = uv.x * OutputSize.x - 0.5 * maskLocked;
        float phase = x * maskFreq - (1.0 / 6.0);

        if (cp_mask_type >= 1.5) {
            float row = floor((uv.y * OutputSize.y - 0.5 * scanLocked) * scanFreq + 1e-3);
            phase += 0.5 * mod(row, 2.0);
        }

        float dc = 1.0 - 0.5 * maskAmp;
        float ac = 0.5 * maskAmp * mix(boxSinc(maskLocal), 1.0, maskLocked);
        mask.rg = dc + ac * cos(TAU * (fract(phase) - vec2(0.0, 1.0 / 3.0)));
        mask.b  = max(3.0 * dc - mask.r - mask.g, 0.0);
    }

    // Brightness rides the pattern, so the clamp below lands on the product.
    // Clamping the picture instead flattens highlights before the mask shapes
    // them.
    vec3 gain = sqrt(max(mask * (scan * cp_brightness), 0.0));

    FragColor = vec4(clamp(color * gain, 0.0, 1.0), 1.0);
}

#endif
