BINDLESS_SAMPLED_IMAGES :: 0;
BINDLESS_SAMPLERS       :: 1;
BINDLESS_STORAGE_IMAGES :: 2;

MAX_BINDLESS_IMAGES :: 100;
RESERVED_BINDLESS_IMAGES_COUNT :: 10;
MAX_BINDLESS_SAMPLERS :: 32;

Bindless_System :: struct {
    images:   [..] GPUImage;
    samplers: [..] VkSampler;

	descriptor_layout: VkDescriptorSetLayout;
	descriptor_set:    VkDescriptorSet;
}

init_bindless_system :: () {
    bindless_system := *r_ctx.bindless_system;

    bindless_system.descriptor_layout = create_descriptor_set_layout(
        .[
            .{binding = BINDLESS_SAMPLED_IMAGES, type = .SAMPLED_IMAGE, count = MAX_BINDLESS_IMAGES},
            .{binding = BINDLESS_SAMPLERS, type = .SAMPLER, count = MAX_BINDLESS_SAMPLERS},
            .{binding = BINDLESS_STORAGE_IMAGES, type = .STORAGE_IMAGE, count = MAX_BINDLESS_IMAGES},
        ],
        .UPDATE_AFTER_BIND_POOL_BIT,
        .VERTEX_BIT | .FRAGMENT_BIT | .COMPUTE_BIT,
    );
	defer_destroy(bindless_system.descriptor_layout);

	bindless_system.descriptor_set = allocate_descriptor_set(
		*r_ctx.global_descriptor_allocator,
		bindless_system.descriptor_layout,
	);
}

ImageId :: u32;
SamplerId :: u32;

get_identifier_name :: (name: Code) -> string {
    #import "Compiler";

    node := compiler_get_nodes(name);
    if node.kind != .IDENT {
        compiler_report("Not an identifier.", make_location(node));
        return "";
    }

    ident := cast(*Code_Ident) node;
    return ident.name;
}

// Aliases for picking the slang version of the type.
add_image :: (image: GPUImage) -> ImageId {
    bindless_system := *r_ctx.bindless_system;
    image_id := cast(ImageId)bindless_system.images.count;

	array_add(*bindless_system.images, image);

    if (image.usage & .STORAGE_BIT) != 0 {
        write_descriptor_set(bindless_system.descriptor_set, .[
            .{
                binding = BINDLESS_STORAGE_IMAGES,
                type = .STORAGE_IMAGE,
                image_view = image.view,
                image_layout = .GENERAL,
                array_index = image_id,
            },
        ]);
    }

    if (image.usage & .SAMPLED_BIT) != 0 {
        write_descriptor_set(bindless_system.descriptor_set, .[
            .{
                binding = BINDLESS_SAMPLED_IMAGES,
                type = .SAMPLED_IMAGE,
                image_view = image.view,
                image_layout = .GENERAL,
                array_index = image_id,
            },
        ]);
    }

	return image_id;
}

// Writes a image to the bindless ID and updates the descriptor.
set_image :: (image: GPUImage, image_id: ImageId) -> bool {
	resized := false;

	bindless_system := *r_ctx.bindless_system;

	// Ensure our image id can fit
	if bindless_system.bindless_images.count <= image_id.index {
		array_resize(*bindless_system.bindless_images, image_id.index + 1);
		resized = true;
	}

	bindless_system.bindless_images[image_id.index] = image;

	write_descriptor_set(bindless_system.descriptor_set, .[
		.{
			binding = 0,
			type = .SAMPLED_IMAGE,
			image_view = image.view,
			image_layout = .READ_ONLY_OPTIMAL,
			array_index = xx image_id,
		},
	]);

	return resized;
}

add_sampler :: (sampler: VkSampler) -> SamplerId {
    bindless_system := *r_ctx.bindless_system;

    sampler_id := cast(SamplerId)bindless_system.samplers.count;
    array_add(*bindless_system.samplers, sampler);

	write_descriptor_set(bindless_system.descriptor_set, .[
        .{binding = BINDLESS_SAMPLERS, type = .SAMPLER, sampler = sampler, array_index = sampler_id} 
    ]);

    return sampler_id;
}
