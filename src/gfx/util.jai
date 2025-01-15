init_command_pool_create_info :: (queue_family_index: u32, flags: VkCommandPoolCreateFlags) -> VkCommandPoolCreateInfo {
	info := VkCommandPoolCreateInfo.{
		sType = .COMMAND_POOL_CREATE_INFO,
		pNext = null,
		queueFamilyIndex = queue_family_index,
		flags = flags,
	};

	return info;
}

init_command_buffer_allocate_info :: (pool: VkCommandPool, count: u32) -> VkCommandBufferAllocateInfo {
	info := VkCommandBufferAllocateInfo.{
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext = null,

		commandPool = pool,
		commandBufferCount = count,
		level = .PRIMARY,
	};

	return info;
}

init_fence_create_info :: (flags: VkFenceCreateFlags) -> VkFenceCreateInfo {
	info := VkFenceCreateInfo.{
		sType = .FENCE_CREATE_INFO,
		pNext = null,
		flags = flags,
	};

	return info;
}

init_semaphore_create_info :: (flags: VkSemaphoreCreateFlags) -> VkSemaphoreCreateInfo {
	info := VkSemaphoreCreateInfo.{
		sType = .SEMAPHORE_CREATE_INFO,
		pNext = null,
		flags = flags,
	};

	return info;
}

init_command_buffer_begin_info :: (flags: VkCommandBufferUsageFlags) -> VkCommandBufferBeginInfo {
	info := VkCommandBufferBeginInfo.{
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		pNext = null,

		pInheritanceInfo = null,
		flags = flags,
	};

	return info;
}

init_image_subresource_range :: (aspect_mask: VkImageAspectFlags) -> VkImageSubresourceRange {
	sub_image := VkImageSubresourceRange.{
		aspectMask     = aspect_mask,
		baseMipLevel   = 0,
		levelCount     = VK_REMAINING_MIP_LEVELS,
		baseArrayLayer = 0,
		layerCount     = VK_REMAINING_ARRAY_LAYERS,
	};

	return sub_image;
}

init_semaphore_submit_info :: (stage_mask: VkPipelineStageFlags2, semaphore: VkSemaphore) -> VkSemaphoreSubmitInfo {
	info := VkSemaphoreSubmitInfo.{
		sType       = .SEMAPHORE_SUBMIT_INFO,
		pNext       = null,
		semaphore   = semaphore,
		stageMask   = stage_mask,
		deviceIndex = 0,
		value       = 1,
	};

	return info;
}

init_command_buffer_submit_info :: (cmd: VkCommandBuffer) -> VkCommandBufferSubmitInfo {
	info := VkCommandBufferSubmitInfo.{
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		pNext         = null,
		commandBuffer = cmd,
		deviceMask    = 0,
	};

	return info;
}

init_submit_info :: (
	cmd: *VkCommandBufferSubmitInfo,
	signal_semaphore_info: *VkSemaphoreSubmitInfo,
	wait_semaphore_info: *VkSemaphoreSubmitInfo
) -> VkSubmitInfo2 {
	info := VkSubmitInfo2.{
		sType                    = .SUBMIT_INFO_2,
		pNext                    = null,
		waitSemaphoreInfoCount   = xx ifx wait_semaphore_info == null then 0 else 1,
		pWaitSemaphoreInfos      = wait_semaphore_info,
		signalSemaphoreInfoCount = xx ifx signal_semaphore_info == null then 0 else 1,
		pSignalSemaphoreInfos    = signal_semaphore_info,
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = cmd,
	};

	return info;
}

init_image_create_info :: (
	format: VkFormat,
	usage_flags: VkImageUsageFlags,
	extent: VkExtent3D,
	mip_levels: u32 = 1,
	array_layers: u32 = 1,
	msaa_samples: VkSampleCountFlags = ._1_BIT,
	image_type: VkImageType = ._2D,
	flags: VkImageCreateFlags = 0,
	tiling: VkImageTiling = .OPTIMAL
) -> VkImageCreateInfo {
	info := VkImageCreateInfo.{
		sType       = .IMAGE_CREATE_INFO,
		imageType   = image_type,
		format      = format,
		extent      = extent,
		mipLevels   = mip_levels,
		arrayLayers = array_layers,
		samples     = msaa_samples,
		tiling      = tiling,
		usage       = usage_flags,
		flags       = flags,
	};

	return info;
}

init_imageview_create_info :: (
	format: VkFormat,
	image: VkImage,
	aspect_flags: VkImageAspectFlags,
	view_type: VkImageViewType = ._2D,
	base_mip_level: u32 = 0,
	mip_count: u32 = 1,
	base_array_layer: u32 = 0,
	layer_count: u32 = 1
) -> VkImageViewCreateInfo {
	info := VkImageViewCreateInfo.{
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = view_type,
		image = image,
		format = format,
		subresourceRange = .{baseMipLevel = base_mip_level, levelCount = mip_count, baseArrayLayer = base_array_layer, layerCount = layer_count, aspectMask = aspect_flags},
	};

	return info;
}

init_sampler_create_info :: (
	filter: VkFilter,
	address_mode: VkSamplerAddressMode,
	compare_op: VkCompareOp = .NEVER,
	border_color: VkBorderColor = .FLOAT_TRANSPARENT_BLACK,
	max_lod: f32 = 1.0
) -> VkSamplerCreateInfo {
	sampler_create_info := VkSamplerCreateInfo.{
		sType         = .SAMPLER_CREATE_INFO,
		magFilter     = filter,
		minFilter     = filter,
		mipmapMode    = .LINEAR,
		addressModeU  = address_mode,
		addressModeV  = address_mode,
		addressModeW  = address_mode,
		mipLodBias    = 0.0,
		maxAnisotropy = 1.0,
		minLod        = 0.0,
		maxLod        = max_lod,
		borderColor   = border_color,
		compareOp     = compare_op,
		compareEnable = ifx compare_op != .NEVER then VK_TRUE else VK_FALSE,
	};

	return sampler_create_info;
}

init_attachment_info :: (
	view: VkImageView,
	clear: *VkClearValue,
	layout: VkImageLayout,
	resolve_image_view: VkImageView = null,
	resolve_image_layout: VkImageLayout = .UNDEFINED
) -> VkRenderingAttachmentInfo {
	attachment := VkRenderingAttachmentInfo.{
		sType              = .RENDERING_ATTACHMENT_INFO,
		imageView          = view,
		imageLayout        = layout,
		loadOp             = ifx clear != null then .CLEAR else .LOAD,
		storeOp            = .STORE,
		clearValue         = ifx clear != null then clear.* else .{},
		resolveMode        = ifx resolve_image_view == null then .NONE else .AVERAGE_BIT,
		resolveImageView   = resolve_image_view,
		resolveImageLayout = resolve_image_layout,
	};

	return attachment;
}

init_rendering_info :: (
	area: VkExtent2D,
	color_attachment: *VkRenderingAttachmentInfo,
	depth_attachment: *VkRenderingAttachmentInfo
) -> VkRenderingInfo {
	info := VkRenderingInfo.{
		sType = .RENDERING_INFO,
		layerCount = 1,
		renderArea = .{extent = area},
		pDepthAttachment = depth_attachment,
		pColorAttachments = color_attachment,
		colorAttachmentCount = xx ifx color_attachment != null then 1 else 0,
	};

	return info;
}

init_pipeline_layout_create_info :: () -> VkPipelineLayoutCreateInfo {
	info := VkPipelineLayoutCreateInfo.{
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext                  = null,
		flags                  = 0,
		setLayoutCount         = 0,
		pSetLayouts            = null,
		pushConstantRangeCount = 0,
		pPushConstantRanges    = null,
	};

	return info;
}

init_pipeline_shader_stage_create_info :: (
	stage: VkShaderStageFlags,
	shader_module: VkShaderModule,
	entry: string = "main"
) -> VkPipelineShaderStageCreateInfo {
	info := VkPipelineShaderStageCreateInfo.{
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = stage,
		module = shader_module,
		pName  = entry.data,
	};

	return info;
}
