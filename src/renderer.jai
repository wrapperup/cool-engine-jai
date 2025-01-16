// TODO: Un-hard code this stuff.
SHADOW_ID: TextureId : 0;
TONY_MC_MAPFACE_ID: TextureId : 1;
DFG_ID: TextureId : 2;
ENVIRONMENT_MAP_ID: TextureId : 3;
TEST_SH_0_3_3D_ID: TextureId : 4;
TEST_SH_4_7_3D_ID: TextureId : 5;
TEST_SH_8_9_3D_ID: TextureId : 6;
FONT_ATLAS_ID: TextureId : 7;

DEFAULT_SAMPLER_ID: u32 : 0;
SHADOW_SAMPLER_ID: u32 : 1;
ENVIRONMENT_SAMPLER_ID: u32 : 2;
FONT_SAMPLER_ID: u32 : 3;

RESOLVED_IMAGE_ID: u32 : 0;

MAX_BINDLESS_IMAGES :: 100;
RESERVED_BINDLESS_IMAGES_COUNT :: 10;
MAX_BINDLESS_SAMPLERS :: 32;

NUM_CASCADES: u32 : 3;

GPUDrawPushConstants :: struct @ShaderShared {
	global_data:    GPU_Pointer(GPUGlobalData);
	vertex_buffer:  GPU_Pointer(GPUVertex);
	model_matrices: GPU_Pointer(Mat4x4);
	materials:      GPU_Pointer(GPU_PBR_Material);
	model_index:    u32;
	material_index: MaterialId;
	num_cascades:   u32;
}

GPUDrawShadowDepthPushConstants :: struct @ShaderShared {
	vertex_buffer:  GPU_Pointer(GPUVertex);
	model_matrices: GPU_Pointer(Mat4x4);
	global_data:    GPU_Pointer(GPUGlobalData);
	model_index:    u32;
	cascade_index:  u32;
}

GPUSkinningPushConstants :: struct @ShaderShared {
	input_vertex_buffer:  GPU_Pointer(GPUVertex);
	output_vertex_buffer: GPU_Pointer(GPUVertex);
	joint_matrices:       GPU_Pointer(Mat4x4); // TODO: Make these Mat4x3 since they're just affine transforms.
	attrs:                GPU_Pointer(GPUSkeletonVertexAttribute);
	vertex_count:         u32;
}

GPUSkyboxPushConstants :: struct @ShaderShared {
	vertex_buffer: GPU_Pointer(GPUVertex);
	global_data:   GPU_Pointer(GPUGlobalData);
}

// TODO: Make these typed so the generator can generate the correct bindless type.
TextureId :: #type,isa u32;
SamplerId :: #type,isa u32;
MaterialId :: u32;
ShaderId :: #type,isa u32;

GPU_PBR_Material :: struct @ShaderShared {
	base_color:            TextureId; @As(Tex2D)
	normal_map:            TextureId; @As(Tex2D)
	ao_roughness_metallic: TextureId; @As(Tex2D)
}

GPUEnvironment :: struct @ShaderShared {
	sh_volume:        GPU_Pointer(Sh_Coefficients);
	point_lights:     GPU_Pointer(GPU_Point_Light);
	num_point_lights: u32;
}

GPUCascadeConfig :: struct @ShaderShared {
	split_dist: f32;
	bias:       f32;
	slope_bias: f32;
}

GPUGlobalData :: struct @ShaderShared {
	cascade_world_to_shadows: GPU_Pointer(Mat4x4);
	cascade_configs:          GPU_Pointer(GPUCascadeConfig);
	view_to_clip:             Mat4x4;
	world_to_view:			  Mat4x4;
	sun_color:                Vec3;
	sky_color:                Vec3;
	camera_pos:               Vec3;
	sun_direction:            Vec3;
	environment:              GPUEnvironment;
}

RenderState :: struct {
	frame_data: [FRAME_OVERLAP]GameFrameData;

	// Bindless textures, etc
	bindless_descriptor_layout: VkDescriptorSetLayout;
	bindless_descriptor_set:    VkDescriptorSet;
	global_uniform_data:        GPUGlobalData;

	scene_resources: struct {
		bindless_textures:            [..] GPUImage;
		bindless_texture_start_index: u32; // 0-10 is for reserved internal textures

		materials:                    [..] GPU_PBR_Material;
		materials_buffer:             GPU_Buffer(GPU_PBR_Material);

		point_lights:                 [256] GPU_Point_Light;
		point_light_buffer:           GPU_Buffer(GPU_Point_Light); // TODO: Maybe this is where we want to combine CPU/GPU buffers into 1?
	};

	temp_resources: struct {
		tony_mc_mapface:      GPUImage;
		dfg:                  GPUImage;
		env:                  GPUImage;
		mesh_image_sampler:   VkSampler;
		shadow_depth_sampler: VkSampler;
		env_sampler:          VkSampler;
	};
	
	shaders:        [..] Shader;
	global_session: *Slang.IGlobalSession;

	// Mesh pipelines
	mesh_pipeline_layout: VkPipelineLayout;
	mesh_shader:          ShaderId;
	model_matrices:       [..] Mat4x4;

	// Skeletal mesh pipelines
	skinning_pipeline_layout: VkPipelineLayout;
	skinning_shader:          ShaderId;

	// Shadow pipelines
	shadow_pipeline_layout:          VkPipelineLayout;
	mesh_shadow_shader:              ShaderId;
	shadow_depth_image:              GPUImage;
	shadow_depth_attach_image_views: [NUM_CASCADES]VkImageView;
	cascade_world_to_shadows:        [NUM_CASCADES]Mat4x4;
	cascade_configs:                 [NUM_CASCADES]GPUCascadeConfig;

	// Tonemapper pipelines
	tonemapper_shader:          ShaderId;
	tonemapper_pipeline_layout: VkPipelineLayout;

	// Skybox pipelines
	skybox_pipeline_layout: VkPipelineLayout;
	skybox_shader:          ShaderId;
	skybox_mesh:            MeshBuffers;
	draw_skybox:            bool;
}

GameFrameData :: struct {
	global_uniform_buffer:         GPU_Buffer(GPUGlobalData);
	model_matrices_buffer:         GPU_Buffer(Mat4x4);
	cascade_matrices_buffer:       GPU_Buffer(Mat4x4);
	cascade_configs_buffer:        GPU_Buffer(GPUCascadeConfig);
	test_preskinned_vertex_buffer: GPU_Buffer(GPUVertex);
	mesh_draws:                    [..] MeshDraw;
	skel_instances:                [..] *SkeletalMeshInstance;
}

current_frame_game :: () -> *GameFrameData {
	return *game.render_state.frame_data[current_frame_index()];
}

add_texture :: (image: GPUImage) -> TextureId {
	scene_resources := *game.render_state.scene_resources;
	texture_id := cast(TextureId, scene_resources.bindless_texture_start_index + cast(u32, scene_resources.bindless_textures.count));

	array_add(*scene_resources.bindless_textures, image);

	write_descriptor_set(game.render_state.bindless_descriptor_set, .[
		.{
			binding = 0,
			type = .SAMPLED_IMAGE,
			image_view = image.view,
			image_layout = .READ_ONLY_OPTIMAL,
			array_index = xx texture_id,
		},
	]);

	return texture_id;
}

// Writes a texture to the bindless ID and updates the descriptor.
set_texture :: (image: GPUImage, texture_id: TextureId) -> bool {
	resized := false;

	scene_resources := *game.render_state.scene_resources;

	// Ensure our texture id can fit
	if cast(TextureId, scene_resources.bindless_textures.count) <= texture_id {
		array_resize(*scene_resources.bindless_textures, texture_id + 1);
		resized = true;
	}

	scene_resources.bindless_textures[texture_id] = image;

	write_descriptor_set(game.render_state.bindless_descriptor_set, .[
		.{
			binding = 0,
			type = .SAMPLED_IMAGE,
			image_view = image.view,
			image_layout = .READ_ONLY_OPTIMAL,
			array_index = xx texture_id,
		},
	]);

	return resized;
}

add_material :: (material: GPU_PBR_Material) -> MaterialId {
	scene_resources := *game.render_state.scene_resources;
	material_id := cast(MaterialId, scene_resources.materials.count);

	array_add(*scene_resources.materials, material);

	staging_write_buffer(*scene_resources.materials_buffer, scene_resources.materials);

	return material_id;
}

//// INITIALIZATION
init_game_renderer :: () {
	init_shadow_maps();
	init_bindless_descriptors();
	init_pipelines();
	init_buffers();
	init_test_materials();
}

init_test_materials :: () {
	game.render_state.scene_resources.bindless_texture_start_index = RESERVED_BINDLESS_IMAGES_COUNT;

	game.render_state.scene_resources.materials_buffer = 
		create_buffer(GPU_PBR_Material, 20, .Storage);
	defer_destroy(game.render_state.scene_resources.materials_buffer);

	{
		color_tex := load_image_from_file("assets/textures/test_basecolor2.ktx2");
		defer_destroy(color_tex);

		normal_tex := load_image_from_file("assets/textures/test_normalmap.ktx2");
		defer_destroy(normal_tex);

		rma_tex := load_image_from_file("assets/textures/test_rma.ktx2");
		defer_destroy(rma_tex);

		color_id := add_texture(color_tex);
		normal_id := add_texture(normal_tex);
		rma_id := add_texture(rma_tex);

		add_material(.{color_id, normal_id, rma_id});
		add_material(.{color_id, normal_id, rma_id});
	}

	{
		color_tex := load_image_from_file("assets/textures/materialball2/basecolor.ktx2");
		defer_destroy(color_tex);

		normal_tex := load_image_from_file("assets/textures/materialball2/normalmap.ktx2");
		defer_destroy(normal_tex);

		rma_tex := load_image_from_file("assets/textures/materialball2/rma.ktx2");
		defer_destroy(rma_tex);

		color_id := add_texture(color_tex);
		normal_id := add_texture(normal_tex);
		rma_id := add_texture(rma_tex);

		add_material(.{color_id, normal_id, rma_id});
	}
}

init_shadow_maps :: () {
	extent := VkExtent3D.{game.config.shadow_map_size, game.config.shadow_map_size, 1};

	game.render_state.shadow_depth_image =
		create_image(.D32_SFLOAT, extent, .DEPTH_STENCIL_ATTACHMENT_BIT | .SAMPLED_BIT, array_layers = NUM_CASCADES);
	create_image_view(*game.render_state.shadow_depth_image, .DEPTH_BIT, ._2D_ARRAY);
	defer_destroy(game.render_state.shadow_depth_image);

	depth_image := *game.render_state.shadow_depth_image;

	for * view, i: game.render_state.shadow_depth_attach_image_views {
		view.* = create_image_view(depth_image.image, depth_image.format, .DEPTH_BIT, ._2D, 0, 1, xx i, 1);
		defer_destroy(view.*);
	}
}

init_bindless_descriptors :: () {
	game.render_state.bindless_descriptor_layout = create_descriptor_set_layout(
		.[
			.{binding = 0, type = .SAMPLED_IMAGE, count = MAX_BINDLESS_IMAGES},
			.{binding = 1, type = .SAMPLER, count = MAX_BINDLESS_SAMPLERS},
			.{binding = 2, type = .STORAGE_IMAGE},
		],
		.UPDATE_AFTER_BIND_POOL_BIT,
		.VERTEX_BIT | .FRAGMENT_BIT | .COMPUTE_BIT,
	);
	defer_destroy(game.render_state.bindless_descriptor_layout);

	game.render_state.bindless_descriptor_set = allocate_descriptor_set(
		*r_ctx.global_descriptor_allocator,
		game.render_state.bindless_descriptor_layout,
	);

	tony_mc_mapface := load_image_from_file("assets/textures/tonemapping/tony-mc-mapface.ktx2", ._3D, ._3D);
	defer_destroy(tony_mc_mapface);

	dfg := load_image_from_file("assets/gen/dfg.ktx2");
	defer_destroy(dfg);

	env := load_image_from_file("assets/gen/test_cubemap_ld.ktx2", ._2D, .CUBE);
	defer_destroy(env);

	// Default Texture Sampler
	TEMP_mesh_image_sampler := create_sampler(
		.LINEAR,
		.REPEAT,
		max_lod = 10.0,
		max_anisotropy = r_ctx.limits.maxSamplerAnisotropy,
	);
	defer_destroy(TEMP_mesh_image_sampler);

	// Shadow Depth Texture Sampler
	shadow_depth_sampler := create_sampler(.LINEAR, .CLAMP_TO_EDGE, .LESS_OR_EQUAL);
	defer_destroy(shadow_depth_sampler);

	env_sampler := create_sampler(.LINEAR, .CLAMP_TO_EDGE, max_lod = 8.0);
	defer_destroy(env_sampler);

	game.render_state.temp_resources.tony_mc_mapface = tony_mc_mapface;
	game.render_state.temp_resources.dfg = dfg;
	game.render_state.temp_resources.env = env;
	game.render_state.temp_resources.mesh_image_sampler = TEMP_mesh_image_sampler;
	game.render_state.temp_resources.shadow_depth_sampler = shadow_depth_sampler;
	game.render_state.temp_resources.env_sampler = env_sampler;

	write_builtin_bindless_descriptors();
}

// TODO: Automate this shit, there's no need to have any of this hard-coded.
write_builtin_bindless_descriptors :: () {
	tony_mc_mapface := game.render_state.temp_resources.tony_mc_mapface;
	dfg := game.render_state.temp_resources.dfg;
	env := game.render_state.temp_resources.env;
	mesh_image_sampler := game.render_state.temp_resources.mesh_image_sampler;
	shadow_depth_sampler := game.render_state.temp_resources.shadow_depth_sampler;
	env_sampler := game.render_state.temp_resources.env_sampler;

	write_descriptor_set(game.render_state.bindless_descriptor_set, .[
		.{ binding = 0, type = .SAMPLED_IMAGE, image_view = game.render_state.shadow_depth_image.view, image_layout = .DEPTH_READ_ONLY_OPTIMAL, array_index = SHADOW_ID },
		.{ binding = 0, type = .SAMPLED_IMAGE, image_view = tony_mc_mapface.view, image_layout = .READ_ONLY_OPTIMAL, array_index = TONY_MC_MAPFACE_ID },
		.{ binding = 0, type = .SAMPLED_IMAGE, image_view = dfg.view, image_layout = .READ_ONLY_OPTIMAL, array_index = DFG_ID },
		.{ binding = 0, type = .SAMPLED_IMAGE, image_view = env.view, image_layout = .READ_ONLY_OPTIMAL, array_index = ENVIRONMENT_MAP_ID },

		.{ binding = 1, type = .SAMPLER, sampler = mesh_image_sampler, image_layout = .READ_ONLY_OPTIMAL, array_index = DEFAULT_SAMPLER_ID },
		.{ binding = 1, type = .SAMPLER, sampler = shadow_depth_sampler, image_layout = .DEPTH_READ_ONLY_OPTIMAL, array_index = SHADOW_SAMPLER_ID },
		.{ binding = 1, type = .SAMPLER, sampler = env_sampler, image_layout = .READ_ONLY_OPTIMAL, array_index = ENVIRONMENT_SAMPLER_ID },

		.{ binding = 2, type = .STORAGE_IMAGE, image_view = r_ctx.resolve_image.view, image_layout = .GENERAL },
	]);
}

init_pipelines :: () {
	assert(Slang.slang_createGlobalSession(Slang.SLANG_API_VERSION, *game.render_state.global_session) == Slang.SLANG_OK);

	init_mesh_pipelines();
	init_skinning_pipelines();
	init_skybox_pipelines();
	init_tonemapper_pipelines();
}

init_mesh_pipelines :: () {
	game.render_state.mesh_pipeline_layout = create_pipeline_layout_pc(
		"Basic_Mesh_Pipeline_Layout",
		*game.render_state.bindless_descriptor_layout,
		GPUDrawPushConstants,
	);
	defer_destroy(game.render_state.mesh_pipeline_layout);

	game.render_state.mesh_shader = add_shader(
		"shaders/mesh.slang", 
		module => create_graphics_pipeline(
			name = "Basic_Mesh_Pipeline",
			pipeline_layout = game.render_state.mesh_pipeline_layout,
			shader = module,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = .BACK_BIT,
			front_face = .COUNTER_CLOCKWISE,
			depth = .{
				format = r_ctx.depth_image.format,
				compare_op = .LESS_OR_EQUAL,
				write_enabled = true
			},
			color_format = r_ctx.draw_image.format,
			multisampling_samples = msaa_samples(),
		)
	);
	defer_destroy(game.render_state.mesh_shader);

	game.render_state.shadow_pipeline_layout = create_pipeline_layout_pc(
		"Shadow_Depth_Pipeline_Layout",
		*game.render_state.bindless_descriptor_layout,
		GPUDrawShadowDepthPushConstants,
	);
	defer_destroy(game.render_state.shadow_pipeline_layout);

	game.render_state.mesh_shadow_shader = add_shader(
		"shaders/shadow_depth.slang", 
		module => create_graphics_pipeline(
			name = "Shadow_Depth_Pipeline",
			pipeline_layout = game.render_state.shadow_pipeline_layout,
			shader = module,
			vertex_entry = "vertex_main",
			fragment_entry = "", // TODO: Only need vertex depth currently for shadow maps.
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = 0,
			front_face = .COUNTER_CLOCKWISE,
			depth = .{
				format = r_ctx.depth_image.format, 
				compare_op = .LESS_OR_EQUAL,
				write_enabled = true
			},
		)
	);
	defer_destroy(game.render_state.mesh_shadow_shader);
}

init_skinning_pipelines :: () {
	game.render_state.skinning_pipeline_layout = create_pipeline_layout_pc("Skinning", null, GPUSkinningPushConstants, .COMPUTE_BIT);
	defer_destroy(game.render_state.skinning_pipeline_layout);

	game.render_state.skinning_shader = add_shader(
		"shaders/skinning.slang",
		module => create_compute_pipelines("Skinning", game.render_state.skinning_pipeline_layout, module)
	);
	defer_destroy(game.render_state.skinning_shader);
}

init_skybox_pipelines :: () {
	game.render_state.skybox_pipeline_layout = create_pipeline_layout_pc(
		"Skybox_Pipeline_Layout",
		*game.render_state.bindless_descriptor_layout,
		GPUSkyboxPushConstants,
	);
	defer_destroy(game.render_state.skybox_pipeline_layout);

	game.render_state.skybox_shader = add_shader(
		"shaders/skybox.slang", 
		module => create_graphics_pipeline(
			name = "Skybox_Pipeline",
			pipeline_layout = game.render_state.skybox_pipeline_layout,
			shader = module,
			input_topology = .TRIANGLE_LIST,
			polygon_mode = .FILL,
			cull_mode = .BACK_BIT,
			front_face = .COUNTER_CLOCKWISE,
			depth = .{
				format = r_ctx.depth_image.format,
				compare_op = .LESS_OR_EQUAL,
				write_enabled = true
			},
			color_format = r_ctx.draw_image.format,
			multisampling_samples = msaa_samples(),
		)
	);
	defer_destroy(game.render_state.skybox_shader);
}

init_tonemapper_pipelines :: () {
	game.render_state.tonemapper_pipeline_layout = create_pipeline_layout(
		"Tonemapper_Pipeline_Layout",
		*game.render_state.bindless_descriptor_layout,
	);
	defer_destroy(game.render_state.tonemapper_pipeline_layout);

	game.render_state.tonemapper_shader = add_shader(
		"shaders/tonemapping.slang", 
		module => create_compute_pipelines("Tonemapper_Pipeline", game.render_state.tonemapper_pipeline_layout, module)
	);
	defer_destroy(game.render_state.tonemapper_shader);
}

init_buffers :: () {
	// Skybox 
	{
		mesh, ok := load_gpu_mesh_from_file("assets/meshes/static/skybox.glb");
		assert(ok);
		defer_destroy(mesh);
		game.render_state.skybox_mesh = mesh;
	}

	for * frame: game.render_state.frame_data {
		frame.global_uniform_buffer = create_buffer(GPUGlobalData, kind = .DynUniform);
		defer_destroy(frame.global_uniform_buffer);

		// TODO: This should be storage... probably.
		frame.model_matrices_buffer = create_buffer(Mat4x4, 16_384, .DynUniform);
		defer_destroy(frame.model_matrices_buffer);

		// TODO: This should be storage... probably?
		frame.cascade_matrices_buffer = create_buffer(Mat4x4, NUM_CASCADES, .DynUniform, name = "Cascade Matrices");
		defer_destroy(frame.cascade_matrices_buffer);

		// TODO: This should be storage... probably?
		frame.cascade_configs_buffer = create_buffer(GPUCascadeConfig, NUM_CASCADES, .DynUniform);
		defer_destroy(frame.cascade_configs_buffer);
	}

	comp_coeffs := process_sh_coefficients_from_cubemap_file("assets/gen/test_cubemap_ld.ktx2");
	// comp_coeffs := process_sh_coefficients_from_equirectangular_file("assets/gen/test_equirectangular.ktx2")

	sh_volume_buf := create_buffer(Sh_Coefficients, kind = .Storage);
	defer_destroy(sh_volume_buf);

	staging_write_buffer(*sh_volume_buf, *comp_coeffs);

	environment := *game.render_state.global_uniform_data.environment;

	// epic name mega struct cancer this fucking sucks
	game.render_state.scene_resources.point_light_buffer = create_buffer(
		GPU_Point_Light,
		game.render_state.scene_resources.point_lights.count,
		.Storage,
	);
	defer_destroy(game.render_state.scene_resources.point_light_buffer);

	environment.* = .{
		sh_volume        = sh_volume_buf.ptr,
		point_lights     = game.render_state.scene_resources.point_light_buffer.ptr,
		num_point_lights = xx game.render_state.scene_resources.point_lights.count,
	};

	array_reserve(*game.render_state.model_matrices, 16_000);
}

get_shader :: (id: ShaderId) -> *Shader {
	return *game.render_state.shaders[id];
}

add_shader :: (path: string, pipeline_create_callback: ShaderCreatePipelineCallback) -> ShaderId {
	shader := init_shader(path, pipeline_create_callback);

	id : ShaderId = xx game.render_state.shaders.count;
	array_add(*game.render_state.shaders, shader);

	return id;
}

defer_destroy :: (shader_id: ShaderId) {
	defer_destroy(get_shader(shader_id).*);
}

check_shader_hotreload :: () -> bool {
	needs_reload := false;
	// TODO: SPEED: Maybe iter this across frames?
	for * shader: game.render_state.shaders {
		if is_outdated(shader) {
			shader.needs_recompile = true;
			needs_reload = true;
		}
	}

	return needs_reload;
}

hotreload_modified_shaders :: () -> bool {
	// TODO: SPEED: Maybe iter this across frames?
	for * shader: game.render_state.shaders {
		if shader.needs_recompile {
			ok := reload_shader_pipeline(shader);
			defer_destroy(shader.pipeline); // Kinda leaky, but it's fine.
			shader.needs_recompile = false;
			bump_shader(shader);
			return ok;
		}
	}

	return false;
}

draw :: () {
	scope_stat_time(.Render);

	#if DEBUG {
		if check_shader_hotreload() {
			vk_check(vkDeviceWaitIdle(r_ctx.device));
			hotreload_start := current_time_monotonic();
			if hotreload_modified_shaders() {
				hotreload_end := current_time_monotonic();
				log("Shaders hotreloaded in %", to_float64_seconds(hotreload_end - hotreload_start));
			} else {
				log_error("Shaders failed to load!");
			}
		}
	}

	// TEMP: test draw command
	for * ball: get_entities(Ball) {
		draw_skeletal_mesh(*ball.skel_mesh_instance, ball.material, ball.translation, ball.rotation, VEC_ONE);
	}

	for static_mesh: get_entities(StaticMesh) {
		draw_mesh(static_mesh.mesh, static_mesh.material, static_mesh.translation, static_mesh.rotation, VEC_ONE);
	}

	cmd := begin_command_buffer();

	update_buffers();

	// TODO: This updates every frame... probably bad?
	write_builtin_bindless_descriptors();

	// Begin Skinning pass
	for instance: current_frame_game().skel_instances {
		transition_buffer(
			cmd,
			instance.preskinned_vertex_buffers[current_frame_index()],
			.MEMORY_READ_BIT,
			.MEMORY_WRITE_BIT,
			r_ctx.graphics_queue_family,
		);
		skinning_pass(cmd, instance);
		transition_buffer(
			cmd,
			instance.preskinned_vertex_buffers[current_frame_index()],
			.MEMORY_WRITE_BIT,
			.MEMORY_READ_BIT,
			r_ctx.graphics_queue_family,
		);
	}
	// End skinning pass

	// Begin shadow pass
	transition_image(cmd, game.render_state.shadow_depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL);
	for view, i: game.render_state.shadow_depth_attach_image_views {
		shadow_map_pass(cmd, xx i);
	}
	// End shadow pass

	// Clear
	transition_image(cmd, r_ctx.draw_image.image, .UNDEFINED, .GENERAL);
	background_pass(cmd);

	// Begin mesh pass
	transition_image(cmd, r_ctx.draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL);
	transition_image(cmd, r_ctx.depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL);
	transition_image(cmd, game.render_state.shadow_depth_image.image, .DEPTH_ATTACHMENT_OPTIMAL, .DEPTH_READ_ONLY_OPTIMAL);
	if game.render_state.draw_skybox {
		skybox_pass(cmd);
	}
	geometry_pass(cmd);
	// End mesh pass

	final_image: VkImage;
	if game.view_state == {
		case .SceneDepth;
			transition_image(cmd, r_ctx.depth_image.image, .DEPTH_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL);
			final_image = r_ctx.depth_image.image;
		case .ShadowDepth;
			transition_image(cmd, game.render_state.shadow_depth_image.image, .DEPTH_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL);
			final_image = game.render_state.shadow_depth_image.image;
		case .SceneColor;
			if msaa_enabled() {
				// Resolve MSAA
				transition_image(cmd, r_ctx.draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL);
				transition_image(cmd, r_ctx.resolve_image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL);

				ex := r_ctx.draw_extent;

				resolve_region := VkImageResolve.{
					srcSubresource = .{
						mipLevel = 0,
						aspectMask = .COLOR_BIT,
						baseArrayLayer = 0,
						layerCount = 1
					},
					srcOffset = .{0, 0, 0},
					dstSubresource = .{
						mipLevel = 0, 
						aspectMask = .COLOR_BIT, 
						baseArrayLayer = 0, 
						layerCount = 1
					},
					dstOffset = .{0, 0, 0},
					extent = .{ex.width, ex.height, 1},
				};

				vkCmdResolveImage(
					cmd,
					// r_ctx.draw_image.image,
					r_ctx.draw_image.image,
					.TRANSFER_SRC_OPTIMAL,
					r_ctx.resolve_image.image,
					.TRANSFER_DST_OPTIMAL,
					1,
					*resolve_region,
				);

				transition_image(cmd, r_ctx.resolve_image.image, .TRANSFER_DST_OPTIMAL, .GENERAL);
				post_processing_pass(cmd);

				// Prepare swapchain image
				transition_image(cmd, r_ctx.resolve_image.image, .GENERAL, .TRANSFER_SRC_OPTIMAL);
				final_image = r_ctx.resolve_image.image;
			} else {
				post_processing_pass(cmd);
				// Prepare swapchain image
				transition_image(cmd, r_ctx.draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL);
				final_image = r_ctx.draw_image.image;
			}
	}

	copy_image_to_swapchain(cmd, final_image, r_ctx.draw_extent);

	submit(cmd);

	array_reset(*current_frame_game().mesh_draws);
	array_reset(*current_frame_game().skel_instances);
	array_reset(*game.render_state.model_matrices);
}

skinning_pass :: (cmd: VkCommandBuffer, instance: *SkeletalMeshInstance) {
	vkCmdBindPipeline(cmd, .COMPUTE, get_shader(game.render_state.skinning_shader).pipeline);

	cmd_push_constants(
		cmd,
		game.render_state.skinning_pipeline_layout,
		stages = .COMPUTE_BIT,
		push_constants = GPUSkinningPushConstants.{
			input_vertex_buffer = instance.skel.buffers.vertex_buffer.ptr,
			output_vertex_buffer = instance.preskinned_vertex_buffers[current_frame_index()].ptr,
			attrs = instance.skel.buffers.skel_vert_attrs_buffer.ptr,
			joint_matrices = instance.joint_matrices_buffers[current_frame_index()].ptr,
			vertex_count = instance.skel.buffers.vertex_count,
		}
	);

	vkCmdDispatch(cmd, xx ceil(cast(f32, instance.skel.buffers.vertex_count) / 64.0), 1, 1);
}

// TODO: Encode this as indirect draw args instead.
MeshDraw :: struct {
	vertex_buffer_address: GPU_Pointer(GPUVertex);
	index_buffer:          VkBuffer;
	index_count:           u32;
	model_index:           u32;
	material_index:        MaterialId;
}

draw_mesh :: (mesh: MeshBuffers, material: MaterialId, translation: Vec3, rotation: Quat, scale: Vec3) {
	model_index := game.render_state.model_matrices.count;

	array_add(
		*current_frame_game().mesh_draws,
		MeshDraw.{
			vertex_buffer_address = mesh.vertex_buffer.ptr,
			index_buffer = mesh.index_buffer.buffer,
			index_count = mesh.index_count,
			model_index = xx model_index,
			material_index = material,
		},
	);

	model_to_world := make_translation_matrix4(translation)
		* make_scale_matrix4(scale)
		* rotation_matrix(Mat4x4, rotation);

	array_add(*game.render_state.model_matrices, model_to_world);
}

draw_skeletal_mesh :: (
	instance: *SkeletalMeshInstance,
	material: MaterialId,
	translation: Vec3,
	rotation: Quat,
	scale: Vec3
) {
	model_index := game.render_state.model_matrices.count;

	array_add(*current_frame_game().skel_instances, instance);
	array_add(
		*current_frame_game().mesh_draws,
		MeshDraw.{
			vertex_buffer_address = instance.preskinned_vertex_buffers[current_frame_index()].ptr,
			index_buffer = instance.skel.buffers.index_buffer.buffer,
			index_count = instance.skel.buffers.index_count,
			model_index = xx model_index,
			material_index = material,
		},
	);

	model_to_world := make_translation_matrix4(translation)
		* make_scale_matrix4(scale)
		* rotation_matrix(Mat4x4, rotation);

	array_add(*game.render_state.model_matrices, model_to_world);
}

shadow_map_pass :: (cmd: VkCommandBuffer, cascade: u32) {
	image_view := game.render_state.shadow_depth_attach_image_views[cascade];
	clear_value := VkClearValue.{depthStencil = .{depth = 1.0}};
	depth_attachment := init_attachment_info(image_view, *clear_value, .DEPTH_ATTACHMENT_OPTIMAL);

	width := game.render_state.shadow_depth_image.extent.width;
	height := game.render_state.shadow_depth_image.extent.height;

	render_info := init_rendering_info(.{width, height}, null, *depth_attachment);
	vkCmdBeginRendering(cmd, *render_info);

	set_viewport_and_scissor(cmd, game.render_state.shadow_depth_image.extent);

	vkCmdBindPipeline(cmd, .GRAPHICS, get_shader(game.render_state.mesh_shadow_shader).pipeline);
	vkCmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		game.render_state.mesh_pipeline_layout,
		0,
		1,
		*game.render_state.bindless_descriptor_set,
		0,
		null,
	);

	for mesh_draw: current_frame_game().mesh_draws {
		vkCmdBindIndexBuffer(cmd, mesh_draw.index_buffer, 0, .UINT32);

		cmd_push_constants(
			cmd,
			game.render_state.shadow_pipeline_layout,
			GPUDrawShadowDepthPushConstants.{
				vertex_buffer = mesh_draw.vertex_buffer_address,
				model_matrices = current_frame_game().model_matrices_buffer.ptr,
				global_data = current_frame_game().global_uniform_buffer.ptr,
				model_index = mesh_draw.model_index,
				cascade_index = cascade,
			}
		);

		vkCmdDrawIndexed(cmd, mesh_draw.index_count, 1, 0, 0, 0);
	}

	vkCmdEndRendering(cmd);
}

background_pass :: (cmd: VkCommandBuffer) {
	clear_color := VkClearColorValue.{
		_float32 = .[0, 0, 0, 1],
	};

	clear_range := init_image_subresource_range(.COLOR_BIT);

	vkCmdClearColorImage(cmd, r_ctx.draw_image.image, .GENERAL, *clear_color, 1, *clear_range);
}

geometry_pass :: (cmd: VkCommandBuffer) {
	// begin a render pass  connected to our draw image
	color_attachment := init_attachment_info(r_ctx.draw_image.view, null, .GENERAL);
	clear_value := VkClearValue.{depthStencil = .{depth = 1.0}};
	depth_attachment := init_attachment_info(
		r_ctx.depth_image.view,
		*clear_value,
		.DEPTH_ATTACHMENT_OPTIMAL,
	);

	// Start render pass.
	render_info := init_rendering_info(r_ctx.draw_extent, *color_attachment, *depth_attachment);
	vkCmdBeginRendering(cmd, *render_info);

	set_viewport_and_scissor(cmd, r_ctx.draw_extent);

	vkCmdBindPipeline(cmd, .GRAPHICS, get_shader(game.render_state.mesh_shader).pipeline);
	vkCmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		game.render_state.mesh_pipeline_layout,
		0,
		1,
		*game.render_state.bindless_descriptor_set,
		0,
		null,
	);

	for mesh_draw: current_frame_game().mesh_draws {
		vkCmdBindIndexBuffer(cmd, mesh_draw.index_buffer, 0, .UINT32);

		cmd_push_constants(
			cmd,
			game.render_state.mesh_pipeline_layout,
			GPUDrawPushConstants.{
				global_data = current_frame_game().global_uniform_buffer.ptr,
				vertex_buffer = mesh_draw.vertex_buffer_address,
				model_matrices = current_frame_game().model_matrices_buffer.ptr,
				materials = game.render_state.scene_resources.materials_buffer.ptr,
				model_index = mesh_draw.model_index,
				material_index = mesh_draw.material_index,
				num_cascades = NUM_CASCADES,
}
		);

		vkCmdDrawIndexed(cmd, mesh_draw.index_count, 1, 0, 0, 0);
	}

	vkCmdEndRendering(cmd);
}

skybox_pass :: (cmd: VkCommandBuffer) {
	// begin a render pass  connected to our draw image
	color_attachment := init_attachment_info(r_ctx.draw_image.view, null, .COLOR_ATTACHMENT_OPTIMAL);
	clear_value := VkClearValue.{depthStencil = .{depth = 1.0}};
	depth_attachment := init_attachment_info(
		r_ctx.depth_image.view,
		*clear_value,
		.DEPTH_ATTACHMENT_OPTIMAL,
	);

	// Start render pass.
	render_info := init_rendering_info(r_ctx.draw_extent, *color_attachment, *depth_attachment);
	vkCmdBeginRendering(cmd, *render_info);

	set_viewport_and_scissor(cmd, r_ctx.draw_extent);

	vkCmdBindPipeline(cmd, .GRAPHICS, get_shader(game.render_state.skybox_shader).pipeline);
	vkCmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		game.render_state.skybox_pipeline_layout,
		0,
		1,
		*game.render_state.bindless_descriptor_set,
		0,
		null,
	);
	vkCmdBindIndexBuffer(cmd, game.render_state.skybox_mesh.index_buffer.buffer, 0, .UINT32);

	cmd_push_constants(
		cmd,
		game.render_state.skybox_pipeline_layout,
		GPUSkyboxPushConstants.{
			vertex_buffer = game.render_state.skybox_mesh.vertex_buffer.ptr,
			global_data = current_frame_game().global_uniform_buffer.ptr,
		},
	);

	vkCmdDrawIndexed(cmd, game.render_state.skybox_mesh.index_count, 1, 0, 0, 0);
	vkCmdEndRendering(cmd);
}

post_processing_pass :: (cmd: VkCommandBuffer) {
	vkCmdBindPipeline(cmd, .COMPUTE, get_shader(game.render_state.tonemapper_shader).pipeline);
	vkCmdBindDescriptorSets(
		cmd,
		.COMPUTE,
		game.render_state.tonemapper_pipeline_layout,
		0,
		1,
		*game.render_state.bindless_descriptor_set,
		0,
		null,
	);

	vkCmdDispatch(
		cmd,
		xx (ceil(cast(f32, r_ctx.draw_extent.width) / 16.0)),
		xx (ceil(cast(f32, r_ctx.draw_extent.height) / 16.0)),
		1,
	);
}

calculate_shadow_view_projection_matrices :: (near: f32 = 0.1, far: f32 = 300) {
	cascade_split_lambda := game.config.shadow_cascade_split_lambda;

	cascade_splits: [NUM_CASCADES] f32;

	clip_range := far - near;
	ratio := far / near;

	// Calculate split depths based on view camera frustum
	// Based on method presented in https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch10.html
	for i: 0 .. NUM_CASCADES - 1 {
		p := (cast(f32, i) + 1) / cast(f32, NUM_CASCADES);
		log := near * pow(ratio, p);
		uniform := near + clip_range * p;
		d := cascade_split_lambda * (log - uniform) + uniform;
		cascade_splits[i] = (d - near) / clip_range;
	}

	last_near := near;
	for i: 0 .. NUM_CASCADES - 1 {
		split_dist := cascade_splits[i];

		test_far := near + split_dist * clip_range;

		world_to_clip := get_current_projection_matrix_clipped(near = last_near, far = test_far) * get_current_view_matrix();
		clip_to_world := inverse(world_to_clip);

		CORNERS_NDC :: Vec4.[
			.{-1.0, -1.0, -1.0, 1.0},
			.{-1.0, -1.0, 1.0, 1.0},
			.{-1.0, 1.0, -1.0, 1.0},
			.{-1.0, 1.0, 1.0, 1.0},
			.{1.0, -1.0, -1.0, 1.0},
			.{1.0, -1.0, 1.0, 1.0},
			.{1.0, 1.0, -1.0, 1.0},
			.{1.0, 1.0, 1.0, 1.0},
		];

		corners_ws: [8]Vec4;
		for pos_fs, j: CORNERS_NDC {
			pos_ws := clip_to_world * pos_fs;
			corners_ws[j] = pos_ws / pos_ws.w;

			if i == 1 {
				debug_draw_dot(corners_ws[j].xyz);
			}
		}

		center_ws: Vec3;
		for corner_ws: corners_ws {
			center_ws += corner_ws.xyz;
		}
		center_ws /= corners_ws.count;

		sun_dir := game.state.environment.sun_direction;

		radius: f32;
		for corner: corners_ws {
			// distance := length(corner - center_ws)
			// radius = max(radius, distance)

			distance_x := abs(corner.x - center_ws.x);
			distance_y := abs(corner.y - center_ws.y);
			distance_z := abs(corner.z - center_ws.z);

			new_radius := ceil(max(distance_x, distance_y, distance_z) / 4.0) * 4.0;
			radius = max(new_radius, distance_x, distance_y, distance_z);
		}

		aabb: Aabb;
		aabb.min = Vec3.{-radius, -radius, -radius};
		aabb.max = -aabb.min;

		cascade_world_to_view := make_look_at_matrix(center_ws, center_ws + sun_dir, .{0.0, 1.0, 0.0}, x_is_forward = false);
		cascade_view_to_clip := orthographic_projection_matrix(aabb.min.x, aabb.max.x, aabb.min.y, aabb.max.y, aabb.max.z * 3, aabb.min.z, depth_range_01 = true);

		if game.config.use_stable_shadow_maps {
			sMapSize := cast(f32, game.config.shadow_map_size);

			shadowMatrix := cascade_view_to_clip * cascade_world_to_view;
			shadowOrigin := Vec4.{0, 0, 0, 1};
			shadowOrigin = shadowMatrix * shadowOrigin; // to World space
			shadowOrigin *= sMapSize / 2.0;

			roundedOrigin := shadowOrigin;
			roundedOrigin.x = floor(shadowOrigin.x);
			roundedOrigin.y = floor(shadowOrigin.y);
			roundedOrigin.z = floor(shadowOrigin.z);
			roundOffset := roundedOrigin - shadowOrigin;
			roundOffset *= 2.0 / sMapSize;

			shadowProj := cascade_view_to_clip;
			shadowProj._14 += roundOffset.x;
			shadowProj._24 += roundOffset.y;
			// Don't offset Z or W.
			cascade_view_to_clip = shadowProj;
		}

		game.render_state.cascade_world_to_shadows[i] = cascade_view_to_clip * cascade_world_to_view;
		game.render_state.cascade_configs[i] = .{
			split_dist = test_far,
			bias       = game.config.shadow_map_biases[i],
			slope_bias = game.config.shadow_map_slope_biases[i],
		};

		last_near = test_far;
	}
}

update_buffers :: () {
	global_uniform_data := *game.render_state.global_uniform_data;
	player := get_entity(game.state.player_id);

	// TODO: Clean this shit up
	global_uniform_data.view_to_clip = get_current_projection_matrix();
	global_uniform_data.world_to_view = get_current_view_matrix();
	global_uniform_data.sun_color = game.state.environment.sun_color;
	global_uniform_data.sky_color = game.state.environment.sky_color;
	global_uniform_data.camera_pos = ifx player != null then player.translation else .{0, 0, 0};
	global_uniform_data.sun_direction = game.state.environment.sun_direction;
	global_uniform_data.environment.num_point_lights = xx entities_count(Point_Light);
	global_uniform_data.cascade_world_to_shadows = current_frame_game().cascade_matrices_buffer.ptr;
	global_uniform_data.cascade_configs = current_frame_game().cascade_configs_buffer.ptr;

	write_buffer(*current_frame_game().cascade_matrices_buffer, game.render_state.cascade_world_to_shadows);
	write_buffer(*current_frame_game().cascade_configs_buffer, game.render_state.cascade_configs);
	write_buffer(*current_frame_game().global_uniform_buffer, global_uniform_data);

	write_buffer(*current_frame_game().model_matrices_buffer, game.render_state.model_matrices);

	for * ball: get_entities(Ball) {
		write_buffer(
			*ball.skel_mesh_instance.joint_matrices_buffers[current_frame_index()],
			ball.skel_animator.calc_joints,
		);
	}

	for * point_light, i: get_entities(Point_Light) {
		if i >= game.render_state.scene_resources.point_lights.count then break;
		game.render_state.scene_resources.point_lights[i] = point_light_to_gpu(point_light);
	}

	staging_write_buffer(
		*game.render_state.scene_resources.point_light_buffer,
		game.render_state.scene_resources.point_lights,
	);

	calculate_shadow_view_projection_matrices();
}
