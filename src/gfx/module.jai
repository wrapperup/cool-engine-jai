#module_parameters (DEBUG := false);

vk_check :: (result: VkResult, loc := #caller_location) {
	if result != .SUCCESS {
		assert(false, "vk_check failed: %", result, loc = loc);
	}
}

r_ctx: *Renderer;

DeviceLimits :: struct {
	max_anisotropy: f32;
}

Renderer :: struct {
	debug_messenger: VkDebugUtilsMessengerEXT;
	instance:        VkInstance;
	physical_device: VkPhysicalDevice;
	device:          VkDevice;
	window:          *SDL_Window;

	// Queues
	graphics_queue:        VkQueue;
	graphics_queue_family: u32;
	surface:               VkSurfaceKHR;

	// Swapchain
	swapchain: Swapchain;

	// Command Pool/Buffer
	frames:                [FRAME_OVERLAP] FrameData;
	frame_number:          int;
	global_deletion_queue: Deletion_Queue;
	allocator:             VmaAllocator;

	// Draw resources
	draw_image:    GPUImage;
	resolve_image: GPUImage;
	depth_image:   GPUImage;
	draw_extent:   VkExtent2D;
	msaa_samples:  VkSampleCountFlags;

	// Descriptors
	global_descriptor_allocator: DescriptorAllocator;

	// Immediate submit
	imm_fence:          VkFence;
	imm_command_buffer: VkCommandBuffer;
	imm_command_pool:   VkCommandPool;

	// Dear Imgui
	imgui_ctx:  *ImGui.ImGuiContext;
	imgui_init: bool;
	imgui_pool: VkDescriptorPool;

	limits: VkPhysicalDeviceLimits; // TODO: Too big?
}

FrameData :: struct {
	swapchain_semaphore, render_semaphore: VkSemaphore;

	render_fence:        VkFence;
	command_pool:        VkCommandPool;
	main_command_buffer: VkCommandBuffer;
	deletion_queue:      Deletion_Queue;
}

RequiredFeatures :: struct{
	vk_10: VkPhysicalDeviceFeatures;
	vk_11: VkPhysicalDeviceVulkan11Features;
	vk_12: VkPhysicalDeviceVulkan12Features;
	vk_13: VkPhysicalDeviceVulkan13Features;
}

InitConfig :: struct {
	window:            *SDL_Window;
	msaa_samples:      VkSampleCountFlags;
	enable_validation: bool;
	required_features: RequiredFeatures;
}

gfx_init :: (config := InitConfig.{}) -> *Renderer {
	r_ctx = New(Renderer);

	assert(init_vulkan(config), "Failed to initialize Vulkan.");

	return r_ctx;
}

gfx_shutdown :: () {
    cleanup_vulkan();
}

current_frame_index :: () -> int {
    return r_ctx.frame_number % FRAME_OVERLAP;
}

current_frame :: () -> *FrameData {
    return *r_ctx.frames[current_frame_index()];
}

msaa_samples :: () -> VkSampleCountFlags {
    return r_ctx.msaa_samples;
}

msaa_enabled :: () -> bool {
    return r_ctx.msaa_samples > ._1_BIT;
}

renderer :: () -> *Renderer {
    return r_ctx;
}

set_renderer :: (r: *Renderer) {
    r_ctx = r;
}


Swapchain :: struct {
	swapchain:              VkSwapchainKHR;
	swapchain_images:       []VkImage;
	swapchain_image_index:  u32;
	swapchain_image_views:  []VkImageView;
	swapchain_image_format: VkFormat;
	swapchain_extent:       VkExtent2D;
}

create_swapchain :: () {
	capabilities: VkSurfaceCapabilitiesKHR;
	vkGetPhysicalDeviceSurfaceCapabilitiesKHR(r_ctx.physical_device, r_ctx.surface, *capabilities);

	format_count: u32;
	vkGetPhysicalDeviceSurfaceFormatsKHR(r_ctx.physical_device, r_ctx.surface, *format_count, null);

    formats := NewArray(format_count, VkSurfaceFormatKHR);
	defer free(formats.data);
	vkGetPhysicalDeviceSurfaceFormatsKHR(r_ctx.physical_device, r_ctx.surface, *format_count, formats.data);

	present_mode_count: u32;
	vkGetPhysicalDeviceSurfacePresentModesKHR(r_ctx.physical_device, r_ctx.surface, *present_mode_count, null);

    present_modes := NewArray(present_mode_count, VkPresentModeKHR);
	defer free(present_modes.data);
	vkGetPhysicalDeviceSurfacePresentModesKHR(r_ctx.physical_device, r_ctx.surface, *present_mode_count, present_modes.data);

	surface_format := formats[0];

	for format: formats {
		if format.format == .B8G8R8A8_UNORM && format.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR {
			surface_format = format;
		}
	}

	present_mode := choose_swap_present_mode(present_modes);
	extent := choose_swap_extent(r_ctx.window, *capabilities);

	image_count := capabilities.minImageCount + 1;

	if capabilities.maxImageCount > 0 && image_count > capabilities.maxImageCount {
		image_count = capabilities.maxImageCount;
	}

	old_swapchain := r_ctx.swapchain.swapchain;

	create_info := VkSwapchainCreateInfoKHR.{
		sType                 = .SWAPCHAIN_CREATE_INFO_KHR,
		surface               = r_ctx.surface,
		minImageCount         = image_count,
		imageFormat           = surface_format.format,
		imageColorSpace       = surface_format.colorSpace,
		imageExtent           = extent,
		imageArrayLayers      = 1,
		imageUsage            = .COLOR_ATTACHMENT_BIT | .TRANSFER_DST_BIT,

		// TODO: Support multiple queues?
		imageSharingMode      = .EXCLUSIVE,
		queueFamilyIndexCount = 0, // Optional
		pQueueFamilyIndices   = null, // Optional
		preTransform          = capabilities.currentTransform,
		compositeAlpha        = .OPAQUE_BIT_KHR,
		presentMode           = present_mode,
		clipped               = VK_TRUE,
		oldSwapchain          = old_swapchain,
	};

	swapchain := *r_ctx.swapchain;

	vk_check(vkCreateSwapchainKHR(r_ctx.device, *create_info, null, *swapchain.swapchain));

    vkGetSwapchainImagesKHR(r_ctx.device, swapchain.swapchain, *image_count, null);
    swapchain.swapchain_images = NewArray(image_count, VkImage);
    vkGetSwapchainImagesKHR(r_ctx.device, swapchain.swapchain, *image_count, swapchain.swapchain_images.data);

    swapchain.swapchain_image_format = surface_format.format;
    swapchain.swapchain_extent = extent;

    swapchain.swapchain_image_views = NewArray(swapchain.swapchain_images.count, VkImageView);

	for i: 0 .. swapchain.swapchain_images.count - 1 {
		create_info := VkImageViewCreateInfo.{
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = swapchain.swapchain_images[i],
			viewType = ._2D,
			format = swapchain.swapchain_image_format,
			components = .{r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = .{aspectMask = .COLOR_BIT, baseMipLevel = 0, levelCount = 1, baseArrayLayer = 0, layerCount = 1},
		};

		vk_check(vkCreateImageView(r_ctx.device, *create_info, null, *swapchain.swapchain_image_views[i]));
	}

	x, y: s32;

	if (SDL_GetWindowFlags(r_ctx.window) & SDL_WINDOW_FULLSCREEN) == 0 {
		SDL_GetWindowSize(r_ctx.window, *x, *y);
		log("Windowed size: %, %", x, y);
	} else {
		display_index := SDL_GetWindowDisplayIndex(r_ctx.window);

		display_mode: SDL_DisplayMode;
		SDL_GetDesktopDisplayMode(display_index, *display_mode);

		x = display_mode.w;
		y = display_mode.h;

		log("Fullscreen size: %, %", x, y);
	}

	draw_image_format: VkFormat = .R32G32B32A32_SFLOAT;
	draw_image_extent := VkExtent3D.{xx x, xx y, 1};
	draw_image_usages : VkImageUsageFlags = .TRANSFER_SRC_BIT | .TRANSFER_DST_BIT | .STORAGE_BIT | .COLOR_ATTACHMENT_BIT;

	r_ctx.draw_image = create_image(draw_image_format, draw_image_extent, draw_image_usages, msaa_samples = r_ctx.msaa_samples);
	create_image_view(*r_ctx.draw_image, .COLOR_BIT);
	defer_destroy(r_ctx.draw_image);

	// Used for MSAA resolution
	r_ctx.resolve_image = create_image(draw_image_format, draw_image_extent, draw_image_usages, msaa_samples = ._1_BIT);
	create_image_view(*r_ctx.resolve_image, .COLOR_BIT);
	defer_destroy(r_ctx.resolve_image);

	r_ctx.depth_image = create_image(.D32_SFLOAT, draw_image_extent, .DEPTH_STENCIL_ATTACHMENT_BIT, msaa_samples = r_ctx.msaa_samples);
	create_image_view(*r_ctx.depth_image, .DEPTH_BIT);
	defer_destroy(r_ctx.depth_image);

	r_ctx.draw_extent.width = r_ctx.draw_image.extent.width;
	r_ctx.draw_extent.height = r_ctx.draw_image.extent.height;
}

destroy_swapchain_resources :: () {
	// We don't need to delete the images, it was created by the driver
	// However, we did create the views, so we will destroy those now.
	for image_view: r_ctx.swapchain.swapchain_image_views {
		vkDestroyImageView(r_ctx.device, image_view, null);
	}

	array_free(r_ctx.swapchain.swapchain_image_views);
	array_free(r_ctx.swapchain.swapchain_images);
}

resize_swapchain :: () {
	vkDeviceWaitIdle(r_ctx.device);

	destroy_swapchain_resources();
	defer_destroy(r_ctx.swapchain.swapchain);
	create_swapchain();
}

copy_image_to_swapchain :: (cmd: VkCommandBuffer, source: VkImage, src_size: VkExtent2D) {
	transition_image(cmd, r_ctx.swapchain.swapchain_images[r_ctx.swapchain.swapchain_image_index], .UNDEFINED, .TRANSFER_DST_OPTIMAL);

	copy_image_to_image(
		cmd,
		source,
		r_ctx.swapchain.swapchain_images[r_ctx.swapchain.swapchain_image_index],
		src_size,
		r_ctx.swapchain.swapchain_extent,
	);
}


begin_immediate_submit :: () -> VkCommandBuffer {
	vk_check(vkResetFences(r_ctx.device, 1, *r_ctx.imm_fence));
	vk_check(vkResetCommandBuffer(r_ctx.imm_command_buffer, 0));

	cmd := r_ctx.imm_command_buffer;

	cmd_begin_info := init_command_buffer_begin_info(.ONE_TIME_SUBMIT_BIT);

	vk_check(vkBeginCommandBuffer(cmd, *cmd_begin_info));

	return cmd;
}

end_immediate_submit :: () {
	cmd := r_ctx.imm_command_buffer;

	vk_check(vkEndCommandBuffer(cmd));

	cmd_info := init_command_buffer_submit_info(cmd);
	submit := init_submit_info(*cmd_info, null, null);

	// submit command buffer to the queue and execute it.
	//  _renderFence will now block until the graphic commands finish execution
	vk_check(vkQueueSubmit2(r_ctx.graphics_queue, 1, *submit, r_ctx.imm_fence));

	vk_check(vkWaitForFences(r_ctx.device, 1, *r_ctx.imm_fence, VK_TRUE, 9_999_999_999));
}

// Begin an immediate submit in the current scope. Ends when the scope ends.
immediate_submit :: () -> VkCommandBuffer #expand {
    cmd := begin_immediate_submit();
    `defer end_immediate_submit();
    return cmd;
}


init_vulkan :: (config: InitConfig) -> bool {
    r_ctx.window = config.window;

	{
		if config.enable_validation && !check_validation_layers() {
			assert(false, "Validation layers are not available");
		}

        app_info := VkApplicationInfo.{
			sType = .APPLICATION_INFO,
			pApplicationName = "Hello Triangle",
			applicationVersion = VK_MAKE_API_VERSION(0, 1, 0, 0),
			pEngineName = "No Engine",
			engineVersion = VK_MAKE_API_VERSION(0, 1, 0, 0),
			apiVersion = VK_API_VERSION_1_3,
		};

        extensions := get_required_extensions(config.enable_validation);
        defer array_free(extensions);

		create_info := VkInstanceCreateInfo.{
			sType = .INSTANCE_CREATE_INFO,
			pApplicationInfo = *app_info,

			ppEnabledExtensionNames = extensions.data,
			enabledExtensionCount = xx extensions.count,
		};

        debug_create_info := VkDebugUtilsMessengerCreateInfoEXT.{};

		validation_features := VkValidationFeaturesEXT.{
			sType                         = .VALIDATION_FEATURES_EXT,
			pEnabledValidationFeatures    = VALIDATION_FEATURES.data,
			enabledValidationFeatureCount = xx VALIDATION_LAYERS.count,
        };

		if config.enable_validation {
            create_info.ppEnabledLayerNames = VALIDATION_LAYERS.data;
            create_info.enabledLayerCount   = xx VALIDATION_LAYERS.count;

            debug_create_info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
            debug_create_info.messageSeverity = .WARNING_BIT_EXT | .ERROR_BIT_EXT | .INFO_BIT_EXT;
            debug_create_info.messageType = .GENERAL_BIT_EXT | .VALIDATION_BIT_EXT | .PERFORMANCE_BIT_EXT;
            debug_create_info.pfnUserCallback = debug_callback;
            debug_create_info.pNext = *validation_features;

            create_info.pNext = *debug_create_info;
		} else {
            create_info.enabledLayerCount = 0;
            create_info.pNext = null;
		}

        vk_check(vkCreateInstance(*create_info, null, *r_ctx.instance));

		n_ext: u32;
		vkEnumerateInstanceExtensionProperties(null, *n_ext, null);

        extension_props := NewArray(n_ext, VkExtensionProperties);
        defer free(extension_props.data);

		vkEnumerateInstanceExtensionProperties(null, *n_ext, extension_props.data);

		log("Available Extensions:", flags = .VERBOSE_ONLY);

		for ext: extension_props {
			log(" - %s", to_string(*ext.extensionName[0]), flags = .VERBOSE_ONLY);
		}

		if config.enable_validation && !check_validation_layers() {
			assert(false, "Validation layers are not available");
		}
	}

	{
		if config.enable_validation {
			log("Creating Debug Messenger", flags = .VERBOSE_ONLY);
			create_info := VkDebugUtilsMessengerCreateInfoEXT.{
				sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
				messageSeverity = .VERBOSE_BIT_EXT | .WARNING_BIT_EXT | .INFO_BIT_EXT | .ERROR_BIT_EXT,
				messageType     = .GENERAL_BIT_EXT | .VALIDATION_BIT_EXT,
				pfnUserCallback = debug_callback,
				pUserData       = null,
			};

			vk_check(CreateDebugUtilsMessengerEXT(r_ctx.instance, *create_info, null, *r_ctx.debug_messenger));
		}
	}

	if r_ctx.window != null {
		could_create_surface := SDL_Vulkan_CreateSurface(r_ctx.window, r_ctx.instance, *r_ctx.surface);
		assert(could_create_surface == .SDL_TRUE, "Failed to create Vulkan surface.");
	}

	{
		device_count: u32;
		vkEnumeratePhysicalDevices(r_ctx.instance, *device_count, null);

        devices := NewArray(device_count, VkPhysicalDevice);
        defer free(devices.data);

		vkEnumeratePhysicalDevices(r_ctx.instance, *device_count, devices.data);

		for device: devices {
			if is_device_suitable(device, config.required_features) {
				r_ctx.physical_device = device;
				break;
			}
		}

		if r_ctx.physical_device == null {
			assert(false, "No GPU found that supports all required features.");
		}
	}

	{ // Keep device limits
		properties: VkPhysicalDeviceProperties;
		vkGetPhysicalDeviceProperties(r_ctx.physical_device, *properties);

		r_ctx.limits = properties.limits;
	}

	{
		queue_family_count: u32;
		vkGetPhysicalDeviceQueueFamilyProperties(r_ctx.physical_device, *queue_family_count, null);

		queue_families := NewArray(queue_family_count, VkQueueFamilyProperties);
        defer free(queue_families.data);
		vkGetPhysicalDeviceQueueFamilyProperties(r_ctx.physical_device, *queue_family_count, queue_families.data);

		has_graphics := false;

		for queue_family, i: queue_families {
			if queue_family.queueFlags & .GRAPHICS_BIT {
				r_ctx.graphics_queue_family = xx i;
				has_graphics = true;
			}
		}

		assert(has_graphics, "No graphics queue is supported.");
	}

	{
		queue_priority: f32 = 1.0;

		queue_create_info := VkDeviceQueueCreateInfo.{
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = r_ctx.graphics_queue_family,
			queueCount       = 1,
			pQueuePriorities = *queue_priority,
		};

		// TODO: Maybe we don't want to do this, but it's fine for now..?
		vk_13_features := VkPhysicalDeviceVulkan13Features.{
			sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		};

		vk_12_features := VkPhysicalDeviceVulkan12Features.{
			sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
			pNext = *vk_13_features,
		};

		vk_11_features := VkPhysicalDeviceVulkan11Features.{
			sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
			pNext = *vk_12_features,
		};

		features := VkPhysicalDeviceFeatures2.{
			sType = .PHYSICAL_DEVICE_FEATURES_2,
			pNext = *vk_11_features,
		};

		vkGetPhysicalDeviceFeatures2(r_ctx.physical_device, *features);

		device_create_info := VkDeviceCreateInfo.{
			sType                   = .DEVICE_CREATE_INFO,
			pNext                   = *features,
			pQueueCreateInfos       = *queue_create_info,
			queueCreateInfoCount    = 1,
			ppEnabledExtensionNames = DEVICE_EXTENSIONS.data,
			enabledExtensionCount   = xx DEVICE_EXTENSIONS.count,
		};

		vk_check(vkCreateDevice(r_ctx.physical_device, *device_create_info, null, *r_ctx.device));

		assert(r_ctx.device != null);

		vkGetDeviceQueue(r_ctx.device, r_ctx.graphics_queue_family, 0, *r_ctx.graphics_queue);
	}

	{
		allocator_info := VmaAllocatorCreateInfo.{
			vulkanApiVersion = VK_API_VERSION_1_3,
			physicalDevice   = r_ctx.physical_device,
			device           = r_ctx.device,
			instance         = r_ctx.instance,
			flags            = .VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
		};

		vmaCreateAllocator(*allocator_info, *r_ctx.allocator);
	}

	context.deletion_queue = *r_ctx.global_deletion_queue;

	r_ctx.msaa_samples = config.msaa_samples;

	if r_ctx.window != null {
		create_swapchain();
	}

	{
		command_pool_info := VkCommandPoolCreateInfo.{
			sType = .COMMAND_POOL_CREATE_INFO,
			pNext = null,
			flags = .RESET_COMMAND_BUFFER_BIT,
			queueFamilyIndex = r_ctx.graphics_queue_family,
		};

		for i: 0 .. FRAME_OVERLAP-1 {
			vk_check(vkCreateCommandPool(r_ctx.device, *command_pool_info, null, *r_ctx.frames[i].command_pool));

			// allocate the default command buffer that we will use for rendering
			cmd_alloc_info := VkCommandBufferAllocateInfo.{
				sType = .COMMAND_BUFFER_ALLOCATE_INFO,
				pNext = null,
				commandPool = r_ctx.frames[i].command_pool,
				commandBufferCount = 1,
				level = .PRIMARY,
			};

			vk_check(vkAllocateCommandBuffers(r_ctx.device, *cmd_alloc_info, *r_ctx.frames[i].main_command_buffer));
		}

		vk_check(vkCreateCommandPool(r_ctx.device, *command_pool_info, null, *r_ctx.imm_command_pool));

		// allocate the command buffer for immediate submits
		cmd_alloc_info := init_command_buffer_allocate_info(r_ctx.imm_command_pool, 1);

		vk_check(vkAllocateCommandBuffers(r_ctx.device, *cmd_alloc_info, *r_ctx.imm_command_buffer));

		defer_destroy(r_ctx.imm_command_pool);
	}

	{
		fence_create_info := init_fence_create_info(.SIGNALED_BIT);
		semaphore_create_info := init_semaphore_create_info(0);

		for * frame: r_ctx.frames {
			vk_check(vkCreateFence(r_ctx.device, *fence_create_info, null, *frame.render_fence));

			vk_check(vkCreateSemaphore(r_ctx.device, *semaphore_create_info, null, *frame.swapchain_semaphore));
			vk_check(vkCreateSemaphore(r_ctx.device, *semaphore_create_info, null, *frame.render_semaphore));
		}

		vkCreateFence(r_ctx.device, *fence_create_info, null, *r_ctx.imm_fence);
		defer_destroy(r_ctx.imm_fence);
	}

	if r_ctx.window != null {
		pool_sizes: []VkDescriptorPoolSize =.[
			.{.SAMPLER, 1000},
			.{.COMBINED_IMAGE_SAMPLER, 1000},
			.{.SAMPLED_IMAGE, 1000},
			.{.STORAGE_IMAGE, 1000},
			.{.UNIFORM_TEXEL_BUFFER, 1000},
			.{.STORAGE_TEXEL_BUFFER, 1000},
			.{.UNIFORM_BUFFER, 1000},
			.{.STORAGE_BUFFER, 1000},
			.{.UNIFORM_BUFFER_DYNAMIC, 1000},
			.{.STORAGE_BUFFER_DYNAMIC, 1000},
			.{.INPUT_ATTACHMENT, 1000},
		];

		pool_info := VkDescriptorPoolCreateInfo.{
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			flags         = .FREE_DESCRIPTOR_SET_BIT,
			maxSets       = 1_000,
			pPoolSizes    = pool_sizes.data,
			poolSizeCount = xx pool_sizes.count,
		};

		vk_check(vkCreateDescriptorPool(r_ctx.device, *pool_info, null, *r_ctx.imgui_pool));

		gfx_init_imgui();

	}

	{
		//create a descriptor pool that will hold 10 sets with 1 image each
		ratio: f32 = 1.0 / 3.0;
		sizes : [] PoolSizeRatio =.[
			.{.SAMPLER, ratio},
			.{.SAMPLED_IMAGE, ratio},
			.{.STORAGE_IMAGE, ratio},
		];

		init_descriptor_allocator(*r_ctx.global_descriptor_allocator, 10, sizes, .UPDATE_AFTER_BIND_BIT);
	}

	return true;
}

gfx_init_imgui :: () {
	alloc_imgui :: (sz: u64, user_data: *void) -> *void #c_call {
		push_context {
			return alloc(xx sz);
		}
	}

	free_imgui :: (ptr: *void, user_data: *void) #c_call {
		push_context {
			free(ptr);
		}
	}

	ImGui.SetAllocatorFunctions(alloc_imgui, free_imgui);
	r_ctx.imgui_ctx = ImGui.CreateContext();
	ImGui.SetCurrentContext(r_ctx.imgui_ctx);

	ImGui_ImplSDL2_InitForVulkan(r_ctx.window);

	init_info := ImGui_ImplVulkan_InitInfo.{
		Instance              = r_ctx.instance,
		PhysicalDevice        = r_ctx.physical_device,
		Device                = r_ctx.device,
		Queue                 = r_ctx.graphics_queue,
		DescriptorPool        = r_ctx.imgui_pool,
		MinImageCount         = 3,
		ImageCount            = 3,
		UseDynamicRendering   = true,
		PipelineRenderingCreateInfo = .{
			colorAttachmentCount = 1,
			pColorAttachmentFormats = *r_ctx.swapchain.swapchain_image_format,
		},
		MSAASamples           = ._1_BIT,
	};

	assert(ImGui_ImplVulkan_Init(*init_info), "Could not initialize ImGui Vulkan backend.");

	r_ctx.imgui_init = true;
}

gfx_shutdown_imgui :: () {
	vkDeviceWaitIdle(r_ctx.device);

	ImGui_ImplVulkan_Shutdown();
	ImGui_ImplSDL2_Shutdown();
	ImGui.DestroyContext();

	r_ctx.imgui_init = false;
}

cleanup_vulkan :: () {
	vkDeviceWaitIdle(r_ctx.device);

	if r_ctx.imgui_init {
		gfx_shutdown_imgui();
		vkDestroyDescriptorPool(r_ctx.device, r_ctx.imgui_pool, null);
	}

	destroy_pools(*r_ctx.global_descriptor_allocator);
	destroy_descriptor_allocator(*r_ctx.global_descriptor_allocator);

	// Cleanup queued resources
	flush_deletion_queue(*r_ctx.global_deletion_queue);
	delete_deletion_queue(r_ctx.global_deletion_queue);

	for frame: r_ctx.frames {
		vkDestroyCommandPool(r_ctx.device, frame.command_pool, null);

		vkDestroyFence(r_ctx.device, frame.render_fence, null);
		vkDestroySemaphore(r_ctx.device, frame.render_semaphore, null);
		vkDestroySemaphore(r_ctx.device, frame.swapchain_semaphore, null);

		flush_deletion_queue(*frame.deletion_queue);
		delete_deletion_queue(frame.deletion_queue);
	}

	if r_ctx.swapchain.swapchain != null {
		vkDestroySwapchainKHR(r_ctx.device, r_ctx.swapchain.swapchain, null);
		destroy_swapchain_resources();
	}

	// Headless mode
	if r_ctx.surface != null {
		vkDestroySurfaceKHR(r_ctx.instance, r_ctx.surface, null);
	}

	vmaDestroyAllocator(r_ctx.allocator);
	vkDestroyDevice(r_ctx.device, null);

	if r_ctx.debug_messenger != null {
		DestroyDebugUtilsMessengerEXT(r_ctx.instance, r_ctx.debug_messenger, null);
	}

	vkDestroyInstance(r_ctx.instance, null);
}

set_viewport_and_scissor :: (cmd: VkCommandBuffer, extent: VkExtent2D) {
	set_viewport_and_scissor(cmd, .{extent.width, extent.height, 1});
}

set_viewport_and_scissor :: (cmd: VkCommandBuffer, extent: VkExtent3D) {
	//set dynamic viewport and scissor
	viewport := VkViewport.{
		x        = 0,
		y        = 0,
		width    = xx extent.width,
		height   = xx extent.height,
		minDepth = 0.0,
		maxDepth = 1.0,
	};

	vkCmdSetViewport(cmd, 0, 1, *viewport);

	scissor := VkRect2D.{
		offset = .{x = 0, y = 0},
		extent = .{extent.width, extent.height},
	};

	vkCmdSetScissor(cmd, 0, 1, *scissor);
}

// Called by the user before they start drawing to the screen.
begin_command_buffer :: () -> VkCommandBuffer {
	vk_check(vkWaitForFences(r_ctx.device, 1, *current_frame().render_fence, VK_TRUE, 1_000_000_000));

	// Delete resources for the current frame
	flush_deletion_queue(*current_frame().deletion_queue);

	acquire_image_result := vkAcquireNextImageKHR(
		r_ctx.device,
		r_ctx.swapchain.swapchain,
		1_000_000_000,
		current_frame().swapchain_semaphore,
		null,
		*r_ctx.swapchain.swapchain_image_index,
	);

	if acquire_image_result == .ERROR_OUT_OF_DATE_KHR {
		resize_swapchain();
		return null;
	} else {
		vk_check(acquire_image_result);
	}

	r_ctx.draw_extent.width = r_ctx.draw_image.extent.width;
	r_ctx.draw_extent.height = r_ctx.draw_image.extent.height;

	vk_check(vkResetFences(r_ctx.device, 1, *current_frame().render_fence));

	// now that we are sure that the commands finished executing, we can safely
	// reset the command buffer to begin recording again.
	vk_check(vkResetCommandBuffer(current_frame().main_command_buffer, .RELEASE_RESOURCES_BIT));

	// naming it cmd for shorter writing
	cmd := current_frame().main_command_buffer;

	// begin the command buffer recording. We will use this command buffer exactly once, so we want to let vulkan know that
	cmd_begin_info := init_command_buffer_begin_info(.ONE_TIME_SUBMIT_BIT);

	vk_check(vkBeginCommandBuffer(cmd, *cmd_begin_info));

	return cmd;
}

// Called by the user when they end drawing to the screen.
submit :: (cmd: VkCommandBuffer) {
	ImGui.Render();

	// set swapchain image layout to Attachment Optimal so we can draw it
	transition_image(
		cmd,
		r_ctx.swapchain.swapchain_images[r_ctx.swapchain.swapchain_image_index],
		.TRANSFER_DST_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	);

	//draw imgui into the swapchain image
	{
		color_attachment := init_attachment_info(r_ctx.swapchain.swapchain_image_views[r_ctx.swapchain.swapchain_image_index], null, .GENERAL);
		render_info := init_rendering_info(r_ctx.swapchain.swapchain_extent, *color_attachment, null);

		vkCmdBeginRendering(cmd, *render_info);

		ImGui_ImplVulkan_RenderDrawData(ImGui.GetDrawData(), cmd);

		vkCmdEndRendering(cmd);

		// set swapchain image layout to Present so we can show it on the screen
		transition_image(
			cmd,
			r_ctx.swapchain.swapchain_images[r_ctx.swapchain.swapchain_image_index],
			.COLOR_ATTACHMENT_OPTIMAL,
			.PRESENT_SRC_KHR,
		);
	}

	//finalize the command buffer (we can no longer add commands, but it can now be executed)
	vk_check(vkEndCommandBuffer(cmd));

	cmd_info := init_command_buffer_submit_info(cmd);

	wait_info := init_semaphore_submit_info(.COLOR_ATTACHMENT_OUTPUT_BIT, current_frame().swapchain_semaphore);
	signal_info := init_semaphore_submit_info(.ALL_GRAPHICS_BIT, current_frame().render_semaphore);

	submit := init_submit_info(*cmd_info, *signal_info, *wait_info);

	vk_check(vkQueueSubmit2(r_ctx.graphics_queue, 1, *submit, current_frame().render_fence));

	present_info := VkPresentInfoKHR.{
		sType              = .PRESENT_INFO_KHR,
		pSwapchains        = *r_ctx.swapchain.swapchain,
		swapchainCount     = 1,
		pWaitSemaphores    = *current_frame().render_semaphore,
		waitSemaphoreCount = 1,
		pImageIndices      = *r_ctx.swapchain.swapchain_image_index,
	};

	queue_present_result := vkQueuePresentKHR(r_ctx.graphics_queue, *present_info);

	if queue_present_result == .ERROR_OUT_OF_DATE_KHR {
		resize_swapchain();
	} else {
		// TODO: Do normal assert check, maybe other cases though?
		vk_check(queue_present_result);
	}

	r_ctx.frame_number += 1;
}

choose_swap_present_mode :: (available_present_modes: [] VkPresentModeKHR) -> VkPresentModeKHR {
	return .IMMEDIATE_KHR;
}

choose_swap_extent :: (window: *SDL_Window, capabilities: *VkSurfaceCapabilitiesKHR) -> VkExtent2D {
	if capabilities.currentExtent.width != U32_MAX {
		return capabilities.currentExtent;
	}

	width, height: s32;
	SDL_GetWindowSize(window, *width, *height);

	actual_extent := VkExtent2D.{xx width, xx height};

	actual_extent.width = clamp(actual_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
	actual_extent.height = clamp(actual_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);

	return actual_extent;
}

supports_required_features :: (required: $T, test: T) -> bool 
#modify {
	info := cast(*Type_Info, T);
	return info.type == .STRUCT;
} {
	info := cast(*Type_Info_Struct, T);

	builder: String_Builder;

	print_to_builder(*builder, " - ");
	print_type_to_builder(*builder, info);
	print_to_builder(*builder, "\n");

	has_any_flags := false;
	supports_all_flags := true;

	struct_info := cast(*Type_Info_Struct) info;

	for member: info.members {
		// The flags are of type boolean
		if member.type.type == .BOOL {
			offset := member.offset_in_bytes;

			// Grab the values at the offsets
			required_value := cast(*u32, (*required) + offset).*;
			test_value := cast(*u32, (*test) + offset).*;

			// Check if the flag is required
			if required_value != 0 {
				print_to_builder(*builder, "   + %", member.name);

				// Returns false if the test doesn't have the required flag.
				if required_value != test_value {
					print_to_builder(*builder, " \xE2\x9D\x8C\n");
					supports_all_flags = false;
				} else {
					print_to_builder(*builder, " \xE2\x9C\x94\n");
					has_any_flags = true;
				}
			}
		}
	}

	if has_any_flags {
		log(builder_to_string(*builder), flags = .VERBOSE_ONLY);
	}

	return supports_all_flags;
}

is_device_suitable :: (device: VkPhysicalDevice, required_features: RequiredFeatures) -> bool {
	properties: VkPhysicalDeviceProperties;
	vkGetPhysicalDeviceProperties(device, *properties);

	vk_13_features := VkPhysicalDeviceVulkan13Features.{
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
	};

	vk_12_features := VkPhysicalDeviceVulkan12Features.{
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext = *vk_13_features,
	};

	vk_11_features := VkPhysicalDeviceVulkan11Features.{
		sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		pNext = *vk_12_features,
	};

	features := VkPhysicalDeviceFeatures2.{
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = *vk_11_features,
	};

	vkGetPhysicalDeviceFeatures2(device, *features);

	required_features_2 := VkPhysicalDeviceFeatures2.{
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		features = required_features.vk_10,
	};

	log("Required Features:", flags = .VERBOSE_ONLY);
	supports_features :=
		supports_required_features(required_features_2, features) &&
		supports_required_features(required_features.vk_11, vk_11_features) &&
		supports_required_features(required_features.vk_12, vk_12_features) &&
		supports_required_features(required_features.vk_13, vk_13_features);

	extensions_supported := check_device_extension_support(device);

	// Headless mode
	if r_ctx.swapchain.swapchain == null {
		return extensions_supported && properties.deviceType == .DISCRETE_GPU && supports_features;
	}

	swapchain_adequate := false;
	if extensions_supported {
		format_count: u32;
		vkGetPhysicalDeviceSurfaceFormatsKHR(r_ctx.physical_device, r_ctx.surface, *format_count, null);
		present_mode_count: u32;
		vkGetPhysicalDeviceSurfacePresentModesKHR(r_ctx.physical_device, r_ctx.surface, *present_mode_count, null);

		swapchain_adequate = format_count > 0 && present_mode_count > 0;
	}

	return swapchain_adequate && extensions_supported && properties.deviceType == .DISCRETE_GPU && supports_features;
}

check_device_extension_support :: (device: VkPhysicalDevice) -> bool {
	extensions_count: u32;
	vkEnumerateDeviceExtensionProperties(device, null, *extensions_count, null);

	available_extensions := NewArray(extensions_count, VkExtensionProperties);
	defer free(available_extensions.data);
	vkEnumerateDeviceExtensionProperties(device, null, *extensions_count, available_extensions.data);

	for expected_extension: DEVICE_EXTENSIONS {
		found := false;
		for available: available_extensions {
			expected_name := to_string(expected_extension);
			available_name := to_string(*available.extensionName[0]);
			if compare(expected_name, available_name) == 0 {
				found = true;
				break;
			}
		}

		if !found then return false;
	}

	return true;
}

debug_callback :: (
	message_severity: VkDebugUtilsMessageSeverityFlagsEXT,
	message_types: VkDebugUtilsMessageTypeFlagsEXT,
	callback_data: *VkDebugUtilsMessengerCallbackDataEXT,
	user_data: *void
) -> VkBool32 #c_call {
	push_context {
		message := to_string(callback_data.pMessage);
		log("%\n", message);

		for i: 0 .. callback_data.objectCount - 1 {
			name := to_string(callback_data.pObjects[i].pObjectName);

			if name.count > 0 {
				log(" - %\n", name);
			}
		}

		log("\n");
	}

	return VK_FALSE;
}

check_validation_layers :: () -> bool {
	layer_count: u32;
	vkEnumerateInstanceLayerProperties(*layer_count, null);

	available_layers := NewArray(layer_count, VkLayerProperties);
	defer free(available_layers.data);
	vkEnumerateInstanceLayerProperties(*layer_count, available_layers.data);

	for layer_name: VALIDATION_LAYERS {
		layer_found := false;

		for layer_property: available_layers {
			required_name := to_string(layer_name);
			layer_property_name := to_string(*layer_property.layerName[0]);

			if compare(required_name, layer_property_name) == 0 {
				layer_found = true;
				break;
			}
		}

		if !layer_found then return false;
	}


	return true;
}

get_required_extensions :: (enable_validation: bool) -> [..] *u8 {
	extensions_count: u32;
	could_get_instance_extensions_count := SDL_Vulkan_GetInstanceExtensions(r_ctx.window, *extensions_count, null);

	extensions: [..] *u8;
	array_reserve(*extensions, extensions_count);
	extensions.count = xx extensions_count;

	SDL_Vulkan_GetInstanceExtensions(r_ctx.window, *extensions_count, extensions.data);

	if enable_validation {
        array_add(*extensions, VK_EXT_DEBUG_UTILS_EXTENSION_NAME.data);
	}

    return extensions;
}

// TODO: Generate a loader for these.
CreateDebugUtilsMessengerEXT :: (
	instance: VkInstance,
	pCreateInfo: *VkDebugUtilsMessengerCreateInfoEXT,
	pAllocator: *VkAllocationCallbacks,
	pDebugMessenger: *VkDebugUtilsMessengerEXT
) -> VkResult {
	func := cast(PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
	if func != null
	{
		return func(instance, pCreateInfo, pAllocator, pDebugMessenger);
	}
	else
	{
		return .ERROR_EXTENSION_NOT_PRESENT;
	}
}

DestroyDebugUtilsMessengerEXT :: (instance: VkInstance, debugMessenger: VkDebugUtilsMessengerEXT, pAllocator: *VkAllocationCallbacks) {
	func := cast(PFN_vkDestroyDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
	if func != null then func(instance, debugMessenger, pAllocator);
}

#scope_module

f32 :: float32;
f64 :: float64;

#import "Basic";
#import "String";
#import "Math";
#import "File";
#import "Print_Color";

#import "SDL"(VULKAN = true);
#import "jai-libktx";
#import "jai-vulkan";
#import "jai-vma";
#import "jai-libktx";
ImGui :: #import "jai-imgui";
for_expansion :: ImGui.for_expansion;

#load "imgui_backends/imgui_impl_sdl2.jai";
#load "imgui_backends/imgui_impl_vulkan.jai";

#load "buffers.jai";
#load "commands.jai";
#load "config.jai";
#load "debug.jai";
#load "deletion_queue.jai";
#load "descriptors.jai";
#load "images.jai";
#load "pipelines.jai";
#load "textures.jai";
#load "util.jai";
