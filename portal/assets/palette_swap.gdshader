shader_type canvas_item;

uniform sampler2D palette_tex;
uniform int palette_index = 0;

void fragment() {
    vec4 src = texture(TEXTURE, UV);
    vec4 final_color = src;

    ivec2 palette_dim = textureSize(palette_tex, 0);

    int palette_size  = palette_dim.x;
    int palette_count = palette_dim.y;

    int clamped_index = clamp(palette_index, 0, palette_count - 1);

    float v_from = (0.5) / float(palette_count);
    float v_to   = (float(clamped_index) + 0.5) / float(palette_count);

    for (int i = 0; i < palette_size; i++) {
        float u = (float(i) + 0.5) / float(palette_size);

        vec3 from_color = texture(palette_tex, vec2(u, v_from)).rgb;

        if (all(equal(src.rgb, from_color))) {
            vec3 to_color = texture(palette_tex, vec2(u, v_to)).rgb;
            final_color = vec4(to_color, src.a);
            break;
        }
    }

    COLOR = final_color;
}
