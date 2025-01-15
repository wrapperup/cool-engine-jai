configure_im :: () {
	io := ImGui.GetIO();

	font_config := ImGui.ImFontConfig.{};

	font_config.FontDataOwnedByAtlas = true;
	font_config.OversampleH = 6;
	font_config.OversampleV = 6;
	font_config.GlyphMaxAdvanceX = FLOAT32_MAX;
	font_config.RasterizerMultiply = 1.4;
	font_config.RasterizerDensity = 1.0;
	font_config.EllipsisChar = cast(ImGui.ImWchar, U16_MAX);

	font_config.PixelSnapH = false;
	font_config.GlyphOffset = .{0.0, -1.0};

	io.Fonts.AddFontFromFileTTF(io.Fonts, "C:\\Windows\\Fonts\\segoeui.ttf", 18.0, *font_config);

	font_config.MergeMode = true;

	ICON_MIN_FA: u16 : 0xe005;
	ICON_MAX_FA: u16 : 0xf8ff;

	FA_RANGES :: u16.[ICON_MIN_FA, ICON_MAX_FA, 0];

	font_config.RasterizerMultiply = 1.0;
	font_config.GlyphOffset = .{0.0, -1.0};

	// io.Fonts.AddFontFromFileTTF(io.Fonts, "assets/fonts/fa-regular-400.ttf", 14.0, *font_config, FA_RANGES.data);

	font_config.MergeMode = false;

	style := ImGui.GetStyle();

	tone_text_1 := ImGui.ImVec4.{0.69, 0.69, 0.69, 1.0};
	tone_text_2 := ImGui.ImVec4.{0.69, 0.69, 0.69, 0.8};

	tone_1 := ImGui.ImVec4.{0.16, 0.16, 0.18, 1.0};
	tone_1_b := tone_1 * 1.2;
	tone_1_e := tone_1 * 1.2;
	tone_1_e_a := tone_1_e;
	tone_3 := ImGui.ImVec4.{0.11, 0.11, 0.12, 1.0};
	//tone_2 := ImGui.ImVec4.{0.12, 0.12, 0.13, 1.0};
	tone_2 := tone_3;
	tone_2_b := tone_2;

	style.Colors[ImGui.Col.Text] = tone_text_1;
	style.Colors[ImGui.Col.TextDisabled] = tone_text_2;
	style.Colors[ImGui.Col.WindowBg] = tone_1;
	style.Colors[ImGui.Col.ChildBg] = tone_2;
	style.Colors[ImGui.Col.PopupBg] = tone_2_b;
	style.Colors[ImGui.Col.Border] = tone_2;
	style.Colors[ImGui.Col.BorderShadow] = .{0.0, 0.0, 0.0, 0.0};
	style.Colors[ImGui.Col.FrameBg] = tone_3;
	style.Colors[ImGui.Col.FrameBgHovered] = tone_3;
	style.Colors[ImGui.Col.FrameBgActive] = tone_3;
	style.Colors[ImGui.Col.TitleBg] = tone_2;
	style.Colors[ImGui.Col.TitleBgActive] = tone_2;
	style.Colors[ImGui.Col.TitleBgCollapsed] = tone_2;
	style.Colors[ImGui.Col.MenuBarBg] = tone_2;
	style.Colors[ImGui.Col.ScrollbarBg] = tone_3;
	style.Colors[ImGui.Col.ScrollbarGrab] = tone_1_e;
	style.Colors[ImGui.Col.ScrollbarGrabHovered] = tone_1_e;
	style.Colors[ImGui.Col.ScrollbarGrabActive] = tone_1_e_a;
	style.Colors[ImGui.Col.CheckMark] = tone_1_e;
	style.Colors[ImGui.Col.SliderGrab] = tone_1_e;
	style.Colors[ImGui.Col.SliderGrabActive] = tone_1_e_a;
	style.Colors[ImGui.Col.Button] = tone_2;
	style.Colors[ImGui.Col.ButtonHovered] = tone_2;
	style.Colors[ImGui.Col.ButtonActive] = tone_3;
	style.Colors[ImGui.Col.Header] = tone_2;
	style.Colors[ImGui.Col.HeaderHovered] = tone_2;
	style.Colors[ImGui.Col.HeaderActive] = tone_2;
	style.Colors[ImGui.Col.Separator] = tone_2;
	style.Colors[ImGui.Col.SeparatorHovered] = tone_2;
	style.Colors[ImGui.Col.SeparatorActive] = tone_2;
	style.Colors[ImGui.Col.ResizeGrip] = .{0.0, 0.0, 0.0, 0.0};
	style.Colors[ImGui.Col.ResizeGripHovered] = .{0.0, 0.0, 0.0, 0.0};
	style.Colors[ImGui.Col.ResizeGripActive] = .{0.0, 0.0, 0.0, 0.0};
	style.Colors[ImGui.Col.Tab] = tone_2;
	style.Colors[ImGui.Col.TabHovered] = tone_1;
	style.Colors[ImGui.Col.TabActive] = tone_1;
	style.Colors[ImGui.Col.TabUnfocused] = tone_1;
	style.Colors[ImGui.Col.TabUnfocusedActive] = tone_1;
	style.Colors[ImGui.Col.PlotLines] = tone_1_e;
	style.Colors[ImGui.Col.PlotLinesHovered] = tone_2;
	style.Colors[ImGui.Col.PlotHistogram] = tone_1_e;
	style.Colors[ImGui.Col.PlotHistogramHovered] = tone_2;
	style.Colors[ImGui.Col.TableHeaderBg] = tone_2;
	style.Colors[ImGui.Col.TableBorderStrong] = tone_2;
	style.Colors[ImGui.Col.TableBorderLight] = tone_2;
	style.Colors[ImGui.Col.TableRowBg] = tone_2;
	style.Colors[ImGui.Col.TableRowBgAlt] = tone_1;
	style.Colors[ImGui.Col.TextSelectedBg] = tone_1_e;
	style.Colors[ImGui.Col.DragDropTarget] = tone_2;
	style.Colors[ImGui.Col.NavHighlight] = tone_2;
	style.Colors[ImGui.Col.NavWindowingHighlight] = tone_2;
	style.Colors[ImGui.Col.NavWindowingDimBg] = tone_2_b;
	style.Colors[ImGui.Col.ModalWindowDimBg] = tone_2_b * 0.5;

	style.Colors[ImGui.Col.DockingPreview] = .{1.0, 1.0, 1.0, 0.5};
	style.Colors[ImGui.Col.DockingEmptyBg] = .{0.0, 0.0, 0.0, 0.0};

	style.WindowPadding = .{10.00, 10.00};
	style.FramePadding = .{5.00, 5.00};
	style.CellPadding = .{2.50, 2.50};
	style.ItemSpacing = .{5.00, 5.00};
	style.ItemInnerSpacing = .{5.00, 5.00};
	style.TouchExtraPadding = .{5.00, 5.00};
	style.IndentSpacing = 10;
	style.ScrollbarSize = 15;
	style.GrabMinSize = 10;
	style.WindowBorderSize = 0;
	style.ChildBorderSize = 0;
	style.PopupBorderSize = 0;
	style.FrameBorderSize = 0;
	style.TabBorderSize = 0;
	style.WindowRounding = 10;
	style.ChildRounding = 5;
	style.FrameRounding = 5;
	style.PopupRounding = 5;
	style.GrabRounding = 5;
	style.ScrollbarRounding = 10;
	style.LogSliderDeadzone = 5;
	style.TabRounding = 5;
	style.DockingSeparatorSize = 5;
}

update_imgui :: () {
	scope_stat_time(.Imgui);

	view_projection := get_current_projection_view_matrix();

	bl := ImGui.GetBackgroundDrawList();

	// rb := PxScene_getRenderBuffer(game.phys.scene);
	// for i: 0 .. PxRenderBuffer_getNbLines(rb)-1 {
	// 	line := PxRenderBuffer_getLines(rb)[i];
	//
	// 	line0, ok := world_space_to_clip_space(view_projection, line.pos0);
	// 	line1, ok2 := world_space_to_clip_space(view_projection, line.pos1);
	//
	// 	if !ok && !ok2 then continue;
	//
	// 	bl.AddLine(bl, line0, line1, line.color0, 1.0);
	// }

	if game.input_system.mouse_locked then return;

	editor_draw_imgui();

	dl := ImGui.GetForegroundDrawList();
	red := ImGui.GetColorU32(ImGui.ImVec4.{1.0, 0.0, 0.0, 1.0});
	green := ImGui.GetColorU32(ImGui.ImVec4.{0.0, 1.0, 0.0, 1.0});
	blue := ImGui.GetColorU32(ImGui.ImVec4.{0.0, 0.0, 1.0, 1.0});

	player := get_entity(game.state.player_id);
	{
		view_matrix := rotation_matrix(Mat4x4, ifx player != null then player.rotation else .{});

		projection_matrix := orthographic_projection_matrix(-1, 1, -1, 1, 0.1, 1, depth_range_01 = true);
		projection_matrix.coef[1][1] *= -1.0;

		view_projection_matrix := view_matrix * projection_matrix;

		origin_ws := Vec4.{0, 0, 0, 1};

		x_pos_ws := Vec4.{1, 0, 0, 1} * 20;
		y_pos_ws := Vec4.{0, 1, 0, 1} * 20;
		z_pos_ws := Vec4.{0, 0, 1, 1} * 20;

		offset_vs := Vec2.{xx (r_ctx.draw_extent.width - 30), xx (r_ctx.draw_extent.height - 30)};

		origin := (view_projection_matrix * origin_ws).xy + offset_vs;
		x_pos := (view_projection_matrix * x_pos_ws).xy + offset_vs;
		y_pos := (view_projection_matrix * y_pos_ws).xy + offset_vs;
		z_pos := (view_projection_matrix * z_pos_ws).xy + offset_vs;

		dl.AddLine(dl, origin, x_pos, red, 2);
		dl.AddLine(dl, origin, y_pos, green, 2);
		dl.AddLine(dl, origin, z_pos, blue, 2);
	}

	if ImGui.Begin("physics") {
		enabled := PxScene_getVisualizationParameter(game.phys.scene, .Scale) > 0.0;
		if ImGui.Checkbox("enable debug view", *enabled) {
			player := get_entity(game.state.player_id);
			range := Vec3.{50, 50, 50};
			min := player.translation - range;
			max := player.translation + range;
			PxScene_setVisualizationCullingBox(game.phys.scene, *PxBounds3_new(*min, *max));
			PxScene_setVisualizationParameter(game.phys.scene, .Scale, ifx enabled then 1.0 else 0.0);
			PxScene_setVisualizationParameter(game.phys.scene, .CollisionShapes, ifx enabled then 1.0 else 0.0);
			PxScene_setVisualizationParameter(game.phys.scene, .CollisionCompounds, ifx enabled then 1.0 else 0.0);
			PxScene_setVisualizationParameter(game.phys.scene, .SimulationMesh, ifx enabled then 1.0 else 0.0);
			PxScene_setVisualizationParameter(game.phys.scene, .WorldAxes, ifx enabled then 1.0 else 0.0);

		}
	}
	ImGui.End();

	if ImGui.Begin("Entities") {
		if ImGui.CollapsingHeader("Raw Entities") {
			clipper: ImGui.ListClipper;

			ImGui.ListClipper.Begin(*clipper, cast(s32, game.entity_system.num_entities));
			while ImGui.ListClipper.Step(*clipper) == true {
				for i: clipper.DisplayStart .. clipper.DisplayEnd-1 {
					entity := game.entity_system.entities[i];
					ImGui.Text("entity");
					ImGui.BulletText("id %", entity.id.index);
					ImGui.BulletText("gen %", entity.id.generation);
				}
			}
		}
	}
	ImGui.End();

	if player != null {
		if ImGui.Begin("Camera") {
			ImGui.InputFloat3("pos", *player.translation.component);
			ImGui.InputFloat3("vel", *player.velocity.component);
			ImGui.InputFloat3("pitch yaw", *player.camera_rot.component);
			ImGui.InputFloat("fov", *player.camera_fov_deg);
			// items := [#run count_of(ViewState)]cstring{"SceneColor", "SceneDepth", "ShadowDepth"};
			// ImGui.ComboChar("view", cast(^i32)(*game.view_state), raw_data(*items), len(items));
		}
		ImGui.End();
	}

	if ImGui.Begin("Environment") {
		ImGui.Checkbox("Draw skybox", *game.render_state.draw_skybox);
		dir_vec := game.state.environment.sun_direction;
		ImGui.InputFloat3("direction", *dir_vec.component);
		game.state.environment.sun_direction = dir_vec;
		ImGui.ColorEdit3("sun_color", *game.state.environment.sun_color.component);
		ImGui.ColorEdit3("sky_color", *game.state.environment.sky_color.component);

		for i: 0 .. NUM_CASCADES-1 {
			bias := *game.config.shadow_map_biases[i];
			slope_bias := *game.config.shadow_map_slope_biases[i];

			ImGui.InputFloat(tprint("bias %\0", i).data, bias, format = "%.5f");
			ImGui.InputFloat(tprint("slope_bias %\0", i).data, slope_bias, format = "%.5f");
		}

	}
	ImGui.End();

	if (ImGui.Begin("Stats")) {
		smooth_alpha: f32 = 0.995;

		if game.frame_times_smooth[0] == 0 {
			for i: 0..count_of(FrameTimeStats)-1 {
				game.frame_times_smooth[i] = game.frame_times[i];
			}
		} else {
			for i: 0..count_of(FrameTimeStats)-1 {
				game.frame_times_smooth[i] = lerp(game.frame_times[i], game.frame_times_smooth[i], smooth_alpha);
				// game.frame_times_smooth[i] *= smooth_alpha;
			}
		}

		names := type_info(FrameTimeStats).names;

		ImGui.Text("% FPS", formatFloat((1.0 / game.frame_times_smooth[0]) * 1000, trailing_width = 0, zero_removal = .NO));
		for ms, i: game.frame_times_smooth {
			text_proc := ifx i == 0 then ImGui.Text else ImGui.BulletText;
			text_proc("% %ms", names[i], formatFloat(ms, trailing_width = 3, zero_removal = .NO));
		}
	}
	ImGui.End();

	// if (ImGui.Begin("Skeletal Animation")) {
	// 	ImGui.SliderFloat("sample time", *game.skel_mesh_instance.sample_time, 0.0, 5.0)
	// 	ImGui.SliderFloat("sample rate", *game.skel_mesh_instance.skel_animator.rate, 0.1, 10.0)
	//
	// 	ImGui.Checkbox("Use game time", *game.skel_mesh_instance.use_game_time)
	// 	if game.skel_mesh_instance.use_game_time {
	// 		game.skel_mesh_instance.sample_time = f32(game.live_time)
	// 	}
	//
	// 	ImGui.Text("sample time %f s", game.skel_mesh_instance.sample_time)
	// 	for joint, i in game.skel_mesh_instance.skel_animator.calc_joints {
	// 		if ImGui.CollapsingHeader(fmt.ctprint("Joint", i)) {
	// 			ImGui.InputFloat4("", *[4]f32{joint[0, 0], joint[1, 0], joint[2, 0], joint[3, 0]})
	// 			ImGui.InputFloat4("", *[4]f32{joint[0, 1], joint[1, 1], joint[2, 1], joint[3, 1]})
	// 			ImGui.InputFloat4("", *[4]f32{joint[0, 2], joint[1, 2], joint[2, 2], joint[3, 2]})
	// 			ImGui.InputFloat4("", *[4]f32{joint[0, 3], joint[1, 3], joint[2, 3], joint[3, 3]})
	// 		}
	// 	}
	// }
	// ImGui.End()
}

debug_draw_line :: (
	pos0: Vec3,
	pos1: Vec3,
	thickness: f32 = 1.0,
	color := ImGui.ImVec4.{1.0, 0.0, 0.0, 1.0},
	dots := false
) {
	player := get_entity(game.state.player_id);

	// TODO: cache this
	view_projection := get_current_projection_view_matrix();

	line0, ok := world_space_to_clip_space(view_projection, pos0);
	line1, ok1 := world_space_to_clip_space(view_projection, pos1);

	bl := ImGui.GetBackgroundDrawList();
	col_u32 := ImGui.GetColorU32(color);

	if ok && ok1 {
		bl.AddLine(bl, line0, line1, col_u32);
	}

	if dots {
		pad: Vec2 = .{5, 5};

		if ok then  bl.AddRectFilled(bl, line0 - pad, line0 + pad, col_u32);
		if ok1 then bl.AddRectFilled(bl, line1 - pad, line1 + pad, col_u32);
	}
}

debug_draw_dot :: (pos: Vec3, half_size: f32 = 5.0, color := ImGui.ImVec4.{1.0, 0.0, 0.0, 1.0}) {
	player := get_entity(game.state.player_id);

	// TODO: cache this
	view_projection := get_current_projection_view_matrix();

	bl := ImGui.GetBackgroundDrawList();

	col_u32 := ImGui.GetColorU32(color);

	pos_cs, ok := world_space_to_clip_space(view_projection, pos);

	if ok {
		bl.AddRectFilled(
			bl, 
			pos_cs - Vec2.{half_size, half_size}, 
			pos_cs + Vec2.{half_size, half_size}, 
			col_u32
		);
	}
}
