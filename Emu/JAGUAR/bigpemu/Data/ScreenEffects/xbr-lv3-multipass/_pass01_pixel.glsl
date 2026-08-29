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

layout(binding = 3) uniform sampler2D Original;
layout(binding = 2) uniform sampler2D Source;

layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in vec4 t1;
layout(location = 2) in vec2 delta;
layout(location = 0) out vec4 FragColor;

float remapFrom01(float v, float high)
{
    return (high * v) + 0.5;
}

vec4 unpack_info(inout float i)
{
    float _27 = i;
    float _30 = modf(_27 / 2.0, i);
    vec4 info;
    info.x = floor(_30 + 0.5);
    float _36 = i;
    float _38 = modf(_36 / 2.0, i);
    info.y = floor(_38 + 0.5);
    float _43 = i;
    float _45 = modf(_43 / 2.0, i);
    info.z = floor(_45 + 0.5);
    info.w = i;
    return info;
}

void main()
{
    vec2 pos = fract(vTexCoord * params.SourceSize.xy) - vec2(0.5);
    vec2 dir = sign(pos);
    vec2 g1 = dir * ((t1.zw * clamp((-dir.y) * dir.x, 0.0, 1.0)) + (t1.xy * clamp(dir.y * dir.x, 0.0, 1.0)));
    vec2 g2 = dir * ((t1.zw * clamp(dir.y * dir.x, 0.0, 1.0)) + (t1.xy * clamp((-dir.y) * dir.x, 0.0, 1.0)));
    vec3 F = texture(Original, vTexCoord + g1).xyz;
    vec3 B = texture(Original, vTexCoord - g2).xyz;
    vec3 D = texture(Original, vTexCoord - g1).xyz;
    vec3 H = texture(Original, vTexCoord + g2).xyz;
    vec3 E = texture(Original, vTexCoord).xyz;
    vec3 F4 = texture(Original, vTexCoord + (g1 * 2.0)).xyz;
    vec3 I = texture(Original, (vTexCoord + g1) + g2).xyz;
    vec3 H5 = texture(Original, vTexCoord + (g2 * 2.0)).xyz;
    vec4 icomp = floor(clamp(mat2x4(vec4(1.0, 1.0, -1.0, -1.0), vec4(1.0, -1.0, -1.0, 1.0)) * dir, vec4(0.0), vec4(1.0)) + vec4(0.5));
    float param = dot(texture(Source, vTexCoord), icomp);
    float param_1 = 255.0;
    float info = remapFrom01(param, param_1);
    float param_2 = dot(texture(Source, vTexCoord + g1), icomp);
    float param_3 = 255.0;
    float info_nr = remapFrom01(param_2, param_3);
    float param_4 = dot(texture(Source, vTexCoord + g2), icomp);
    float param_5 = 255.0;
    float info_nd = remapFrom01(param_4, param_5);
    float _239 = info;
    float _241 = modf(_239 / 2.0, info);
    float _242 = info;
    float _244 = modf(_242 / 2.0, info);
    float _246 = info;
    float _248 = modf(_246 / 2.0, info);
    vec2 px;
    px.x = floor(_248 + 0.5);
    float _252 = info;
    float _254 = modf(_252 / 2.0, info);
    px.y = floor(_254 + 0.5);
    float param_6 = info;
    vec4 _261 = unpack_info(param_6);
    vec4 flags = _261;
    float _263 = info_nr;
    float _265 = modf(_263 / 2.0, info_nr);
    float edr3_nrl = floor(_265 + 0.5);
    float _268 = info_nr;
    float _270 = modf(_268 / 2.0, info_nr);
    float _271 = info_nr;
    float _273 = modf(_271 / 2.0, info_nr);
    float _275 = info_nr;
    float _277 = modf(_275 / 2.0, info_nr);
    float pxr = floor(_277 + 0.5);
    float _280 = info_nd;
    float _282 = modf(_280 / 2.0, info_nd);
    float _284 = info_nd;
    float _286 = modf(_284 / 2.0, info_nd);
    float edr3_ndu = floor(_286 + 0.5);
    float _289 = info_nd;
    float _291 = modf(_289 / 2.0, info_nd);
    float _293 = info_nd;
    float _295 = modf(_293 / 2.0, info_nd);
    float pxd = floor(_295 + 0.5);
    float aux = floor(dot(vec4(8.0, 4.0, 2.0, 1.0), flags) + 0.5);
    vec3 slep;
    if (aux >= 6.0)
    {
        vec3 _315;
        if (aux == 6.0)
        {
            _315 = vec3(-1.0, 2.0, 0.5);
        }
        else
        {
            vec3 _323;
            if (aux == 7.0)
            {
                _323 = vec3(2.0, -1.0, 0.5);
            }
            else
            {
                vec3 _330;
                if (aux == 8.0)
                {
                    _330 = vec3(-1.0, 3.0, 0.5);
                }
                else
                {
                    vec3 _339;
                    if (aux == 9.0)
                    {
                        _339 = vec3(3.0, -1.0, 0.5);
                    }
                    else
                    {
                        _339 = (aux == 10.0) ? vec3(3.0, 1.0, 1.5) : vec3(1.0, 3.0, 1.5);
                    }
                    _330 = _339;
                }
                _323 = _330;
            }
            _315 = _323;
        }
        slep = _315;
    }
    else
    {
        vec3 _358;
        if (aux == 0.0)
        {
            _358 = vec3(1.0, 1.0, 0.75);
        }
        else
        {
            vec3 _366;
            if (aux == 1.0)
            {
                _366 = vec3(1.0, 1.0, 0.5);
            }
            else
            {
                vec3 _373;
                if (aux == 2.0)
                {
                    _373 = vec3(2.0, 1.0, 0.5);
                }
                else
                {
                    vec3 _380;
                    if (aux == 3.0)
                    {
                        _380 = vec3(1.0, 2.0, 0.5);
                    }
                    else
                    {
                        _380 = (aux == 4.0) ? vec3(3.0, 1.0, 0.5) : vec3(1.0, 3.0, 0.5);
                    }
                    _373 = _380;
                }
                _366 = _373;
            }
            _358 = _366;
        }
        slep = _358;
    }
    vec2 _401;
    if ((dir.x * dir.y) > 0.0)
    {
        _401 = abs(pos);
    }
    else
    {
        _401 = abs(pos.yx);
    }
    vec2 fp = _401;
    vec3 fp1 = vec3(fp.yx, -1.0);
    vec3 color = E;
    float fx;
    if (aux < 10.0)
    {
        fx = clamp((dot(fp1, slep) / (2.0 * delta.x)) + 0.5, 0.0, 1.0);
        color = mix(E, mix(mix(H, F, vec3(px.y)), mix(D, B, vec3(px.y)), vec3(px.x)), vec3(fx));
    }
    else
    {
        if (edr3_nrl == 1.0)
        {
            fx = clamp((dot(fp1, vec3(3.0, 1.0, 1.5)) / (2.0 * delta.x)) + 0.5, 0.0, 1.0);
            color = mix(E, mix(I, F4, vec3(pxr)), vec3(fx));
        }
        else
        {
            if (edr3_ndu == 1.0)
            {
                fx = clamp((dot(fp1, vec3(1.0, 3.0, 1.5)) / (2.0 * delta.x)) + 0.5, 0.0, 1.0);
                color = mix(E, mix(H5, I, vec3(pxd)), vec3(fx));
            }
        }
    }
    FragColor = vec4(color, 1.0);
}

