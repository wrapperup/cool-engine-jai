GPUBuffer :: struct($T: Type) #modify {
	return T != void, "Type must be sized.";
} {
	buffer:     VkBuffer;
	allocation: VmaAllocation;
	info:       VmaAllocationInfo;
	ptr:        GPUPtr(T);
}

GPUPtr :: struct($T: Type) {
	address: VkDeviceAddress;
}

// This is hopefully very common kinds of buffers
// you may typically want to create. Uniform and Storage
// buffers will always create a valid GPUPtr(T).
Buffer_Kind :: enum {
	Storage;    // Includes ptr
	Uniform;    // Includes ptr. However, prefer uniform access for speed.
	DynUniform; // Mapped uniform buffer // TODO: HOST_ACCESS_ALLOW_TRANSFER_INSTEAD_BIT
	Index;
	Staging;    // For CPU -> GPU writes onto device-local buffers.
	Readback;   // For GPU -> CPU reads from device-local buffers.
}

vk_buffer_flags :: (kind: Buffer_Kind) -> VkBufferUsageFlags, VmaAllocationCreateFlags  {
	if #complete kind == {
		case .Storage;    return (.TRANSFER_DST_BIT | .STORAGE_BUFFER_BIT | .SHADER_DEVICE_ADDRESS_BIT), (0);
		case .Uniform;    return (.TRANSFER_DST_BIT | .UNIFORM_BUFFER_BIT | .SHADER_DEVICE_ADDRESS_BIT), (0);
		case .DynUniform; return (.TRANSFER_DST_BIT | .UNIFORM_BUFFER_BIT | .SHADER_DEVICE_ADDRESS_BIT), (.MAPPED_BIT | .HOST_ACCESS_RANDOM_BIT);
		case .Index;      return (.TRANSFER_DST_BIT | .INDEX_BUFFER_BIT), (0);
		case .Staging;    return (.TRANSFER_SRC_BIT), (.MAPPED_BIT | .HOST_ACCESS_SEQUENTIAL_WRITE_BIT);
		case .Readback;   return (.TRANSFER_DST_BIT), (.MAPPED_BIT | .HOST_ACCESS_RANDOM_BIT);
	}
}

create_buffer :: (
	$T: Type,
	count: s64 = 1,
	kind: Buffer_Kind = .Storage,
	name := "",
	loc := #caller_location
) -> GPUBuffer(T) {
	alloc_size := size_of(T) * count;

	vk_usage_flags, vma_create_flags := vk_buffer_flags(kind);

	buffer_info := VkBufferCreateInfo.{
		sType = .BUFFER_CREATE_INFO,
		size = xx alloc_size,
		usage = vk_usage_flags,
	};

	vma_alloc_info := VmaAllocationCreateInfo.{
		usage = .AUTO,
		flags = vma_create_flags,
	};

	new_buffer: GPUBuffer(T);
	vk_check(vmaCreateBuffer(r_ctx.allocator, *buffer_info, *vma_alloc_info, *new_buffer.buffer, *new_buffer.allocation, *new_buffer.info), loc);

	if vk_usage_flags & .SHADER_DEVICE_ADDRESS_BIT {
		new_buffer.ptr = get_gpu_pointer(new_buffer);
	}

	#if DEBUG {
		if name.count > 0 {
			debug_set_object_name(new_buffer.buffer, name);
		} else {
			debug_set_object_name(new_buffer.buffer, type_to_string(type_info(T)));
		}
	}

	return new_buffer;
}

destroy_buffer :: (allocated_buffer: GPUBuffer) {
	vmaDestroyBuffer(r_ctx.allocator, allocated_buffer.buffer, allocated_buffer.allocation);
}

get_gpu_pointer :: (buffer: GPUBuffer($T)) -> GPUPtr(T) {
	device_address_info := VkBufferDeviceAddressInfo.{
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer.buffer,
	};

	return .{vkGetBufferDeviceAddress(r_ctx.device, *device_address_info)};
}

// Writes to the buffer with the input data at offset.
write_buffer :: (buffer: *GPUBuffer, in_data: *$T, offset: s64 = 0, loc := #caller_location) {
	size := size_of(T);
	assert(buffer.info.size >= cast(VkDeviceSize, size + offset), "The size of the data and offset is larger than the buffer", loc);

	data := buffer.info.pMappedData;
	memcpy(data + offset, in_data, size);
	vmaFlushAllocation(r_ctx.allocator, buffer.allocation, 0, U64_MAX); // VK_WHOLE_SIZE
}

// Writes to the buffer with the input array view at offset.
write_buffer :: (buffer: *GPUBuffer, in_data: []$T, offset: s64 = 0, loc := #caller_location) {
	size := size_of(T) * in_data.count;
	assert(buffer.info.size >= cast(VkDeviceSize, size + offset), "The size of the slice and offset is larger than the buffer", loc);

	data := buffer.info.pMappedData;
	memcpy(data + offset, in_data.data, size);
	vmaFlushAllocation(r_ctx.allocator, buffer.allocation, 0, U64_MAX); // VK_WHOLE_SIZE
}

// Uploads the data via a staging buffer. This is useful if your buffer is GPU only.
staging_write_buffer :: (buffer: *GPUBuffer, in_data: *$T, offset: s64 = 0, loc := #caller_location) {
	size := size_of(T);
	assert(buffer.info.size >= cast(VkDeviceSize, size + offset), "The size of the data and offset is larger than the buffer", loc);

	staging := create_buffer(u8, size, .Staging);
	write_buffer(*staging, in_data);

	{
		cmd := immediate_submit();
		region := VkBufferCopy.{
			dstOffset = xx offset,
			srcOffset = 0,
			size      = xx size,
		};

		vkCmdCopyBuffer(cmd, staging.buffer, buffer.buffer, 1, *region);
	}

	destroy_buffer(staging);
}

// Uploads the data via a staging buffer. This is useful if your buffer is GPU only.
staging_write_buffer :: (buffer: *GPUBuffer, in_data: []$T, offset: s64 = 0, loc := #caller_location) {
	size := size_of(T) * in_data.count;
	assert(buffer.info.size >= cast(VkDeviceSize, size + offset), "The size of the slice and offset is larger than the buffer", loc);

	staging := create_buffer(u8, size, .Staging);
	write_buffer(*staging, in_data);

	{
		cmd := immediate_submit();
		region := VkBufferCopy.{
			dstOffset = xx offset,
			srcOffset = 0,
			size      = xx size,
		};

		vkCmdCopyBuffer(cmd, staging.buffer, buffer.buffer, 1, *region);
	}

	destroy_buffer(staging);
}

transition_buffer :: (
	cmd: VkCommandBuffer,
	buffer: GPUBuffer,
	src_flags: VkAccessFlags2,
	dst_flags: VkAccessFlags2,
	queue_family_index: u32
) {
	buffer_memory_barrier := VkBufferMemoryBarrier2.{
		sType               = .BUFFER_MEMORY_BARRIER_2,
		pNext               = null,
		srcStageMask        = .VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
		srcAccessMask       = src_flags,
		dstStageMask        = .VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
		dstAccessMask       = dst_flags,
		buffer              = buffer.buffer,
		size                = buffer.info.size,
		srcQueueFamilyIndex = queue_family_index,
		dstQueueFamilyIndex = queue_family_index,
	};

	dep_info := VkDependencyInfo.{
		sType                    = .DEPENDENCY_INFO,
		pNext                    = null,
		bufferMemoryBarrierCount = 1,
		pBufferMemoryBarriers    = *buffer_memory_barrier,
	};

	vkCmdPipelineBarrier2(cmd, *dep_info);
}

// TODO: Do we need this? It would be useful I think at some point.
// It's specific push/pop functions will update a buffer automatically,
// and maps to a dynamic array.
// GPUDynamicArray :: struct {
//     using _: GPUBuffer;
// }
