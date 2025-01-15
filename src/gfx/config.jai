// Set required extensions to support.
DEVICE_EXTENSIONS := (*u8).[
	VK_KHR_SWAPCHAIN_EXTENSION_NAME,
	VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME, // Enabled by default in 1.3
	VK_KHR_SHADER_NON_SEMANTIC_INFO_EXTENSION_NAME, // Enabled by default in 1.3
];

// Set validation layers to enable.
VALIDATION_LAYERS: [] *u8 = .["VK_LAYER_KHRONOS_validation"];

// Set validation features to enable.
VALIDATION_FEATURES: [] VkValidationFeatureEnableEXT = .[.DEBUG_PRINTF_EXT];

// Number of frames to provide in flight.
FRAME_OVERLAP :: 2;
