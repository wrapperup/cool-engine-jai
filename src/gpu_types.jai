GPUVertex :: struct @ShaderShared {
	position: Vec3;
	uv_x:     f32;
	normal:   Vec3;
	uv_y:     f32;
	color:    Vec4;
	tangent:  Vec4;
}

GPUSkeletonVertexAttribute :: struct @ShaderShared {
	joints:  [4]u8;
	weights: [4]f32;
}

MeshBuffers :: struct {
	index_buffer:  GPU_Buffer(u32);
	index_count:   u32;
	vertex_buffer: GPU_Buffer(GPUVertex);
	vertex_count:  u32;
}

SkelMeshBuffers :: struct {
	using mesh_buffers:     MeshBuffers;

	skel_vert_attrs_buffer: GPU_Buffer(GPUSkeletonVertexAttribute);
	attrs_count:            u32;
}
