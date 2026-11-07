// Copyright (c) 2026 Magnominus
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// armGBA's LCD Ghosting and Interlaced Rows for RetroArch's gl driver; armgba-lcd-fade.slang says what
// it draws. The preset's feedback_pass gives it the last frame shown.

#pragma parameter GHOSTING "LCD Ghosting (0 Off, 0.25 to 1)" 1.0 0.0 1.0 0.25
#pragma parameter INTERLACED "Interlaced Rows (Color and Advance)" 0.0 0.0 1.0 1.0
#pragma parameter GHOST_DARKEN "Ghosting: Time to Darken (ms)" 15.0 5.0 200.0 1.0
#pragma parameter GHOST_LIGHTEN "Ghosting: Time to Lighten (ms)" 30.0 5.0 200.0 1.0
#pragma parameter DRIVEN_SHARE "Interlaced Rows: Driven Rows' Share of the Time" 0.8 0.5 1.0 0.05

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 TEX0;

uniform mat4 MVPMatrix;

void main() {
	gl_Position = MVPMatrix * VertexCoord;
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

uniform COMPAT_PRECISION vec2 TextureSize;
uniform int FrameCount;
uniform sampler2D Texture;
uniform sampler2D FeedbackTexture;
COMPAT_VARYING vec4 TEX0;

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float GHOSTING;
uniform COMPAT_PRECISION float INTERLACED;
uniform COMPAT_PRECISION float GHOST_DARKEN;
uniform COMPAT_PRECISION float GHOST_LIGHTEN;
uniform COMPAT_PRECISION float DRIVEN_SHARE;
#else
#define GHOSTING 1.0
#define INTERLACED 0.0
#define GHOST_DARKEN 15.0
#define GHOST_LIGHTEN 30.0
#define DRIVEN_SHARE 0.8
#endif

void main() {
	vec3 now = COMPAT_TEXTURE(Texture, TEX0.xy).rgb;
	vec3 before = COMPAT_TEXTURE(FeedbackTexture, TEX0.xy).rgb;
	bool interlaced = INTERLACED > 0.5;
	if (FrameCount < 2 || (GHOSTING <= 0.0 && !interlaced)) {
		FragColor = vec4(now, 1.0);
		return;
	}
	float row = floor(TEX0.y * TextureSize.y);
	bool weak = interlaced && mod(row + float(FrameCount), 2.0) > 0.5;
	if (GHOSTING <= 0.0) {
		FragColor = vec4(weak ? before : now, 1.0);
		return;
	}
	float scale = !interlaced ? 1.0 : weak ? 1.0 / (2.0 - 1.0 / DRIVEN_SHARE) : DRIVEN_SHARE;
	float frames = 16.743 / GHOSTING / scale;
	float dark = 1.0 - exp(-frames / GHOST_DARKEN);
	float light = 1.0 - exp(-frames / GHOST_LIGHTEN);
	vec3 was = floor(before * 255.0 + 0.5), want = floor(now * 255.0 + 0.5);
	vec3 linearWas = pow(was / 255.0, vec3(2.2)), linearWant = pow(want / 255.0, vec3(2.2));
	vec3 diff = linearWant - linearWas;
	vec3 moved = linearWas + diff * mix(vec3(light), vec3(dark), 1.0 - step(vec3(0.0), diff));
	vec3 next = floor(pow(moved, vec3(1.0 / 2.2)) * 255.0 + 0.5);
	next += sign(want - was) * step(abs(next - was), vec3(0.0)) * step(0.5, abs(want - was));
	FragColor = vec4(next / 255.0, 1.0);
}

#endif
