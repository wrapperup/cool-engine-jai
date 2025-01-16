GamePhysicsFilter :: enum_flags u32 {
	NonWalkable;
}

get_words_from_filter :: (filter_set: GamePhysicsFilter) -> u32, u32, u32, u32 {
	bits := cast(u32, filter_set);

	return bits, 0, 0, 0;
}

RAYCAST_BUFFER_BASE_STRUCT : *PxRaycastCallback;

init_raycast_buffer :: () -> PxRaycastCallback {
	// unholy retarded shit
	// oh my fucking god why does this leak... fucking dumb
	if RAYCAST_BUFFER_BASE_STRUCT == null {
		RAYCAST_BUFFER_BASE_STRUCT = create_raycast_buffer();
	}

	buffer := RAYCAST_BUFFER_BASE_STRUCT.*;
	return buffer;
}

query_raycast_single :: (
	origin: Vec3,
	unit_dir: Vec3,
	distance: f32,
	filter: GamePhysicsFilter = 0,
	query_flags := PxQueryFlags.Static,
	debug := false
) -> PxRaycastHit, bool {
	hit := init_raycast_buffer();
	w0, w1, w2, w3 := get_words_from_filter(filter);
	filter_data := PxFilterData_new(w0, w1, w2, w3);
	query_filter := PxQueryFilterData_new(*filter_data, xx query_flags);

	ok := PxSceneQuerySystemBase_raycast(
		cast(*PxSceneQuerySystemBase, game.phys.scene),
		*origin,
		*unit_dir,
		distance,
		*hit,
		.FaceIndex | .Normal | .Position,
		*query_filter,
		null,
		null,
		.SimdGuard,
	);

	if debug {
		pos := hit.block.position;
		normal := hit.block.normal;

		debug_draw_line(origin, pos, dots = true);
		debug_draw_line(pos, pos + normal, dots = false);
	}

	return hit.block, ok;
}

collision_filter_shader :: (
	attributes0: *u32,
	filterData0: *PxFilterData,
	attributes1: *u32,
	filterData1: *PxFilterData,
	pairFlags: *PxPairFlags
) -> u16 #c_call {
	pairFlags.* = .SolveContact | .DetectDiscreteContact | .NotifyTouchFound;

	return 0;
}

collision_callback :: (user_data: *void, pair_header: *PxContactPairHeader, pairs: *PxContactPair, nb_pairs: u32) #c_call {
	// push_context {
	// 	 log("collide");
	// }
}

trigger_callback :: (user_data: *void, pairs: *PxTriggerPair, nb_pairs: u32) #c_call {
	// push_context {
	// 	log("trigger");
	// }
}

constraint_break_callback :: (user_data: *void, constraints: *PxConstraintInfo, nb_pairs: u32) #c_call {
	// push_context {
	// 	log("constraint break");
	// }
}

wake_sleep_callback :: (user_data: *void, actors: **PxActor, count: u32, is_wake: bool) #c_call {
	// push_context {
	// 	log("wake_sleep: %", is_wake);
	// }
}

advance_callback :: (user_data: *void, body_buffer: **PxRigidBody, pose_buffer: *PxTransform, count: u32) #c_call {
	// push_context {
	// 	log("advance");
	// }
}
