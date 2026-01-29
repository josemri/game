shader_type canvas_item;

/* ===== PSX INTENSE POST PROCESS ===== */

/* Internal resolution (lower = chunkier pixels) */
uniform vec2 internal_resolution = vec2(640.0, 480.0);

/* PSX color depth */
uniform float color_levels : hint_range(8.0, 32.0) = 16.0;

/* Dither */
uniform float dither_strength : hint_range(0.0, 2.0) = 1.4;

/* Saturation boost */
uniform float saturation : hint_range(0.5, 2.0) = 1.25;

/* Slight contrast curve */
uniform float contrast : hint_range(0.5, 2.0) = 1.15;

/* Screen */
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

void fragment() {
	/* --- Pixelated UVs --- */
	vec2 uv = SCREEN_UV;
	uv = floor(uv * internal_resolution) / internal_resolution;

	/* Final lit color */
	vec3 col = texture(screen_tex, uv).rgb;

	/* Saturation */
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);

	/* Contrast (simple curve) */
	col = pow(col, vec3(1.0 / contrast));

	/* 4x4 PSX ordered dither */
	int dither[16] = int[16](
		-4,  0, -3,  1,
		 2, -2,  3, -1,
		-3,  1, -4,  0,
		 3, -1,  2, -2
	);

	int x = int(FRAGCOORD.x) & 3;
	int y = int(FRAGCOORD.y) & 3;
	float noise = float(dither[x + y * 4]) / 255.0;

	col += noise * dither_strength;

	/* PSX color quantization */
	col = floor(col * color_levels) / color_levels;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
