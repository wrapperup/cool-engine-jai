ShCoefficients :: struct @ShaderShared {
	coef: [9]Vec4;
}

process_sh_coefficients_from_cubemap_file :: (in_filename: string) -> ShCoefficients {
	buffer, w, h := load_image_into_bytes(in_filename);
	coeffs := process_sh_from_cubemap(buffer, w);

	return coeffs;
}

process_sh_coefficients_from_equirectangular_file :: (in_filename: string, loc := #caller_location) -> ShCoefficients {
	buffer, w, h := load_image_into_bytes(in_filename, loc);
	coeffs := process_sh_from_equirectangular(buffer, w);

	return coeffs;
}

CUBEMAP_FACE_NORMALS_TABLE :: ([3]Vec3).[
	.[
		// +x
		.{0.0, 0.0, -1.0},
		.{0.0, -1.0, 0.0},
		.{1.0, 0.0, 0.0},
	],
	.[
		// -x
		.{0.0, 0.0, 1.0},
		.{0.0, -1.0, 0.0},
		.{-1.0, 0.0, 0.0},
	],
	.[
		// +y
		.{1.0, 0.0, 0.0},
		.{0.0, 0.0, 1.0},
		.{0.0, 1.0, 0.0},
	],
	.[
		// -y
		.{1.0, 0.0, 0.0},
		.{0.0, 0.0, -1.0},
		.{0.0, -1.0, 0.0},
	],
	.[
		// +z
		.{1.0, 0.0, 0.0},
		.{0.0, -1.0, 0.0},
		.{0.0, 0.0, 1.0},
	],
	.[
		// -z
		.{-1.0, 0.0, 0.0},
		.{0.0, -1.0, 0.0},
		.{0.0, 0.0, -1.0},
	],
];


process_sh_from_cubemap :: (faces: []Vec4, size: int) -> ShCoefficients {
	// Forsyth's weights
	weight1: f32 = 4.0 / 17.0;
	weight2: f32 = 8.0 / 17.0;
	weight3: f32 = 15.0 / 17.0;
	weight4: f32 = 5.0 / 68.0;
	weight5: f32 = 15.0 / 68.0;

	sh: ShCoefficients;

	weight_accum: f32 = 0.0;

	// TODO: This smells...
	cubemap_face_dirs: [..][..]Vec3;
	array_reserve(*cubemap_face_dirs, 6);

	for i: 0 .. 6 - 1 {
		face_dirs: [..]Vec3;
		array_reserve(*face_dirs, size * size);

		for v: 0 .. size - 1 {
			for u: 0 .. size - 1 {
				u_f32 := cast(f32, u);
				v_f32 := cast(f32, v);
				fu := (2.0 * u_f32 / (cast(f32, size) - 1.0)) - 1.0;
				fv := (2.0 * v_f32 / (cast(f32, size) - 1.0)) - 1.0;

				x := CUBEMAP_FACE_NORMALS_TABLE[i][0] * fu;
				y := CUBEMAP_FACE_NORMALS_TABLE[i][1] * fv;
				z := CUBEMAP_FACE_NORMALS_TABLE[i][2];

				tex_v := x + y + z;
				tex_v = normalize(tex_v);

				array_add(*face_dirs, tex_v);
			}
		}
		array_add(*cubemap_face_dirs, face_dirs);
	}

	for i: 0 .. 6 - 1 {
		for v: 0 .. size - 1 {
			for u: 0 .. size - 1 {
				color := faces[u + (v * size) + (i * size * size)];

				tex_v := cubemap_face_dirs[i][u + (v * size)];

				u_f32 := cast(f32, u);
				v_f32 := cast(f32, v);

				weight := solid_angle_cubemap(xx u, xx v, xx size);

				color *= weight;

				sh.coef[0] += color * weight1;

				sh.coef[1] += color * weight2 * tex_v.x;
				sh.coef[2] += color * weight2 * tex_v.y;
				sh.coef[3] += color * weight2 * tex_v.z;

				sh.coef[4] += color * weight3 * tex_v.x * tex_v.z;
				sh.coef[5] += color * weight3 * tex_v.z * tex_v.y;
				sh.coef[6] += color * weight3 * tex_v.y * tex_v.x;
				sh.coef[7] += color * weight4 * (3.0 * tex_v.z * tex_v.z - 1.0);
				sh.coef[8] += color * weight5 * (tex_v.x * tex_v.x - tex_v.y * tex_v.y);

				weight_accum += weight * 3.0;
			}
		}
	}

	for * coef: sh.coef {
		coef.* *= 4.0 * PI / weight_accum;
	}

	return sh;
}

process_sh_from_equirectangular :: (equirectangular: []Vec4, width: int) -> ShCoefficients {
	// Forsyth's weights
	weight1: f32 = 4.0 / 17.0;
	weight2: f32 = 8.0 / 17.0;
	weight3: f32 = 15.0 / 17.0;
	weight4: f32 = 5.0 / 68.0;
	weight5: f32 = 15.0 / 68.0;

	sh: ShCoefficients;

	weight_accum: f32 = 0.0;

	height := equirectangular.count / width;

	for v: 0 .. height - 1 {
		for u: 0 .. width - 1 {
			fu := cast(f32, v) / cast(f32, height);
			fv := cast(f32, u) / cast(f32, width);

			latitude := (1.0 - fv) * PI - (PI / 2);
			longitude := fu * (2.0 * PI) - PI;

			x := -cos(latitude) * cos(longitude);
			y := -sin(latitude);
			z := -cos(latitude) * sin(longitude);

			tex_v := normalize(Vec3.{x, y, z});

			color := equirectangular[u + (v * width)];

			solid_angle_equirectangular :: (v: f32, w: f32, h: f32) -> f32 {
				delta_phi := 2 * PI / w;
				delta_theta := PI / h;

				theta := v * PI;

				solid_angle := delta_phi * delta_theta * sin(theta);
				return solid_angle;
			}

			weight := solid_angle_equirectangular(fv, xx width, xx height);

			color *= weight;

			sh.coef[0] += color * weight1;

			sh.coef[1] += color * weight2 * tex_v.x;
			sh.coef[2] += color * weight2 * tex_v.y;
			sh.coef[3] += color * weight2 * tex_v.z;

			sh.coef[4] += color * weight3 * tex_v.x * tex_v.z;
			sh.coef[5] += color * weight3 * tex_v.z * tex_v.y;
			sh.coef[6] += color * weight3 * tex_v.y * tex_v.x;
			sh.coef[7] += color * weight4 * (3.0 * tex_v.z * tex_v.z - 1.0);
			sh.coef[8] += color * weight5 * (tex_v.x * tex_v.x - tex_v.y * tex_v.y);
			
			weight_accum += weight * 3.0;
		}
	}

	for * coef: sh.coef {
		coef.* *= 4.0 * PI / weight_accum;
	}

	return sh;
}


// // Explanation: https://www.rorydriscoll.com/2012/01/15/cubemap-texel-solid-angle/
// solid_angle_cubemap :: inline (au: f32, av: f32, size: f32) -> f32 {
// 	u := (2.0 * (au + 0.5) / size) - 1.0;
// 	v := (2.0 * (av + 0.5) / size) - 1.0;
//
// 	inv_size := 1.0 / size;
//
// 	// U and V are the -1..1 texture coordinate on the current face.
// 	// get projected area for this texel
// 	x0 := u - inv_size;
// 	y0 := v - inv_size;
// 	x1 := u + inv_size;
// 	y1 := v + inv_size;
// 	angle := area_element(x0, y0) - area_element(x0, y1) - area_element(x1, y0) + area_element(x1, y1);
//
// 	return angle;
// }
//
// area_element :: inline (x: f32, y: f32) -> f32 {
// 	return atan2(x * y, sqrt(x * x + y * y + 1.0));
// }

load_image_into_bytes :: (filename: string, loc := #caller_location) -> []Vec4, int, int {
	ktx_texture: *ktxTexture2;
	ktx_result := ktxTexture2_CreateFromNamedFile(temp_c_string(filename), .LOAD_IMAGE_DATA_BIT, *ktx_texture);
	assert(ktx_result == .SUCCESS, "Failed to load image.", loc);
	defer ktxTexture2_Destroy(ktx_texture);

	is_compressed := ktx_texture.isCompressed;
	assert(!is_compressed);

	size := ktxTexture_GetDataSize(ktx_texture);
	data := ktxTexture_GetData(ktx_texture);
	format := ktxTexture2_GetVkFormat(ktx_texture);

	// For now... I wonder if we can have this converted automatically for us.
	assert(format == .R32G32B32A32_SFLOAT);

	// TODO: More idiomatic way?
	arr := NewArray(xx (size / size_of(Vec4)), Vec4, initialized = false);
	memcpy(arr.data, data, xx size);

	return arr, ktx_texture.baseWidth, ktx_texture.baseHeight;
}

// Exact, but fewer ops.
area_element :: inline (x: f32, y: f32) -> f32 {
    // atan2(x*y, sqrt(x*x + y*y + 1)) == atan( (x*y) / sqrt(x*x + y*y + 1) )
    // Use rsqrt for speed if your platform has it.
    r2 := x*x + y*y + 1.0;
    inv_len := 1.0 / sqrt(r2); // if unavailable, use 1.0 / sqrt(r2)
    return atan(x * y * inv_len);
}

solid_angle_cubemap :: inline (au: f32, av: f32, size: f32) -> f32 {
    // Precompute invariants
    inv_size := 1.0 / size;
    two_inv_size := 2.0 * inv_size;

    // Texel center in [-1, 1]
    u := two_inv_size * (au + 0.5) - 1.0;
    v := two_inv_size * (av + 0.5) - 1.0;

    // Half-texel offsets in face coords
    du := inv_size;
    dv := inv_size;

    x0 := u - du;
    x1 := u + du;
    y0 := v - dv;
    y1 := v + dv;

    // Reuse squares across the 4 corners (separable!)
    x0_2 := x0*x0;
    x1_2 := x1*x1;
    y0_2 := y0*y0;
    y1_2 := y1*y1;

    // Corner area elements using shared terms + rsqrt
    // a(x,y) = atan( x*y * rsqrt(x^2 + y^2 + 1) )
    a00 := atan(x0 * y0 * (1.0/sqrt(x0_2 + y0_2 + 1.0)));
    a01 := atan(x0 * y1 * (1.0/sqrt(x0_2 + y1_2 + 1.0)));
    a10 := atan(x1 * y0 * (1.0/sqrt(x1_2 + y0_2 + 1.0)));
    a11 := atan(x1 * y1 * (1.0/sqrt(x1_2 + y1_2 + 1.0)));

    return a00 - a01 - a10 + a11;
}
