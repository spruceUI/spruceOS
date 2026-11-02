// Copyright (c) 2026 Magnominus
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// armGBA's LCD Grid for RetroArch's gl driver; armgba-lcd.slang says what it draws.

#pragma parameter GAP_SHARE "Gap Width (Share of a Pixel)" 0.15 0.0 0.5 0.01
#pragma parameter GAP_ACROSS "Gap Strength Between Columns" 0.75 0.0 1.0 0.05
#pragma parameter GAP_DOWN "Gap Strength Between Rows" 0.75 0.0 1.0 0.05
#pragma parameter GAP_RED "Gap Color Red" 0.0 0.0 255.0 1.0
#pragma parameter GAP_GREEN "Gap Color Green" 0.0 0.0 255.0 1.0
#pragma parameter GAP_BLUE "Gap Color Blue" 0.0 0.0 255.0 1.0
#pragma parameter KEEP_BRIGHTNESS "Keep the Screen's Brightness" 0.0 0.0 1.0 1.0
#pragma parameter UNLIT_RED "Unlit Screen Red" 0.0 0.0 255.0 1.0
#pragma parameter UNLIT_GREEN "Unlit Screen Green" 0.0 0.0 255.0 1.0
#pragma parameter UNLIT_BLUE "Unlit Screen Blue" 0.0 0.0 255.0 1.0
#pragma parameter SHADOW "Pixel Shadow" 0.0 0.0 0.5 0.01
#pragma parameter SHADOW_WAY "Pixel Shadow Way (Up, then Clockwise)" 4.0 1.0 8.0 1.0
#pragma parameter SHADOW_DISTANCE "Pixel Shadow Distance (Dots)" 1.5 0.5 2.5 0.5

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#endif

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
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
uniform COMPAT_PRECISION float GAP_SHARE;
uniform COMPAT_PRECISION float GAP_ACROSS;
uniform COMPAT_PRECISION float GAP_DOWN;
uniform COMPAT_PRECISION float GAP_RED;
uniform COMPAT_PRECISION float GAP_GREEN;
uniform COMPAT_PRECISION float GAP_BLUE;
uniform COMPAT_PRECISION float KEEP_BRIGHTNESS;
uniform COMPAT_PRECISION float UNLIT_RED;
uniform COMPAT_PRECISION float UNLIT_GREEN;
uniform COMPAT_PRECISION float UNLIT_BLUE;
uniform COMPAT_PRECISION float SHADOW;
uniform COMPAT_PRECISION float SHADOW_WAY;
uniform COMPAT_PRECISION float SHADOW_DISTANCE;
#else
#define GAP_SHARE 0.15
#define GAP_ACROSS 0.75
#define GAP_DOWN 0.75
#define GAP_RED 0.0
#define GAP_GREEN 0.0
#define GAP_BLUE 0.0
#define KEEP_BRIGHTNESS 0.0
#define UNLIT_RED 0.0
#define UNLIT_GREEN 0.0
#define UNLIT_BLUE 0.0
#define SHADOW 0.0
#define SHADOW_WAY 4.0
#define SHADOW_DISTANCE 1.5
#endif

// The share of a tent two output pixels wide, centered on 0, that lies below u output pixels.
float tentBelow(float u) {
	u = clamp(u, -1.0, 1.0);
	return u < 0.0 ? (u + 1.0) * (u + 1.0) * 0.5 : 1.0 - (1.0 - u) * (1.0 - u) * 0.5;
}

// How much of the gaps at the edges either side of p an output pixel, size wide in dots, centered at
// p, sees through a tent two output pixels wide: each gap spreads over the same two pixels wherever it
// lands, so lines under a pixel wide stay even instead of some looking darker.
float gapCoverage(float p, float size) {
	float halfGap = GAP_SHARE * 0.5;
	float below = floor(p) - p;
	float above = below + 1.0;
	return min(tentBelow((below + halfGap) / size) - tentBelow((below - halfGap) / size) +
	           tentBelow((above + halfGap) / size) - tentBelow((above - halfGap) / size), 1.0);
}

// How strongly the grid shows, a dot being pitch output pixels wide, as lcd.h's libretroLcdFade: a
// tenth of the photos' darkness for each, all of it from 10 on. A gap under a pixel wide lands
// unevenly; fainter, it reads as the screen's texture rather than as lines.
float gridFade(float pitch) {
	return clamp(pitch * 0.1, 0.0, 1.0);
}

// sRGB to linear light, and back.
vec3 toLinear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 fromLinear(vec3 l) {
	return mix(l * 12.92, 1.055 * pow(l, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, l));
}

// Luminance in linear light: the light a pixel keeps from the reflector.
float level(vec3 c) {
	return dot(toLinear(c), vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	vec2 at = TEX0.xy * TextureSize;
	vec2 size = InputSize / OutputSize;
	vec3 color = COMPAT_TEXTURE(Texture, (floor(at) + 0.5) / TextureSize).rgb;
	vec3 gap = vec3(GAP_RED, GAP_GREEN, GAP_BLUE) / 255.0;
	float fade = gridFade(1.0 / max(size.x, size.y));
	float across = gapCoverage(at.x, size.x) * GAP_ACROSS * fade;
	float down = gapCoverage(at.y, size.y) * GAP_DOWN * fade;
	float covered = across + down - across * down;
	vec3 unlit = vec3(UNLIT_RED, UNLIT_GREEN, UNLIT_BLUE) / 255.0;
	if (KEEP_BRIGHTNESS > 0.5) {
		// The pixel set, in linear light, so its square with the gaps around it averages the color it
		// had: the Game Boy screens' colors are measured that way. Beside a pixel too dark for the gap,
		// the gaps darken; on a black matrix, beside one too bright, they lighten.
		float acrossAll = GAP_SHARE * GAP_ACROSS * fade, downAll = GAP_SHARE * GAP_DOWN * fade;
		float shown = max(acrossAll + downAll - acrossAll * downAll, 0.0001);
		vec3 want = toLinear(color);
		vec3 lit = toLinear(gap);
		vec3 inside = (want - shown * lit) / (1.0 - shown);
		lit = mix(lit, want / shown, step(inside, vec3(0.0)));
		if (level(unlit) == 0.0) {
			lit = mix(lit, (want - (1.0 - shown)) / shown, step(vec3(1.0), inside));
		}
		color = fromLinear(mix(clamp(inside, 0.0, 1.0), clamp(lit, 0.0, 1.0), covered));
	} else {
		color = mix(color, gap, covered);
	}
	if (SHADOW > 0.0) {
		float way = (SHADOW_WAY - 1.0) * 0.785398;
		vec2 toward = vec2(sin(way), -cos(way)) * SHADOW_DISTANCE;
		vec3 caster = COMPAT_TEXTURE(Texture, (at - toward) / TextureSize).rgb;
		float start = level(unlit) * 0.9375;
		float dark = clamp((start - level(caster)) / max(start, 0.001), 0.0, 1.0);
		color *= 1.0 - SHADOW * dark;
	}
	FragColor = vec4(color, 1.0);
}
#endif
