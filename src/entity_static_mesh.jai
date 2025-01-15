StaticMesh :: struct {
	using #as entity: *Entity;

	mesh:         MeshBuffers;
	material:     MaterialId;
	body:         *PxRigidStatic;
}

init :: (static_mesh: *StaticMesh, mesh_file_name: string, material: MaterialId) {
	mesh, ok := load_mesh_from_file(mesh_file_name);
	assert(ok);

	gpu_mesh := upload_mesh_to_gpu(mesh);
	defer_destroy(gpu_mesh);

	tolerances_scale := PxTolerancesScale_new(1, 10);
	params := PxCookingParams_new(*tolerances_scale);

	points_data := NewArray(mesh.vertices.count, Vec3);
	defer free(points_data.data);

	for vertex, i: mesh.vertices {
		points_data[i] = vertex.position;
	}

	mesh_desc := PxTriangleMeshDesc_new();

	mesh_desc.points.count = xx mesh.vertices.count;
	mesh_desc.points.stride = size_of(Vec3);
	mesh_desc.points.data = points_data.data;

	mesh_desc.triangles.count = xx (mesh.indices.count / 3);
	mesh_desc.triangles.stride = 3 * size_of(u32);
	mesh_desc.triangles.data = mesh.indices.data;

	// valid := PxValidateTriangleMesh(*params, *mesh_desc);
	// assert(valid);

	result: PxTriangleMeshCookingResult;
	tri_mesh := PxCreateTriangleMesh(*params, *mesh_desc, PxPhysics_getPhysicsInsertionCallback(game.phys.physics), *result);
	assert(result != .Failure); // OK

	geometry := PxTriangleMeshGeometry_new(tri_mesh, *PxMeshScale_new(1), 0);

	phys_material := PxPhysics_createMaterial(game.phys.physics, 0.9, 0.5, 0.1);

	static_mesh.body = PxCreateStatic(
		game.phys.physics,
		*PxTransform_new(*(Vec3.{0, 0, 0})),
		*geometry,
		phys_material,
		*PxTransform_new(*(Vec3.{0, 0, 0})),
	);
	assert(static_mesh.body != null);

	PxScene_addActor(game.phys.scene, static_mesh.body, null);

	static_mesh.mesh = gpu_mesh;
	static_mesh.material = material;
}
