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

layout(binding = 2) uniform sampler2D Source;

layout(location = 0) in vec2 texCoord;
layout(location = 1) in vec4 t1;
layout(location = 2) in vec4 t2;
layout(location = 3) in vec4 t3;
layout(location = 4) in vec4 t4;
layout(location = 5) in vec4 t5;
layout(location = 6) in vec4 t6;
layout(location = 7) in vec4 t7;
layout(location = 0) out vec4 FragColor;

vec4 diff(vec4 A, vec4 B)
{
    return vec4(notEqual(A, B));
}

vec4 df(vec4 A, vec4 B)
{
    return vec4(abs(A - B));
}

vec4 eq(vec4 A, vec4 B)
{
    vec4 param = A;
    vec4 param_1 = B;
    return step(df(param, param_1), vec4(params.XBR_EQ_THRESHOLD));
}

vec4 neq(vec4 A, vec4 B)
{
    vec4 param = A;
    vec4 param_1 = B;
    return vec4(1.0) - eq(param, param_1);
}

vec4 wd(vec4 a, vec4 b, vec4 c, vec4 d, vec4 e, vec4 f, vec4 g, vec4 h)
{
    vec4 param = a;
    vec4 param_1 = b;
    vec4 param_2 = a;
    vec4 param_3 = c;
    vec4 param_4 = d;
    vec4 param_5 = e;
    vec4 param_6 = d;
    vec4 param_7 = f;
    vec4 param_8 = g;
    vec4 param_9 = h;
    return (((df(param, param_1) + df(param_2, param_3)) + df(param_4, param_5)) + df(param_6, param_7)) + (df(param_8, param_9) * 4.0);
}

vec4 weighted_distance(vec4 a, vec4 b, vec4 c, vec4 d, vec4 e, vec4 f, vec4 g, vec4 h, vec4 i, vec4 j, vec4 k, vec4 l)
{
    vec4 param = a;
    vec4 param_1 = b;
    vec4 param_2 = a;
    vec4 param_3 = c;
    vec4 param_4 = d;
    vec4 param_5 = e;
    vec4 param_6 = d;
    vec4 param_7 = f;
    vec4 param_8 = i;
    vec4 param_9 = j;
    vec4 param_10 = k;
    vec4 param_11 = l;
    vec4 param_12 = g;
    vec4 param_13 = h;
    return (((((df(param, param_1) + df(param_2, param_3)) + df(param_4, param_5)) + df(param_6, param_7)) + df(param_8, param_9)) + df(param_10, param_11)) + (df(param_12, param_13) * 2.0);
}

float c_df(vec3 c1, vec3 c2)
{
    vec3 df_1 = abs(c1 - c2);
    return (df_1.x + df_1.y) + df_1.z;
}

void main()
{
    vec2 fp = fract(texCoord * params.SourceSize.xy);
    vec3 A1 = texture(Source, t1.xw).xyz;
    vec3 B1 = texture(Source, t1.yw).xyz;
    vec3 C1 = texture(Source, t1.zw).xyz;
    vec3 A = texture(Source, t2.xw).xyz;
    vec3 B = texture(Source, t2.yw).xyz;
    vec3 C = texture(Source, t2.zw).xyz;
    vec3 D = texture(Source, t3.xw).xyz;
    vec3 E = texture(Source, t3.yw).xyz;
    vec3 F = texture(Source, t3.zw).xyz;
    vec3 G = texture(Source, t4.xw).xyz;
    vec3 H = texture(Source, t4.yw).xyz;
    vec3 I = texture(Source, t4.zw).xyz;
    vec3 G5 = texture(Source, t5.xw).xyz;
    vec3 H5 = texture(Source, t5.yw).xyz;
    vec3 I5 = texture(Source, t5.zw).xyz;
    vec3 A0 = texture(Source, t6.xy).xyz;
    vec3 D0 = texture(Source, t6.xz).xyz;
    vec3 G0 = texture(Source, t6.xw).xyz;
    vec3 C4 = texture(Source, t7.xy).xyz;
    vec3 F4 = texture(Source, t7.xz).xyz;
    vec3 I4 = texture(Source, t7.xw).xyz;
    vec4 b = vec4(dot(B, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(D, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(H, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(F, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)));
    vec4 c = vec4(dot(C, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(A, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(G, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(I, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)));
    vec4 d = b.yzwx;
    vec4 e = vec4(dot(E, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)));
    vec4 f = b.wxyz;
    vec4 g = c.zwxy;
    vec4 h = b.zwxy;
    vec4 i = c.wxyz;
    float y_weight = params.XBR_Y_WEIGHT;
    vec4 i4;
    vec4 i5;
    vec4 h5;
    if (params.small_details < 0.5)
    {
        i4 = vec4(dot(I4, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(C1, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(A0, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(G5, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)));
        i5 = vec4(dot(I5, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(C4, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(A1, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(G0, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)));
        h5 = vec4(dot(H5, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(F4, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(B1, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)), dot(D0, vec3(14.35200023651123046875, 28.1760005950927734375, 5.4720001220703125)));
    }
    else
    {
        i4 = (vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875) * y_weight) * mat4x3(vec3(I4), vec3(C1), vec3(A0), vec3(G5));
        i5 = (vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875) * y_weight) * mat4x3(vec3(I5), vec3(C4), vec3(A1), vec3(G0));
        h5 = (vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875) * y_weight) * mat4x3(vec3(H5), vec3(F4), vec3(B1), vec3(D0));
    }
    vec4 f4 = h5.yzwx;
    vec4 fx = (vec4(1.0, -1.0, -1.0, 1.0) * fp.y) + (vec4(1.0, 1.0, -1.0, -1.0) * fp.x);
    vec4 fx_l = (vec4(1.0, -1.0, -1.0, 1.0) * fp.y) + (vec4(0.5, 2.0, -0.5, -2.0) * fp.x);
    vec4 fx_u = (vec4(1.0, -1.0, -1.0, 1.0) * fp.y) + (vec4(2.0, 0.5, -2.0, -0.5) * fp.x);
    vec4 param = e;
    vec4 param_1 = f;
    vec4 param_2 = e;
    vec4 param_3 = h;
    vec4 _564 = diff(param, param_1) * diff(param_2, param_3);
    vec4 irlv0 = _564;
    vec4 irlv1 = _564;
    vec4 param_4 = f;
    vec4 param_5 = b;
    vec4 param_6 = f;
    vec4 param_7 = c;
    vec4 param_8 = h;
    vec4 param_9 = d;
    vec4 param_10 = h;
    vec4 param_11 = g;
    vec4 param_12 = e;
    vec4 param_13 = i;
    vec4 param_14 = f;
    vec4 param_15 = f4;
    vec4 param_16 = f;
    vec4 param_17 = i4;
    vec4 param_18 = h;
    vec4 param_19 = h5;
    vec4 param_20 = h;
    vec4 param_21 = i5;
    vec4 param_22 = e;
    vec4 param_23 = g;
    vec4 param_24 = e;
    vec4 param_25 = c;
    irlv1 = irlv0 * (((((neq(param_4, param_5) * neq(param_6, param_7)) + (neq(param_8, param_9) * neq(param_10, param_11))) + (eq(param_12, param_13) * ((neq(param_14, param_15) * neq(param_16, param_17)) + (neq(param_18, param_19) * neq(param_20, param_21))))) + eq(param_22, param_23)) + eq(param_24, param_25));
    vec4 param_26 = e;
    vec4 param_27 = g;
    vec4 param_28 = d;
    vec4 param_29 = g;
    vec4 irlv2l = diff(param_26, param_27) * diff(param_28, param_29);
    vec4 param_30 = e;
    vec4 param_31 = c;
    vec4 param_32 = b;
    vec4 param_33 = c;
    vec4 irlv2u = diff(param_30, param_31) * diff(param_32, param_33);
    vec4 fx45i = clamp((((fx + vec4(0.3333333432674407958984375)) - vec4(1.5, 0.5, -0.5, 0.5)) - vec4(0.25)) / vec4(0.666666686534881591796875), vec4(0.0), vec4(1.0));
    vec4 fx45 = clamp(((fx + vec4(0.3333333432674407958984375)) - vec4(1.5, 0.5, -0.5, 0.5)) / vec4(0.666666686534881591796875), vec4(0.0), vec4(1.0));
    vec4 fx30 = clamp(((fx_l + vec4(0.16666667163372039794921875, 0.3333333432674407958984375, 0.16666667163372039794921875, 0.3333333432674407958984375)) - vec4(1.0, 1.0, -0.5, 0.0)) / vec4(0.3333333432674407958984375, 0.666666686534881591796875, 0.3333333432674407958984375, 0.666666686534881591796875), vec4(0.0), vec4(1.0));
    vec4 fx60 = clamp(((fx_u + vec4(0.3333333432674407958984375, 0.16666667163372039794921875, 0.3333333432674407958984375, 0.16666667163372039794921875)) - vec4(2.0, 0.0, -1.0, 0.5)) / vec4(0.666666686534881591796875, 0.3333333432674407958984375, 0.666666686534881591796875, 0.3333333432674407958984375), vec4(0.0), vec4(1.0));
    vec4 wd1;
    vec4 wd2;
    if (params.small_details < 0.5)
    {
        vec4 param_34 = e;
        vec4 param_35 = c;
        vec4 param_36 = g;
        vec4 param_37 = i;
        vec4 param_38 = h5;
        vec4 param_39 = f4;
        vec4 param_40 = h;
        vec4 param_41 = f;
        wd1 = wd(param_34, param_35, param_36, param_37, param_38, param_39, param_40, param_41);
        vec4 param_42 = h;
        vec4 param_43 = d;
        vec4 param_44 = i5;
        vec4 param_45 = f;
        vec4 param_46 = i4;
        vec4 param_47 = b;
        vec4 param_48 = e;
        vec4 param_49 = i;
        wd2 = wd(param_42, param_43, param_44, param_45, param_46, param_47, param_48, param_49);
    }
    else
    {
        vec4 param_50 = e;
        vec4 param_51 = c;
        vec4 param_52 = g;
        vec4 param_53 = i;
        vec4 param_54 = f4;
        vec4 param_55 = h5;
        vec4 param_56 = h;
        vec4 param_57 = f;
        vec4 param_58 = b;
        vec4 param_59 = d;
        vec4 param_60 = i4;
        vec4 param_61 = i5;
        wd1 = weighted_distance(param_50, param_51, param_52, param_53, param_54, param_55, param_56, param_57, param_58, param_59, param_60, param_61);
        vec4 param_62 = h;
        vec4 param_63 = d;
        vec4 param_64 = i5;
        vec4 param_65 = f;
        vec4 param_66 = b;
        vec4 param_67 = i4;
        vec4 param_68 = e;
        vec4 param_69 = i;
        vec4 param_70 = g;
        vec4 param_71 = h5;
        vec4 param_72 = c;
        vec4 param_73 = f4;
        wd2 = weighted_distance(param_62, param_63, param_64, param_65, param_66, param_67, param_68, param_69, param_70, param_71, param_72, param_73);
    }
    vec4 edri = step(wd1, wd2) * irlv0;
    vec4 edr = step(wd1 + vec4(0.100000001490116119384765625), wd2) * step(vec4(0.5), irlv1);
    vec4 param_74 = f;
    vec4 param_75 = g;
    vec4 param_76 = h;
    vec4 param_77 = c;
    vec4 edr_l = (step(df(param_74, param_75) * params.XBR_LV2_COEFFICIENT, df(param_76, param_77)) * irlv2l) * edr;
    vec4 param_78 = h;
    vec4 param_79 = c;
    vec4 param_80 = f;
    vec4 param_81 = g;
    vec4 edr_u = (step(df(param_78, param_79) * params.XBR_LV2_COEFFICIENT, df(param_80, param_81)) * irlv2u) * edr;
    fx45 = edr * fx45;
    fx30 = edr_l * fx30;
    fx60 = edr_u * fx60;
    fx45i = edri * fx45i;
    vec4 param_82 = e;
    vec4 param_83 = f;
    vec4 param_84 = e;
    vec4 param_85 = h;
    vec4 px = step(df(param_82, param_83), df(param_84, param_85));
    vec4 maximos = max(max(fx30, fx60), max(fx45, fx45i));
    vec3 res1 = E;
    res1 = mix(res1, mix(H, F, vec3(px.x)), vec3(maximos.x));
    res1 = mix(res1, mix(B, D, vec3(px.z)), vec3(maximos.z));
    vec3 res2 = E;
    res2 = mix(res2, mix(F, B, vec3(px.y)), vec3(maximos.y));
    res2 = mix(res2, mix(D, H, vec3(px.w)), vec3(maximos.w));
    vec3 param_86 = E;
    vec3 param_87 = res1;
    vec3 param_88 = E;
    vec3 param_89 = res2;
    vec3 res = mix(res1, res2, vec3(step(c_df(param_86, param_87), c_df(param_88, param_89))));
    FragColor = vec4(res, 1.0);
}

