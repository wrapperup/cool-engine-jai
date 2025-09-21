load_image_from_file :: (
	filename: string,
	image_type: VkImageType = ._2D,
	image_view_type: VkImageViewType = ._2D,
	out_width: *u32 = null,
	out_height: *u32 = null,
	out_depth: *u32 = null
) -> GPUImage {
	ktx_texture: *ktxTexture2;

	ktx_result := ktxTexture2_CreateFromNamedFile(temp_c_string(filename), .LOAD_IMAGE_DATA_BIT, *ktx_texture);
	assert(ktx_result == .SUCCESS, "Failed to load image.");
	defer ktxTexture2_Destroy(ktx_texture);

	num_faces := ktx_texture.numFaces; // Faces (cubemap)
	num_levels := ktx_texture.numLevels; // Mip levels
	num_layers := ktx_texture.numLayers; // Array levels

	is_array := ktx_texture.isArray;
	is_cubemap := ktx_texture.isCubemap;

	// Don't support cubemap arrays... if that's even a thing.
	assert(!(is_cubemap && is_array));

	// Assign cubemap faces instead.
	if is_cubemap then num_layers = num_faces;

	size := ktxTexture_GetDataSize(ktx_texture);
	data := ktxTexture_GetData(ktx_texture);
	format := ktxTexture2_GetVkFormat(ktx_texture);

	extent := VkExtent3D.{ktx_texture.baseWidth, ktx_texture.baseHeight, ktx_texture.baseDepth};

	image := create_image(
		format,
		extent,
		.SAMPLED_BIT | .TRANSFER_DST_BIT,
		image_type = image_type,
		mip_levels = num_levels,
		array_layers = num_layers,
		flags = ifx is_cubemap then .CUBE_COMPATIBLE_BIT else cast(VkImageCreateFlagBits, 0),
	);
	create_image_view(*image, .COLOR_BIT, image_view_type, 0, 0);

	staging := create_buffer(u8, xx size, .Staging);
	defer destroy_buffer(*staging);

	mapped_data := staging.info.pMappedData;
	memcpy(mapped_data, data, xx size);

	copy_regions: [..] VkBufferImageCopy;
	defer array_free(copy_regions);

	for i: 0 .. num_layers-1 {
		for level: 0 .. num_levels-1 {
			offset: u64;
			if is_cubemap {
				ret := ktxTexture_GetImageOffset(ktx_texture, level, 0, i, *offset);
				assert(ret == .SUCCESS);
			} else {
				ret := ktxTexture_GetImageOffset(ktx_texture, level, i, 0, *offset);
				assert(ret == .SUCCESS);
			}

			copy_region := VkBufferImageCopy.{
				imageSubresource = .{
					aspectMask = .COLOR_BIT,
					mipLevel = level,
					baseArrayLayer = i,
					layerCount = 1,
				},
				imageExtent = .{
					width = max(ktx_texture.baseWidth >> level, 1),
					height = max(ktx_texture.baseHeight >> level, 1),
					depth = max(ktx_texture.baseDepth >> level, 1),
				},
				bufferOffset = xx offset,
			};

			array_add(*copy_regions, copy_region);
		}
	}

	{
		cmd := immediate_submit();
		transition_image(cmd, image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL);
		vkCmdCopyBufferToImage(cmd, staging.buffer, image.image, .TRANSFER_DST_OPTIMAL, xx copy_regions.count, copy_regions.data);
		transition_image(cmd, image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);
	}

	if out_width != null {
		out_width.* = ktx_texture.baseWidth;
	}
	if out_height != null {
		out_height.* = ktx_texture.baseHeight;
	}
	if out_depth != null {
		out_depth.* = ktx_texture.baseDepth;
	}

	return image;
}

load_image_from_bytes :: (
	bytes: []u8,
	extent: VkExtent3D,
	image_format: VkFormat,
	image_type: VkImageType = ._2D,
	image_view_type: VkImageViewType = ._2D
) -> GPUImage {
	image := create_image(image_format, extent, .SAMPLED_BIT | .TRANSFER_DST_BIT, image_type = image_type);
	create_image_view(*image, .COLOR_BIT, image_view_type);

	// Next, upload image data to vk GPUImage
	staging := create_buffer(u8, bytes.count, .Staging);
	defer destroy_buffer(staging);

	data := staging.info.pMappedData;

	memcpy(data, bytes.data, bytes.count);

	{
		cmd := immediate_submit();
		transition_image(cmd, image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL);

		copy_region := VkBufferImageCopy.{
			bufferOffset = 0,
			bufferRowLength = 0,
			bufferImageHeight = 0,
			imageSubresource = .{aspectMask = .COLOR_BIT, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
			imageExtent = extent,
		};

		vkCmdCopyBufferToImage(cmd, staging.buffer, image.image, .TRANSFER_DST_OPTIMAL, 1, *copy_region);

		transition_image(cmd, image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);
	}

	return image;
}

write_buffer_to_ktx_file :: (
	filename: string,
	buffer: *GPUBuffer,
	extent: VkExtent3D,
	format: VkFormat,
	format_size: u32,
	image_type: VkImageType = ._2D,
	levels: u32 = 1,
	layers: u32 = 1,
	faces: u32 = 1,
	is_array := false
) {
	info := buffer.info;
	max_size := info.size;
	data := info.pMappedData;

	assert(data != null);

	ktx_texture: *ktxTexture2;
	createInfo := ktxTextureCreateInfo.{
		vkFormat        = xx format,
		baseWidth       = extent.width,
		baseHeight      = extent.height,
		baseDepth       = extent.depth,
		numDimensions   = xx (image_type + 1),
		numLevels       = levels,
		numLayers       = layers,
		numFaces        = faces,
		isArray         = is_array,
		generateMipmaps = false,
	};

	ktxTexture2_Create(*createInfo, .ALLOC_STORAGE, *ktx_texture);

	offset: u32;
	for level: 0 .. levels-1 {
		for face: 0 .. faces-1 {
			w := extent.width >> level;
			h := extent.width >> level;

			size := w * h * format_size;

			assert(cast(u32, offset) + size <= cast(u32, max_size));

			res := ktxTexture_SetImageFromMemory(ktx_texture, level, 0, face, data + offset, xx size);
			assert(res == .SUCCESS);

			offset += size;
		}
	}

	res := ktxTexture_WriteToNamedFile(ktx_texture, temp_c_string(filename));
	assert(res == .SUCCESS);

	ktxTexture_Destroy(ktx_texture);
}
