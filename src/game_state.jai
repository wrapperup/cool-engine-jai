NUM_FRAME_AVG_COUNT :: 10;

FrameTimeStats :: enum {
	Total;
	GameState;
	Imgui;
	Physics;
	Render;
}

PhysicsContext :: struct {
	foundation:         *PxFoundation;
	dispatcher:         *PxDefaultCpuDispatcher;
	physics:            *PxPhysics;
	scene:              *PxScene;
	controller_manager: *PxControllerManager;
}

ViewState :: enum {
	SceneColor;
	SceneDepth;
	ShadowDepth;
}

SkeletalMeshInstance :: struct {
	preskinned_vertex_buffers: [FRAME_OVERLAP]GPUBuffer(GPUVertex);
	joint_matrices_buffers:    [FRAME_OVERLAP]GPUBuffer(Mat4x4);
	skel:                      *Skeleton;
}

init_skeletal_mesh_instance :: (skel: *Skeleton, anim: *SkeletalAnimation) -> SkeletalMeshInstance {
	instance := SkeletalMeshInstance.{
		skel = skel,
	};

	for i: 0 .. FRAME_OVERLAP-1 {
		instance.preskinned_vertex_buffers[i] = create_buffer(GPUVertex, instance.skel.buffers.vertex_count, .Storage);
		defer_destroy(instance.preskinned_vertex_buffers[i]);

		instance.joint_matrices_buffers[i] = create_buffer(Mat4x4, instance.skel.joint_count, .DynUniform);
		defer_destroy(instance.joint_matrices_buffers[i]);
	}

	return instance;
}

Game :: struct {
	window: *SDL_Window;
	is_shutting_down: bool;
	is_minimized: bool;
	is_fullscreen: bool;

	config:             GameConfig;
	state:              GameState;
	editor:             Editor_State;
	renderer:           *Renderer;

	// Systems
	entity_system:      EntitySystem;
	input_system:       InputSystem;
	sound_system:       SoundSystem;
	// asset_system:       AssetSystem;
	view_state:         ViewState;
	render_state:       RenderState;

	// Physics
	phys:               PhysicsContext;

	// Stats
	frame_times:        [#run count_of(FrameTimeStats)]f32;
	frame_times_smooth: [#run count_of(FrameTimeStats)]f32;
	frame_times_start:  [#run count_of(FrameTimeStats)]Apollo_Time;
	frame_time_start:   Apollo_Time;
	delta_time:         f64;
	live_time:          f64;

	start_live_time: Apollo_Time;
}

scope_stat_time :: (stat_type: FrameTimeStats) #expand {
	start_scope_stat_time(stat_type);
	`defer end_scope_stat_time(stat_type);
}

start_scope_stat_time :: (stat_type: FrameTimeStats) {
	game.frame_times_start[stat_type] = current_time_monotonic();
}

end_scope_stat_time :: (stat_type: FrameTimeStats) {
	end_time := current_time_monotonic();
	frame_time := to_float64_seconds(end_time - game.frame_times_start[stat_type]) * 1000;
	game.frame_times[stat_type] = cast(f32, frame_time);
}

GameState :: struct {
	environment: Environment;
	player_id:   TypedEntityId(Player);
}

Environment :: struct {
	sun_color:     Vec3;
	sky_color:     Vec3;
	sun_direction: Vec3;
}
