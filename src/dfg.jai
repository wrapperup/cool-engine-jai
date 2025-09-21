// DfgGeneratePassPC :: struct {
// 	sample_count: u32;
// 	multiscatter: u32;
// }
//
// DfgGeneratePass :: struct {
// 	descriptor_set_layout: VkDescriptorSetLayout;
// 	descriptor_set:        VkDescriptorSet;
// 	pipeline:              ComputePipeline;
//
// 	// Resources
// 	dfg_image:               GPUImage;
// 	dfg_image_mapped_buffer: GPUBuffer(u8);
// 	width, height:           u32;
// }
//
// create_dfg_generate_pipeline :: (width: u32, height: u32) -> DfgGeneratePass {
// 	pass := DfgGeneratePass.{
// 		width  = width,
// 		height = height,
// 	};
//
// 	pass.descriptor_set_layout = create_descriptor_set_layout(
// 		.[.{binding = 0, type = .STORAGE_IMAGE}],
// 		.UPDATE_AFTER_BIND_POOL_BIT,
// 		.COMPUTE_BIT,
// 	);
//
// 	defer_destroy(pass.descriptor_set_layout);
//
// 	pass.descriptor_set = allocate_descriptor_set(
// 		*r_ctx.global_descriptor_allocator,
// 		pass.descriptor_set_layout,
// 	);
//
// 	pass.dfg_image = create_image(.R16G16_SFLOAT, .{width, height, 1}, .STORAGE_BIT | .TRANSFER_SRC_BIT);
// 	create_image_view(*pass.dfg_image, .COLOR_BIT);
//
// 	// Maybe we can make a nicer abstraction?
// 	write_descriptor_set(
// 		pass.descriptor_set,
// 		.[
// 			.{
// 				binding      = 0,
// 				type         = .STORAGE_IMAGE, // We know this
// 				image_view   = pass.dfg_image.view,
// 				image_layout = .GENERAL,
// 			},
// 		],
// 	);
//
// 	dfg_shader, ok := load_shader_module("shaders/out/dfg.spv");
// 	assert(ok, "Failed to load shaders.");
//
// 	pass.pipeline = create_compute_pipelines("DFG", dfg_shader, *pass.descriptor_set_layout, DfgGeneratePassPC);
//
// 	destroy_shader_module(dfg_shader);
//
// 	defer_destroy(pass.pipeline);
// 	defer_destroy(pass.pipeline_layout);
//
// 	// R16G16_SFLOAT = size_of(f32) * 1 (2 components mapped to bytes of float)
// 	size := width * height * size_of(f32);
// 	pass.dfg_image_mapped_buffer = create_buffer(u8, size, .Readback);
//
// 	return pass;
// }
//
// run_dfg_generate_pass :: (pass: *DfgGeneratePass, cmd: VkCommandBuffer) {
//     cmd_bind_pipeline(cmd, pass.pipeline);
// 	vkCmdBindDescriptorSets(cmd, .COMPUTE, pass.pipeline.layout, 0, 1, *pass.descriptor_set, 0, null);
//
// 	cmd_push_constants(
// 		cmd, 
// 		pass.pipeline.layout, 
// 		stages = .COMPUTE_BIT, 
// 		push_constants = DfgGeneratePassPC.{
// 		sample_count = 4096,
// 		multiscatter = 0,
// 	});
//
// 	vkCmdDispatch(cmd, pass.width / 16, pass.height / 16, 1);
// }
