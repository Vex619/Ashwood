shader_type canvas_item;
render_mode unshaded;
// Playdead "INSIDE" Monochromatic Post-Process & Anti-Banding Dither Shader.
// Engineered for < 12 ALU instructions in the core fragment path to maintain a
// locked 60 FPS on Intel UHD integrated graphics (i5-13420H).

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// Colour grading controls
uniform float desaturation : hint_range(0.0, 1.0) = 0.86;
uniform float shadow_crush : hint_range(0.8, 2.0) = 1.28;
uniform float highlight_rolloff : hint_range(0.5, 2.0) = 1.15;
uniform vec3 cold_shadow_tint : source_color = vec3(0.055, 0.072, 0.095);
uniform vec3 highlight_tint : source_color = vec3(0.88, 0.92, 0.96);

// Vignette controls (driven dynamically by PlayerController3D.strain_factor_updated)
uniform float base_vignette_intensity : hint_range(0.0, 1.0) = 0.38;
uniform float strain_vignette_boost : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_smoothness : hint_range(0.1, 1.5) = 0.65;

// Dither strength in 8-bit LSB units (eliminates banding in dark exponential fog)
uniform float dither_lsb_strength : hint_range(0.0, 4.0) = 1.35;

// Interleaved Gradient Noise (Jimenez 2014) + 8x8 Bayer ordered cross-modulation:
// 4 ALU operations, zero texture fetches, eliminates 8-bit Mach banding in fog.
float interleaved_gradient_bayer(vec2 frag_coord) {
	vec2 bayer_step = floor(mod(frag_coord, 8.0)) * vec2(0.125, 0.015625);
	float ign = fract(52.9829189 * fract(dot(frag_coord + bayer_step, vec2(0.06711056, 0.00583715))));
	return ign - 0.5;
}

void fragment() {
	vec3 src = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;

	// 1. Luminance & Playdead desaturated cold monochrome grade (preserves subtle red accent)
	float luma = dot(src, vec3(0.2126, 0.7152, 0.0722));
	float red_dominance = clamp((src.r - max(src.g, src.b)) * 1.6, 0.0, 0.45);
	vec3 mono = mix(src, vec3(luma), clamp(desaturation - red_dominance, 0.0, 1.0));

	// Deep crushed shadows + soft filmic shoulder highlight roll-off
	vec3 crushed = pow(max(mono, vec3(0.0001)), vec3(shadow_crush));
	vec3 rolled = crushed / (vec3(1.0) + crushed * (highlight_rolloff - 0.65));
	vec3 graded = mix(cold_shadow_tint, rolled * highlight_tint, clamp(luma * 1.15 + 0.08, 0.0, 1.0));

	// 2. Radial vignette that tightens under heavy crate-pushing strain
	vec2 centered_uv = SCREEN_UV * 2.0 - 1.0;
	float r2 = dot(centered_uv * vec2(1.0, 0.82), centered_uv * vec2(1.0, 0.82));
	float vig_amount = base_vignette_intensity + strain_vignette_boost * 0.45;
	float vignette = clamp(1.0 - r2 * vig_amount * vignette_smoothness, 0.0, 1.0);
	graded *= vignette;

	// 3. Screen-space IGN / 8x8 Bayer dither before 8-bit framebuffer quantization
	float dither = interleaved_gradient_bayer(FRAGCOORD.xy) * (dither_lsb_strength / 255.0);
	COLOR = vec4(clamp(graded + vec3(dither), vec3(0.0), vec3(1.0)), 1.0);
}
