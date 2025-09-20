MAX_ROUGHNESS_LEVELS: u32 : 9;
PREFILTERED_DEFAULT_SIZE: u32 : 1024;

PrefilteredCubeMapPushConstants :: struct {
	mip_level:    u32;
	sample_count: u32;
}

PrefilteredCubeMapPass :: struct {
	descriptor_set_layout:         VkDescriptorSetLayout;
	descriptor_set:                VkDescriptorSet;
	pipeline:                      VkPipeline;
	pipeline_layout:               VkPipelineLayout;

	// Resources
	cube_image:                    GPU_Image;
	cube_sampler:                  VkSampler;
	prefilter_image:               GPU_Image;
	prefilter_image_views:         [MAX_ROUGHNESS_LEVELS]VkImageView;
	prefilter_image_mapped_buffer: GPU_Buffer(u8);
	width:                         u32;
	height:                        u32;
}


create_prefiltered_cubemap_pipeline :: (filename: string, out_width: u32, out_height: u32) -> PrefilteredCubeMapPass {
	pass := PrefilteredCubeMapPass.{
		width  = out_width,
		height = out_height,
	};

	pass.descriptor_set_layout = create_descriptor_set_layout(.[
			.{binding = 0, type = .COMBINED_IMAGE_SAMPLER},
			.{binding = 1, type = .STORAGE_IMAGE, count = MAX_ROUGHNESS_LEVELS}, // Count is for mipmap views.
		],
		.UPDATE_AFTER_BIND_POOL_BIT,
		.COMPUTE_BIT,
	);
	defer_destroy(pass.descriptor_set_layout);

	pass.descriptor_set = allocate_descriptor_set(*r_ctx.global_descriptor_allocator, pass.descriptor_set_layout);

	w, h: u32;
	pass.cube_image = load_image_from_file(filename, ._2D, .CUBE, *w, *h);
	pass.cube_sampler = create_sampler(.LINEAR, .CLAMP_TO_EDGE);

	if pass.width <= 0 then  pass.width = w;
	if pass.height <= 0 then pass.height = h;

	pass.prefilter_image = create_image(
		.R32G32B32A32_SFLOAT,
		.{pass.width, pass.height, 1},
		.STORAGE_BIT | .TRANSFER_SRC_BIT,
		MAX_ROUGHNESS_LEVELS,
		6,
	);

	write_descriptor_set(pass.descriptor_set, .[
		.{
			binding      = 0,
			type         = .COMBINED_IMAGE_SAMPLER, // We know this
			image_view   = pass.cube_image.view,
			sampler      = pass.cube_sampler,
			image_layout = .SHADER_READ_ONLY_OPTIMAL,
		},
	]);

	for i: 0 .. MAX_ROUGHNESS_LEVELS-1 {
		dview_info := init_imageview_create_info(
			pass.prefilter_image.format,
			pass.prefilter_image.image,
			.COLOR_BIT,
			._2D_ARRAY,
			i,
			1,
			0,
			6,
		);
		vk_check(vkCreateImageView(r_ctx.device, *dview_info, null, *pass.prefilter_image_views[i]));

		write_descriptor_set(pass.descriptor_set, .[
			.{
				binding      = 1,
				type         = .STORAGE_IMAGE, // We know this
				image_view   = pass.prefilter_image_views[i],
				image_layout = .GENERAL,
				array_index  = i,
			},
		]);
	}

	prefilter_shader, f_ok := load_shader_module("shaders/out/prefilter_env.spv");
	assert(f_ok, "Failed to load shaders.");

	pass.pipeline_layout = create_pipeline_layout("Environment Prefilter", *pass.descriptor_set_layout, PrefilteredCubeMapPushConstants, .COMPUTE_BIT);
	pass.pipeline, _ = create_compute_pipelines("Environment Prefiler", pass.pipeline_layout, prefilter_shader);

	destroy_shader_module(prefilter_shader);

	defer_destroy(pass.pipeline);
	defer_destroy(pass.pipeline_layout);

	size: u32;
	for level: 0 .. MAX_ROUGHNESS_LEVELS - 1 {
		w := pass.width >> level;
		h := pass.height >> level;
		size += xx (w * h * size_of(f32) * 4 * 6); // R32G32B32A32_SFLOAT
	}

	pass.prefilter_image_mapped_buffer = create_buffer(u8, size, .Readback);

	return pass;
}

run_prefilter_cubemap_pass :: (pass: *PrefilteredCubeMapPass, cmd: VkCommandBuffer, sample_count: u32 = 4096) {
	vkCmdBindPipeline(cmd, .COMPUTE, pass.pipeline);
	vkCmdBindDescriptorSets(cmd, .COMPUTE, pass.pipeline_layout, 0, 1, *pass.descriptor_set, 0, null);

	for level: 0 .. MAX_ROUGHNESS_LEVELS-1 {
		cmd_push_constants(
			cmd,
			pass.pipeline_layout,
			stages = .COMPUTE_BIT,
			push_constants = PrefilteredCubeMapPushConstants.{
				mip_level    = level,
				sample_count = sample_count,
			}
		);

		vkCmdDispatch(cmd, xx (ceil(cast(f32, pass.width >> level) / 16.0)), xx (ceil(cast(f32, pass.height >> level) / 16.0)), 6);
	}
}
