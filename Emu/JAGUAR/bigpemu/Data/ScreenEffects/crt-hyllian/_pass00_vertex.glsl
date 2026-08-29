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

layout(location = 0) in vec4 Position;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) in vec2 TexCoord;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
}

