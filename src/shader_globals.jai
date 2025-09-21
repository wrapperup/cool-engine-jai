NUM_CASCADES: u32 : 3;

GPUDrawPushConstants :: struct @ShaderShared {
	global_data:    GPUPtr(GPUGlobalData);
	vertex_buffer:  GPUPtr(GPUVertex);
	model_matrices: GPUPtr(Mat4x4);
	materials:      GPUPtr(GPU_PBR_Material);
	model_index:    u32;
	num_cascades:   u32;

    material_index: MaterialId;

    shadow_depth:   ImageId;   @Image2DArray<f32>
    shadow_sampler: SamplerId; @SamplerComparison
}

GPUDrawShadowDepthPushConstants :: struct @ShaderShared {
	vertex_buffer:  GPUPtr(GPUVertex);
	model_matrices: GPUPtr(Mat4x4);
	global_data:    GPUPtr(GPUGlobalData);
	model_index:    u32;
	cascade_index:  u32;
}

GPUSkinningPushConstants :: struct @ShaderShared {
	input_vertex_buffer:  GPUPtr(GPUVertex);
	output_vertex_buffer: GPUPtr(GPUVertex);
	joint_matrices:       GPUPtr(Mat4x4); // TODO: Make these Mat4x3 since they're just affine transforms.
	attrs:                GPUPtr(GPUSkeletonVertexAttribute);
	vertex_count:         u32;
}

GPUSkyboxPushConstants :: struct @ShaderShared {
	vertex_buffer: GPUPtr(GPUVertex);
	global_data:   GPUPtr(GPUGlobalData);
}

GPUPostProcessingPushConstants :: struct @ShaderShared {
    resolved_image:  ImageId; @RWImage2D
    tony_mc_mapface: ImageId; @Image3D<Vec3>
    sampler:         SamplerId; @Sampler
}

GPU_PBR_Material :: struct @ShaderShared {
	base_color:            ImageId; @Image2D
	normal_map:            ImageId; @Image2D
	ao_roughness_metallic: ImageId; @Image2D
}

GPUEnvironment :: struct @ShaderShared {
	sh_volume:        GPUPtr(ShCoefficients);
	point_lights:     GPUPtr(GPU_Point_Light);
	num_point_lights: u32;

    env_map:     ImageId; @ImageCube
    dfg:         ImageId; @Image2D
    env_sampler: SamplerId; @Sampler
}

GPUCascadeConfig :: struct @ShaderShared {
	split_dist: f32;
	bias:       f32;
	slope_bias: f32;
}

GPUGlobalData :: struct @ShaderShared {
	environment: GPUEnvironment;

	cascade_world_to_shadows: GPUPtr(Mat4x4);
	cascade_configs:          GPUPtr(GPUCascadeConfig);
	view_to_clip:             Mat4x4;
	world_to_view:			  Mat4x4;
	sun_color:                Vec3;
	sky_color:                Vec3;
	camera_pos:               Vec3;
	sun_direction:            Vec3;

    default_sampler: SamplerId; @Sampler
}
