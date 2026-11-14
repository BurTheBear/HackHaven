// ECHO reveal shader: surfaces are black except where a ping's ring passes.
// Ping data comes from global shader parameters set by the Echo autoload.
// Slots 0-3 are the player's pings (radius ~6 = a whisper), 4-7 pebble pings.
// Kept cheap: inactive slots and points the ring hasn't reached return early,
// and textures are only sampled where some light actually reaches.
// Texturing: use_triplanar (cave CSG: world-space tex_floor/tex_wall + normals,
// picked by surface normal), use_albedo_tex (imported props: albedo_tex via UV)
// or use_flat (a plain albedo_color). With none of them on (Listener, phantoms)
// the old texture-less echo_color look is used.
shader_type spatial;
render_mode unshaded, cull_disabled;

global uniform vec4 ping_0;
global uniform vec4 ping_1;
global uniform vec4 ping_2;
global uniform vec4 ping_3;
global uniform vec4 ping_4;
global uniform vec4 ping_5;
global uniform vec4 ping_6;
global uniform vec4 ping_7;
global uniform float ping_radius_0;
global uniform float ping_radius_1;
global uniform float ping_radius_2;
global uniform float ping_radius_3;
global uniform float ping_radius_4;
global uniform float ping_radius_5;
global uniform float ping_radius_6;
global uniform float ping_radius_7;
global uniform vec3 player_pos;
global uniform float step_glow;
global uniform float hint_glow;

uniform vec3 echo_color : source_color = vec3(0.24, 0.96, 1.0);
uniform float ping_speed = 18.0;
uniform float ring_width = 1.2;
uniform float afterglow = 2.0;
uniform float grid_scale = 1.0;
uniform float near_glow = 0.35;
// The afterglow stutters a little as it dies, like a failing light.
uniform float flicker = 0.35;
// Extras below default to OFF so Listener / phantom materials (which don't set
// them) look exactly as before. level.gd switches them on for cave materials.
// Echo memory: a very faint, long-lived trace of what your echoes touched.
uniform float echo_memory = 0.0;
uniform float memory_time = 15.0;
// Always-on floor outline around the player, scaled by Settings.hint_glow.
uniform float floor_hint = 0.0;
// How gold pebble pings look (0 = same color as yours).
uniform float pebble_tint = 0.0;
// Surfaces right next to you stay a little brighter in the afterglow.
uniform float close_boost = 0.0;
// Water: the afterglow ripples outward in rings.
uniform float ripple = 0.0;

// How much the real surface colour is pulled toward echo_color when lit.
uniform float tint = 0.35;
uniform float exposure = 2.2;
uniform float use_triplanar = 0.0;
uniform float use_albedo_tex = 0.0;
uniform float use_flat = 0.0;
uniform float tex_scale = 0.3;
uniform float normal_strength = 1.0;
uniform vec3 albedo_color : source_color = vec3(0.6);
uniform sampler2D tex_floor : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_wall : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nor_floor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D nor_wall : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// 0 turns the world-space grid lines off completely.
uniform float use_grid = 1.0;
// Listener look (ai_listener_body.gd): crimson body with a near-black core,
// sickly pale rim, wet sheen, glowing bright spots, pulse when a ring passes.
// Uses albedo_tex / listener_normal via UV (white / flat when unset).
uniform float listener_look = 0.0;
uniform sampler2D listener_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// 0..1 white-hot hurt flash, and 0..1 death (darken + dissolve).
uniform float hurt_flash = 0.0;
uniform float dying = 0.0;

const vec3 GOLD = vec3(1.0, 0.76, 0.3);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Ring timing (fractions of the ring's travel time T = max_r / ping_speed).
// The ring still reaches max_r at exactly T (distance / ping_speed on average).
const float EASE_B = 0.25;     // gentle ease-out: starts 1.25x fast, ends 0.75x
const float BACK_START = 0.25; // the faint return ring leaves a moment after T
const float BACK_SPEED = 0.8;  // return ring speed (x ping_speed)

// Soft gaussian bump around 0 with width w.
float soft(float x, float w) {
	float k = x / max(w, 0.001);
	return exp(-k * k);
}

// The ring's eased position: for a ring that has travelled `y` (0..1) of its
// way out, how far through its travel TIME it is (0..1). This undoes the
// ease used for the ring radius, so we can tell when the ring passed a point.
float time_fraction_at(float y) {
	if (y >= 1.0) {
		return 1.0;
	}
	float a = 1.0 + EASE_B;
	float root = sqrt(a * a - 4.0 * EASE_B * y);
	return (a - root) / (2.0 * EASE_B);
}

// One ping at `pos`. x = ring, y = afterglow, z = soft leading glow, w = memory.
// One soft ring eases out to max_r and fades there; a faint soft ring then
// drifts back toward the origin. Surfaces brighten gently as the ring passes
// and settle smoothly into the afterglow.
vec4 ping_light(vec3 pos, vec4 p, float max_r, float pebble) {
	if (p.w < 0.0) {
		return vec4(0.0);
	}
	vec3 dv = pos - p.xyz;
	float d = length(dv);
	if (d > max_r * 1.08) {
		return vec4(0.0);
	}
	// t = seconds since the ping, T = how long the ring takes to reach max_r.
	float t = p.w;
	float T = max_r / ping_speed;
	float x = t / T;
	// u = how far past the end the ring is (0 while still travelling).
	float u = max(x - 1.0, 0.0);
	float xc = min(x, 1.0);
	// Current ring radius (eased so it slows down near the end).
	float r = max_r * (xc + EASE_B * xc * (1.0 - xc));
	// > 0: the ring hasn't reached this point yet (nothing else has either).
	float ahead = d - r;
	if (ahead > ring_width * 1.6) {
		return vec4(0.0);
	}
	// Whisper pings (player slots, radius ~6 m) are drawn thinner and dimmer.
	float whisper = (1.0 - pebble) * step(5.5, max_r) * step(max_r, 6.5);
	float thin = mix(1.0, 0.5, whisper);
	float dim = mix(1.0, 0.55, whisper);
	float extra = mix(1.0, 0.7, max(pebble, whisper));
	float edge = 1.0 - smoothstep(max_r * 0.75, max_r * 1.08, d);
	// The ring softly fades out once it has reached max_r.
	float out_amp = 1.0 - smoothstep(0.0, 0.45, u);
	float w = ring_width * thin;
	// Wide soft band: a little tighter in front, a long soft tail behind.
	float band_width = w * 1.5;
	if (ahead > 0.0) {
		band_width = w * 0.6;
	}
	float ring = soft(ahead, band_width) * out_amp;
	// The leading edge is a soft glow, not a line.
	float lead = soft(ahead - 0.05, w * 0.45) * out_amp * 0.4;
	// Bounce back: one faint, soft ring drifting from max_r toward the origin.
	float tb0 = T * (1.0 + BACK_START);
	float back = 0.0;
	if (t > tb0) {
		float rb = max_r - (t - tb0) * ping_speed * BACK_SPEED;
		if (rb > -ring_width) {
			float prog = clamp(1.0 - rb / max_r, 0.0, 1.0);
			float fade_in = smoothstep(0.0, 0.15, prog);
			float fade_out = 1.0 - smoothstep(0.4, 1.0, prog);
			float amp = 0.2 * extra * fade_in * fade_out;
			back = soft(d - rb, w * 1.1) * amp;
		}
	}
	// Seconds since the main ring passed this point (invert the ease).
	float y = d / max_r;
	float xa = time_fraction_at(y);
	float since = t - xa * T;
	float passed = smoothstep(-0.1, 0.12, since);
	float sp = max(since, 0.0);
	float fade = clamp(sp / afterglow, 0.0, 1.0);
	float glow = passed * (1.0 - fade) * (1.0 - fade * 0.3) * 0.45;
	// A random number (0..1) that changes 14 times a second: the flicker.
	float flicker_seed = floor(p.w * 14.0) * 12.9898 + p.x * 4.1 + p.z * 1.7;
	float n = fract(sin(flicker_seed) * 43758.5453);
	glow *= 1.0 - flicker * smoothstep(0.35, 1.0, fade) * n;
	glow *= 1.0 + ripple * 0.6 * sin(d * 4.0 - p.w * 7.0);
	// A gentle brightening as the ring passes that eases into the afterglow.
	float k = sp / 0.3;
	glow += passed * k * exp(1.0 - k) * 0.22;
	float mem = step(0.0, since) * echo_memory * (1.0 - clamp(sp / memory_time, 0.0, 1.0));
	float out_ring = (ring + back) * dim;
	float out_glow = glow * dim;
	float out_lead = (lead + back * 0.2) * dim;
	return vec4(out_ring, out_glow, out_lead, mem) * edge;
}

void fragment() {
	vec4 a0 = ping_light(wpos, ping_0, ping_radius_0, 0.0);
	vec4 a1 = ping_light(wpos, ping_1, ping_radius_1, 0.0);
	vec4 a2 = ping_light(wpos, ping_2, ping_radius_2, 0.0);
	vec4 a3 = ping_light(wpos, ping_3, ping_radius_3, 0.0);
	vec4 b0 = ping_light(wpos, ping_4, ping_radius_4, 1.0);
	vec4 b1 = ping_light(wpos, ping_5, ping_radius_5, 1.0);
	vec4 b2 = ping_light(wpos, ping_6, ping_radius_6, 1.0);
	vec4 b3 = ping_light(wpos, ping_7, ping_radius_7, 1.0);
	vec4 lp = a0 + a1 + a2 + a3;
	vec4 lb = b0 + b1 + b2 + b3;
	// Memory takes the strongest trace, so overlapping pings don't pile up.
	float mem = a0.w;
	mem = max(mem, a1.w);
	mem = max(mem, a2.w);
	mem = max(mem, a3.w);
	mem = max(mem, b0.w);
	mem = max(mem, b1.w);
	mem = max(mem, b2.w);
	mem = max(mem, b3.w);

	bool textured = use_triplanar > 0.5 || use_albedo_tex > 0.5 || use_flat > 0.5;

	// World-space grid lines (1 m apart), skipped on the axis a face points along.
	vec3 g = wpos * grid_scale;
	vec3 f = abs(fract(g + 0.5) - 0.5);
	vec3 gw = fwidth(g) * 1.5;
	vec3 near_line = vec3(1.0) - smoothstep(vec3(0.0), gw, f);
	vec3 not_facing = vec3(1.0) - step(vec3(0.9), abs(wnorm));
	vec3 lines = near_line * not_facing;
	float grid = max(max(lines.x, lines.y), lines.z) * use_grid;
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float detail = 1.0;
	// Textured surfaces keep only a very faint grid.
	float gk = grid;
	if (textured) {
		gk = 0.15 * grid;
	} else {
		detail = 0.3 + 0.7 * grid + 0.5 * rim;
	}

	float to_player = distance(wpos, player_pos);
	float close = 1.0 + close_boost * (1.0 - smoothstep(1.0, 3.5, to_player));
	float ip = (lp.x * 1.4 + lp.y * close) * detail;
	float ib = (lb.x * 1.4 + lb.y * close) * detail;

	float floor_up = step(0.7, wnorm.y);
	// Footstep glow: each step briefly lights the floor around the player.
	float near_player = 1.0 - smoothstep(0.6, 1.6, to_player);
	float near = near_player * floor_up * near_glow * step_glow * (0.4 + gk);
	// Assist outline (Settings.hint_glow): the floor and the foot of the
	// walls within a few meters, so nobody gets completely lost.
	float around = 1.0 - smoothstep(1.5, 4.0, distance(wpos.xz, player_pos.xz));
	float height = wpos.y - player_pos.y;
	float wall_foot = (1.0 - floor_up) * step(-0.3, height) * (1.0 - smoothstep(0.05, 0.4, height));
	float assist_shape = floor_up * (0.08 + 0.5 * gk) + wall_foot * 0.9;
	float assist = hint_glow * floor_hint * around * assist_shape * 0.6;
	float memv = mem * (0.35 + 0.65 * gk);
	float lead = clamp(lp.z + lb.z, 0.0, 1.0);

	// Three looks: the Listener creature, textured cave/props, or plain echo color.
	vec3 col;
	if (listener_look > 0.5) {
		// Dissolve while dying: hashed cells drop out, edges smoulder.
		vec3 cell = floor(wpos * 14.0);
		float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float cut = dying * 1.05;
		if (dying > 0.001 && h < cut) {
			discard;
		}
		float burn = 0.0;
		if (dying > 0.001) {
			burn = 1.0 - smoothstep(0.0, 0.12, h - cut);
		}
		float L = lp.x * 1.4 + lp.y + lb.x * 1.4 + lb.y + mem * 0.6;
		float pulse = clamp((lp.x + lb.x) * 1.2 + lead, 0.0, 1.5);
		vec3 tex = texture(albedo_tex, UV).rgb;
		float lum = dot(tex, vec3(0.299, 0.587, 0.114));
		vec3 nm = texture(listener_normal, UV).xyz * 2.0 - 1.0;
		vec3 n = normalize(NORMAL);
		vec3 pn = normalize(TANGENT * nm.x + BINORMAL * nm.y + n * max(nm.z, 0.2));
		if (!FRONT_FACING) {
			pn = -pn;
			n = -n;
		}
		float ndv = clamp(dot(pn, VIEW), 0.0, 1.0);
		// Near-black core in the cavities, deep crimson on the raised flesh.
		float flesh = clamp(lum * 3.5, 0.0, 1.0);
		vec3 body = mix(vec3(0.05, 0.0, 0.008), vec3(0.62, 0.02, 0.05), flesh);
		body = mix(body, echo_color * 0.5, 0.15) * (0.55 + 0.45 * ndv);
		float fres = pow(1.0 - ndv, 2.6);
		vec3 rim = vec3(0.86, 0.9, 0.72) * fres * 0.9;
		float sheen = pow(ndv, 28.0) * (0.35 + flesh * 0.6);
		float eyes = smoothstep(0.3, 0.5, lum);
		vec3 lit = (body * exposure * 1.4 + rim + vec3(1.0, 0.85, 0.8) * sheen * 0.5) * L;
		lit += vec3(1.0, 0.25, 0.08) * eyes * min(L * 3.0, 1.0) * 1.6;
		// A short pulse as a ring sweeps over it: brighter, paler edges.
		lit += (vec3(0.9, 0.08, 0.1) * 0.6 + vec3(0.85, 0.9, 0.75) * fres) * pulse * 0.8;
		col = lit * (1.0 - dying * 0.85);
		col += vec3(1.0, 0.18, 0.05) * burn * 2.0;
		col = mix(col, vec3(1.6, 1.45, 1.25), clamp(hurt_flash, 0.0, 1.0));
	} else if (textured) {
		vec3 albedo = vec3(0.6);
		float shade = 1.0;
		float light_sum = ip + ib + near + assist + memv + lead;
		if (light_sum > 0.004) {
			if (use_triplanar > 0.5) {
				// Triplanar: sample the textures from the three world axes and
				// blend them by which way the surface faces.
				vec3 nn = normalize(wnorm);
				vec3 wt = pow(abs(nn), vec3(6.0));
				wt /= (wt.x + wt.y + wt.z);
				float up = smoothstep(0.0, 0.3, nn.y);
				vec2 uvy = wpos.xz * tex_scale;
				vec2 uvx = wpos.zy * tex_scale;
				vec2 uvz = wpos.xy * tex_scale;
				vec3 af = texture(tex_floor, uvy).rgb;
				vec3 aw = texture(tex_wall, uvy).rgb;
				vec3 ax = texture(tex_wall, uvx).rgb;
				vec3 az = texture(tex_wall, uvz).rgb;
				albedo = ax * wt.x + az * wt.z + mix(aw, af, up) * wt.y;
				vec3 nf = texture(nor_floor, uvy).xyz * 2.0 - 1.0;
				vec3 nw = texture(nor_wall, uvy).xyz * 2.0 - 1.0;
				vec3 nx = texture(nor_wall, uvx).xyz * 2.0 - 1.0;
				vec3 nz = texture(nor_wall, uvz).xyz * 2.0 - 1.0;
				vec3 ty = mix(nw, nf, up);
				// Bend the surface normal by each projection's normal map.
				vec3 off_y = vec3(ty.x, 0.0, ty.y) * wt.y;
				vec3 off_x = vec3(0.0, nx.y, nx.x) * wt.x;
				vec3 off_z = vec3(nz.x, nz.y, 0.0) * wt.z;
				vec3 off = off_y + off_x + off_z;
				vec3 pn = normalize(nn + off * normal_strength);
				vec3 vn = normalize((VIEW_MATRIX * vec4(pn, 0.0)).xyz);
				// Shade = how much the bumpy normal faces us vs. the flat one.
				float bumpy_facing = clamp(dot(vn, VIEW), 0.0, 1.0);
				float flat_facing = max(abs(dot(normalize(NORMAL), VIEW)), 0.3);
				float rl = bumpy_facing / flat_facing;
				shade = clamp(rl, 0.25, 1.3);
			} else if (use_albedo_tex > 0.5) {
				albedo = texture(albedo_tex, UV).rgb * albedo_color;
			} else {
				albedo = albedo_color;
			}
		}
		vec3 base = albedo * shade;
		float lum = dot(base, vec3(0.299, 0.587, 0.114));
		vec3 pc = mix(echo_color, GOLD, pebble_tint);
		vec3 ce = mix(base, echo_color * (0.1 + lum * 2.2), tint);
		vec3 cb = mix(base, pc * (0.1 + lum * 2.2), tint);
		col = (ce * (ip + near + assist + memv) + cb * ib) * exposure;
		// A very faint grid, only where the ring is passing.
		col += echo_color * grid * (lp.x + lb.x) * 0.1;
		float peak = max(max(col.r, col.g), col.b);
		col = mix(col, vec3(peak), clamp((lp.x + lb.x) * 0.12, 0.0, 0.25));
		col += vec3(lead * 0.6);
	} else {
		col = echo_color * (ip + near + assist + memv) + mix(echo_color, GOLD, pebble_tint) * ib;
		float peak = max(max(col.r, col.g), col.b);
		col = mix(col, vec3(peak), clamp((lp.x + lb.x) * 0.35, 0.0, 0.6));
		col += vec3(lead * (0.55 + 0.45 * grid) * 1.2);
	}
	ALBEDO = col;
}
