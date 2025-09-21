// TODO: Factor out the shader from the renderer.
ShaderManager :: struct {
    graphics_shaders: [..] Shader(GraphicsPipeline);
    compute_shaders: [..] Shader(ComputePipeline);
}

add_graphics_shader :: (path: string, pipeline_create_callback: (VkShaderModule) -> GraphicsPipeline) -> *GraphicsPipeline {
	shader := init_shader(GraphicsPipeline, path, pipeline_create_callback);
    array_add(*game.render_state.shader_manager.graphics_shaders, shader);
    return shader.pipeline;
}

add_compute_shader :: (path: string, pipeline_create_callback: (VkShaderModule) -> ComputePipeline) -> *ComputePipeline {
	shader := init_shader(ComputePipeline, path, pipeline_create_callback);
	array_add(*game.render_state.shader_manager.compute_shaders, shader);
	return shader.pipeline;
}

remove_shader :: (pipeline: *GraphicsPipeline) {
    shaders := *game.render_state.shader_manager.graphics_shaders;

    index: int;
    for * (shaders.*) {
        if it.pipeline == pipeline {
            index = it_index;
            break;
        }
    }

    array_unordered_remove_by_index(shaders, index);
    return;
}

remove_shader :: (pipeline: *ComputePipeline) {
    shaders := *game.render_state.shader_manager.compute_shaders;

    index: int;
    for * (shaders.*) {
        if it.pipeline == pipeline {
            index = it_index;
            break;
        }
    }

    array_unordered_remove_by_index(shaders, index);
    return;
}

check_shader_hotreload :: () -> bool {
    graphics_shaders := game.render_state.shader_manager.graphics_shaders;
    compute_shaders := game.render_state.shader_manager.compute_shaders;

	needs_reload := false;
	// TODO: SPEED: Maybe iter this across frames?
	for * shader: graphics_shaders {
		if is_outdated(shader) {
			shader.needs_recompile = true;
			needs_reload = true;
		}
	}

	for * shader: compute_shaders {
		if is_outdated(shader) {
			shader.needs_recompile = true;
			needs_reload = true;
		}
	}

	return needs_reload;
}

hotreload_modified_shaders :: () -> bool {
    graphics_shaders := game.render_state.shader_manager.graphics_shaders;
    compute_shaders := game.render_state.shader_manager.compute_shaders;

	// TODO: SPEED: Maybe iter this across frames?
	for * shader: graphics_shaders {
		if shader.needs_recompile {
			ok := reload_shader_pipeline(shader, force = true);
			// defer_destroy(shader.pipeline); // Kinda leaky, but it's fine.
			shader.needs_recompile = false;
			bump_shader(shader);
			return ok;
		}
	}

	for * shader: compute_shaders {
		if shader.needs_recompile {
			ok := reload_shader_pipeline(shader, force = true);
			// defer_destroy(shader.pipeline); // Kinda leaky, but it's fine.
			shader.needs_recompile = false;
			bump_shader(shader);
			return ok;
		}
	}

	return false;
}


Shader :: struct($T: Type) {
	pipeline:                 *T;
	pipeline_create_callback: (VkShaderModule) -> T;

	file:            ShaderFile;
	extra_files:     [] ShaderFile;
	needs_recompile: bool;

}

ShaderFile :: struct {
	path: string;

	#if DEBUG {
		modtime: Apollo_Time;
		size: s64;
	}
}

get_shader_file :: (path: string) -> ShaderFile, bool {
	#if DEBUG {
		modtime, size, ok := file_modtime_and_size(path);
		if !ok then return .{}, false;

		shader_file := ShaderFile.{
			path = path,
			modtime = modtime,
			size = size,
		};

		return shader_file, true;
	} else {
		shader_file := ShaderFile.{
			path = path,
		};

		return shader_file, true;
	}
}

bump_shader_file :: (file: *ShaderFile) {
	#if DEBUG {
		modtime, size, ok := file_modtime_and_size(file.path);
		if !ok return;

		file.modtime = modtime;
		file.size = size;
	} else {
		// No-op in release.
	}
}

is_outdated :: (shader: Shader) -> bool {
	#if DEBUG {
		modtime, size, ok := file_modtime_and_size(shader.file.path);
		if !ok return false; // Can't really check if there's no file... play it safe.

		if shader.file.size != size || shader.file.modtime < modtime {
			return true;
		}

		for shader.extra_files {
			modtime, size, ok = file_modtime_and_size(it.path);
			if !ok continue;

			if it.size != size || it.modtime != modtime {
				return true;
			}
		}
	}

	return false;
}

bump_shader :: (shader: *Shader($T)) {
	bump_shader_file(*shader.file);

	for * shader.extra_files {
		bump_shader_file(it);
	}
}

init_shader :: ($T: Type, path: string, pipeline_create_callback: type_of(Shader(T).pipeline_create_callback)) -> Shader(T), bool {
	assert(file_exists(path), "File doesn't exist, cannot init shader.");

	shader_file := get_shader_file(path);
	extra_files := get_dependency_shader_files(shader_file);

	shader := Shader(T).{
		file                     = shader_file,
		extra_files              = extra_files,
		pipeline_create_callback = pipeline_create_callback,
	};

	ok := reload_shader_pipeline(*shader);

	return shader, ok;
}

defer_destroy :: (shader: Shader) {
	defer_destroy(shader.pipeline);
}

get_cached_shader_path :: (filepath: string) -> string {
	path := parse_path(filepath);
	base := path.words[path.words.count-1]; // Grab the filename from path.

	builder: String_Builder;
	print_to_builder(*builder, "shaders/.cache/%", base);

	return builder_to_string(*builder);
}

reload_shader_pipeline :: (shader: *Shader($T), force := false) -> bool {
	cached_path := get_cached_shader_path(shader.file.path);

	use_cached_spirv := false;

	if file_exists(cached_path) && is_outdated(shader) {
		use_cached_spirv = true;
	}

    use_cached_spirv = false;

	code: [] u8;

	if use_cached_spirv && !force {
		spirv_code_string, success := read_entire_file(cached_path);
		if !success then return false;

		code = cast([]u8, spirv_code_string);
	} else {
		ok: bool = ---;
		code, ok = compile_slang_to_spirv(shader);
		if !ok then return false;
	
		make_directory_if_it_does_not_exist("shaders/.cache", recursive = true);
		success := write_entire_file(cached_path, cast(string, code));
		if !success then log_error("Warning: Shader couldn't be cached: %", cached_path);
	}

	shader_module, ok := load_shader_module_from_bytes(code);
	assert(ok, "Failed to load shaders.");

    pipeline := cast(*T) alloc(size_of(T));
	pipeline.* = shader.pipeline_create_callback(shader_module);

	if pipeline.pipeline == null then return false;
	if pipeline.layout == null then return false;

    if shader.pipeline {
        free(shader.pipeline);
    }

	shader.pipeline = pipeline;

	destroy_shader_module(shader_module);

	return true;
}

slang_check :: inline (result: Slang.SlangResult, loc := #caller_location) {
	code := Slang.SLANG_GET_RESULT_CODE(result);
	facility := Slang.SLANG_GET_RESULT_FACILITY(result);
	assert(Slang.SLANG_SUCCEEDED(result), "Slang failed: %, Facility (%)", code, facility, loc = loc);
}

diagnostics_check :: inline (diagnostics: *Slang.IBlob, loc := #caller_location) {
	using Slang;

	if diagnostics != null {
		view: [] u8 = ---;
		view.data = ISlangBlob_getBufferPointer(diagnostics);
		view.count = xx ISlangBlob_getBufferSize(diagnostics);

		log_error("Diagnostics at %:\n%\n", cast(string, view), loc = loc);
	}
}

init_slang_session :: () -> *Slang.ISession {
	using Slang;

	target_options := CompilerOptionEntry.[
		.{name = .GLSLForceScalarLayout, value = .{kind = .Int, intValue0 = 1}},
	];

	target_desc := TargetDesc.{
		format                      = .SPIRV,
		flags                       = xx SLANG_TARGET_FLAG.GENERATE_SPIRV_DIRECTLY,
		profile                     = IGlobalSession_findProfile(game.render_state.global_session, "sm_6_0"),
		forceGLSLScalarBufferLayout = true,
		compilerOptionEntries       = target_options.data,
		compilerOptionEntryCount    = target_options.count,
	};

	session_options := CompilerOptionEntry.[
		.{name = .VulkanUseEntryPointName, value = .{kind = .Int, intValue0 = 1}},
		.{name = .GLSLForceScalarLayout, value = .{kind = .Int, intValue0 = 1}},
		.{name = .DisableWarning, value = .{kind = .String, stringValue0 = "39001"}},
	];

	session_desc := SessionDesc.{
		targets                  = *target_desc,
		targetCount              = 1,
		compilerOptionEntries    = session_options.data,
		compilerOptionEntryCount = session_options.count,
	};

	session: *ISession;
	slang_check(IGlobalSession_createSession(game.render_state.global_session, *session_desc, *session));

	return session;
}

safe_release :: (unknown: *Slang.ISlangUnknown) {
	if unknown != null {
		// log_error("We would free, but it's broken.");
		Slang.ISlangUnknown_release(unknown);
	}
}

get_dependency_shader_files :: (file: ShaderFile) -> [] ShaderFile {
	using Slang;

	session := init_slang_session();
	defer safe_release(session);

	diagnostics: *IBlob;
	module: *IModule = ISession_loadModule(session, temp_c_string(file.path), *diagnostics);
	diagnostics_check(diagnostics);
	assert(module != null);

	count := IModule_getDependencyFileCount(module);

	files := NewArray(count, ShaderFile);

	for i: 0 .. count - 1 {
		str := IModule_getDependencyFilePath(module, i);
		temp_str := to_string(str);

		files[i] = get_shader_file(copy_string(temp_str));
	}

	return files;
}

compile_slang_to_spirv :: (shader: *Shader) -> []u8, bool {
	using Slang;

	code, diagnostics: *IBlob;
	r: SlangResult;

	session := init_slang_session();
	defer safe_release(session);

	module: *IModule = ISession_loadModule(session, temp_c_string(shader.file.path), *diagnostics);
	diagnostics_check(diagnostics);
	if module == null {
		log_error("Shader", shader.file.path, "doesn't exist.");
		return .{}, false;
	}

	components: [..] *IComponentType;
	defer array_free(components);

	array_add(*components, module);

	linked_program: *IComponentType;
	r = ISession_createCompositeComponentType(session, components.data, components.count, *linked_program, *diagnostics);
	diagnostics_check(diagnostics);
	slang_check(r);

	target_code: *IBlob;
	r = IComponentType_getTargetCode(linked_program, 0, *target_code, *diagnostics);
	diagnostics_check(diagnostics);
	slang_check(r);

	code_size := ISlangBlob_getBufferSize(target_code);
	buffer_ptr := ISlangBlob_getBufferPointer(target_code);

	assert(code_size % 4 == 0);

	compiled_code := NewArray(xx code_size, u8, initialized = false);
	memcpy(compiled_code.data, buffer_ptr, xx code_size);


	return compiled_code, true;
}
