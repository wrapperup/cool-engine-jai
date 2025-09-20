Story_Progress :: struct {
    // Chapter Progress
    current_chapter: enum {
        Chapter1;
        Chapter2;
        Chapter3;
        Chapter4;
        Chapter5;
        Chapter6;
    };

    // Chapter 1
    visited_home: enum { No; Approached; Entered; };

    // Chapter 2
    dated: bool;

    // Chapter 3
} @Serializable

Player :: struct {
	using #as entity: *Entity;

	move_mode: enum {
        Ground;
        Noclip;
    }

	fire_mode: enum {
        CreatePointLight;
        LaunchForward;
    };

	controller:                 *PxController;
	camera_rot:                 Vec3;
	camera_fov_deg:             f32;
	ground_contact_normals:     [..]Vec3;
	fire_time:                  f64;
	momentum:                   f32;
	is_grounded_last_frame:     bool;
	footstep_distance_traveled: f32;
	footstep_time:              f64;
	footstep:                   u32;
	camera_shake_time:          f64;
	temp_cycler:                u32;
}

on_shape_hit_callback :: (userData: *void, hit: *PxControllerShapeHit) #c_call {
	push_context {
		id := entity_id_from_ptr(PxController_getUserData(hit.controller));

		player := get_entity(Player, id);
		if player != null {
			array_add(*player.ground_contact_normals, hit.worldNormal);
		}
	}
}

init :: (player: *Player) {
	material := PxPhysics_createMaterial(game.phys.physics, 0.9, 0.5, 0.1);

	desc := PxCapsuleControllerDesc_new_alloc();
	desc.height = 2.0;
	desc.radius = 1.0;
	desc.maxJumpHeight = 2.0;
	desc.slopeLimit = 0.3;
	desc.stepOffset = 0.3;
	desc.material = material;
	desc.nonWalkableMode = xx PxControllerNonWalkableMode.PreventClimbing;
	desc.climbingMode = xx PxCapsuleClimbingMode.Constrained;
	desc.contactOffset = 0.1;

	hit_report_callbacks := UserControllerHitReportInfo.{
		shapeHitCallback = on_shape_hit_callback,
	};
	desc.reportCallback = create_user_controller_hit_report(*hit_report_callbacks);

	player.controller = PxControllerManager_createController(game.phys.controller_manager, desc);
	PxController_setUserData(player.controller, entity_id_to_ptr(player.id));
	PxController_setPosition(player.controller, *(PxExtendedVec3.{0.0, 10.0, 0.0}));

	assert(player.controller != null);
}

update_player :: (player: *Player, dt: f64) {
	// Values / Constants
	max_ground_acceleration: f32 = 50;
	max_air_acceleration: f32 = 50;
	max_braking_acceleration: f32 = 80;

	max_ground_speed: f32 = 10;
	max_sprinting_ground_speed: f32 = 15;
	max_air_speed: f32 = 10;

	max_jump_force: f32 = 20;

	{ 	// Physics Character Controller
		w0, w1, w2, w3 := get_words_from_filter(0);
		filter_data := PxFilterData_new(w0, w1, w2, w3);
		filters := PxControllerFilters_new(*filter_data, null, null);

		collision_flags := PxController_move(
			player.controller,
			*((player.velocity * cast(f32, dt)) - Vec3.{0, ifx player.is_grounded_last_frame then 0.05 else 0, 0}),
			0.001,
			xx dt,
			*filters,
			null,
		);
	}

	camera_forward: Vec3;
	// camera_right: Vec3
	forward: Vec3;
	right: Vec3;
	{
		// Look scheme
		yaw_delta: f32;
		pitch_delta: f32;

		mouse_x := axis_get_value(.LookRight);
		mouse_y := axis_get_value(.LookUp);

		if action_just_pressed(.LockCamera) {
			toggle_lock_mouse();
		}

		yaw_delta = to_radians(xx mouse_x);
		pitch_delta = to_radians(xx mouse_y);

		player.camera_rot += Vec3.{xx pitch_delta, xx yaw_delta, 0};
		player.camera_rot.x = clamp(player.camera_rot.x, -PI / 2, PI / 2);
		player.camera_rot.y = player.camera_rot.y; // TODO: Wrap this?

		pitch: Quaternion;
		yaw: Quaternion;

		set_from_axis_and_angle(*pitch, -VEC_RIGHT, player.camera_rot.x);
		set_from_axis_and_angle(*yaw, -VEC_UP, player.camera_rot.y);

		look := yaw * pitch;

		camera_forward = rotate(VEC_FORWARD, player.rotation);
		forward = rotate(VEC_FORWARD, yaw);
		right = rotate(VEC_RIGHT, yaw);

		tilt_angle := atan(dot(player.velocity / 100.0, right)) / 5.0;
		player.camera_rot.z = lerp(player.camera_rot.z, tilt_angle, 20.0 * cast(f32, dt));

		tilt: Quaternion;
		set_from_axis_and_angle(*tilt, VEC_FORWARD, player.camera_rot.z);

		player.rotation = look * tilt;
	}

	move_input := axis_get_2d_normalized(.MoveRight, .MoveForward);
	move_forward := move_input.y; 
	move_right := move_input.x;
        extra_args: [..] string;
        array_add(*extra_args,
            "-DTHEKLA_BAKER_SHARED",
            "-DTHEKLA_BAKER_EXPORTS",
            "-DNV_OS_OSX_NO_WRITE_CRASH_FILE",
            "-DNV_NO_IMAGEIO",
        );

	move_direction := move_forward * forward + move_right * right;
	move_direction_n := normalize(move_forward * forward + move_right * right);

	if action_just_pressed(.ToggleNoclip) {
        if player.move_mode == {
            case .Ground; player.move_mode = .Noclip;
            case .Noclip;   player.move_mode = .Ground;
        }
	}

	set_listener_position(player.translation, camera_forward);

	if player.move_mode == {
		case .Ground;
			is_sliding := false;
			is_grounded := false;

			acceleration: Vec3;

			for normal: player.ground_contact_normals {
				slope_angle := angle_between(normal, VEC_UP);
				is_grounded = is_grounded || slope_angle < PI / 4;
				is_sliding = !is_grounded;

				if is_grounded || is_sliding {
					test_normal := normal;
					new_velocity := normalize(test_normal) * max((dot(-test_normal, player.velocity * 1)), 0);

					if is_grounded {
						player.velocity.y += new_velocity.y;
					} else {
						player.velocity += new_velocity;
					}
				}
			}

			pos := PxController_getPosition(player.controller);
			last_player_translation := player.translation;
			player.translation = .{xx pos.x, xx pos.y, xx pos.z};

			player.fire_time += dt;

			if action_is_pressed(.Sprint) {
				max_ground_speed = max_sprinting_ground_speed;
			}

			if length(move_direction) > 0.01 {
				max_acceleration := ifx is_grounded then max_ground_acceleration else max_air_acceleration;
				max_speed := ifx is_grounded then max_ground_speed else max_air_speed;

				accel_y := acceleration.y;
				acceleration += apply_acceleration(move_direction_n, max_speed, max_acceleration, player.velocity, is_grounded, dt);
				acceleration.y = accel_y;
			} else if is_grounded && length(player.velocity) >= 1 {
				accel_y := acceleration.y;
				acceleration += apply_acceleration(-normalize(player.velocity), 10, max_braking_acceleration, player.velocity, is_grounded, dt);
				acceleration.y = accel_y;
			} else if is_grounded && length(player.velocity) < 1 {
				acceleration.x = 0;
				acceleration.z = 0;
				player.velocity.x = 0;
				player.velocity.z = 0;
			}

			player.velocity += .{0, -70, 0} * cast(f32, dt);

			// if action_is_pressed(.AltFire) {
			// 	player.fire_mode = xx ((cast(s64) player.fire_mode + 1) % count_of(Fire_Mode));
			// }

			if action_just_pressed(.Fire) {
				log("Fire");
				if player.fire_mode == {
					case .CreatePointLight;
						if player.fire_time > 0.1 {
							point_light := new_entity(Point_Light);
							color: Vec3 = ---;
							if player.temp_cycler == {
								case 0;
									color = .{1, 0, 0};
								case 1;
									color = .{0, 1, 0};
								case 2;
									color = .{0, 0, 1};
							}

							init(point_light, player.translation, color, 10, 10);

							player.temp_cycler = (player.temp_cycler + 1) % 3;
							player.fire_time = 0;
						}
					case .LaunchForward;
						player.velocity.x += move_direction_n.x * 15;
						player.velocity.z += move_direction_n.z * 15;
						player.velocity += Vec3.{0, 1, 0} * 10;
				}
			}

			array_reset(*player.ground_contact_normals);

			player.velocity += acceleration * cast(f32, dt);
			player.is_grounded_last_frame = is_grounded && !is_sliding;

			if action_is_pressed(.Jump) && is_grounded {
				player.velocity.y = max_jump_force;
				player.is_grounded_last_frame = false;
			}

			if is_grounded {
				if player.footstep_distance_traveled > 3.5 && player.footstep_time > 0.15 {
					player.footstep_distance_traveled = 0;
					player.footstep_time = 0;

					play_sound(tprint("assets/audio/footsteps/step%.wav", player.footstep + 1));
					player.footstep += 1;
					player.footstep = player.footstep % 20;
				}

				player.footstep_distance_traveled += length(last_player_translation - player.translation);
			} else {
				player.footstep_distance_traveled = 2;
			}

			player.footstep_time += dt;

		case .Noclip;
			max_noclip_speed: f32 = 15;

			if action_is_pressed(.Fire) {
				max_noclip_speed = 50;
			}

			player.velocity = move_direction_n * max_noclip_speed;

			if action_is_pressed(.Jump) {
				player.velocity.y = max_noclip_speed;
			}
			if action_is_pressed(.Sprint) {
				player.velocity.y = -max_noclip_speed;
			}

			player.translation += player.velocity * dt;

			// Force capsule to move.
			PxController_setPosition(
				player.controller,
				*(PxExtendedVec3.{
					xx player.translation.x,
					xx player.translation.y, 
					xx player.translation.z,
				})
			);
	}
}

// Returns the change in acceleration to apply to the player's current acceleration.
apply_acceleration :: (
	requested_dir: Vec3,
	max_speed: f32,
	max_acceleration: f32,
	current_velocity: Vec3,
	has_traction: bool,
	dt: f64
) -> Vec3 {
	current_speed := dot(current_velocity, requested_dir);
	add_speed := max_speed - current_speed;

	if add_speed < 0 && !has_traction {
		return .{};
	}

	acceleration_change := ((max_speed * requested_dir) - current_velocity) / cast(f32, dt);
	acceleration_change = clamp_length(acceleration_change, max_acceleration);

	return acceleration_change;
}

get_current_projection_matrix :: () -> Mat4x4 {
	player := get_entity(game.state.player_id);

	return player_get_projection_matrix(player);
}

get_current_projection_matrix_clipped :: (near: f32, far: f32) -> Mat4x4 {
	player := get_entity(game.state.player_id);
	return player_get_projection_matrix_clipped(player, near, far);
}

get_current_view_matrix :: () -> Mat4x4 {
	player := get_entity(game.state.player_id);

	return player_get_view_matrix(player);
}

get_current_projection_view_matrix :: () -> Mat4x4 {
	return get_current_projection_matrix() * get_current_view_matrix();
}

player_get_view_matrix :: (player: *Player) -> Mat4x4 {
	identity := Matrix4_Identity;
	translation := ifx player != null then player.translation else .{};
	rotation := ifx player != null then player.rotation else .{};

	translation_mat := make_translation_matrix4(translation);
	rotation_mat := rotation_matrix(Mat4x4, rotation);

	_, mat := inverse(translation_mat * rotation_mat);
    return mat;
}

player_get_fov :: (player: *Player) -> f32 {
	return to_radians(ifx player != null then player.camera_fov_deg else 0);
}

player_get_projection_matrix :: (player: *Player, near: f32 = 0.1) -> Mat4x4 {
	aspect_ratio := cast(f32, r_ctx.draw_extent.width) / cast(f32, r_ctx.draw_extent.height);

	projection_matrix := make_infinite_projection_matrix(
		player_get_fov(player),
		aspect_ratio,
		near,
		depth_range_01 = true,
	);
	projection_matrix.coef[1][1] *= -1.0;

	return projection_matrix;
}

player_get_projection_matrix_clipped :: (player: *Player, near: f32, far: f32) -> Mat4x4 {
	aspect_ratio := cast(f32, r_ctx.draw_extent.width) / cast(f32, r_ctx.draw_extent.height);

	projection_matrix := make_projection_matrix(
		player_get_fov(player),
		aspect_ratio,
		near,
		far,
		depth_range_01 = true
	);
	projection_matrix.coef[1][1] *= -1.0;

	return projection_matrix;
}

world_space_to_clip_space :: (view_projection: Mat4x4, vec: Vec3) -> Vec2, bool {
	vec_p := view_projection * Vec4.{vec.x, vec.y, vec.z, 1.0};
	clip_vec := vec_p.xyz / vec_p.w;

	ok := true;

	// TODO: uhh.... is there a better way?
	if clip_vec.x > 1 then  ok = false;
	if clip_vec.y > 1 then  ok = false;
	if clip_vec.z > 1 then  ok = false;
	if clip_vec.x < -1 then ok = false;
	if clip_vec.y < -1 then ok = false;
	if clip_vec.z < -1 then ok = false;

	return (clip_vec.xy * .{0.5, 0.5} + .{0.5, 0.5}) * Vec2.{xx r_ctx.draw_extent.width, xx r_ctx.draw_extent.height}, ok;
}
