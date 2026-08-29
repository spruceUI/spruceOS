#version 430


//This file has been auto-generated from 'crt-hyllian' by author 'Hyllian'. Original license and copyright:

/*

    Copyright (C) 2011-2016 Hyllian - sergiogdb@gmail.com

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
*/

layout(binding = 0, std140) uniform UBO
{
    mat4 MVP;
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
} global;

struct Push
{
    float PHOSPHOR;
    float VSCANLINES;
    float InputGamma;
    float OutputGamma;
    float SHARPNESS;
    float COLOR_BOOST;
    float RED_BOOST;
    float GREEN_BOOST;
    float BLUE_BOOST;
    float SCANLINES_STRENGTH;
    float BEAM_MIN_WIDTH;
    float BEAM_MAX_WIDTH;
    float CRT_ANTI_RINGING;
};

uniform Push param;

layout(binding = 2) uniform sampler2D Source;

layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
float B;
float C;
mat4 invX;

void main()
{
    B = 0.0;
    C = 0.5;
    invX = mat4(vec4(((-B) - (6.0 * C)) / 6.0, ((3.0 * B) + (12.0 * C)) / 6.0, (((-3.0) * B) - (6.0 * C)) / 6.0, B / 6.0), vec4(((12.0 - (9.0 * B)) - (6.0 * C)) / 6.0, (((-18.0) + (12.0 * B)) + (6.0 * C)) / 6.0, 0.0, (6.0 - (2.0 * B)) / 6.0), vec4((-((12.0 - (9.0 * B)) - (6.0 * C))) / 6.0, ((18.0 - (15.0 * B)) - (12.0 * C)) / 6.0, ((3.0 * B) + (6.0 * C)) / 6.0, B / 6.0), vec4((B + (6.0 * C)) / 6.0, -C, 0.0, 0.0));
    vec2 TextureSize = vec2(param.SHARPNESS * global.SourceSize.x, global.SourceSize.y);
    vec2 dx = mix(vec2(1.0 / TextureSize.x, 0.0), vec2(0.0, 1.0 / TextureSize.y), vec2(param.VSCANLINES));
    vec2 dy = mix(vec2(0.0, 1.0 / TextureSize.y), vec2(1.0 / TextureSize.x, 0.0), vec2(param.VSCANLINES));
    vec2 pix_coord = (vTexCoord * TextureSize) + vec2(-0.5, 0.5);
    vec2 tc = mix((floor(pix_coord) + vec2(0.5)) / TextureSize, (floor(pix_coord) + vec2(1.0, -0.5)) / TextureSize, vec2(param.VSCANLINES));
    vec2 fp = mix(fract(pix_coord), fract(pix_coord.yx), vec2(param.VSCANLINES));
    vec3 c00 = pow(texture(Source, (tc - dx) - dy).xyz, vec3(param.InputGamma, param.InputGamma, param.InputGamma));
    vec3 c01 = pow(texture(Source, tc - dy).xyz, vec3(param.InputGamma, param.InputGamma, param.InputGamma));
    vec3 c02 = pow(texture(Source, (tc + dx) - dy).xyz, vec3(param.InputGamma, param.InputGamma, param.InputGamma));
    vec3 c03 = pow(texture(Source, (tc + (dx * 2.0)) - dy).xyz, vec3(param.InputGamma, param.InputGamma, param.InputGamma));
    vec3 c10 = pow(texture(Source, tc - dx).xyz, vec3(param.InputGamma, param.InputGamma, param.InputGamma));
    vec3 c11 = pow(texture(Source, tc).xyz, vec3(param.InputGamma, param.InputGamma, param.InputGamma));
    vec3 c12 = pow(texture(Source, tc + dx).xyz, vec3(param.InputGamma, param.InputGamma, param.InputGamma));
    vec3 c13 = pow(texture(Source, tc + (dx * 2.0)).xyz, vec3(param.InputGamma, param.InputGamma, param.InputGamma));
    vec3 min_sample = min(min(c01, c11), min(c02, c12));
    vec3 max_sample = max(max(c01, c11), max(c02, c12));
    mat4x3 color_matrix0 = mat4x3(vec3(c00), vec3(c01), vec3(c02), vec3(c03));
    mat4x3 color_matrix1 = mat4x3(vec3(c10), vec3(c11), vec3(c12), vec3(c13));
    vec4 invX_Px = vec4((fp.x * fp.x) * fp.x, fp.x * fp.x, fp.x, 1.0) * invX;
    vec3 color0 = color_matrix0 * invX_Px;
    vec3 color1 = color_matrix1 * invX_Px;
    vec3 aux = color0;
    color0 = clamp(color0, min_sample, max_sample);
    color0 = mix(aux, color0, vec3(param.CRT_ANTI_RINGING));
    aux = color1;
    color1 = clamp(color1, min_sample, max_sample);
    color1 = mix(aux, color1, vec3(param.CRT_ANTI_RINGING));
    float pos0 = fp.y;
    float pos1 = 1.0 - fp.y;
    vec3 lum0 = mix(vec3(param.BEAM_MIN_WIDTH), vec3(param.BEAM_MAX_WIDTH), color0);
    vec3 lum1 = mix(vec3(param.BEAM_MIN_WIDTH), vec3(param.BEAM_MAX_WIDTH), color1);
    vec3 d0 = clamp(vec3(pos0) / (lum0 + vec3(1.0000000116860974230803549289703e-07)), vec3(0.0), vec3(1.0));
    vec3 d1 = clamp(vec3(pos1) / (lum1 + vec3(1.0000000116860974230803549289703e-07)), vec3(0.0), vec3(1.0));
    d0 = exp((d0 * ((-10.0) * param.SCANLINES_STRENGTH)) * d0);
    d1 = exp((d1 * ((-10.0) * param.SCANLINES_STRENGTH)) * d1);
    vec3 color = clamp((color0 * d0) + (color1 * d1), vec3(0.0), vec3(1.0));
    color *= (vec3(param.RED_BOOST, param.GREEN_BOOST, param.BLUE_BOOST) * param.COLOR_BOOST);
    float mod_factor = mix(vTexCoord.x * global.OutputSize.x, vTexCoord.y * global.OutputSize.y, param.VSCANLINES);
    vec3 dotMaskWeights = mix(vec3(1.0, 0.699999988079071044921875, 1.0), vec3(0.699999988079071044921875, 1.0, 0.699999988079071044921875), vec3(floor(mod(mod_factor, 2.0))));
    color *= mix(vec3(1.0), dotMaskWeights, vec3(param.PHOSPHOR));
    color = pow(color, vec3(1.0 / param.OutputGamma, 1.0 / param.OutputGamma, 1.0 / param.OutputGamma));
    FragColor = vec4(color, 1.0);
}

