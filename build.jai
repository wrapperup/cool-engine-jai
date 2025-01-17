#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "System";
#import "Process";
Compiler :: #import "Compiler";

#if OS == .WINDOWS {
    Windows_Resources :: #import "Windows_Resources";
    Ico_File :: #import "Ico_File";
}

Build_Mode :: enum {
    // Hotreloadable platform/dll
    Debug_Hot_Library;
    Debug_Hot_Platform;

    Debug;
    Release;
}

// Development_Mode :: enum {
//     None;
//     Development_With_Editor;
//     Development;
// }

copy_dlls :: (output_path: string) {
    copy_file("modules/SDL/windows/SDL2.dll", tprint("%/SDL2.dll", output_path));
    copy_file("modules/jai-imgui/windows/ImGui.dll", tprint("%/ImGui.dll", output_path));
    copy_file("modules/jai-libktx/windows/ktx.dll", tprint("%/ktx.dll", output_path));
    copy_file("modules/jai-vma/windows/VMA.dll", tprint("%/VMA.dll", output_path));
    copy_file("modules/jai-vulkan/win/vulkan-1.dll", tprint("%/vulkan-1.dll", output_path));
    copy_file("modules/miniaudio-jai/windows/miniaudio.dll", tprint("%/miniaudio.dll", output_path));
    copy_file("modules/slang-jai/lib/win/slang.dll", tprint("%/slang.dll", output_path));
    // copy_file("modules/slang-jai/lib/win/slang-glslang.dll", tprint("%/slang-glslang.dll", output_path));
}

build :: () {
    Compiler.set_build_options_dc(.{do_output=false});

    build_mode := Build_Mode.Debug;

    opts := Compiler.get_build_options();
    args := opts.compile_time_command_line;
    for arg: args {
    	if arg == {
            case "debug_hot_library";
                build_mode = .Debug_Hot_Library;
            case "debug_hot_platform";
                build_mode = .Debug_Hot_Platform;

    		case "debug"; // Redundant?
                build_mode = .Debug;
    		case "release";
                build_mode = .Release;

            case;
                log_error("Unsupported argument %", arg);
    	}
    }

    if build_mode == {
        case .Debug_Hot_Library;
            build_game(dynamic = true);

        case .Debug_Hot_Platform;
            build_game(dynamic = true);
            build_hotreloadable_platform();

        case .Debug;
            build_game(dynamic = false);

        case .Release;
            build_game(dynamic = false, release = true);
    }
}

build_game :: (dynamic: bool, release := false) {
    w := Compiler.compiler_create_workspace("Target Program");
    if !w {
        print("Workspace creation failed.\n");
        return;
    }

    opts := Compiler.get_build_options(w);

    import_path: [..] string;

    array_add(*import_path, .. opts.import_path);
    array_add(*import_path, "./my_modules");

    if release {
        opts.backend = .LLVM;
        opts.output_path = "build/release/";
        opts.emit_debug_info = .NONE;
        opts.enable_bytecode_inliner = true;
        Compiler.set_optimization(*opts, .VERY_OPTIMIZED);   
    } else {
        opts.backend = .X64;
        opts.output_path = "build/debug/";
        Compiler.set_optimization(*opts, .DEBUG);   
    }

    if dynamic {
        opts.output_executable_name = "game";
        opts.output_type            = .DYNAMIC_LIBRARY;
    } else {
        opts.output_executable_name = "main";
    }

    opts.use_custom_link_command = true;
    opts.import_path = import_path;

    Compiler.set_build_options(opts, w);

    make_directory_if_it_does_not_exist(opts.output_path, recursive = true);
    copy_dlls(opts.output_path);

    Compiler.compiler_begin_intercept(w);

    {
        build_string: string = ---;

        if release {
            build_string = #string END
                RELEASE     :: true;
                DEBUG       :: false;
                EDITOR      :: false;
                DEVELOPMENT :: false;
            END
        } else {
            build_string = #string END
                RELEASE     :: false;
                DEBUG       :: true;
                EDITOR      :: true;
                DEVELOPMENT :: true;
            END
        }

        Compiler.add_build_string(build_string, w);
    }

    if dynamic {
        Compiler.add_build_file(tprint("%/src/main.jai", #filepath), w);
    } else {
        Compiler.add_build_file(tprint("%/entrypoints/release.jai", #filepath), w);
    }

    message_loop(unique_pdb = dynamic);

    Compiler.compiler_end_intercept(w);
}

build_hotreloadable_platform :: (release := false) {
    w := Compiler.compiler_create_workspace("Hotreloadable Platform Program");
    if !w {
        print("Workspace creation failed.\n");
        return;
    }

    opts := Compiler.get_build_options(w);

    if release {
        opts.backend = .LLVM;
        opts.output_path = "build/release/";
        opts.emit_debug_info = .NONE;
        opts.enable_bytecode_inliner = true;
        Compiler.set_optimization(*opts, .VERY_OPTIMIZED);   
    } else {
        opts.backend = .X64;
        opts.output_path = "build/debug/";
        Compiler.set_optimization(*opts, .DEBUG);   
    }

    opts.output_executable_name = "main_hotreload";

    opts.use_custom_link_command = true;

    Compiler.set_build_options(opts, w);

    make_directory_if_it_does_not_exist(opts.output_path, recursive = true);
    copy_dlls(opts.output_path);

    Compiler.compiler_begin_intercept(w);

    {
        build_string: string = ---;

        if release {
            build_string = #string END
                RELEASE     :: true;
                DEBUG       :: false;
                EDITOR      :: false;
                DEVELOPMENT :: false;
            END
        } else {
            build_string = #string END
                RELEASE     :: false;
                DEBUG       :: true;
                EDITOR      :: true;
                DEVELOPMENT :: true;
            END
        }

        Compiler.add_build_string(build_string, w);
    }

    Compiler.add_build_file(tprint("%/entrypoints/debug.jai", #filepath), w);

    while true {
        message := Compiler.compiler_wait_for_message();
        if message.kind == {
            case .PHASE;
                phase := cast(*Compiler.Message_Phase) message;
                if phase.phase == .POST_WRITE_EXECUTABLE {
                    print("\n");
                    if phase.executable_write_failed {
                        print("FAILED writing '%'! Linker exit code was %.\n", phase.executable_name, phase.linker_exit_code);
                    } else {
                        print("Success writing '%'! Linker exit code was %.\n", phase.executable_name, phase.linker_exit_code);
                    }
                }

                if phase.phase == .READY_FOR_CUSTOM_LINK_COMMAND {
                    run_custom_link_command(message.workspace, phase);
                }

            case .COMPLETE;
                break;
        }
    }

    Compiler.compiler_end_intercept(w);
}

#run build();

message_loop :: (unique_pdb := true) {
    slang_builder: String_Builder;
    while true {
        message := Compiler.compiler_wait_for_message();
        if message.kind == {
            case .TYPECHECKED;
                typechecked := cast(*Compiler.Message_Typechecked) message;
                for typechecked_struct: typechecked.structs {
                    struct_t := typechecked_struct.expression;
                    if has_note(struct_t, "ShaderShared") {
                        struct_to_slang_struct(*slang_builder, struct_t);
                    }
                }

            case .PHASE;
                phase := cast(*Compiler.Message_Phase) message;
                if phase.phase == .POST_WRITE_EXECUTABLE {
                    print("\n");
                    if phase.executable_write_failed {
                        print("FAILED writing '%'! Linker exit code was %.\n", phase.executable_name, phase.linker_exit_code);
                    } else {
                        print("Success writing '%'! Linker exit code was %.\n", phase.executable_name, phase.linker_exit_code);
                    }
                }

                if phase.phase == .READY_FOR_CUSTOM_LINK_COMMAND {
                    run_custom_link_command(message.workspace, phase, unique_pdb = unique_pdb);
                }

            case .COMPLETE;
                // The compiler sends us this message when compilation is finished.
                complete := cast(*Compiler.Message_Complete) message;

                if complete.error_code == .NONE {
                    write_entire_file("./shaders/gen/structs.slang", *slang_builder);
                }
                break;
        }
    }
}

has_note :: (struct_t: *Compiler.Code_Struct, note: string) -> bool {
    for struct_t.notes  if it.text == note  return true;
    return false;
}

// is_shared_shader_type :: (info: *Type_Info) -> bool {
// }

Type_Mapping :: struct {
    from: string;
    to:   string;
}

BANNED_TYPES :: string.[
    "TextureId", // Raw Id is not allowed, must be assigned with the `@As(SlangType)` note.
];

TYPE_MAPPING_TABLE :: Type_Mapping.[
    .{ "float",   "float" },
    .{ "float32", "float" },
    .{ "float64", "double" },
    .{ "Vector2", "Vec2" },
    .{ "Vector3", "Vec3" },
    .{ "Vector4", "Vec4" },
    .{ "Matrix4", "Mat4x4" },
];

map_type_to_slang_mappings :: (type: string) -> string {
    for TYPE_MAPPING_TABLE {
        if type == it.from {
            return it.to;
        }
    }

    return strip_gpu_name(type);
}

struct_to_slang_struct :: (builder: *String_Builder, struct_t: *Compiler.Code_Struct) -> bool {
    info := struct_t.defined_type;

    print_to_builder(builder, "struct % {\n", strip_gpu_name(info.name));
    for member: info.members {
        slang_string := parse_into_slang_member(*member, 1);

        print_to_builder(builder, slang_string);
    }
    print_to_builder(builder, "}\n\n");

    return true;
}

strip_gpu_name :: (s: string) -> string {
    if starts_with(s, "GPU_") {
        stripped := s;
        stripped.data += 4;
        stripped.count -= 4;

        return stripped;
    } else if starts_with(s, "GPU") {
        stripped := s;
        stripped.data += 3;
        stripped.count -= 3;

        return stripped;
    } else {
        return s;
    }
}

unwrap_gpu_pointer :: (struct_info: *Type_Info_Struct) -> *Type_Info, bool {
    if struct_info.name != "GPU_Pointer"  return null, false; 

    if !struct_info.polymorph_source_struct  return null, false;
    if struct_info.specified_parameters.count != 1  return null, false;

    polymorph_member := struct_info.specified_parameters[0];
    assert(polymorph_member.type.type == .TYPE, "GPU_Pointer polymorph member must be Type.");

    offset := polymorph_member.offset_into_constant_storage;
    polymorph_type_info := cast(**Type_Info, *struct_info.constant_storage[offset]).*;

    return polymorph_type_info, true; 
}

recurse_type_string :: (in_info: *Type_Info, num_ptrs: *s64, array_sizes: *[..] s64) -> string {
    if in_info.type == {
        case .INTEGER;
            info := cast(*Type_Info_Integer, in_info);

            if info.signed {
                if info.runtime_size == {
                    case 1; return "s8";
                    case 2; return "s16";
                    case 4; return "s32";
                    case 8; return "s64";

                    case; assert(false, "Unsupported integer %.", info.type);
                }
            } else {
                if info.runtime_size == {
                    case 1; return "u8";
                    case 2; return "u16";
                    case 4; return "u32";
                    case 8; return "u64";

                    case; assert(false, "Unsupported integer %.", info.type);
                }
            }

        case .FLOAT;
            info := cast(*Type_Info_Float, in_info);

            if info.runtime_size == {
                case 4; return "float32";
                case 8; return "float64";

                case; assert(false, "Unsupported float %.", info.type);
            }

        case .VARIANT;
            info := cast(*Type_Info_Variant, in_info);
            return info.name;

        case .STRUCT;
            info := cast(*Type_Info_Struct, in_info);

            inner_type, gpu_ok := unwrap_gpu_pointer(info);
            if gpu_ok {
                num_ptrs.* += 1;
                return recurse_type_string(inner_type, num_ptrs, array_sizes);
            }

            return info.name;

        case .ARRAY;
            info := cast(*Type_Info_Array, in_info);
            assert(info.array_type == .FIXED, "Only fixed array types are allowed on shader structs %.", info.type);

            array_add(array_sizes, info.array_count);

            return recurse_type_string(info.element_type, num_ptrs, array_sizes);

        case;
            assert(false, "Unsupported type on shader struct %.", in_info.type);
    } 

    return "";
}

member_has_slang_as_note :: (member_info: *Type_Info_Struct_Member) -> string, bool {
    for member_info.notes {
        if starts_with(it, "As(") {
            stripped := it;
            stripped.count -= 4; // Trim off `)` end and `As(`
            stripped.data += 3;

            return stripped, true;
        }
    }

    return "", false;
}

is_banned_type :: (type_string: string) -> bool {
    for BANNED_TYPES {
        if it == type_string {
            return true;
        }
    }

    return false;
}

parse_into_slang_member :: (member_info: *Type_Info_Struct_Member, indent: s64) -> member_string: string {
    builder: String_Builder;

    for 0..indent-1 {
        print_to_builder(*builder, "    ");
    }

    type_note, has_type_note := member_has_slang_as_note(member_info);
    if has_type_note {
        print_to_builder(*builder, "% %;\n", type_note, member_info.name);
        return builder_to_string(*builder);
    }

    num_ptrs := 0;
    array_sizes: [..] s64;
    defer array_free(array_sizes);

    type_string := recurse_type_string(member_info.type, *num_ptrs, *array_sizes);
    type_string = map_type_to_slang_mappings(type_string);

    if is_banned_type(type_string) {
        assert(false, "Type is banned. If it's a texture type, use the `@As()` note to modify the type in the shader.");
    }

    print_to_builder(*builder, "% ", type_string);

    if num_ptrs > 0 && array_sizes.count > 0 {
        print_to_builder(*builder, "(");
    }

    for 0..num_ptrs-1 {
        print_to_builder(*builder, "*");
    }

    print_to_builder(*builder, "%", member_info.name);

    if num_ptrs > 0 && array_sizes.count > 0 {
        print_to_builder(*builder, ")");
    }

    for array_sizes {
        print_to_builder(*builder, "[%]", it);
    }

    print_to_builder(*builder, ";\n");

    return builder_to_string(*builder);
}




// @Cutnpaste from the sokoban implementation
// but generalized to support cross-compilation/linking
// when we support doing so!
run_custom_link_command :: (w: Workspace, m: *Compiler.Message_Phase, use_system_linker_if_able := false, unique_pdb := false) {
    options := Compiler.get_build_options(w);

    // Use the workspace's Os_Target since we want to support
    // cross-compilation at some point!
    target := options.os_target;
    target_windows := target == .WINDOWS;
    target_linux   := target == .LINUX;
    target_macosx  := target == .MACOS;

    use_lld := !((target == OS) && use_system_linker_if_able);

    #if OS == .WINDOWS {
        system_linker_exe_name := "link.exe";
    }

    #if OS == .LINUX || OS == .MACOS {
        system_linker_exe_name := "ld";
    }

    #if OS == .WINDOWS {
        if !use_lld && target_windows {
            // If we have opted to use the system linker and we're on Windows,
            // then attempt to find link.exe, otherwise fallback to LLD (or maybe error?)
            vc_path, linker_path := Windows_Resources.find_visual_studio_in_a_ridiculous_garbage_way();
            if linker_path {
                system_linker_exe_name = tprint("%\\%", linker_path, system_linker_exe_name);
            } else {
                Compiler.compiler_report("Could not find link.exe path, falling back to using LLD", mode=.WARNING);
                use_lld = true;
            }
        }
    }

    suffix := "";
    #if OS == .WINDOWS {
        if options.output_type == .EXECUTABLE {
            suffix = ".exe";
        } else if options.output_type == .DYNAMIC_LIBRARY {
            suffix = ".dll";
        } else {
            assert(false, "Unsupported output type.");
        }
    }

    target_filename := tprint("%1%2%3", options.output_path, options.output_executable_name, suffix);

    lld_exe_name: string;
    if use_lld {
        compiler_base_path := Compiler.compiler_get_base_path();

        #if OS == .WINDOWS  lld := "lld.exe";
        #if OS == .MACOS    lld := "lld-macosx";
        #if OS == .LINUX    lld := "lld-linux";

        lld_exe_name = tprint("%/bin/%", compiler_base_path, lld);
    }


    // Unfortunately, right now we are using CreateProcessW because that allows
    // one to be specific about security, etc (or if it isn't specific enough we can
    // change to CreateProcessExW). HOWEVER, it doesn't inherit the path so we need
    // to provide the path explicitly. That sucks. Maybe we have to change to system.
    // Or duplicate system's ability to use the path.

    arguments: [..] string;

    if use_lld {
        array_add(*arguments, lld_exe_name);
        array_add(*arguments, "-flavor");

        // choose the flavor based on the target OS.
        if      target_windows array_add(*arguments, "link");
        else if target_linux   array_add(*arguments, "Gnu");
        else if target_macosx  array_add(*arguments, "Darwin");
    } else {
        array_add(*arguments, system_linker_exe_name);
    }

    if target_windows array_add(*arguments, "/nologo");

    // Object files.
    for m.compiler_generated_object_files array_add(*arguments, it);
    for m.support_object_files array_add(*arguments, it);

    if target_windows {
        // Target filename.
        array_add(*arguments, tprint("/OUT:%", target_filename));

        array_add(*arguments, "/MACHINE:AMD64");
        array_add(*arguments, "/INCREMENTAL:NO");
        array_add(*arguments, "/DEBUG");
//        array_add(*arguments, "/OPT:REF");

        // If generating an executable, then create lib and exp file inside intermediate directory.
        if options.output_type == .EXECUTABLE {
            array_add(*arguments, tprint("/IMPLIB:%1%2.lib", options.intermediate_path, path_strip_extension(options.output_executable_name)));
        }
    } else if target_linux {
        array_add(*arguments, "--eh-frame-hdr");
        array_add(*arguments, "-export-dynamic");
        array_add(*arguments, tprint("-o%", target_filename));
        array_add(*arguments, "--dynamic-linker");
        array_add(*arguments, "/lib64/ld-linux-x86-64.so.2");
        array_add(*arguments, "-rpath=$ORIGIN");
    } else { // target_macosx
        array_add(*arguments, "-export_dynamic");
        array_add(*arguments, "-dynamic");
        array_add(*arguments, "-o");
        array_add(*arguments, target_filename);

        array_add(*arguments, "-macosx_version_min");
        array_add(*arguments, "10.13");

        array_add(*arguments, "-rpath");
        array_add(*arguments, "@loader_path"); // NOTE: on the command-line we have to single-quote this, here it must be unquoted!
    }

    // @TODO we probably need to do something similar using LLD on non-Windows hosts
    #if OS == .WINDOWS {
        if target_windows {
            vc_path := Windows_Resources.find_visual_studio_in_a_ridiculous_garbage_way();
            if vc_path {
                array_add(*arguments, tprint("/libpath:\"%\"", vc_path));
            } else {
                Compiler.compiler_report(#file, #line, 0, "Unable to find Visual Studio runtime library folder; can't compile.\n");
            }

            kit_root, windows_version := Windows_Resources.find_windows_kit_root();
            if kit_root {
                // I guess both Windows 8 and 10 use the same um / ucrt format.
                // kit_root does not have a slash at the end!! Sigh.
                array_add(*arguments, tprint("/libpath:\"%/um/x64\"", kit_root));
                array_add(*arguments, tprint("/libpath:\"%/ucrt/x64\"", kit_root));
            } else {
                // Report error.
                Compiler.compiler_report(#file, #line, 0, "Unable to find Windows Kit root; can't compile.\n");
            }


            if (options.output_type == .DYNAMIC_LIBRARY) {
                array_add(*arguments, "/DLL");
            }

            array_add(*arguments, "-nodefaultlib");
        }
    }

    // Write to a non-clashing PDB.
    if unique_pdb {
        target_pdb := tprint("%1%2", options.output_path, options.output_executable_name);

        version := 0;

        while file_exists(tprint("%1_%2.pdb", target_pdb, version)) {
            version += 1;
        }

        array_add(*arguments, tprint("/PDB:%_%.pdb", target_pdb, version));
    }

    for m.system_libraries    array_add(*arguments, it);
    for m.user_libraries      array_add(*arguments, it);


    print("Link line: %\n", get_quoted_command_string(arguments));
    process_result := run_command(..arguments);

    if process_result.exit_code != 0 {
        print("Error: Link step failed! (Exit code %).\n", process_result.exit_code);
    }

    // Report to the compiler that we have finished linking
    Compiler.compiler_custom_link_command_is_complete(w);
}
