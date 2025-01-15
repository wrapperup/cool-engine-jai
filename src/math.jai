VEC_UP      :: Vec3.{0, 1, 0};
VEC_RIGHT   :: Vec3.{1, 0, 0};
VEC_FORWARD :: Vec3.{0, 0, -1};
VEC_ONE     :: Vec3.{1, 1, 1};

Vec2 :: Vector2;
Vec3 :: Vector3;
Vec4 :: Vector4;

Mat4x4 :: Matrix4;
Mat4x3 :: Matrix4x3;

Mat3x3 :: Matrix3;

Mat2x2 :: Matrix2;

Quat :: Quaternion;

Aabb :: struct {
    min: Vec3;
    max: Vec3;
};

aabb_center :: (box: Aabb) -> Vec3 {
    offset := (box.max - box.min) / 2.0;
    return box.min + offset;
}

debug_draw_aabb :: (box: Aabb) {
    offset := box.max - box.min;

    debug_draw_dot(box.min);

    debug_draw_dot(box.min + .{offset.x, 0, 0});
    debug_draw_dot(box.min + .{0, offset.y, 0});
    debug_draw_dot(box.min + .{0, 0, offset.z});

    debug_draw_dot(box.min + .{offset.x, offset.y, 0});
    debug_draw_dot(box.min + .{0, offset.y, offset.z});
    debug_draw_dot(box.min + .{offset.x, 0, offset.z});

    debug_draw_dot(box.max);
}

make_infinite_projection_matrix :: (fov_vertical: float, aspect_ratio_horizontal_over_vertical: float, z_near: float, x_offset:=0.0, y_offset:=0.0, depth_range_01:=false) -> Matrix4 {
    result := Matrix4_Identity;

    tan_theta := tan(fov_vertical * 0.5);
    cot_theta := 1 / tan_theta;

    n := z_near;

    result._11 = cot_theta / aspect_ratio_horizontal_over_vertical;
    result._22 = cot_theta;
    result._33 = -1;
    result._43 = -1;
    result._34 = -2 * n;
    result._44 = 0;

    result._13 = x_offset; // / w;
    result._23 = y_offset; // / h;

    if depth_range_01 {
        result._34 = -n;
    }

    return result;
}

clamp_length :: (v: $T, a: float) -> T #modify {
    return T == Vector2 || T == Vector3;
} {
	if a <= 0 {
        return .{};
	}
	
    m2 := length_squared(v);
	if m2 <= (a * a) {
        return v;
    } else {
        return v / sqrt(m2) * a;
    }
}

count_of :: ($T: Type) -> s64 #modify {
    info := cast(*Type_Info) T;
    return info.type == .ENUM;  // Ensure it is an enum.
} {
    return type_info(T).values.count;
}

to_radians :: (deg: f32) -> f32 {
    return deg * (PI/180.0);
}

angle_between :: (a: Vector2, b: Vector2) -> float {
    a0 := normalize(a);
    b0 := normalize(b);
    d  := clamp(dot(a0, b0), -1, +1);
    return acos(d);
}

angle_between :: (a: Vector3, b: Vector3) -> float {
    a0 := normalize(a);
    b0 := normalize(b);
    d  := clamp(dot(a0, b0), -1, +1);
    return acos(d);
}

round :: (x: float) -> float {
    return cast(float)cast(int)(x + 0.5 * ifx x < 0 then -1 else 1);
}

round :: (x: Vector2) -> Vector2 {
    return .{
        round(x.x),
        round(x.y),
    };
}

round :: (x: Vector3) -> Vector3 {
    return .{
        round(x.x),
        round(x.y),
        round(x.z),
    };
}

round :: (x: Vector4) -> Vector4 {
    return .{
        round(x.x),
        round(x.y),
        round(x.z),
        round(x.w),
    };
}
