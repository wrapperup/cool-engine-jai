cmd_push_constants :: (
    cmd: VkCommandBuffer,
    pipeline_layout: VkPipelineLayout,
    push_constants: $T,
    stages: VkShaderStageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
    offset: u32 = 0
) {
	vkCmdPushConstants(
		cmd,
		pipeline_layout,
		stages,
		0,
		size_of(T),
		*push_constants,
	);
}
