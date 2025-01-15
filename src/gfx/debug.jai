object_type_of_handle :: (T: Type) -> VkObjectType {
	if T == {
		case VkBuffer_T;              return .BUFFER;
		case VkImage_T;               return .IMAGE;
		case VkImageView_T;           return .IMAGE_VIEW;
		case VkCommandPool_T;         return .COMMAND_POOL;
		case VkDescriptorPool_T;      return .DESCRIPTOR_POOL;
		case VkDescriptorSetLayout_T; return .DESCRIPTOR_SET_LAYOUT;
		case VkDescriptorSet_T;       return .DESCRIPTOR_SET;
		case VkFence_T;               return .FENCE;
		case VkPipeline_T;            return .PIPELINE;
		case VkPipelineLayout_T;      return .PIPELINE_LAYOUT;
		case VkSampler_T;             return .SAMPLER;
	}

	return .UNKNOWN;
}

debug_set_object_name :: (handle: *$T, object_name: string, loc := #caller_location)
#modify {
	object_type := object_type_of_handle(T);
	return object_type != .UNKNOWN;
} {
	if object_name.count <= 0 then return;

	object_type := #run object_type_of_handle(T);
	if r_ctx.debug_messenger == null {
		return;
	}

    name_info := VkDebugUtilsObjectNameInfoEXT.{
        sType = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
        objectType = object_type,
        pObjectName = temp_c_string(object_name),
        objectHandle = xx handle,
	};

	SetDebugUtilsObjectNameEXT(r_ctx.device, *name_info);
}

SetDebugUtilsObjectNameEXT :: (
	device: VkDevice,
	pNameInfo: *VkDebugUtilsObjectNameInfoEXT
) -> VkResult {
	func := cast(PFN_vkSetDebugUtilsObjectNameEXT, vkGetInstanceProcAddr(r_ctx.instance, "vkSetDebugUtilsObjectNameEXT"));
	if func != null then return func(device, pNameInfo);

	return .ERROR_EXTENSION_NOT_PRESENT;
}
