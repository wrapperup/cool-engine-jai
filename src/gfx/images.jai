GPU_Image :: struct {
	image:      VkImage;
	view:       VkImageView;
	allocation: VmaAllocation;

	extent:       VkExtent3D;
	format:       VkFormat;
	mip_levels:   u32;
	array_layers: u32;

    usage: VkImageUsageFlags;
}

// This allocates on the GPU, make sure to call `destroy_image` or add to the deletion queue when you are finished with the image.
create_image :: (
	format: VkFormat,
	extent: VkExtent3D,
	image_usage_flags: VkImageUsageFlags,
	mip_levels: u32 = 1,
	array_layers: u32 = 1,
	image_type: VkImageType = ._2D,
	msaa_samples: VkSampleCountFlags = ._1_BIT,
	tiling: VkImageTiling = .OPTIMAL,
	flags: VkImageCreateFlags = 0,
	alloc_flags: VmaAllocationCreateFlags = 0,
	usage: VmaMemoryUsage = .GPU_ONLY
) -> GPU_Image {
	img_alloc_info := VmaAllocationCreateInfo.{
		usage         = usage,
		requiredFlags = .DEVICE_LOCAL_BIT,
		flags         = alloc_flags,
	};

	img_info := init_image_create_info(
		format,
		image_usage_flags,
		extent,
		mip_levels,
		array_layers,
		msaa_samples,
		image_type,
		flags,
		tiling,
	);

	new_image := GPU_Image.{
		extent       = extent,
		format       = format,
		mip_levels   = mip_levels,
		array_layers = array_layers,
        usage        = image_usage_flags,
	};

	vk_check(vmaCreateImage(r_ctx.allocator, *img_info, *img_alloc_info, *new_image.image, *new_image.allocation, null));

	return new_image;
}

destroy_image :: (image: GPU_Image) {
	if image.view != null {
		vkDestroyImageView(r_ctx.device, image.view, null);
	}
	vmaDestroyImage(r_ctx.allocator, image.image, image.allocation);
}

create_image_view :: (
	image: *GPU_Image,
	aspect_flags: VkImageAspectFlags,
	view_type: VkImageViewType = ._2D,
	base_mip_level: u32 = 0,
	base_array_layer: u32 = 0
) {
	image.view = create_image_view(
		image.image,
		image.format,
		aspect_flags,
		view_type,
		base_mip_level,
		image.mip_levels,
		base_array_layer,
		image.array_layers,
	);
}

create_image_view :: (
	image: VkImage,
	format: VkFormat,
	aspect_flags: VkImageAspectFlags,
	view_type: VkImageViewType = ._2D,
	base_mip_level: u32 = 0,
	mip_levels: u32 = 1,
	base_array_layer: u32 = 0,
	array_layers: u32 = 1
) -> VkImageView {
	info := VkImageViewCreateInfo.{
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = view_type,
		image = image,
		format = format,
		subresourceRange = .{
			baseMipLevel = base_mip_level,
			levelCount = mip_levels,
			baseArrayLayer = base_array_layer,
			layerCount = array_layers,
			aspectMask = aspect_flags,
		},
	};

	image_view: VkImageView;
	vk_check(vkCreateImageView(r_ctx.device, *info, null, *image_view));

	return image_view;
}

create_sampler :: (
	filter: VkFilter,
	address_mode: VkSamplerAddressMode,
	compare_op: VkCompareOp = .NEVER,
	border_color: VkBorderColor = .FLOAT_TRANSPARENT_BLACK,
	max_lod: f32 = 1.0,
	max_anisotropy: f32 = 1.0
) -> VkSampler {
	sampler_create_info := VkSamplerCreateInfo.{
		sType            = .SAMPLER_CREATE_INFO,
		magFilter        = filter,
		minFilter        = filter,
		mipmapMode       = .LINEAR,
		addressModeU     = address_mode,
		addressModeV     = address_mode,
		addressModeW     = address_mode,
		mipLodBias       = 0.0,
		anisotropyEnable = ifx max_anisotropy > 1.0 then VK_TRUE else VK_FALSE,
		maxAnisotropy    = max_anisotropy,
		minLod           = 0.0,
		maxLod           = max_lod,
		borderColor      = border_color,
		compareOp        = compare_op,
		compareEnable    = ifx compare_op != .NEVER then VK_TRUE else VK_FALSE,
	};

	sampler: VkSampler;
	vk_check(vkCreateSampler(r_ctx.device, *sampler_create_info, null, *sampler));

	return sampler;
}

transition_image :: (cmd: VkCommandBuffer, image: VkImage, current_layout: VkImageLayout, new_layout: VkImageLayout) {
	image_barrier := VkImageMemoryBarrier2.{
		sType         = .IMAGE_MEMORY_BARRIER_2,
		pNext         = null,
		srcStageMask  = .ALL_COMMANDS_BIT,
		srcAccessMask = .MEMORY_WRITE_BIT,
		dstStageMask  = .ALL_COMMANDS_BIT,
		dstAccessMask = .MEMORY_WRITE_BIT | .MEMORY_READ_BIT,
		oldLayout     = current_layout,
		newLayout     = new_layout,
	};

	aspect_mask: VkImageAspectFlags =
		ifx (new_layout == .DEPTH_ATTACHMENT_OPTIMAL || new_layout == .DEPTH_READ_ONLY_OPTIMAL) then .DEPTH_BIT else .COLOR_BIT;

	image_barrier.subresourceRange = init_image_subresource_range(aspect_mask);
	image_barrier.image = image;

	dep_info := VkDependencyInfo.{
		sType                   = .DEPENDENCY_INFO,
		pNext                   = null,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = *image_barrier,
	};

	vkCmdPipelineBarrier2(cmd, *dep_info);
}

copy_image_to_image :: (cmd: VkCommandBuffer, source: VkImage, destination: VkImage, src_size: VkExtent2D, dst_size: VkExtent2D) {
	blit_region := VkImageBlit2.{
		sType = .IMAGE_BLIT_2,
		pNext = null,
	};

	blit_region.srcOffsets[1].x = xx src_size.width;
	blit_region.srcOffsets[1].y = xx src_size.height;
	blit_region.srcOffsets[1].z = 1;

	blit_region.dstOffsets[1].x = xx dst_size.width;
	blit_region.dstOffsets[1].y = xx dst_size.height;
	blit_region.dstOffsets[1].z = 1;

	blit_region.srcSubresource.aspectMask = .COLOR_BIT;
	blit_region.srcSubresource.baseArrayLayer = 0;
	blit_region.srcSubresource.layerCount = 1;
	blit_region.srcSubresource.mipLevel = 0;
	
	blit_region.dstSubresource.aspectMask = .COLOR_BIT;
	blit_region.dstSubresource.baseArrayLayer = 0;
	blit_region.dstSubresource.layerCount = 1;
	blit_region.dstSubresource.mipLevel = 0;

	blit_info := VkBlitImageInfo2.{
		sType          = .BLIT_IMAGE_INFO_2,
		pNext          = null,
		dstImage       = destination,
		dstImageLayout = .TRANSFER_DST_OPTIMAL,
		srcImage       = source,
		srcImageLayout = .TRANSFER_SRC_OPTIMAL,
		filter         = .LINEAR,
		regionCount    = 1,
		pRegions       = *blit_region,
	};

	vkCmdBlitImage2(cmd, *blit_info);
}
