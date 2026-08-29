#version 430


//This file has been auto-generated from 'xbr-lv2' by author 'Hyllian'. Original license and copyright:

/*

   Copyright (C) 2011-2015 Hyllian - sergiogdb@gmail.com

   Permission is hereby granted, free of charge, to any person obtaining a
   copy of this software and associated documentation files (the
   "Software"), to deal in the Software without restriction, including
   without limitation the rights to use, copy, modify, merge, publish,
   distribute, sublicense, and/or sell copies of the Software, and to permit
   persons to whom the Software is furnished to do so, subject to the
   following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
   THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
   DEALINGS IN THE SOFTWARE.

*/

layout(binding = 0, std140) uniform UBO
{
    mat4 MVP;
} global;

struct Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
    float XBR_Y_WEIGHT;
    float XBR_EQ_THRESHOLD;
    float XBR_LV1_COEFFICIENT;
    float XBR_LV2_COEFFICIENT;
    float small_details;
};

uniform Push params;

layout(location = 0) in vec4 Position;
layout(location = 0) out vec2 texCoord;
layout(location = 1) in vec2 TexCoord;
layout(location = 1) out vec4 t1;
layout(location = 2) out vec4 t2;
layout(location = 3) out vec4 t3;
layout(location = 4) out vec4 t4;
layout(location = 5) out vec4 t5;
layout(location = 6) out vec4 t6;
layout(location = 7) out vec4 t7;

void main()
{
    gl_Position = global.MVP * Position;
    texCoord = TexCoord;
    float dx = params.SourceSize.z;
    float dy = params.SourceSize.w;
    t1 = TexCoord.xxxy + vec4(-dx, 0.0, dx, (-2.0) * dy);
    t2 = TexCoord.xxxy + vec4(-dx, 0.0, dx, -dy);
    t3 = TexCoord.xxxy + vec4(-dx, 0.0, dx, 0.0);
    t4 = TexCoord.xxxy + vec4(-dx, 0.0, dx, dy);
    t5 = TexCoord.xxxy + vec4(-dx, 0.0, dx, 2.0 * dy);
    t6 = TexCoord.xyyy + vec4((-2.0) * dx, -dy, 0.0, dy);
    t7 = TexCoord.xyyy + vec4(2.0 * dx, -dy, 0.0, dy);
}

