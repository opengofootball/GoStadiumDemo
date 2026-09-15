shader_type spatial;
render_mode cull_disabled;

// EA FC / eFootball style pitch rendered on a SINGLE PlaneMesh.
// Grass + broadcast mowing bands + crisp regulation lines are all composited in one
// surface pass, so there is no separate line geometry and Z-fighting is impossible.
//
// Line mask is sampled with hardware 16x anisotropic filtering and negative LOD bias,
// plus edge-threshold sharpening to prevent distant mipmap blurring from widening the lines.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D pitch_lines_tex : filter_linear_mipmap_anisotropic, hint_default_black;

uniform vec4 grass_tint : source_color = vec4(0.66, 0.9, 0.66, 1.0);
uniform float grass_tile = 6.0;   // metres per grass-texture repeat

// Line mask placement in world space (metres)
uniform vec2 lines_min = vec2(-45.0, -65.0);
uniform vec2 lines_size = vec2(90.0, 130.0);

// Broadcast mowing bands (alternate light/dark turf)
uniform int mow_axis = 1;          // 0 = bands vary along X, 1 = bands vary along Z
uniform float mow_count = 15.0;    // number of bands across the measured axis
uniform float mow_span = 130.0;    // world extent along that axis
uniform float mow_darkness = 0.78; // darker alternate bands

// White markings
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Surface
uniform float roughness_base = 0.86;
uniform float wetness = 0.12;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Grass: tile the authentic texture by world position
	vec2 g_uv = vec2(world_pos.x, world_pos.z) / grass_tile;
	vec3 grass = texture(grass_tex, g_uv).rgb;

	// Broadcast mowing bands: soft sine so edges are gentle, not hard stripes
	float coord = (mow_axis == 0) ? world_pos.x : world_pos.z;
	float band = 0.5 + 0.5 * sin(coord * mow_count * 2.0 * PI / mow_span);
	float shade = mix(mow_darkness, 1.0, band);
	grass *= shade;
	grass *= grass_tint.rgb;

	// Regulation lines mapped from world XZ into the baked mask (0..1)
	vec2 l_uv = (vec2(world_pos.x, world_pos.z) - lines_min) / lines_size;

	// Sample with negative LOD bias (-1.5) to keep mipmaps razor sharp at grazing angles
	vec4 lines = texture(pitch_lines_tex, l_uv, -1.5);

	// Edge-threshold sharpening: removes the wide blurred halo caused by mipmap downsampling
	// so the line stays thin (12 cm) at all viewing distances
	float line_alpha = smoothstep(0.35, 0.75, lines.a);

	vec3 base = mix(grass, line_color.rgb, line_alpha);

	ALBEDO = base;
	ROUGHNESS = clamp(roughness_base - wetness * 0.4, 0.05, 1.0);
	SPECULAR = 0.2 + wetness * 0.7;
}
