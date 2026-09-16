shader_type spatial;
render_mode cull_disabled;

// Corner flag cloth - realistic fluttering fabric.
//
// The cloth is clamped to the mast at UV.x = 0 (the hoist) and free at UV.x = 1 (the tip).
// Displacement is therefore scaled by an anchor envelope that vanishes at the hoist, so the
// fabric stays physically attached to the pole while the trailing edge whips in the wind.
//
// Motion is built from three stacked wave bands (primary gust wave, high-frequency flutter,
// vertical ripple) plus gravity sag and chord foreshortening, which is what makes real flags
// read as fabric instead of a swinging board. Normals are recomputed from the displaced
// surface so light ripples across every fold.

uniform vec4 flag_color : source_color = vec4(0.9, 0.12, 0.1, 1.0);
uniform vec4 trim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float wind_strength = 0.045;  // base out-of-plane amplitude (metres)
uniform float wind_speed = 8.0;       // primary wave travel speed
uniform float wave_freq = 12.0;       // primary wave cycles across the cloth
uniform float flutter_freq = 26.0;    // high-frequency flutter cycles
uniform float flutter_amount = 0.35;  // flutter amplitude relative to the primary wave
uniform float ripple_freq = 9.0;      // vertical ripple cycles
uniform float ripple_amount = 0.25;   // vertical ripple amplitude relative to the wave
uniform float sag_amount = 0.03;      // gravity droop of the free corner
uniform float gust_speed = 2.2;       // slow lull/gust envelope frequency

varying vec2 v_uv;
varying vec3 v_world_pos;

void vertex() {
	v_uv = UV;
	float u = UV.x;  // 0 at the hoist, 1 at the free tip
	float v = UV.y;  // across the flag height

	// Clamp to the mast: no displacement at u = 0, full motion at the tip.
	float anchor = u * u;

	// Slow gust envelope so the flag alternates between lulls and strong flapping.
	float gust = 0.65 + 0.35 * sin(TIME * gust_speed + u * 2.0);

	// Primary travelling wave: ripples run from the mast toward the tip.
	float phase = u * wave_freq - TIME * wind_speed;
	float wave = sin(phase);

	// Secondary high-frequency flutter, offset by v so the top and bottom edges
	// are out of phase and the trailing edge twists instead of sliding sideways.
	float fphase = u * flutter_freq - TIME * wind_speed * 1.9 + v * 5.5;
	float flutter = sin(fphase) * flutter_amount;

	float amp = wind_strength * anchor * gust;

	// Out-of-plane billowing
	VERTEX.z += (wave + flutter) * amp;

	// Vertical ripple along the trailing edge
	VERTEX.y += sin(u * ripple_freq - TIME * wind_speed * 0.8 + v * 2.0) * ripple_amount * amp;

	// Gravity sag of the unsupported free corner
	VERTEX.y -= sag_amount * anchor;

	// Chord foreshortening: real cloth cannot stretch, so as it folds out of plane
	// it pulls back toward the mast.
	VERTEX.x -= (1.0 - cos(phase)) * amp * 0.45;

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = flag_color.rgb;

	// Thin white trim along the top and bottom edges
	float edge = min(v_uv.y, 1.0 - v_uv.y);
	col = mix(trim_color.rgb, col, smoothstep(0.0, 0.06, edge));

	// Slight darkening in the deep folds so the creases read even in flat light
	float fold = abs(sin(v_uv.x * wave_freq - TIME * wind_speed));
	col *= 0.86 + 0.14 * fold;

	// Recompute the normal from the displaced surface so specular light ripples
	// across the waves instead of the flag looking like flat paper.
	vec3 dx = dFdx(v_world_pos);
	vec3 dy = dFdy(v_world_pos);
	vec3 n = cross(dx, dy);
	if (dot(n, n) > 1e-12) {
		NORMAL = normalize((INV_VIEW_MATRIX * vec4(normalize(n), 0.0)).xyz);
	}

	ALBEDO = col;
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
}
