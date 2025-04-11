// TODO: Un-hard code this stuff.
SHADOW_ID          :: Tex2DArray.{ 0 };
TONY_MC_MAPFACE_ID :: Tex3D.{ 1 };
DFG_ID             :: Tex2D.{ 2 };
ENVIRONMENT_MAP_ID :: TexCube.{ 3 };

DEFAULT_SAMPLER_ID     :: SamplerId.{ 0 };
SHADOW_SAMPLER_ID      :: SamplerId.{ 1 };
ENVIRONMENT_SAMPLER_ID :: SamplerId.{ 2 };

RESOLVED_IMAGE_ID :: RWTex2D.{ 0 };

MAX_BINDLESS_IMAGES :: 100;
RESERVED_BINDLESS_IMAGES_COUNT :: 10;
MAX_BINDLESS_SAMPLERS :: 32;

NUM_CASCADES: u32 : 3;

GPUDrawPushConstants :: struct @ShaderShared {
	global_data:    GPU_Ptr(GPUGlobalData);
	vertex_buffer:  GPU_Ptr(GPUVertex);
	model_matrices: GPU_Ptr(Mat4x4);
	materials:      GPU_Ptr(GPU_PBR_Material);
	model_index:    u32;
	material_index: MaterialId;
	num_cascades:   u32;
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

GPU_PBR_Material :: struct @ShaderShared {
	base_color:            Tex2D;
	normal_map:            Tex2D;
	ao_roughness_metallic: Tex2D;
}

GPUEnvironment :: struct @ShaderShared {
	sh_volume:        GPU_Ptr(Sh_Coefficients);
	point_lights:     GPU_Ptr(GPU_Point_Light);
	num_point_lights: u32;
}

GPUCascadeConfig :: struct @ShaderShared {
	split_dist: f32;
	bias:       f32;
	slope_bias: f32;
}

GPUGlobalData :: struct @ShaderShared {
	cascade_world_to_shadows: GPU_Ptr(Mat4x4);
	cascade_configs:          GPU_Ptr(GPUCascadeConfig);
	view_to_clip:             Mat4x4;
	world_to_view:			  Mat4x4;
	sun_color:                Vec3;
	sky_color:                Vec3;
	camera_pos:               Vec3;
	sun_direction:            Vec3;
	environment:              GPUEnvironment;
}
