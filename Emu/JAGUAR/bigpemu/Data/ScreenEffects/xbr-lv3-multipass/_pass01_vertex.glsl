#version 430


//This file has been auto-generated from 'xbr-lv3-pass1' by author 'Hyllian'. Original license and copyright:

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
};

uniform Push params;

layout(location = 0) in vec4 Position;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) in vec2 TexCoord;
layout(location = 1) out vec4 t1;
layout(location = 2) out vec2 delta;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord * 1.00039994716644287109375;
    vec2 ps = vec2(1.0 / params.OriginalSize.x, 1.0 / params.OriginalSize.y);
    float dx = ps.x;
    float dy = ps.y;
    t1 = vec4(dx, 0.0, 0.0, dy);
    delta = vec2(params.SourceSize.x / params.OutputSize.x, (0.5 * params.SourceSize.x) / params.OutputSize.x);
}

