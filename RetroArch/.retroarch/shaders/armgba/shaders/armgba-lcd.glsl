// Copyright (c) 2026 Magnominus
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// armGBA's LCD Grid for RetroArch's gl driver; armgba-lcd.slang says what it draws.

#pragma parameter PIXEL_GAPS "Pixel Gaps" 1.0 0.0 1.0 1.0
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
#pragma parameter SUBPIXELS "Subpixels (Color and Advance)" 0.0 0.0 1.0 0.1
#pragma parameter SUBPIXEL_ORDER "Subpixel Order (0 RGB, 1 BGR)" 0.0 0.0 1.0 1.0

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
uniform COMPAT_PRECISION float PIXEL_GAPS;
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
uniform COMPAT_PRECISION float SUBPIXELS;
uniform COMPAT_PRECISION float SUBPIXEL_ORDER;
#else
#define PIXEL_GAPS 1.0
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
#define SUBPIXELS 0.0
#define SUBPIXEL_ORDER 0.0
#endif

// How much of the gaps either side output pixel x shows, along one way: n source pixels over m output
// pixels, each gap centered on the output pixel edge where one source pixel gives way to the next (the
// picture's edges too), as wide as the screen's gaps, so that every gap is drawn alike however the
// pixels fall (libretro/lcd.h's libretroLcdEdgeGap, as the core's Fit Screen draws them).
float edgeGap(float x, float n, float m) {
	float pitch = m / n;
	float s = floor((x + 0.5) / pitch + 0.001);
	float first = ceil((s - 0.001) * pitch - 0.5);
	float next = ceil((s + 1.0 - 0.001) * pitch - 0.5);
	float halfGap = GAP_SHARE * pitch * 0.5;
	return min(clamp(halfGap - (x - first), 0.0, 1.0) + clamp(halfGap - (next - x - 1.0), 0.0, 1.0), 1.0);
}

// How strongly the grid shows, a dot being pitch output pixels wide, as lcd.h's libretroLcdFade: none
// at 1x, all of it from 3x on; smaller, a gap is under a pixel wide.
float gridFade(float pitch) {
	return clamp((pitch - 1.0) * 0.5, 0.0, 1.0);
}

// How much of the span from 0 to u dots stripe (0 to 2, from a pixel's left) covers.
float stripeBelow(float u, float stripe) {
	return floor(u) / 3.0 + clamp(fract(u) - stripe / 3.0, 0.0, 1.0 / 3.0);
}

// LCD Subpixels' share of each stripe (red, green, blue) in an output column: column of the taken
// columns a pixel spans, its stripes laid across them as bands, as many as bands.
vec3 stripeShare(float column, float taken, float bands, vec3 stripes) {
	float from = column / taken, to = (column + 1.0) / taken;
	vec3 share = vec3(0.0);
	for (int i = 0; i < 16; ++i) {
		float b = float(i);
		if (b >= bands) {
			break;
		}
		float lo = b / bands, hi = (b + 1.0) / bands;
		float overlap = min(to, hi) - max(from, lo);
		if (overlap > 0.0) {
			vec3 below = vec3(stripeBelow(lo, stripes.r), stripeBelow(lo, stripes.g), stripeBelow(lo, stripes.b));
			vec3 above = vec3(stripeBelow(hi, stripes.r), stripeBelow(hi, stripes.g), stripeBelow(hi, stripes.b));
			share += overlap * bands * (above - below);
		}
	}
	return share / (to - from);
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
	// The pixel shown: the one the output pixel's middle falls in, from the output pixel's column and
	// row, so that a middle on the edge between two goes to the right or lower one, the one LCD
	// Subpixels lays its stripes over.
	vec2 shown = floor((floor(at / size) + 0.5) * size + 0.001);
	vec3 color = COMPAT_TEXTURE(Texture, (shown + 0.5) / TextureSize).rgb;
	vec3 gap = vec3(GAP_RED, GAP_GREEN, GAP_BLUE) / 255.0;
	float gapAcross = GAP_ACROSS * PIXEL_GAPS, gapDown = GAP_DOWN * PIXEL_GAPS;
	float fade = gridFade(1.0 / max(size.x, size.y));
	vec2 pixel = floor(at / size);
	float across = edgeGap(pixel.x, InputSize.x, InputSize.x / size.x) * gapAcross * fade;
	float down = edgeGap(pixel.y, InputSize.y, InputSize.y / size.y) * gapDown * fade;
	float covered = across + down - across * down;
	vec3 unlit = vec3(UNLIT_RED, UNLIT_GREEN, UNLIT_BLUE) / 255.0;
	// LCD Subpixels (libretro/lcd.h): each pixel's stripes across the output columns whose middles fall
	// in it, as bands, as many as the narrowest pixel's columns, so that every pixel shows them in the
	// same colors; mixed over the color in linear light. They fade in from one output pixel a dot to two.
	float pitch = 1.0 / size.x;
	float mixed = SUBPIXELS * clamp(pitch - 1.0, 0.0, 1.0);
	float first = ceil(shown.x * pitch - 0.501);
	float taken = max(ceil((shown.x + 1.0) * pitch - 0.501) - first, 1.0);
	float bands = clamp(floor(pitch + 0.001), 1.0, 16.0);
	vec3 stripes = SUBPIXEL_ORDER > 0.5 ? vec3(2.0, 1.0, 0.0) : vec3(0.0, 1.0, 2.0);
	if (KEEP_BRIGHTNESS > 0.5) {
		// The pixel set, in linear light, so its square with the gaps around it averages the color it
		// had: the Game Boy screens' colors are measured that way. Beside a pixel too dark for the gap,
		// the gaps darken; on a black matrix, beside one too bright, they lighten. With LCD Subpixels,
		// each channel sees the gaps over its own stripe: the blue and red ones at the pixel's edges,
		// the green one between them.
		vec3 acrossAll = vec3(GAP_SHARE * gapAcross * fade);
		if (mixed > 0.0) {
			vec3 light = vec3(0.0), lost = vec3(0.0);
			for (int j = 0; j < 64; ++j) {
				float column = float(j);
				if (column >= taken) {
					break;
				}
				vec3 factor = 1.0 - mixed + mixed * stripeShare(column, taken, bands, stripes);
				light += factor;
				lost += factor * edgeGap(first + column, InputSize.x, InputSize.x / size.x);
			}
			acrossAll = lost / light * gapAcross * fade;
		}
		float downAll = GAP_SHARE * gapDown * fade;
		vec3 gapShown = max(acrossAll + downAll - acrossAll * downAll, 0.0001);
		vec3 want = toLinear(color);
		vec3 lit = toLinear(gap);
		vec3 inside = (want - gapShown * lit) / (1.0 - gapShown);
		lit = mix(lit, want / gapShown, step(inside, vec3(0.0)));
		// On a black matrix, beside a color too bright for it, the gaps lighten, but only until the
		// square is nine tenths of the color, so the grid still shows on white.
		if (level(unlit) == 0.0) {
			lit = mix(lit, clamp((want * 0.9 - (1.0 - gapShown)) / gapShown, 0.0, 1.0), step(vec3(1.0), inside));
		}
		color = fromLinear(mix(clamp(inside, 0.0, 1.0), clamp(lit, 0.0, 1.0), covered));
	} else {
		color = mix(color, gap, covered);
	}
	if (mixed > 0.0) {
		vec3 share = stripeShare(floor(at.x * pitch) - first, taken, bands, stripes);
		color = fromLinear(toLinear(color) * (1.0 - mixed + mixed * share));
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
