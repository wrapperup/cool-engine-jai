cmd_bind_pipeline :: inline (cmd: VkCommandBuffer, pipeline: GraphicsPipeline) {
	vkCmdBindDescriptorSets( cmd, .GRAPHICS, pipeline.layout, 0, 1, *r_ctx.bindless_system.descriptor_set, 0, null);
    vkCmdBindPipeline(cmd, .GRAPHICS, pipeline.pipeline);

    r_ctx.current_pipeline = pipeline.common;
}

cmd_bind_pipeline :: inline (cmd: VkCommandBuffer, pipeline: ComputePipeline) {
	vkCmdBindDescriptorSets(cmd, .COMPUTE, pipeline.layout, 0, 1, *r_ctx.bindless_system.descriptor_set, 0, null);
    vkCmdBindPipeline(cmd, .COMPUTE, pipeline.pipeline);

    r_ctx.current_pipeline = pipeline.common;
}

cmd_push_constants :: inline (cmd: VkCommandBuffer, push_constants: $T, offset: u32 = 0) {
	vkCmdPushConstants(
		cmd,
		r_ctx.current_pipeline.layout,
		r_ctx.current_pipeline.stages,
		0,
		size_of(T),
		*push_constants,
	);
}

cmd_bind_index_buffer :: inline (
    cmd: VkCommandBuffer, 
    buffer: VkBuffer, 
    offset: VkDeviceSize = 0,
    index_type: VkIndexType = .UINT32
) {
    vkCmdBindIndexBuffer(cmd, buffer, offset, index_type);
}

cmd_draw_indexed :: inline (
    cmd: VkCommandBuffer,
    index_count: u32,
    instance_count: u32 = 1,
    first_index: u32 = 0,
    vertex_offset: s32 = 0,
    first_instance: u32 = 0
) {
    vkCmdDrawIndexed(cmd, index_count, instance_count, first_index, vertex_offset, first_instance);
}

RenderingInfo :: struct {
    area: VkExtent2D;

    color_attachment: *VkRenderingAttachmentInfo;
    depth_attachment: *VkRenderingAttachmentInfo;
}

cmd_begin_rendering :: inline (cmd: VkCommandBuffer, info: RenderingInfo) {
    render_info := init_rendering_info(info.area, info.color_attachment, info.depth_attachment);
    vkCmdBeginRendering(cmd, *render_info);
}

cmd_end_rendering :: inline (cmd: VkCommandBuffer) {
    vkCmdEndRendering(cmd);
}

cmd_dispatch :: inline (cmd: VkCommandBuffer, group_count_x: u32 = 1, group_count_y: u32 = 1, group_count_z: u32 = 1) {
    vkCmdDispatch(cmd, group_count_x, group_count_y, group_count_z);
}
