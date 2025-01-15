DescriptorBinding :: struct {
	binding: u32;
	type:    VkDescriptorType;
	count:   u32;
}

create_descriptor_set_layout :: (
	bindings: [] DescriptorBinding,
	descriptor_set_layout_flags: VkDescriptorSetLayoutCreateFlags = 0,
	stage_flags: VkShaderStageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
	debug_name: string = .{},
	loc := #caller_location
) -> VkDescriptorSetLayout {
	descriptor_set_bindings: [..] VkDescriptorSetLayoutBinding;
	defer array_free(descriptor_set_bindings);

	array_resize(*descriptor_set_bindings, bindings.count);

	for binding, i: bindings {
		descriptor_set_bindings[i] = VkDescriptorSetLayoutBinding.{
			stageFlags      = stage_flags,
			binding         = binding.binding,
			descriptorType  = binding.type,
			descriptorCount = ifx binding.count > 0 then binding.count else 1, // Default to 1. 0 doesn't make any sense.
		};
	}

	info := VkDescriptorSetLayoutCreateInfo.{
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pBindings    = descriptor_set_bindings.data,
		bindingCount = xx descriptor_set_bindings.count,
		flags        = descriptor_set_layout_flags,
	};

	set: VkDescriptorSetLayout;
	vk_check(vkCreateDescriptorSetLayout(r_ctx.device, *info, null, *set));

	#if DEBUG {
		if debug_name.count > 0 {
			debug_set_object_name(set, debug_name);
		}
	}

	return set;
}

DescriptorAllocator :: struct {
	sets_per_pool: u32;
	pool_ratios:   [..] PoolSizeRatio;
	ready_pools:   [..] VkDescriptorPool;
	full_pools:    [..] VkDescriptorPool;
	flags:         VkDescriptorPoolCreateFlags;
	debug_name:    string;
}

PoolSizeRatio :: struct {
	type:  VkDescriptorType;
	ratio: f32;
}

init_descriptor_allocator :: (
	allocator: *DescriptorAllocator,
	max_sets: u32,
	pool_ratios: [] PoolSizeRatio,
	flags: VkDescriptorPoolCreateFlags = 0,
	debug_name: string = .{},
	loc := #caller_location
) {
	array_reset(*allocator.pool_ratios);

	for ratio: pool_ratios {
		array_add(*allocator.pool_ratios, ratio);
	}

	new_pool := create_pool(allocator, max_sets, pool_ratios, flags);
	allocator.flags = flags;

	#if DEBUG {
		if debug_name.count > 0 {
			allocator.debug_name = debug_name;
		}
	}

	array_add(*allocator.ready_pools, new_pool);
}

get_pool :: (allocator: *DescriptorAllocator) -> VkDescriptorPool {
	if allocator.ready_pools.count > 0 {
		return pop(*allocator.ready_pools);
	} else {
		return create_pool(allocator, allocator.sets_per_pool, allocator.pool_ratios, allocator.flags);
	}
}

create_pool :: (allocator: *DescriptorAllocator, set_count: u32, pool_ratios: [] PoolSizeRatio, flags: VkDescriptorPoolCreateFlags = 0) -> VkDescriptorPool {
	pool_sizes: [..] VkDescriptorPoolSize;
	defer array_free(pool_sizes);

	array_reserve(*pool_sizes, pool_ratios.count);

	for ratio, i: pool_ratios {
		array_add(*pool_sizes, VkDescriptorPoolSize.{type = ratio.type, descriptorCount = xx (ratio.ratio * cast(f32, set_count))});
	}

	pool_info := VkDescriptorPoolCreateInfo.{
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = flags,
		maxSets       = set_count,
		poolSizeCount = xx pool_sizes.count,
		pPoolSizes    = pool_sizes.data,
	};

	new_pool: VkDescriptorPool;
	vk_check(vkCreateDescriptorPool(r_ctx.device, *pool_info, null, *new_pool));

	#if DEBUG {
		debug_set_object_name(new_pool, allocator.debug_name);
	}

	return new_pool;
}

reset_pools :: (allocator: *DescriptorAllocator) {
	for pool: allocator.ready_pools {
		vkResetDescriptorPool(r_ctx.device, pool, 0);
	}

	for pool: allocator.full_pools {
		vkResetDescriptorPool(r_ctx.device, pool, 0);
		array_add(*allocator.ready_pools, pool);
	}

	array_reset(*allocator.full_pools);
}

destroy_pools :: (allocator: *DescriptorAllocator) {
	for pool: allocator.ready_pools {
		vkDestroyDescriptorPool(r_ctx.device, pool, null);
	}
	array_reset(*allocator.ready_pools);

	for pool: allocator.full_pools {
		vkDestroyDescriptorPool(r_ctx.device, pool, null);
	}
	array_reset(*allocator.full_pools);
}

allocate_descriptor_set :: (
	allocator: *DescriptorAllocator,
	layout: VkDescriptorSetLayout,
	debug_name: string = .{},
	loc := #caller_location
) -> VkDescriptorSet {
	pool := get_pool(allocator);

	alloc_info := VkDescriptorSetAllocateInfo.{
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = null,
		descriptorPool     = pool,
		descriptorSetCount = 1,
		pSetLayouts        = *layout,
	};

	descriptor_set: VkDescriptorSet;
	result := vkAllocateDescriptorSets(r_ctx.device, *alloc_info, *descriptor_set);

	if result == .ERROR_OUT_OF_POOL_MEMORY || result == .ERROR_FRAGMENTED_POOL {
		array_add(*allocator.full_pools, pool);

		pool = get_pool(allocator);
		alloc_info.descriptorPool = pool;

		// Try again, if it fails then we're goofed anyway.
		result = vkAllocateDescriptorSets(r_ctx.device, *alloc_info, *descriptor_set);

		vk_check(result);
	}

	array_add(*allocator.ready_pools, pool);

	#if DEBUG {
		if debug_name.count > 0 {
			debug_set_object_name(descriptor_set, debug_name);
		}
	}


	return descriptor_set;
}

destroy_descriptor_allocator :: (allocator: *DescriptorAllocator) {
	array_free(allocator.pool_ratios);
	array_free(allocator.ready_pools);
	array_free(allocator.full_pools);
}

DescriptorWrite :: struct {
	binding:      u32;
	type:         VkDescriptorType;
	image_view:   VkImageView;
	sampler:      VkSampler;
	image_layout: VkImageLayout;
	buffer:       VkBuffer;
	array_index:  u32;
}

is_image_descriptor_type :: (ty: VkDescriptorType) -> bool {
	return ty == .STORAGE_IMAGE || ty == .SAMPLER || ty == .SAMPLED_IMAGE || ty == .COMBINED_IMAGE_SAMPLER;
}

write_descriptor_set :: (descriptor_set: VkDescriptorSet, writes: [] DescriptorWrite) {
	// Collect writes in the convenient format into vk's.
	descriptor_writes: [..] VkWriteDescriptorSet;
	defer array_free(descriptor_writes);

	image_infos: [..] VkDescriptorImageInfo;
	defer array_free(image_infos);

	buffer_infos: [..] VkDescriptorBufferInfo;
	defer array_free(buffer_infos);

	for write: writes {
		if is_image_descriptor_type(write.type) {
			assert(write.buffer == null, "Descriptor write is an image type, but the buffer field was set.");

			image_info := VkDescriptorImageInfo.{
				imageLayout = write.image_layout,
				imageView   = write.image_view,
				sampler     = write.sampler,
			};

			array_add(*image_infos, image_info);

			descriptor_write := VkWriteDescriptorSet.{
				sType           = .WRITE_DESCRIPTOR_SET,
				pNext           = null,
				dstBinding      = write.binding,
				dstSet          = descriptor_set,
				dstArrayElement = write.array_index,
				descriptorCount = 1,
				descriptorType  = write.type,
				pImageInfo      = *image_infos[image_infos.count - 1],
			};

			array_add(*descriptor_writes, descriptor_write);
		} else {
			assert(write.image_layout == .UNDEFINED, "Descriptor write is a buffer type, but the image_layout field was set.");
			assert(write.image_view == null, "Descriptor write is a buffer type, but the image_view field was set.");
			assert(write.sampler == null, "Descriptor write is a buffer type, but the sampler field was set.");

			buffer_info := VkDescriptorBufferInfo.{
				buffer = write.buffer,
			};

			array_add(*buffer_infos, buffer_info);

			descriptor_write := VkWriteDescriptorSet.{
				sType           = .WRITE_DESCRIPTOR_SET,
				pNext           = null,
				dstBinding      = write.binding,
				dstSet          = descriptor_set,
				dstArrayElement = write.array_index,
				descriptorCount = 1,
				descriptorType  = write.type,
				pBufferInfo     = *buffer_infos[buffer_infos.count - 1],
			};

			array_add(*descriptor_writes, descriptor_write);
		}
	}

	// Finally write out all of the writes
	vkUpdateDescriptorSets(r_ctx.device, xx descriptor_writes.count, descriptor_writes.data, 0, null);
}
