// The deletion queue is implemented a bit differently to the one found
// in vkguide. Since Jai doesn't have lambdas, and since Vulkan
// handles are all pointer-sized, we can generalize an API
// that has similar ergonomics.
//
// The API usage is simple: Just pass the handle instead of
// a lambda/procedure. If you allocated with VMA, you can also
// pass in the allocation.
//
// The deletion queue is now basically a (crappy) state machine.
// This could be optimized more by storing each type in SoA form,
// but this works and is simple.

Deletion_Queue :: struct {
	resource_arena: [..] Resource_Handle;
}

#add_context deletion_queue: *Deletion_Queue;

Resource_Handle :: struct {
	ty:              Resource_Type;
	handle:          *void;
	allocation:      VmaAllocation;

	#if DEBUG {
		debug_info:      string;
		loc: Source_Code_Location;
	}
}

Resource_Type :: enum {
	Invalid;
	VmaBuffer;
	VmaImage;
	CommandPool;
	DescriptorPool;
	DescriptorSetLayout;
	Fence;
	ImageView;
	Pipeline;
	PipelineLayout;
	Sampler;
	Swapchain;
}

destroy_resource_by_handle :: (resource: Resource_Handle) {
	#if DEBUG {
		log("Destroy % @ % - %", resource.ty, resource.loc, resource.debug_info, flags = .VERY_VERBOSE_ONLY);
	}

	if resource_requires_allocation(resource.ty) {
		#if DEBUG {
			assert(resource.allocation != null, loc = resource.loc);
		} else {
			assert(resource.allocation != null);
		}
	}

	if resource.ty == {
		case .VmaBuffer;
			vmaDestroyBuffer(r_ctx.allocator, cast(VkBuffer, resource.handle), resource.allocation);
		case .VmaImage;
			vmaDestroyImage(r_ctx.allocator, cast(VkImage, resource.handle), resource.allocation);
		case .CommandPool;
			vkDestroyCommandPool(r_ctx.device, cast(VkCommandPool, resource.handle), null);
		case .DescriptorPool;
			vkDestroyDescriptorPool(r_ctx.device, cast(VkDescriptorPool, resource.handle), null);
		case .DescriptorSetLayout;
			vkDestroyDescriptorSetLayout(r_ctx.device, cast(VkDescriptorSetLayout, resource.handle), null);
		case .Fence;
			vkDestroyFence(r_ctx.device, cast(VkFence, resource.handle), null);
		case .ImageView;
			vkDestroyImageView(r_ctx.device, cast(VkImageView, resource.handle), null);
		case .Pipeline;
			vkDestroyPipeline(r_ctx.device, cast(VkPipeline, resource.handle), null);
		case .PipelineLayout;
			vkDestroyPipelineLayout(r_ctx.device, cast(VkPipelineLayout, resource.handle), null);
		case .Sampler;
			vkDestroySampler(r_ctx.device, cast(VkSampler, resource.handle), null);
		case .Swapchain;
			vkDestroySwapchainKHR(r_ctx.device, cast(VkSwapchainKHR, resource.handle), null);
	}
}

resource_type_of_handle :: (T: Type) -> Resource_Type {
	if T == {
		case VkBuffer_T;              return .VmaBuffer;
		case VkImage_T;               return .VmaImage;
		case VkImageView_T;           return .ImageView;
		case VkCommandPool_T;         return .CommandPool;
		case VkDescriptorPool_T;      return .DescriptorPool;
		case VkDescriptorSetLayout_T; return .DescriptorSetLayout;
		case VkFence_T;               return .Fence;
		case VkPipeline_T;            return .Pipeline;
		case VkPipelineLayout_T;      return .PipelineLayout;
		case VkSampler_T;             return .Sampler;
		case VkSwapchainKHR_T;        return .Swapchain;
	}

	return .Invalid;
}

resource_requires_allocation :: (type: Resource_Type) -> bool {
	if type == {
		case .VmaBuffer; #through;
		case .VmaImage;
			return true;
		case;
			return false;
	}
}

defer_destroy :: (
	handle: *$T,
	allocation: VmaAllocation = null,
	debug: string = "UNKNOWN",
	loc := #caller_location
) 
#modify {
	resource_type := resource_type_of_handle(T);
	return resource_type != .Invalid, "Type is not a valid resource.";
} {
	assert(context.deletion_queue != null, "Deletion queue is null.", loc = loc);

	resource_type := #run resource_type_of_handle(T);

	#if DEBUG {
		log("Add % @ % - %", resource_type, loc, debug, flags = .VERY_VERBOSE_ONLY);
	}

	if resource_requires_allocation(resource_type) {
		assert(allocation != null, "Resource requires an allocation to be passed in", loc = loc);
	}

	resource_handle := Resource_Handle.{
		handle          = cast(*void, handle),
		ty              = resource_type,
		allocation      = allocation,
	};

	#if DEBUG {
		resource_handle.debug_info = debug;
		resource_handle.loc = loc;
	}

	array_add(*context.deletion_queue.resource_arena, resource_handle);
}

defer_destroy :: (
	buffer: GPUBuffer,
	debug: string = "UNKNOWN",
	loc := #caller_location
) {
	defer_destroy(buffer.buffer, buffer.allocation, loc = loc);
}

defer_destroy :: (
	image: GPUImage,
	debug: string = "UNKNOWN",
	loc := #caller_location
) {
	if image.view != null {
		defer_destroy(image.view, loc = loc);
	}

	defer_destroy(image.image, image.allocation, loc = loc);
}

flush_deletion_queue :: (deletion_queue: *Deletion_Queue) {
	for < resource: deletion_queue.resource_arena {
		destroy_resource_by_handle(resource);
	}

	array_reset(*deletion_queue.resource_arena);
}

delete_deletion_queue :: (deletion_queue: Deletion_Queue) {
	array_free(deletion_queue.resource_arena);
}
