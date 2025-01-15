Action :: enum {
	Jump;
	Fire;
	AltFire;
	Sprint;
	ToggleNoclip;
	LockCamera;
	Fullscreen;
	ExitGame;
}

Axis :: enum {
	LookUp;
	LookRight;
	MoveForward;
	MoveRight;
	MoveUp;
}

InputSystem :: struct {
	initialized:  bool;
	actions:      [#run count_of(Action)]ActionState;
	axes:         [#run count_of(Axis)]AxisState; // Yes, I looked it up. Plural of axis is axes. Yargh!!!!
	mouse_locked: bool;
}

init_input_system :: (mouse_locked := false) {
	game.input_system.initialized = true;
	lock_mouse(mouse_locked);
}

lock_mouse :: (lock: bool) {
	assert(game.input_system.initialized);

	game.input_system.mouse_locked = lock;
	SDL_SetRelativeMouseMode(ifx lock then .SDL_TRUE else .SDL_FALSE);
}

toggle_lock_mouse :: () {
	assert(game.input_system.initialized);
	lock_mouse(!game.input_system.mouse_locked);
}

MAX_ACTION_STATE_KEYS :: 2;
MAX_ACTION_STATE_MOUSE :: 2;
MAX_ACTION_STATE_JOYSTICK :: 2;

ActionState :: struct {
	key_codes:         [MAX_ACTION_STATE_KEYS] SDL_Keycode;
	mouse_codes:       [MAX_ACTION_STATE_KEYS] u8;
	key_codes_count:   int;
	mouse_codes_count: int;
	previous_state:    bool;
	current_state:     bool;
}

add_action_key_mapping :: (action: Action, key_code: SDL_Keycode) {
	assert(game.input_system.initialized);

	action_state := *game.input_system.actions[action];

	action_state.key_codes[action_state.key_codes_count] = key_code;
	action_state.key_codes_count += 1;
}

add_action_mouse_mapping :: (action: Action, mouse_code: u8) {
	assert(game.input_system.initialized);

	action_state := *game.input_system.actions[action];

	action_state.mouse_codes[action_state.mouse_codes_count] = mouse_code;
	action_state.mouse_codes_count += 1;
}

// Returns true if the action is pressed, false if released.
// If you want to detect when an input is pressed and released in an immediate-mode style,
// use action_just_pressed and action_just_released.
action_is_pressed :: (action: Action) -> bool {
	assert(game.input_system.initialized);
	state := game.input_system.actions[action];
	return state.current_state;
}

// This is an immediate-mode style interface, this returns true if the
// action state from the previous frame doesn't match, and if the action is pressed.
action_just_pressed :: (action: Action) -> bool {
	assert(game.input_system.initialized);
	state := game.input_system.actions[action];

	return state.current_state && (state.current_state != state.previous_state);
}

// This is an immediate-mode style interface, this returns true if the
// action state from the previous frame doesn't match, and if the action is released.
action_just_released :: (action: Action) -> bool {
	assert(game.input_system.initialized);
	state := game.input_system.actions[action];

	return !state.current_state && (state.current_state != state.previous_state);
}


MAX_AXIS_STATE_KEYS :: 4;
MAX_AXIS_STATE_MOUSE :: 2;
MAX_AXIS_STATE_JOYSTICK :: 2;

AxisCodeValue :: struct {
	key_code: SDL_Keycode;
	scale:    f32;
}

AxisState :: struct {
	keys:         [MAX_ACTION_STATE_KEYS] AxisCodeValue;
	keys_count:   int;
	read_mouse_x: bool;
	mouse_x_scale: f32 = 1;
	read_mouse_y: bool;
	mouse_y_scale: f32 = 1;
	// TODO: Make this f64?
	value:        f32;
}

add_axis_key_mapping :: (axis: Axis, key_code: SDL_Keycode, scale: f32) {
	assert(game.input_system.initialized);
	code_value := AxisCodeValue.{
		key_code = key_code,
		scale    = scale,
	};

	axis_state := *game.input_system.axes[axis];
	axis_state.keys[axis_state.keys_count] = code_value;
	axis_state.keys_count += 1;
}

Mouse_Axis :: enum {
	Mouse_X;
	Mouse_Y;
}

add_axis_mouse_axis :: (axis: Axis, mouse: Mouse_Axis, scale: f32) {
	assert(game.input_system.initialized);

	if mouse == {
		case .Mouse_X;
			game.input_system.axes[axis].read_mouse_x = true;
			game.input_system.axes[axis].mouse_x_scale = scale;
		case .Mouse_Y;
			game.input_system.axes[axis].read_mouse_y = true;
			game.input_system.axes[axis].mouse_y_scale = scale;
	}
}

// TODO: Make these f64?
axis_get_value :: (axis: Axis) -> f32 {
	assert(game.input_system.initialized);
	
	return game.input_system.axes[axis].value;
}

axis_get_2d_normalized :: (axis_x: Axis, axis_y: Axis) -> Vec2 {
	assert(game.input_system.initialized);

	a := game.input_system.axes[axis_x].value;
	b := game.input_system.axes[axis_y].value;
	
	return normalize(Vec2.{a, b});
}

simulate_input :: (event: SDL_Event, mouse_x: s32, mouse_y: s32) {
	assert(game.input_system.initialized);

	if event.type == .SDL_KEYDOWN || event.type == .SDL_KEYUP {
		pressed := event.type == .SDL_KEYDOWN;
		key_code := event.key.keysym.sym;

		for * action_state: game.input_system.actions {
			for i: 0 .. action_state.key_codes_count - 1 {
				action_code := action_state.key_codes[i];
				if key_code == action_code {
					action_state.previous_state = action_state.current_state;
					action_state.current_state = pressed;
				}
			}
		}

		for * axis_state: game.input_system.axes {
			for i: 0 .. axis_state.keys_count - 1 {
				axis_key := axis_state.keys[i];
				if key_code == axis_key.key_code {
					if pressed {
						axis_state.value = axis_key.scale;
					} else {
						axis_state.value = 0.0;
					}
				}
			}
		}
	}
	
	if event.type == .SDL_MOUSEBUTTONDOWN || event.type == .SDL_MOUSEBUTTONUP {
		pressed := event.type == .SDL_MOUSEBUTTONDOWN;
		button := event.button.button;

		for * action_state: game.input_system.actions {
			for i: 0 .. action_state.mouse_codes_count - 1 {
				code := action_state.mouse_codes[i];
				if code == button {
					action_state.current_state = pressed;
					break;
				}
			}
		}
	}

	if event.type == .SDL_MOUSEMOTION {
		for * axis_state: game.input_system.axes {
			// Only read input if the mouse is locked, for reasons...
			if game.input_system.mouse_locked {
				if axis_state.read_mouse_x {
					axis_state.value = event.motion.xrel * axis_state.mouse_x_scale;
				}

				if axis_state.read_mouse_y {
					axis_state.value = event.motion.yrel * axis_state.mouse_y_scale;
				}
			}
		}
	}
}

clear_input_state :: () { 
	for * action_state: game.input_system.actions {
		action_state.previous_state = action_state.current_state;
	}
	for * axis_state: game.input_system.axes {
		// Only read input if the mouse is locked, for reasons...
		if axis_state.read_mouse_x || axis_state.read_mouse_y {
			axis_state.value = 0;
		}
	}
}
