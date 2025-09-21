DEFAULT_VERTEX_ENTRY :: "vertex_main";
DEFAULT_FRAGMENT_ENTRY :: "fragment_main";
DEFAULT_COMPUTE_ENTRY :: "compute_main";

create_pipeline_layout :: (
	debug_name: string,
	descriptor_set_layout: *VkDescriptorSetLayout,
	$T: Type,
	stage_flags: VkShaderStageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
	loc := #caller_location
) -> VkPipelineLayout {
	buffer_range := VkPushConstantRange.{
		offset     = 0,
		size       = size_of(T),
		stageFlags = stage_flags,
	};

	pipeline_layout_info := init_pipeline_layout_create_info();
    // #if T != void {
        pipeline_layout_info.pPushConstantRanges = *buffer_range;
        pipeline_layout_info.pushConstantRangeCount = 1;
    // }
	pipeline_layout_info.pSetLayouts = descriptor_set_layout;
	pipeline_layout_info.setLayoutCount = xx ifx descriptor_set_layout != null then 1 else 0;

	pipeline_layout: VkPipelineLayout;
	vk_check(vkCreatePipelineLayout(r_ctx.device, *pipeline_layout_info, null, *pipeline_layout));

	#if DEBUG {
		debug_set_object_name(pipeline_layout, debug_name);
	}

	return pipeline_layout;
}

Pipeline :: struct {
    layout: VkPipelineLayout;
    pipeline: VkPipeline;
    stages: VkShaderStageFlags;
}

GraphicsPipeline :: struct {
    using common: Pipeline;
    stages = .VERTEX_BIT | .FRAGMENT_BIT;
}

GraphicsPipelineDepth :: struct {
    write_enabled: bool;
    compare_op:    VkCompareOp;
    format:        VkFormat;
}

create_graphics_pipeline :: (
	name: string,
	shader: VkShaderModule,
	input_topology: VkPrimitiveTopology,
	polygon_mode: VkPolygonMode,
	front_face: VkFrontFace,
	cull_mode: VkCullModeFlags,
	depth: GraphicsPipelineDepth,
	$push_constant: Type = void,
	multisampling_samples: VkSampleCountFlags = ._1_BIT,
	color_format: VkFormat = .UNDEFINED,
	vertex_entry: string = DEFAULT_VERTEX_ENTRY,
	fragment_entry: string = DEFAULT_FRAGMENT_ENTRY,
    loc := #caller_location
) -> GraphicsPipeline {
    pipeline_layout: VkPipelineLayout;
    pipeline: VkPipeline;
    
    {
        pipeline_layout = create_pipeline_layout(name, *r_ctx.bindless_system.descriptor_layout, push_constant, loc = loc);
    }

    {
        pipeline_builder := pb_init();
        defer pb_free(pipeline_builder);

        pipeline_builder.pipeline_layout = pipeline_layout;
        pb_set_shaders(*pipeline_builder, shader, vertex_entry, fragment_entry);
        pb_set_input_topology(*pipeline_builder, input_topology);
        pb_set_polygon_mode(*pipeline_builder, polygon_mode);
        pb_set_cull_mode(*pipeline_builder, cull_mode, front_face);
        pb_set_multisampling(*pipeline_builder, multisampling_samples);

        pb_disable_blending(*pipeline_builder);
        
        pb_enable_depthtest(*pipeline_builder, depth.write_enabled, depth.compare_op);
        pb_set_depth_format(*pipeline_builder, depth.format);

        if color_format == .UNDEFINED {
            pb_disable_color_attachment(*pipeline_builder);
        } else {
            pb_set_color_attachment_format(*pipeline_builder, color_format);
        }

        pipeline = pb_build_pipeline(*pipeline_builder);

        debug_set_object_name(pipeline, name);
    }

	return .{
        layout = pipeline_layout,
        pipeline = pipeline,
    };
}

ComputePipeline :: struct {
    using common: Pipeline;
    stages = .COMPUTE_BIT;
}

create_compute_pipeline :: (
	name: string,
	shader: VkShaderModule,
	$push_constant: Type = void,
	entry: string = DEFAULT_COMPUTE_ENTRY,
	loc := #caller_location
) -> ComputePipeline {
    pipeline_layout := create_pipeline_layout(name, *r_ctx.bindless_system.descriptor_layout, push_constant, .COMPUTE_BIT, loc = loc);

	stage_info := VkPipelineShaderStageCreateInfo.{
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = .COMPUTE_BIT,
		module = shader,
		pName  = entry.data,
	};

	compute_pipeline_create_info := VkComputePipelineCreateInfo.{
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = pipeline_layout,
		stage  = stage_info,
	};

	pipeline: VkPipeline;
	vk_check(vkCreateComputePipelines(r_ctx.device, null, 1, *compute_pipeline_create_info, null, *pipeline), loc);

	debug_set_object_name(pipeline, name);

	return .{
        layout = pipeline_layout,
        pipeline = pipeline,
    };
}

// ====================================================================

load_shader_module :: (file_name: string) -> VkShaderModule, bool {
	buffer, ok := read_entire_file(file_name);
	if !ok {
		return null, false;
	}

	defer free(buffer);

	return load_shader_module_from_bytes(xx buffer), true;
}

load_shader_module_from_bytes :: (bytes: [] u8) -> VkShaderModule, bool {
	// Byte length needs to be a multiple of 4
	if bytes.count % 4 != 0 {
		return null, false;
	}

	info := VkShaderModuleCreateInfo.{
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = xx bytes.count, // codeSize needs to be in bytes
		pCode    = cast(*u32, bytes.data), // code needs to be in 32bit words
	};

	module: VkShaderModule;
	if vkCreateShaderModule(r_ctx.device, *info, null, *module) != .SUCCESS {
		return null, false;
	}

	return module, true;
}

destroy_shader_module :: (module: VkShaderModule) {
	vkDestroyShaderModule(r_ctx.device, module, null);
}


//==============================================================


PipelineBuilder :: struct {
	shader_stages:           [..] VkPipelineShaderStageCreateInfo;
	input_assembly:          VkPipelineInputAssemblyStateCreateInfo;
	rasterizer:              VkPipelineRasterizationStateCreateInfo;
	color_blend_attachment:  VkPipelineColorBlendAttachmentState;
	multisampling:           VkPipelineMultisampleStateCreateInfo;
	pipeline_layout:         VkPipelineLayout;
	depth_stencil:           VkPipelineDepthStencilStateCreateInfo;
	render_info:             VkPipelineRenderingCreateInfo;
	color_attachment_format: VkFormat;
}

// This allocates, be sure to call pb_free.
pb_init :: () -> PipelineBuilder {
	pb: PipelineBuilder;
	pb_clear(*pb);
	return pb;
}

pb_clear :: (builder: *PipelineBuilder) {
	builder.input_assembly = .{
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
	};
	builder.rasterizer = .{
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
	};
	builder.color_blend_attachment = .{};
	builder.multisampling = .{
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
	};
	builder.pipeline_layout = null;
	builder.depth_stencil = .{
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
	};
	builder.render_info = .{
		sType = .PIPELINE_RENDERING_CREATE_INFO,
	};
	builder.color_attachment_format = .UNDEFINED;

	array_reset(*builder.shader_stages);
}

pb_set_shaders :: (
	builder: *PipelineBuilder,
	shader: VkShaderModule,
	vertex_entry: string = DEFAULT_VERTEX_ENTRY,
	fragment_entry: string = DEFAULT_FRAGMENT_ENTRY
) {
	array_reset(*builder.shader_stages);
	if vertex_entry.count > 0 {
		array_add(*builder.shader_stages, init_pipeline_shader_stage_create_info(.VERTEX_BIT, shader, vertex_entry));
	}

	if fragment_entry.count > 0 {
		array_add(*builder.shader_stages, init_pipeline_shader_stage_create_info(.FRAGMENT_BIT, shader, fragment_entry));
	}
}

pb_set_input_topology :: (builder: *PipelineBuilder, topology: VkPrimitiveTopology) {
	builder.input_assembly.topology = topology;
	builder.input_assembly.primitiveRestartEnable = VK_FALSE;
}

pb_set_polygon_mode :: (builder: *PipelineBuilder, mode: VkPolygonMode) {
	builder.rasterizer.polygonMode = mode;
	builder.rasterizer.lineWidth = 1.0;
}

pb_set_cull_mode :: (builder: *PipelineBuilder, cull_mode: VkCullModeFlags, front_face: VkFrontFace) {
	builder.rasterizer.cullMode = cull_mode;
	builder.rasterizer.frontFace = front_face;
}

pb_set_multisampling_none :: (builder: *PipelineBuilder) {
	builder.multisampling.sampleShadingEnable = VK_FALSE;

	builder.multisampling.rasterizationSamples = ._1_BIT;
	builder.multisampling.minSampleShading = 1.0;
	builder.multisampling.pSampleMask = null;

	builder.multisampling.alphaToCoverageEnable = VK_FALSE;
	builder.multisampling.alphaToOneEnable = VK_FALSE;
}

pb_set_multisampling :: (builder: *PipelineBuilder, samples: VkSampleCountFlags) {
	builder.multisampling.sampleShadingEnable = VK_FALSE;

	builder.multisampling.rasterizationSamples = samples;
	builder.multisampling.minSampleShading = 1.0;
	builder.multisampling.pSampleMask = null;

	builder.multisampling.alphaToCoverageEnable = VK_FALSE;
	builder.multisampling.alphaToOneEnable = VK_FALSE;
}

pb_disable_blending :: (builder: *PipelineBuilder) {
	builder.color_blend_attachment.colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT;
	builder.color_blend_attachment.blendEnable = VK_FALSE;
}

pb_set_color_attachment_format :: (builder: *PipelineBuilder, format: VkFormat) {
	builder.color_attachment_format = format;

	builder.render_info.colorAttachmentCount = 1;
	builder.render_info.pColorAttachmentFormats = *builder.color_attachment_format;
}

pb_disable_color_attachment :: (builder: *PipelineBuilder) {
	builder.color_attachment_format = .UNDEFINED;

	builder.render_info.colorAttachmentCount = 0;
	builder.render_info.pColorAttachmentFormats = null;
}

pb_set_depth_format :: (builder: *PipelineBuilder, format: VkFormat) {
	builder.render_info.depthAttachmentFormat = format;
}

pb_disable_depthtest :: (builder: *PipelineBuilder) {
	builder.depth_stencil.depthTestEnable = VK_FALSE;
	builder.depth_stencil.depthWriteEnable = VK_FALSE;
	builder.depth_stencil.depthCompareOp = .NEVER;
	builder.depth_stencil.depthBoundsTestEnable = VK_FALSE;
	builder.depth_stencil.stencilTestEnable = VK_FALSE;
	builder.depth_stencil.front = .{};
	builder.depth_stencil.back = .{};
	builder.depth_stencil.minDepthBounds = 0.0;
	builder.depth_stencil.maxDepthBounds = 1.0;
}

pb_enable_depthtest :: (builder: *PipelineBuilder, depth_write_enable: bool, op: VkCompareOp) {
	builder.depth_stencil.depthTestEnable = VK_TRUE;
	builder.depth_stencil.depthWriteEnable = ifx depth_write_enable then VK_TRUE else VK_FALSE;
	builder.depth_stencil.depthCompareOp = op;
	builder.depth_stencil.depthBoundsTestEnable = VK_FALSE;
	builder.depth_stencil.stencilTestEnable = VK_FALSE;
	builder.depth_stencil.front = .{};
	builder.depth_stencil.back = .{};
	builder.depth_stencil.minDepthBounds = 0.0;
	builder.depth_stencil.maxDepthBounds = 1.0;
}

pb_build_pipeline :: (builder: *PipelineBuilder) -> VkPipeline {
	viewport_state := VkPipelineViewportStateCreateInfo.{
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	};

	color_blending := VkPipelineColorBlendStateCreateInfo.{
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = VK_FALSE,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = *builder.color_blend_attachment,
	};

	vertex_input_info := VkPipelineVertexInputStateCreateInfo.{
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	};

	state: [] VkDynamicState = .[.VIEWPORT, .SCISSOR];

	dynamicInfo := VkPipelineDynamicStateCreateInfo.{
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		pDynamicStates    = state.data,
		dynamicStateCount = xx state.count,
	};


	pipelineInfo := VkGraphicsPipelineCreateInfo.{
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = *builder.render_info,
		pStages             = builder.shader_stages.data,
		stageCount          = xx builder.shader_stages.count,
		pVertexInputState   = *vertex_input_info,
		pInputAssemblyState = *builder.input_assembly,
		pViewportState      = *viewport_state,
		pRasterizationState = *builder.rasterizer,
		pMultisampleState   = *builder.multisampling,
		pColorBlendState    = *color_blending,
		pDepthStencilState  = *builder.depth_stencil,
		layout              = builder.pipeline_layout,
		pDynamicState       = *dynamicInfo,
	};

	newPipeline: VkPipeline;
	if vkCreateGraphicsPipelines(r_ctx.device, null, 1, *pipelineInfo, null, *newPipeline) != .SUCCESS {
		log_error("Failed to create pipeline");
		return null;
	}

	return newPipeline;
}

pb_free :: (builder: PipelineBuilder) {
	array_free(builder.shader_stages);
}

// ====================================================================

