// Copyright (c) 2026 Magnominus
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Lower-cost LCD grid approximation for slower GPUs. It keeps pixel gaps and
// approximate brightness compensation, but omits subpixels and pixel shadows.

#pragma parameter PIXEL_GAPS "Pixel Gaps" 1.0 0.0 1.0 1.0
#pragma parameter GAP_SHARE "Gap Width (Share of a Pixel)" 0.15 0.0 0.5 0.01
#pragma parameter GAP_ACROSS "Gap Strength Between Columns" 0.75 0.0 1.0 0.05
#pragma parameter GAP_DOWN "Gap Strength Between Rows" 0.75 0.0 1.0 0.05
#pragma parameter GAP_RED "Gap Color Red" 0.0 0.0 255.0 1.0
#pragma parameter GAP_GREEN "Gap Color Green" 0.0 0.0 255.0 1.0
#pragma parameter GAP_BLUE "Gap Color Blue" 0.0 0.0 255.0 1.0
#pragma parameter KEEP_BRIGHTNESS "Keep the Screen's Brightness (Approximate)" 0.0 0.0 1.0 1.0

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

uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;

#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float PIXEL_GAPS;
uniform COMPAT_PRECISION float GAP_SHARE;
uniform COMPAT_PRECISION float GAP_ACROSS;
uniform COMPAT_PRECISION float GAP_DOWN;
uniform COMPAT_PRECISION float GAP_RED;
uniform COMPAT_PRECISION float GAP_GREEN;
uniform COMPAT_PRECISION float GAP_BLUE;
uniform COMPAT_PRECISION float KEEP_BRIGHTNESS;
#else
#define PIXEL_GAPS 1.0
#define GAP_SHARE 0.15
#define GAP_ACROSS 0.75
#define GAP_DOWN 0.75
#define GAP_RED 0.0
#define GAP_GREEN 0.0
#define GAP_BLUE 0.0
#define KEEP_BRIGHTNESS 0.0
#endif

float gapCoverage(float x, float pitch) {
	// Integrate the periodic gaps over one output pixel without snapping their edges.
	float from = fract(x / pitch + GAP_SHARE * 0.5);
	float to = from + 1.0 / pitch;
	return clamp(pitch * (floor(to) * GAP_SHARE + min(fract(to), GAP_SHARE) - min(from, GAP_SHARE)), 0.0, 1.0);
}

float gridFade(float pitch) {
	return clamp((pitch - 1.0) * 0.5, 0.0, 1.0);
}

void main() {
	vec2 at = TEX0.xy * TextureSize;
	vec2 size = InputSize / OutputSize;
	vec2 shown = floor((floor(at / size) + 0.5) * size + 0.001);
	vec3 color = COMPAT_TEXTURE(Texture, (shown + 0.5) / TextureSize).rgb;
	vec3 gap = vec3(GAP_RED, GAP_GREEN, GAP_BLUE) / 255.0;
	float gapAcross = GAP_ACROSS * PIXEL_GAPS;
	float gapDown = GAP_DOWN * PIXEL_GAPS;
	float fade = gridFade(1.0 / max(size.x, size.y));
	vec2 pixel = floor(at / size);
	float across = gapCoverage(pixel.x, 1.0 / size.x) * gapAcross * fade;
	float down = gapCoverage(pixel.y, 1.0 / size.y) * gapDown * fade;
	float covered = across + down - across * down;
	if (KEEP_BRIGHTNESS > 0.5) {
		float averageAcross = GAP_SHARE * gapAcross * fade;
		float averageDown = GAP_SHARE * gapDown * fade;
		float averageCovered = averageAcross + averageDown - averageAcross * averageDown;
		vec3 inside = clamp((color - gap * averageCovered) / max(1.0 - averageCovered, 0.0001), 0.0, 1.0);
		color = mix(inside, gap, covered);
	} else {
		color = mix(color, gap, covered);
	}
	FragColor = vec4(color, 1.0);
}

#endif
