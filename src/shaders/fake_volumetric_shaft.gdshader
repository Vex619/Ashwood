shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;
// Low-cost depth-fade volumetric light shaft shader (INSIDE aesthetic).
// Replaces expensive real-time VolumetricFog on Intel UHD integrated graphics.

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec4 beam_color : source_color = vec4(0.62, 0.72, 0.84, 0.14);
uniform float depth_fade_distance : hint_range(0.05, 5.0) = 0.85;
uniform float camera_near_fade : hint_range(0.1, 3.0) = 0.65;
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.2;
uniform float edge_softness : hint_range(0.05, 0.5) = 0.22;

// Dual-octave drifting dust & marsh mist controls
uniform vec2 scroll_velocity_1 = vec2(0.025, 0.06);
uniform vec2 scroll_velocity_2 = vec2(-0.018, 0.035);
uniform float noise_scale : hint_range(1.0, 24.0) = 6.5;
uniform float dust_contrast : hint_range(0.0, 1.0) = 0.42;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	// 1. Soft depth intersection against scene geometry & character
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene_depth = -view_pos.z / view_pos.w;
	float frag_depth = -VERTEX.z;
	float geom_fade = smoothstep(0.0, depth_fade_distance, scene_depth - frag_depth);
	float near_fade = smoothstep(0.1, camera_near_fade, frag_depth);

	// 2. Grazing angle Fresnel attenuation (cull_disabled -> abs(dot))
	float ndotv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fresnel_fade = pow(clamp(ndotv, 0.0, 1.0), fresnel_power);

	// Soft horizontal & vertical beam profile
	float h_edge = smoothstep(0.0, edge_softness, UV.x) * smoothstep(1.0, 1.0 - edge_softness, UV.x);
	float v_falloff = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.35) * smoothstep(0.0, 0.12, UV.y);

	// 3. Dual-octave scrolling dust & marsh mist
	vec2 uv1 = UV * noise_scale + TIME * scroll_velocity_1;
	vec2 uv2 = UV * (noise_scale * 2.15) + TIME * scroll_velocity_2 + vec2(17.3, 9.1);
	float n1 = value_noise(uv1);
	float n2 = value_noise(uv2);
	float mist = mix(1.0, (n1 * 0.65 + n2 * 0.35), dust_contrast);

	float alpha = beam_color.a * geom_fade * near_fade * fresnel_fade * h_edge * v_falloff * mist;
	ALBEDO = beam_color.rgb * alpha;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
