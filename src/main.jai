#import "Basic";
#import "File";
#import "Math";
#import "Remap_Context"(VERBOSE = false);
#import "String";

// External deps
#import "JaiPhysX";
#import "SDL"(VULKAN = true);
#import "gltf_parser";
#import "jai-libktx";
#import "jai-vulkan";
#import "slang-jai";
Mikk :: #import "jai-mikktspace";
ImGui :: #import "jai-imgui";
Slang :: #import "slang-jai";

#import,file "./gfx/module.jai";

#load "config.jai";
#load "dfg.jai";
#load "editor.jai";
#load "entity.jai";
#load "entity_ball.jai";
#load "entity_player.jai";
#load "entity_point_light.jai";
#load "entity_sound_source.jai";
#load "entity_static_mesh.jai";
#load "env_prefilter.jai";
#load "game_state.jai";
#load "gltf_loader.jai";
#load "gpu_types.jai";
#load "imgui.jai";
#load "math.jai";
#load "physics.jai";
#load "renderer.jai";
#load "shaders.jai";
#load "skeleton.jai";
#load "spherical_harmonics.jai";
#load "sys_asset.jai";
#load "sys_input.jai";
#load "sys_sound.jai";
#load "util.jai";

f32 :: float32;
f64 :: float64;

REQUIRED_FEATURES :: RequiredFeatures.{
	vk_10 = .{
		samplerAnisotropy             = VK_TRUE,
		shaderStorageImageMultisample = VK_TRUE,
		shaderImageGatherExtended     = VK_TRUE,
		multiDrawIndirect             = VK_TRUE,
		geometryShader                = VK_TRUE,
		shaderInt64                   = VK_TRUE,
		shaderInt16                   = VK_TRUE,
		shaderFloat64                 = VK_TRUE,
	},
	vk_11 = .{
		variablePointers              = VK_TRUE,
		variablePointersStorageBuffer = VK_TRUE,
	},
	vk_12 = .{
		bufferDeviceAddress    = VK_TRUE,
		descriptorIndexing     = VK_TRUE,
		storagePushConstant8   = VK_TRUE,
		shaderInt8             = VK_TRUE,
		runtimeDescriptorArray = VK_TRUE,
		scalarBlockLayout      = VK_TRUE,
	},
	vk_13 = .{
		dynamicRendering = VK_TRUE,
		synchronization2 = VK_TRUE,
	},
};

game: *Game;

#program_export
game_init :: (del_queue_to_use: **Deletion_Queue) {
	Remap_Context();

	game = New(Game);

    result_sdl := SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER);
	if result_sdl != 0 {
		assert(false, "Could not load SDL: %", to_string(SDL_GetError()));
	}

	sdl_flags: SDL_WindowFlags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | 
		SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_VULKAN;

	width: s32 = 1920;
	height: s32 = 1080;

    window := SDL_CreateWindow("Hello Vulkan with Jai", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, width, height, sdl_flags);
	if window == null {
		log_error("Could not create window: %\n", to_string(SDL_GetError()));
		return;
	}

	game.config = default_game_config();
	game.window = window;

    game.renderer = gfx_init(.{
		window = window,
		msaa_samples = ._4_BIT,
		enable_validation = DEBUG,
		required_features = REQUIRED_FEATURES
	});
	del_queue_to_use.* = context.deletion_queue;

	log("context.deletion_queue: %", context.deletion_queue);

	if game.renderer == null {
		log_error("Graphics could not be initialized.");
	}

	// init_entity_system()
	init_input_system();
	init_sound_system();
	// init_asset_system()

	configure_im();

	init_game_renderer();

	game.frame_time_start = current_time_monotonic();

	{ // Init Inputs
		add_action_key_mapping(.Jump,         SDLK_SPACE);
		add_action_key_mapping(.Sprint,       SDLK_LSHIFT);
		add_action_key_mapping(.ToggleNoclip, SDLK_v);
		add_action_key_mapping(.LockCamera,   SDLK_m);
		add_action_key_mapping(.Fullscreen,   SDLK_F11);
		// add_action_key_mapping(.ExitGame,     SDLK_ESCAPE);

		add_action_mouse_mapping(.Fire,    SDL_BUTTON_LEFT);
		add_action_mouse_mapping(.AltFire, SDL_BUTTON_RIGHT);

		add_axis_key_mapping(.MoveForward, SDLK_w,  1.0);
		add_axis_key_mapping(.MoveForward, SDLK_s, -1.0);
		add_axis_key_mapping(.MoveRight,   SDLK_d,  1.0);
		add_axis_key_mapping(.MoveRight,   SDLK_a, -1.0);

		add_axis_mouse_axis(.LookRight, .Mouse_X, 0.05);
		add_axis_mouse_axis(.LookUp,    .Mouse_Y, 0.05);
	}

	// g_physx_error_callback := create_error_callback(user_error_callback, null);

	{ // Init Physx
		PX_PHYSICS_VERSION_MAJOR :: 5;
		PX_PHYSICS_VERSION_MINOR :: 1;
		PX_PHYSICS_VERSION_BUGFIX :: 3;

		PX_PHYSICS_VERSION :: ((PX_PHYSICS_VERSION_MAJOR << 24) + (PX_PHYSICS_VERSION_MINOR << 16) + (PX_PHYSICS_VERSION_BUGFIX << 8) + 0);

		game.phys.foundation = create_foundation();
		game.phys.dispatcher = PxDefaultCpuDispatcherCreate(1, null, .WaitForWork, 0);
		game.phys.physics = create_physics(game.phys.foundation);

		callback_info := SimulationEventCallbackInfo.{
			collisionCallback       = collision_callback,
			triggerCallback         = trigger_callback,
			constraintBreakCallback = constraint_break_callback,
			wakeSleepCallback       = wake_sleep_callback,
			advanceCallback         = advance_callback,
		};

		callback := create_simulation_event_callbacks(*callback_info);

		scene_desc := PxSceneDesc_new(*PxTolerancesScale_new(1.0, 10.0));
		scene_desc.gravity = PxVec3_new(0.0, -9.81 * 2, 0.0);
		scene_desc.cpuDispatcher = cast(*PxCpuDispatcher, game.phys.dispatcher);
		scene_desc.simulationEventCallback = callback;

		filter_handle := create_custom_filter_shader(collision_filter_shader);
		set_custom_filter_shader(*scene_desc, filter_handle);

		game.phys.scene = PxPhysics_createScene(game.phys.physics, *scene_desc);

		game.phys.controller_manager = PxCreateControllerManager(game.phys.scene, false);

		PxScene_setVisualizationCullingBox(game.phys.scene, *PxBounds3_new(*(Vec3.{-50, -50, -50}), *(Vec3.{50, 50, 50})));
	}

	{ // TEMP: Init testing scene.
		game.render_state.draw_skybox = true;

		player := new_entity(Player);
		init(player);

		player.translation = .{3, 3.7, 5};
		player.camera_fov_deg = 65;

		skeleton, anim, ok := load_skel_mesh_from_file("assets/meshes/skel/skeltest2.glb");
		assert(ok);
		defer_destroy(skeleton.buffers);

		// LEAK: Needs asset system.
		skel_ptr := New(Skeleton);
		skel_ptr.* = skeleton;

		// LEAK: Needs asset system.
		anim_ptr := New(SkeletalAnimation);
		anim_ptr.* = anim;

		grid_size := 3;

		for i: 0 .. grid_size-1 {
			for j: 0 .. grid_size-1 {
				for k: 0 .. grid_size-1 {
					ball := new_entity(Ball);
					init(ball, .{xx (i * 3), xx (j * 3), xx (k * 3)}, skel_ptr, anim_ptr);
				}
			}
		}

		ball := new_entity(Ball);
		init(ball, .{0, 0, 0}, skel_ptr, anim_ptr);

		test_mesh := new_entity(StaticMesh);
		init(test_mesh, "assets/meshes/static/map_test.glb", 0);

		test_mesh2 := new_entity(StaticMesh);
		init(test_mesh2, "assets/meshes/static/materialball2.glb", 2);

		sound_source := new_entity(SoundSource);
		init(sound_source, "assets/audio/ambient/outdoors_birds.wav", true, 0.1, false, 0.5);

		point_light := new_entity(Point_Light);
		init(point_light, .{0, 4, 2}, .{1, 0, 0}, 20, 100);

		game.state = GameState.{
			player_id = entity_id_of(player),
			environment = Environment.{
				sun_direction = normalize(Vec3.{12, 15, 10}),
				sun_color = .{2.0, 2.0, 2.0},
				sky_color = .{1.0, 1.0, 1.0}
			},
		};
	}

	game.start_live_time = current_time_monotonic();

	lock_mouse(true);
}

#program_export 
game_hotreloaded :: (mem: *void) {
	Remap_Context();

    result_sdl := SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER);
	if result_sdl != 0 {
		assert(false, "Could not load SDL: %", to_string(SDL_GetError()));
	}

	game = cast(*Game, mem);
	set_renderer(game.renderer);
	lock_mouse(game.input_system.mouse_locked);

	gfx_init_imgui();
	configure_im();

	log("Hot reloaded!");
}

#program_export
game_pre_hotreload :: (mem: *void) {
	Remap_Context();

	gfx_shutdown_imgui();
}

#program_export
game_update :: () -> bool {
	Remap_Context();


	if game.is_shutting_down then return false;

	scope_stat_time(.Total);

	if SDL_GetWindowFlags(game.window) & SDL_WINDOW_INPUT_FOCUS {
		ma_engine_set_volume(*game.sound_system.sound_engine, 1.0);
	} else {
		ma_engine_set_volume(*game.sound_system.sound_engine, 0.0);
	}
	game.live_time = to_float64_seconds(current_time_monotonic() - game.start_live_time);
	game.delta_time = to_float64_seconds(current_time_monotonic() - game.frame_time_start);
	game.frame_time_start = current_time_monotonic();

	dt := game.delta_time;

	mouse_x, mouse_y: s32;
	// SDL_GetRelativeMouseState(*mouse_x, *mouse_y);

	clear_input_state();

	event: SDL_Event;
	while SDL_PollEvent(*event) {
		ImGui_ImplSDL2_ProcessEvent(*event);

		if event.type == {
			case SDL_QUIT;
				game.is_shutting_down = true;
			case SDL_KEYUP;
				// if event.key.keysym.sym == SDLK_ESCAPE {
				// 	game.is_shutting_down = true;
				// }
			case SDL_KEYDOWN;
				if event.key.keysym.sym == SDLK_F11 {
					game.is_fullscreen = !game.is_fullscreen;
					SDL_SetWindowFullscreen(game.window, xx ifx game.is_fullscreen then SDL_WINDOW_FULLSCREEN_DESKTOP else 0);
				}
			case SDL_WINDOWEVENT;
				if event.window.event == {
					case SDL_WINDOWEVENT_MINIMIZED;
						game.is_minimized = true;
					case SDL_WINDOWEVENT_RESTORED;
						game.is_minimized = false;
				}
		}

		simulate_input(*event, mouse_x, mouse_y);
	}

	if game.is_minimized then return true;

	ImGui_ImplVulkan_NewFrame();
	ImGui_ImplSDL2_NewFrame();
	ImGui.NewFrame();

	{ // Update Physics
		scope_stat_time(.Physics);

		PxScene_simulate(game.phys.scene, xx dt, null, null, 0, true);
		error: u32 = 0;
		PxScene_fetchResults(game.phys.scene, true, *error);
	}

	{ // Update Game State
		scope_stat_time(.GameState);

		player := get_entity(game.state.player_id);

		for * ball: get_entities(Ball) {
			update_ball_fixed(ball);
		}

		update_player(player, dt);
	}

	update_imgui();

	draw();

	return true;
}

#program_export
game_shutdown :: () {
	Remap_Context();

	PxControllerManager_release(game.phys.controller_manager);
	PxScene_release(game.phys.scene);
	PxPhysics_release(game.phys.physics);
	PxDefaultCpuDispatcher_release(game.phys.dispatcher);
	PxFoundation_release(game.phys.foundation);

	gfx_shutdown();

	log("Goodbye!");
}

#program_export
game_memory :: () -> *void {
	Remap_Context();

	return game;
}
