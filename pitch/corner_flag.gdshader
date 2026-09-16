shader_type spatial;
render_mode cull_disabled;

// Corner flag cloth: anchored at the pole (UV.x = 0) and flapping freely toward
// the tip (UV.x = 1). The wind wave amplitude grows toward the free tip so the
// flag reads as flexible cloth rather than a rigid board.

uniform vec4 flag_color : source_color = vec4(0.9, 0.12, 0.1, 1.0);
uniform vec4 trim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wind_strength = 0.05;
uniform float wind_speed = 6.0;
uniform float wave_freq = 7.0;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	// Anchor factor: 0 at the pole, 1 at the free tip (quadratic so it stays taut near the hoist)
	float anchor = UV.x * UV.x;
	float phase = UV.x * wave_freq - TIME * wind_speed;
	// Displace out of the flag plane, growing toward the tip
	VERTEX.z += sin(phase) * wind_strength * anchor;
	// Gentle vertical ripple on the trailing edge
	VERTEX.y += cos(phase * 0.8) * wind_strength * 0.3 * anchor;
}

void fragment() {
	// Shading from the fold gives the cloth depth
	float fold = 0.5 + 0.5 * sin(v_uv.x * wave_freq - TIME * wind_speed);
	vec3 col = flag_color.rgb * (0.72 + 0.4 * fold);
	// Thin white trim along the top and bottom edges
	float edge = min(v_uv.y, 1.0 - v_uv.y);
	col = mix(trim_color.rgb, col, smoothstep(0.0, 0.06, edge));
	ALBEDO = col;
	ROUGHNESS = 0.8;
}
