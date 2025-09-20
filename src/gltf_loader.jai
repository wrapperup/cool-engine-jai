create_mesh_buffers :: (mesh: Mesh, loc := #caller_location) -> MeshBuffers {
	index_count := mesh.indices.count;
	vertex_count := mesh.vertices.count;

	assert(index_count > 0);
	assert(vertex_count > 0);

	new_surface: MeshBuffers;
	new_surface.index_count = xx index_count;
	new_surface.vertex_count = xx vertex_count;

	new_surface.vertex_buffer =
		create_buffer(GPUVertex, vertex_count, .Storage, loc = loc);

	new_surface.index_buffer =
		create_buffer(u32, index_count, .Index, name = "Indices", loc = loc);

	return new_surface;
}

staging_write_mesh_buffers :: (buffers: *MeshBuffers, mesh: Mesh, loc := #caller_location) {
	vertex_buffer_size := size_of(GPUVertex) * mesh.vertices.count;
	index_buffer_size := size_of(u32) * mesh.indices.count;

	assert(buffers.index_count == mesh.indices.count);
	assert(buffers.vertex_count == mesh.vertices.count);

	staging := create_buffer(u8, vertex_buffer_size + index_buffer_size, .Staging, loc = loc);

	write_buffer(*staging, mesh.vertices);
	write_buffer(*staging, mesh.indices, vertex_buffer_size);

	{
		cmd := immediate_submit();

		vertex_copy := VkBufferCopy.{
			dstOffset = 0,
			srcOffset = 0,
			size      = xx vertex_buffer_size,
		};

		index_copy := VkBufferCopy.{
			dstOffset = 0,
			srcOffset = xx vertex_buffer_size,
			size      = xx index_buffer_size,
		};

		vkCmdCopyBuffer(cmd, staging.buffer, buffers.vertex_buffer.buffer, 1, *vertex_copy);
		vkCmdCopyBuffer(cmd, staging.buffer, buffers.index_buffer.buffer, 1, *index_copy);
	}

	destroy_buffer(staging);
}

parse_gltf_mesh_into_mesh :: (data: *GLTF_Data, mesh_idx: int) -> Mesh, bool {
	mesh: Mesh;

	gltf_mesh := *data.meshes[mesh_idx];
	primitive := *gltf_mesh.primitives[0]; // TODO: Load all primitives.

	if primitive.position_accessor == -1     then return .{}, false;
	if primitive.indices_accessor == -1      then return .{}, false;
	if primitive.texcoord_0_accessor == -1   then return .{}, false;

    tangent_ok := primitive.tangent_accessor != -1;

	{
		indices_accessor := *data.accessors[primitive.indices_accessor];
		mesh.indices  = NewArray(indices_accessor.count, u32);

		position_accessor := *data.accessors[primitive.position_accessor];
		mesh.vertices = NewArray(position_accessor.count, GPUVertex);
	}

	for iterate_accessor(data, primitive.indices_accessor, u32) {
		mesh.indices[it_index] = it;
	}

	for iterate_accessor(data, primitive.position_accessor, Vec3) {
		mesh.vertices[it_index].position = it;
	}

	for iterate_accessor(data, primitive.texcoord_0_accessor, Vec2) {
		mesh.vertices[it_index].uv_x = it.x;
		mesh.vertices[it_index].uv_y = it.y;
	}

	if primitive.normal_accessor != -1 {
		for iterate_accessor(data, primitive.normal_accessor, Vec3) {
			mesh.vertices[it_index].normal = it;
		}
	}

	if primitive.color_accessor != -1 {
		for iterate_accessor(data, primitive.color_accessor, Vec3) {
			mesh.vertices[it_index].color.xyz = it;
			mesh.vertices[it_index].color.w = 1;
		}
	} else {
		// Default the color to 1
		for * vertex: mesh.vertices {
			vertex.color = Vec4.{1, 1, 1, 1};
		}
	}

	if tangent_ok {
		for iterate_accessor(data, primitive.tangent_accessor, Vec4) {
			mesh.vertices[it_index].tangent = it;
		}
	} else {
		get_num_vertices_of_face :: (pContext: *Mikk.MikkContext, iFace: int) -> int {
			return 3;
		}

		// Generate tangents if we have normals + uv and no tangents are included.
		get_vertex_index :: (pContext: *Mikk.MikkContext, iFace: int, iVert: int) -> int {
			gltf_mesh := cast(*Mesh) pContext.user_data;

			indices_index := iVert + (iFace * get_num_vertices_of_face(pContext, iFace));
			index := gltf_mesh.indices[indices_index];

			return cast(int) index;
		}

		get_num_faces :: (pContext: *Mikk.MikkContext) -> int {
			gltf_mesh := cast(*Mesh) pContext.user_data;
			return gltf_mesh.indices.count / 3;
		}

		get_position :: (pContext: *Mikk.MikkContext, iFace: int, iVert: int) -> Vec3 {
			gltf_mesh := cast(*Mesh) pContext.user_data;
			return gltf_mesh.vertices[get_vertex_index(pContext, iFace, iVert)].position;
		}

		get_normal :: (pContext: *Mikk.MikkContext, iFace: int, iVert: int) -> Vec3 {
			gltf_mesh := cast(*Mesh) pContext.user_data;
			return gltf_mesh.vertices[get_vertex_index(pContext, iFace, iVert)].normal;
		}

		get_tex_coord :: (pContext: *Mikk.MikkContext, iFace: int, iVert: int) -> Vec2 {
			gltf_mesh := cast(*Mesh) pContext.user_data;
			vertex := *gltf_mesh.vertices[get_vertex_index(pContext, iFace, iVert)];
			return .{vertex.uv_x, vertex.uv_y};
		}

		set_t_space_basic :: (pContext: *Mikk.MikkContext, fvTangent: Vec3, fSign: f32, iFace: int, iVert: int) {
			gltf_mesh := cast(*Mesh) pContext.user_data;
			tangent := *gltf_mesh.vertices[get_vertex_index(pContext, iFace, iVert)].tangent;

			// Not sure why I need to flip these? Seems to be fine though.
			tangent.xyz = -fvTangent;
			tangent.w = -fSign;
		}

		mikk_interface := Mikk.MikkInterface.{
			get_num_faces            = get_num_faces,
			get_num_vertices_of_face = get_num_vertices_of_face,
			get_position             = get_position,
			get_normal               = get_normal,
			get_tex_coord            = get_tex_coord,
			set_t_space_basic        = set_t_space_basic,
		};

		ctx := Mikk.MikkContext.{
			mikk_interface = *mikk_interface,
			user_data = *mesh,
		};

		tangent_ok = Mikk.generate_tangents(*ctx);
	}

	assert(tangent_ok, "Tangents were not able to be generated.");

	return mesh, tangent_ok;
}

Mesh :: struct {
	indices:  [] u32;
	// TODO: Maybe store this as AOS instead
	vertices: [] GPUVertex;
}

SkeletalMesh :: struct {
	using mesh: Mesh;
	attrs:      [] GPUSkeletonVertexAttribute;
}


load_mesh_from_file :: (path: string, loc := #caller_location) -> Mesh, bool {
	data := gltf_parse_file(path);
	gltf_load_buffers(*data);

	mesh, ok := parse_gltf_mesh_into_mesh(*data, 0);
	return mesh, ok;
}

load_gpu_mesh_from_file :: (path: string, loc := #caller_location) -> MeshBuffers, bool {
	data := gltf_parse_file(path);
	gltf_load_buffers(*data);

	mesh, ok := parse_gltf_mesh_into_mesh(*data, 0);

	return upload_mesh_to_gpu(mesh, loc = loc), true;
}

defer_destroy :: (gpu_mesh: MeshBuffers) {
	defer_destroy(gpu_mesh.vertex_buffer);
	defer_destroy(gpu_mesh.index_buffer);
}

upload_mesh_to_gpu :: (mesh: Mesh, loc := #caller_location) -> MeshBuffers {
	buffers := create_mesh_buffers(mesh, loc = loc);
	staging_write_mesh_buffers(*buffers, mesh);
	buffers.index_count = xx mesh.indices.count;

	return buffers;
}

// Allocates two slices if successful. Make sure to free them when you're done.
parse_gltf_mesh_into_skel_mesh :: (
	data: *GLTF_Data,
	mesh_idx: int
) -> SkeletalMesh, Skeleton, SkeletalAnimation, bool {
	skel_mesh: SkeletalMesh;
	{
		mesh, ok := parse_gltf_mesh_into_mesh(data, mesh_idx);
		if !ok then return .{}, .{}, .{}, false;

		skel_mesh.mesh = mesh;
	}

	gltf_mesh := *data.meshes[mesh_idx];
	primitive := *gltf_mesh.primitives[0];

	if primitive.joints_accessor == -1  then return .{}, .{}, .{}, false;
	if primitive.weights_accessor == -1   then return .{}, .{}, .{}, false;

	assert(mesh_idx < data.skins.count);

	skin := *data.skins[mesh_idx];

	{
		// Count of joints == weights (in theory...)
		joints_weights_count := data.accessors[primitive.joints_accessor].count;
		skel_mesh.attrs = NewArray(joints_weights_count, GPUSkeletonVertexAttribute);
	}

	for iterate_accessor(data, primitive.joints_accessor, [4]u8) {
		skel_mesh.attrs[it_index].joints = it;
	}

	for iterate_accessor(data, primitive.weights_accessor, [4]f32) {
		skel_mesh.attrs[it_index].weights = it;
	}


	skeleton: Skeleton;
	{
		array_reserve(*skeleton.inverse_bind_matrices, skin.joints.count);
		array_reserve(*skeleton.joint_tree, skin.joints.count);

		skeleton.joint_count = skin.joints.count;

		for iterate_accessor(data, skin.inverse_bind_matrices, Mat4x4) {
			array_add(*skeleton.inverse_bind_matrices, transpose(it));
		}

		// Create hierarchical tree structure for joints (used later for calcing joint matrices)
		for joint_index: skin.joints {
			joint := *data.nodes[joint_index];

			children: [..] u32;
			array_reserve(*children, joint.children.count);

			for child_index: joint.children {
				array_add(*children, xx ((skin.joints.count - child_index) - 1));
			}

			array_add(*skeleton.joint_tree, children);
		}
	}

	skel_anim: SkeletalAnimation;
	{
		// TODO: TESTING: Grab first animation.
		animation := data.animations[0];

		joint_anims: Table(int, JointTrack);

		for channel: animation.channels {
			joint_index := channel.target.node;
			assert(joint_index != -1);

			joint_anim := find_or_add(*joint_anims, joint_index);

			output := animation.samplers[channel.sampler].output;

			if channel.target.property == {
				case .TRANSLATION;
					for iterate_accessor(data, output, Vec3) {
						array_add(*joint_anim.keyframes_translation, it);
					}
				case .ROTATION;
					for iterate_accessor(data, output, Quat) {
						array_add(*joint_anim.keyframes_rotation, it);
					}
				case .SCALE;
					for iterate_accessor(data, output, Vec3) {
						array_add(*joint_anim.keyframes_scale, it);
					}
				case;
					assert(false, "Unsupported animation channel type.");
			}
		}

		array_resize(*skel_anim.joint_animations, joint_anims.count);

		for joint_anims {
			skel_anim.joint_animations[it_index] = it;
		}

		skel_anim.keyframe_count = xx skel_anim.joint_animations[0].keyframes_translation.count;
		skel_anim.fps = 30.0; // TODO: Read this from file...
	}

	return skel_mesh, skeleton, skel_anim, true;
}

gltf_get_local_transform :: (using node: GLTF_Node) -> Matrix4 {
  if has_matrix {
    transform : Matrix4 = ---;
    for matrix transform.floats[it_index] = it;

    // Careful here, we transpose the matrix because glTF
    // store column-major matrices.
    return transpose(transform);
  }

  t := make_vector3(translation);
  r := Quaternion.{rotation[0], rotation[1], rotation[2], rotation[3]};
  s := make_vector3(scale);

  return make_translation_matrix4(t) * rotation_matrix(Matrix4, r) * make_scale_matrix4(s);
}

gltf_get_world_transform :: (gltf_data: *GLTF_Data, node: GLTF_Node) -> Matrix4 {
  parent_index := node.parent;
  node_transform := node.local_transform;

  while parent_index != -1 {
    parent := gltf_data.nodes[parent_index];
    node_transform = parent.local_transform * node_transform;
    parent_index = parent.parent;
  }

  return node_transform;
}

load_skel_mesh_from_file :: (path: string, loc := #caller_location) -> Skeleton, SkeletalAnimation, bool {
	data := gltf_parse_file(path);
	gltf_load_buffers(*data);

	skel_mesh, skeleton, anim, ok := parse_gltf_mesh_into_skel_mesh(*data, 0);
	if !ok then return .{}, .{}, false;

	skeleton.buffers = create_skel_mesh_buffers(skel_mesh, loc = loc);
	staging_write_skel_mesh_buffers(*skeleton.buffers, skel_mesh, loc = loc);

	return skeleton, anim, true;
}

defer_destroy :: (gpu_mesh: SkelMeshBuffers) {
	defer_destroy(gpu_mesh.mesh_buffers);
	defer_destroy(gpu_mesh.skel_vert_attrs_buffer);
}

// Creates the buffers, but doesn't fill them.
create_skel_mesh_buffers :: (skel_mesh: SkeletalMesh, loc := #caller_location) -> SkelMeshBuffers {
	assert(skel_mesh.attrs.count > 0, "Skeleton mesh doesn't have any attributes.");
	assert(skel_mesh.vertices.count == skel_mesh.attrs.count, "Attribute count doesn't match number of verticies (% vs %).", skel_mesh.vertices.count, skel_mesh.attrs.count);

	new_surface: SkelMeshBuffers;
	new_surface.mesh_buffers = create_mesh_buffers(skel_mesh.mesh, loc = loc);
	new_surface.attrs_count = xx skel_mesh.attrs.count;

	new_surface.skel_vert_attrs_buffer =
		create_buffer(GPUSkeletonVertexAttribute, skel_mesh.attrs.count, .Storage, loc = loc);

	return new_surface;
}

staging_write_skel_mesh_buffers :: (buffers: *SkelMeshBuffers, skel_mesh: SkeletalMesh, loc := #caller_location) {
	assert(skel_mesh.attrs.count > 0);
	assert(skel_mesh.vertices.count == skel_mesh.attrs.count);

	// TODO: This could be one write...
	staging_write_mesh_buffers(*buffers.mesh_buffers, skel_mesh.mesh);
	staging_write_buffer(*buffers.skel_vert_attrs_buffer, skel_mesh.attrs);
}

GLTF_Accessor_Iterator :: struct($T: Type) {
	data:     *GLTF_Data;
	accessor: s64;
}

iterate_accessor :: (data: *GLTF_Data, accessor: s64, $T: Type) -> GLTF_Accessor_Iterator(T) {
	return .{
		data = data,
		accessor = accessor,
	};
}

for_expansion :: (iter: GLTF_Accessor_Iterator($T), body: Code, flags: For_Flags) #expand {
	#assert(!(flags & .REVERSE)); // We don't handle the reverse flag.
	#assert(!(flags & .POINTER)); // We don't handle the pointer flag.

	accessor := iter.data.accessors[iter.accessor];

	buffer_view := iter.data.buffer_views[accessor.buffer_view];
	buffer      := iter.data.buffers[buffer_view.buffer];
	buffer_data := cast(*void, buffer.data.data);

	buffer_offset := accessor.byte_offset + buffer_view.byte_offset;

	for `it_index: 0 .. accessor.count-1 {
		offset := buffer_offset + (it_index * accessor.stride);
		value_ptr := buffer_data + offset;

		value, ok := try_cast_accessor_type(T, value_ptr, accessor.component_type, accessor.type);
		`it := value;

		#insert body;
	}
}

try_cast_accessor_type :: ($T: Type, value_ptr: *void, component_type: GLTF_Component_Type, type: GLTF_Accessor_Type) -> T, bool {
	#if type_info(T).type == .STRUCT {
		value, ok := try_cast_vec_type(T, value_ptr, component_type, type);
		return value, ok;
	}
	else #if type_info(T).type == .ARRAY {
		value, ok := try_cast_vec_type(T, value_ptr, component_type, type);
		return value, ok;
	}
	else #if type_info(T).type == .INTEGER {
		value, ok := try_cast_numeric_type(T, value_ptr, component_type);
		return value, ok;
	}
	else #if type_info(T).type == .FLOAT {
		value, ok := try_cast_numeric_type(T, value_ptr, component_type);
		return value, ok;
	}

	// Unreachable.
	v: T = ---;
	return v, false;
}

is_signed :: ($T: Type) -> bool {
	i := cast(*Type_Info_Integer) T;
	return i.signed;
}

try_cast_numeric_type :: ($T: Type, value_ptr: *void, component_type: GLTF_Component_Type) -> T, bool #modify {
	info := cast(*Type_Info) T;
	return info.type == .FLOAT || info.type == .INTEGER;
} {
	info := cast(*Type_Info_Integer) T;

	#if type_info(T).type == .INTEGER {
		#if #run is_signed(T) {
			value, ok := try_cast_int_type(T, value_ptr, component_type);
			return value, ok;
		} else {
			value, ok := try_cast_uint_type(T, value_ptr, component_type);
			return value, ok;
		}
	} else #if type_info(T).type == .FLOAT {
		value, ok := try_cast_float_type(T, value_ptr, component_type);
		return value, ok;
	}

	v: T = ---;
	return v, false;
}

try_cast_int_type :: ($T: Type, value_ptr: *void, component_type: GLTF_Component_Type) -> T, bool #modify {
	info := cast(*Type_Info_Integer, T);
	return info.type == .INTEGER && info.signed == true;
} {
	value: T = ---;

	if component_type == {
		case .BYTE;  value = cast(T, cast(*s8, value_ptr).*);
		case .SHORT; value = cast(T, cast(*s16, value_ptr).*);

		case; return 0, false;
	}

	return value, true;
}

try_cast_uint_type :: ($T: Type, value_ptr: *void, component_type: GLTF_Component_Type) -> T, bool #modify {
	info := cast(*Type_Info_Integer, T);
	return info.type == .INTEGER && info.signed == false;
} {
	value: T = ---;

	if component_type == {
		case .UNSIGNED_BYTE;    value = cast(T, cast(*u8, value_ptr).*);
		case .UNSIGNED_SHORT;   value = cast(T, cast(*u16, value_ptr).*);
		case .UNSIGNED_INTEGER; value = cast(T, cast(*u32, value_ptr).*);

		case; return 0, false;
	}

	return value, true;
}

try_cast_float_type :: ($T: Type, value_ptr: *void, component_type: GLTF_Component_Type) -> T, bool #modify {
	info := cast(*Type_Info, T);
	return info.type == .FLOAT;
} {
	value: T = ---;

	if component_type == {
		case .FLOAT;  value = cast(T, cast(*f32, value_ptr).*);

		case; return 0.0, false;
	}

	return value, true;
}

try_cast_vec_type :: (
	$T: Type,
	value_ptr: *void,
	component_type: GLTF_Component_Type,
	type: GLTF_Accessor_Type,
	$N := 1
) -> T, bool #modify {
	info := cast(*Type_Info_Array, T);

	if info.type == .ARRAY && info.array_type == .FIXED {
		N = info.array_count;
		return true;
	}

	if T == Vector2    { N = 2;  return true; }
	if T == Vector3    { N = 3;  return true; }
	if T == Vector4    { N = 4;  return true; }
	if T == Matrix4    { N = 16; return true; }
	if T == Quaternion { N = 4;  return true; }

	return false;
} {
	value: T = ---;

	ty_ok := true;

	// We don't support casting to different vec types.
	#if N == 2       { if type != .VEC2   then ty_ok = false; }
	else #if N == 3  { if type != .VEC3   then ty_ok = false; }
	else #if N == 4  { if type != .VEC4   then ty_ok = false; }
	else #if N == 16 { if type != .MAT4   then ty_ok = false; }
	else { ty_ok = false; }

	if !ty_ok {
		return value, false;
	}

	if #complete component_type == {
		case .BYTE;
			reinterp_val := cast(*[N] s8, value_ptr).*;
			value = array_cast(reinterp_val, T);
		case .SHORT;
			reinterp_val := cast(*[N] s16, value_ptr).*;
			value = array_cast(reinterp_val, T);
		case .UNSIGNED_BYTE;
			reinterp_val := cast(*[N] u8, value_ptr).*;
			value = array_cast(reinterp_val, T);
		case .UNSIGNED_SHORT;
			reinterp_val := cast(*[N] u16, value_ptr).*;
			value = array_cast(reinterp_val, T);
		case .UNSIGNED_INTEGER;
			reinterp_val := cast(*[N] u32, value_ptr).*;
			value = array_cast(reinterp_val, T);
		case .FLOAT;
			reinterp_val := cast(*[N] float32, value_ptr).*;
			value = array_cast(reinterp_val, T);
	}

	return value, true;
}

// Casts a fixed array to a modules/Math scalar type, or another fixed-array type.
array_cast :: (array: [$N]$T, $U: Type) -> U #modify {
	info := cast(*Type_Info_Array, U);

	if info.type == .ARRAY && info.array_type == .FIXED return true;

	if U == Vector2    return true;
	if U == Vector3    return true;
	if U == Vector4    return true;
	if U == Matrix4    return true;
	if U == Quaternion return true;

	return false;
} {
	value: U = ---;
	#if      U == Vector2 { for i: 0..1  value.component[i] = cast(float) array[i]; }
	else #if U == Vector3 { for i: 0..2  value.component[i] = cast(float) array[i]; }
	else #if U == Vector4 { for i: 0..3  value.component[i] = cast(float) array[i]; }
	else #if U == Quaternion { for i: 0..3  value.component[i] = cast(float) array[i]; }
	else #if U == Matrix4 { for i: 0..15 value.floats[i] = cast(float) array[i]; }
	else {
		info := cast(*Type_Info_Array, U);
		assert(info.type == .ARRAY && info.array_type == .FIXED, "Passed in a non-array type. This shouldn't happen.");

		for i: 0..info.array_count-1  value[i] = xx array[i];
	}

	return value;
}
