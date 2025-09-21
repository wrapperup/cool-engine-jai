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

    if release {
        opts.backend = .LLVM;
        opts.output_path = "build/release";
        opts.emit_debug_info = .NONE;
        opts.enable_bytecode_inliner = true;
        Compiler.set_optimization(*opts, .VERY_OPTIMIZED);   
    } else {
        opts.backend = .X64;
        opts.output_path = "build/debug";
    }

    if dynamic {
        opts.output_executable_name = "game";
        opts.output_type            = .DYNAMIC_LIBRARY;
    } else {
        opts.output_executable_name = "main";
    }

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
        Compiler.add_build_string("HOT_RELOAD :: true;", w);
    } else {
        Compiler.add_build_string("HOT_RELOAD :: false;", w);
    }

    Compiler.add_build_file(tprint("%src/main.jai", #filepath), w);

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
        opts.output_path = "build/release";
        opts.emit_debug_info = .NONE;
        opts.enable_bytecode_inliner = true;
        Compiler.set_optimization(*opts, .VERY_OPTIMIZED);   
    } else {
        opts.backend = .X64;
        opts.output_path = "build/debug";
        Compiler.set_optimization(*opts, .DEBUG);   
    }

    opts.output_executable_name = "main_hotreload";

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

    Compiler.add_build_file(tprint("%entrypoints/debug.jai", #filepath), w);

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

            case .COMPLETE;
                break;
        }
    }

    Compiler.compiler_end_intercept(w);
}

#run build();

message_loop :: (unique_pdb := true) {
    slang_builder: String_Builder;
    append(*slang_builder, "import bindless;\n");
    append(*slang_builder, "import types;\n\n");

    while true {
        message := Compiler.compiler_wait_for_message();
        if message.kind == {
            case .TYPECHECKED;
                typechecked := cast(*Compiler.Message_Typechecked) message;
                for typechecked_struct: typechecked.structs {
                    struct_t := typechecked_struct.expression;
                    if has_note(struct_t.notes, "ShaderShared") {
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

            case .COMPLETE;
                // The compiler sends us this message when compilation is finished.
                complete := cast(*Compiler.Message_Complete) message;

                if complete.error_code == .NONE {
                    write_entire_file("./shaders/generated.slang", *slang_builder);
                }
                break;
        }
    }
}

has_note :: (notes: [] *Compiler.Code_Note, note: string) -> bool {
    for notes  if it.text == note  return true;
    return false;
}

Type_Mapping :: struct {
    from: string;
    to:   string;
}

BANNED_TYPES :: Type_Mapping.[
    .{ "ImageId", "Raw ImageId is not allowed, must be mapped with a note. Eg: @Image2D<f32>" },
    .{ "SamplerId", "Raw SamplerId is not allowed, it must be mapped with a note. Eg: @Sampler or @SamplerComparison" },
];

TYPE_MAPPING_TABLE :: Type_Mapping.[
    .{ "float",   "float" },
    .{ "float32", "float" },
    .{ "float64", "double" },
    .{ "Vector2", "Vec2" },
    .{ "Vector3", "Vec3" },
    .{ "Vector4", "Vec4" },
    .{ "Matrix4", "Mat4x4" },
    .{ "MaterialId", "u32" },
    .{ "GPUPtr", "Ptr" },
];

RENAMABLE_TYPES :: Type_Mapping.[
    .{ "ImageId",   "Image2D" },
    .{ "SamplerId", "Sampler" },
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

    if struct_t.modify_directives.count != 0 {
        Compiler.compiler_report("No modifiers allowed on this struct.", loc = Compiler.make_location(struct_t));
    }
    if struct_t.textual_flags != 0 {
        Compiler.compiler_report("No struct modifier directives allowed.", loc = Compiler.make_location(struct_t));
    }

    print_to_builder(builder, "struct % {\n", strip_gpu_name(info.(*Type_Info_Struct).name));
    for node: struct_t.block.statements {
        if node.kind != .DECLARATION {
            Compiler.compiler_report("No struct modifier directives allowed.", loc = Compiler.make_location(node));
        }

        decl := node.(*Compiler.Code_Declaration);

        slang_string := parse_into_slang_member(decl, 1);
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

recurse_type_instantiation_to_string :: (inst: *Compiler.Code_Type_Instantiation) -> type_name: string, array_str: string {
    using Compiler;

    name_builder: String_Builder;
    array_builder: String_Builder;

    // Handle array.
    if inst.array_element_type {
        if inst.array_dimension == null {
            Compiler.compiler_report("Only fixed-size arrays are allowed.", loc = Compiler.make_location(inst));
        }

        dimensions := inst.array_dimension.(*Code_Literal);

        good_array_value := 
            dimensions.value_type == .NUMBER && 
            !(dimensions.value_flags & .FLOAT) && 
            !(dimensions.value_flags & .MINUS_SIGN);

        if !good_array_value {
            Compiler.compiler_report("Only positive integers are allowed.", loc = Compiler.make_location(dimensions));
        }

        inner_type_name, inner_array_string := 
            recurse_type_instantiation_to_string(inst.array_element_type);

        print_to_builder(*array_builder, "%[%]",inner_array_string, dimensions.values._u64);

        return inner_type_name, builder_to_string(*array_builder);
    }

    if inst.must_implement != null {
        Compiler.compiler_report("Interfaces are not allowed.", Compiler.make_location(inst));
    }

    if inst.pointer_to != null {
        Compiler.compiler_report("Pointers are not allowed.", Compiler.make_location(inst));
    }

    expr := inst.type_valued_expression;

    if expr.kind == {
        case .IDENT;
            ident := expr.(*Code_Ident);

            return map_type_to_slang_mappings(ident.name), "";

        case .PROCEDURE_CALL; // Struct polymorph
            call := expr.(*Code_Procedure_Call);

            if call.procedure_expression.kind != .IDENT {
                Compiler.compiler_report("Member type must be an identifier.", Compiler.make_location(call.procedure_expression));
            }
            ident := call.procedure_expression.(*Code_Ident);

            print_to_builder(*name_builder, "%<", map_type_to_slang_mappings(ident.name));

            for * arg: call.arguments_unsorted {
                if arg.expression.kind != .IDENT {
                    Compiler.compiler_report(tprint("Polymorph member must be an ident. It was %", arg.expression.kind), Compiler.make_location(arg.expression));
                }

                if it_index != call.arguments_unsorted.count-1 {
                    print_to_builder(*name_builder, ",");
                }

                print_to_builder(*name_builder, map_type_to_slang_mappings(arg.expression.(*Code_Ident).name));
            }

            print_to_builder(*name_builder, ">");

            return builder_to_string(*name_builder), "";

        case;
            Compiler.compiler_report(tprint("Unsupported type expression on shader struct %", expr), Compiler.make_location(expr));
    } 

    return "", "";
}

check_banned_type :: (type_string: string, node: *Compiler.Code_Node) {
    for BANNED_TYPES {
        if it.from == type_string {
            Compiler.compiler_report(it.to, loc = Compiler.make_location(node));
        }
    }
}

parse_into_slang_member :: (decl: *Compiler.Code_Declaration, indent: s64) -> member_string: string {
    builder: String_Builder;

    for 0..indent-1 {
        print_to_builder(*builder, "    ");
    }

    if decl.type_inst == null {
        Compiler.compiler_report("There is no type instantiation. This shouldn't happen.", Compiler.make_location(decl));
    }

    type_string, array_string := recurse_type_instantiation_to_string(decl.type_inst);

    if decl.notes.count == 1 {
        type_string = decl.notes[0].text;
    }

    check_banned_type(type_string, decl);

    print_to_builder(*builder, "% ", type_string);
    print_to_builder(*builder, decl.name);
    print_to_builder(*builder, array_string);
    print_to_builder(*builder, ";\n");

    return builder_to_string(*builder);
}
