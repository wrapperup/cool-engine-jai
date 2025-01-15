JointId :: u32;
JointMatrix :: Mat4x4;

// Coordinate Systems:
// Local (ls) - Parent is at origin
// Model (ms) - Model/Root joint is at origin
// Joint (js) - Joint is at origin

Skeleton :: struct {
	joint_count:           int;
	joint_tree:            [..][..] JointId;

	// Stores the joint's bind pose (in local space)
	bind_matrices_ls:      [..] JointMatrix;

	// A matrix describing the transformation from model space to joint space.
	// Useful for transforming vertices in model space to joint space.
	inverse_bind_matrices: [..] JointMatrix;

	// Base static buffers representing the skeleton on the GPU.
	buffers: SkelMeshBuffers;
}

// TODO: Maybe use SOA type?
JointTrack :: struct {
	keyframes_translation: [..] Vec3;
	keyframes_scale:       [..] Vec3;
	keyframes_rotation:    [..] Quat;
}

sample_track :: (animation: *JointTrack, key_a: u32, key_b: u32, a: f32) -> JointMatrix {
	joint: JointMatrix;

	if key_a != key_b {
		translation := lerp(animation.keyframes_translation[key_a], animation.keyframes_translation[key_b], a);
		scale := lerp(animation.keyframes_scale[key_a], animation.keyframes_scale[key_b], a);
		rotation := slerp(animation.keyframes_rotation[key_a], animation.keyframes_rotation[key_b], a);

		joint = make_translation_matrix4(translation)
			* make_scale_matrix4(scale)
			* rotation_matrix(Mat4x4, rotation);
	}

	return joint;
}

SkeletalAnimation :: struct {
	joint_animations: [..] JointTrack;
	fps:              f32;
	keyframe_count:   u32;
}

SkeletonAnimator :: struct {
	calc_joints:   [..] JointMatrix;
	skeleton:      *Skeleton;
	animation:     *SkeletalAnimation;
	rate:          f32;

	// Current state
	current_frame: f32;
}

init_skeleton_animator :: (animator: *SkeletonAnimator, skeleton: *Skeleton, animation: *SkeletalAnimation, rate: f32 = 1) {
	assert(skeleton != null);
	assert(animation != null);

	animator.skeleton = skeleton;
	animator.animation = animation;
	animator.rate = rate;

	array_resize(*animator.calc_joints, skeleton.joint_count);
}

sample_animation :: (animator: *SkeletonAnimator, time_s: f32) {
	assert(animator.animation.joint_animations.count == animator.skeleton.joint_count);

	// TODO: Better solution pls?
	sampled_joints: [256]JointMatrix;

	frame_idx := time_s * animator.rate * animator.animation.fps;
	frame_idx = fmod_cycling(frame_idx, xx animator.animation.keyframe_count);

	key_a := cast(u32, floor(frame_idx));
	key_b := key_a + 1;

	assert(key_a != key_b);

	key_a = key_a % animator.animation.keyframe_count;
	key_b = key_b % animator.animation.keyframe_count;

	animator.current_frame = frame_idx;

	a := frame_idx - cast(f32, key_a);

	// TODO: SIMD
	for * joint_anim, i: animator.animation.joint_animations {
		sampled_joints[i] = sample_track(joint_anim, key_a, key_b, a);
	}

	sampled_joints_view := array_view(sampled_joints, 0, animator.skeleton.joint_count - 1);
	calc_joint_matrices(animator.skeleton, sampled_joints_view, animator.calc_joints);
}

// Transforms a list of joints in local space to joint space. Usually for applying to vertices for skinning.
calc_joint_matrices :: (skeleton: *Skeleton, in_joints_ls: []JointMatrix, out_joints_js: []JointMatrix) {
	// Root joint is assumed to be at the origin in model space (since... it's the root)
	calc_joint_matrix(skeleton, in_joints_ls, cast(JointId, 0), Matrix4_Identity, out_joints_js);
}

// TODO: Make this more efficient, it's recursive.
calc_joint_matrix :: (
	skeleton:        *Skeleton,
	in_joints_ls:    [] JointMatrix,
	in_joint_id:     JointId,
	parent_joint_ms: JointMatrix,
	out_joints_js:   [] JointMatrix
) {
	joint_ls := in_joints_ls[in_joint_id];
	joint_ms := parent_joint_ms * joint_ls;

	inverse_bind_matrix := skeleton.inverse_bind_matrices[in_joint_id];

	out_joints_js[in_joint_id] = joint_ms * inverse_bind_matrix;

	for child_joint_id: skeleton.joint_tree[in_joint_id] {
		calc_joint_matrix(skeleton, in_joints_ls, child_joint_id, joint_ms, out_joints_js);
	}
}
