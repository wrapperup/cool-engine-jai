Ball :: struct {
	using #as entity: *Entity;

	material:           MaterialId;
	num:                int;
	rigid:              *PxRigidDynamic;

	skel_mesh_instance: SkeletalMeshInstance;
	skel_anim:          *SkeletalAnimation;
	skel_animator:      SkeletonAnimator;
	use_game_time:      bool;
	sample_time:        f32;
}

init :: (ball: *Ball, pos: Vec3, skeleton: *Skeleton, anim: *SkeletalAnimation) {
	ball.skel_mesh_instance = init_skeletal_mesh_instance(skeleton, anim);
	ball.material = 1;

	init_skeleton_animator(*ball.skel_animator, skeleton, anim);

	ball.num = entities_count(Ball) - 1;

	sphere_material := PxPhysics_createMaterial(game.phys.physics, 0.9, 0.5, 0.1);
	geo := PxSphereGeometry_new(1.3);

	ball.rigid = PxCreateDynamic(
		game.phys.physics,
		*PxTransform_new(*pos),
		*geo,
		sphere_material,
		10.0,
		*PxTransform_new(*(Vec3.{0, 0, 0})),
	);

	PxRigidBody_setAngularDamping(ball.rigid, 0.1);
	PxRigidBody_setLinearDamping(ball.rigid, 0.1);

	PxScene_addActor(game.phys.scene, ball.rigid, null);
	PxRigidDynamic_setSleepThreshold(ball.rigid, 0.1);

	// base := cast(*PxActor, ball.rigid);
	// base.userData = entity_id_to_ptr(ball.id);
}

update_ball_fixed :: (ball: *Ball) {
	sample_animation(*ball.skel_animator, ball.sample_time);
	ball.sample_time += 0.005;

	pose := PxRigidActor_getGlobalPose(ball.rigid);
	ball.translation = pose.p;
	ball.rotation = pose.q;
	PxRigidBody_addForce(ball.rigid, *(Vec3.{0, 0, 0}), xx PxForceMode.Force, true);
}
