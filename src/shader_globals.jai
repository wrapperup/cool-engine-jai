NUM_CASCADES: u32 : 3;

GPUDrawPushConstants :: struct @ShaderShared {
	global_data:    GPU_Ptr(GPUGlobalData);
	vertex_buffer:  GPU_Ptr(GPUVertex);
	model_matrices: GPU_Ptr(Mat4x4);
	materials:      GPU_Ptr(GPU_PBR_Material);
	model_index:    u32;
	num_cascades:   u32;

    material_index: MaterialId;

    shadow_depth:   ImageId;   @Image2DArray<f32>
    shadow_sampler: SamplerId; @SamplerComparison
}

GPUDrawShadowDepthPushConstants :: struct @ShaderShared {
	vertex_buffer:  GPU_Ptr(GPUVertex);
	model_matrices: GPU_Ptr(Mat4x4);
	global_data:    GPU_Ptr(GPUGlobalData);
	model_index:    u32;
	cascade_index:  u32;
}

GPUSkinningPushConstants :: struct @ShaderShared {
	input_vertex_buffer:  GPU_Ptr(GPUVertex);
	output_vertex_buffer: GPU_Ptr(GPUVertex);
	joint_matrices:       GPU_Ptr(Mat4x4); // TODO: Make these Mat4x3 since they're just affine transforms.
	attrs:                GPU_Ptr(GPUSkeletonVertexAttribute);
	vertex_count:         u32;
}

GPUSkyboxPushConstants :: struct @ShaderShared {
	vertex_buffer: GPU_Ptr(GPUVertex);
	global_data:   GPU_Ptr(GPUGlobalData);
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
	sh_volume:        GPU_Ptr(Sh_Coefficients);
	point_lights:     GPU_Ptr(GPU_Point_Light);
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

	cascade_world_to_shadows: GPU_Ptr(Mat4x4);
	cascade_configs:          GPU_Ptr(GPUCascadeConfig);
	view_to_clip:             Mat4x4;
	world_to_view:			  Mat4x4;
	sun_color:                Vec3;
	sky_color:                Vec3;
	camera_pos:               Vec3;
	sun_direction:            Vec3;

    default_sampler: SamplerId; @Sampler
}
