// We copy the DLL because using it directly would lock it, which would prevent
// the compiler from writing to it.
copy_dll :: (to: string) -> bool {
	ok := copy_file("build/debug/game.dll", to, silent = true);

	if !ok {
		// Logs get spammy.
		// log_error("Failed to copy game.dll to %", to);
		return false;
	}

	return true;
}

Game_API :: struct {
	lib:               *void;
	modification_time: Apollo_Time;
	api_version:       int;

	init:           (**Deletion_Queue);
	update:         () -> bool;
	shutdown:       ();
	memory:         () -> *void;
	hotreloaded:    (mem: *void);
	pre_hotreload:  ();
}

load_game_api :: (api_version: int) -> Game_API, bool {
	mod_time, _, mod_time_ok := file_modtime_and_size("build/debug/game.dll");
	if !mod_time_ok {
		log_error("Failed getting last write time of game.dll");
		return .{}, false;
	}

	game_dll_name := tprint("build/debug/game_%.dll", api_version);
	ok := copy_dll(game_dll_name);
	if !ok then return .{}, false;

	api: Game_API;
	api.api_version = api_version;
	api.modification_time = mod_time;

	api.lib = load(game_dll_name);

	api.init = symbol_address(api.lib, "game_init");
	api.update = symbol_address(api.lib, "game_update");
	api.shutdown = symbol_address(api.lib, "game_shutdown");
	api.memory = symbol_address(api.lib, "game_memory");
	api.hotreloaded = symbol_address(api.lib, "game_hotreloaded");
	api.pre_hotreload = symbol_address(api.lib, "game_pre_hotreload");

	return api, true;
}

unload_game_api :: (api: *Game_API) {
	if api.lib != null {
		if !unload(api.lib) {
			log_error("Failed unloading lib");
		}
	}

	if !file_delete(tprint("build/debug/game_%.dll", api.api_version)) {
		log_error("Failed to remove game_%.dll copy", api.api_version);
	}
}

main_logger :: (message: string, data: *void, info: Log_Info)
{
	#if RELEASE then return;
	if info.common_flags == .VERBOSE_ONLY && context.log_level != .VERBOSE then return;
	if info.common_flags == .VERY_VERBOSE_ONLY && context.log_level != .VERY_VERBOSE then return;

	color := Console_Color.WHITE;
	if info.common_flags == .ERROR then color = .RED;
	if info.common_flags == .WARNING then color = .YELLOW;

	to_standard_error := (info.common_flags & .ERROR) != 0;
	
	if message[message.count-1] != #char "\n" {
		with_console_color(color, write_strings(message, "\n", to_standard_error = to_standard_error));
    } else {
		with_console_color(color, write_string(message, to_standard_error = to_standard_error));
    }

}


main :: () {
	context.logger = main_logger;

	game_api_version := 0;
	game_api, game_api_ok := load_game_api(game_api_version);

	if !game_api_ok {
		log_error("Failed to load Game API");
		return;
	}

	game_api_version += 1;
	game_api.init(*context.deletion_queue);

	old_game_apis: [..] Game_API;

	window_open := true;
	while window_open {
		window_open = game_api.update();
		game_dll_mod, _, game_dll_mod_ok := file_modtime_and_size("build/debug/game.dll");

		reload := game_dll_mod_ok && game_api.modification_time < game_dll_mod;

		if reload {
			new_game_api, new_game_api_ok := load_game_api(game_api_version);

			if new_game_api_ok {
				log("Succeeded!");
				game_api.pre_hotreload();

				array_add(*old_game_apis, game_api);
				game_memory := game_api.memory();

				game_api = new_game_api;
				game_api.hotreloaded(game_memory);

				game_api_version += 1;
			}
		}

		reset_temporary_storage();
	}

	reset_temporary_storage();
	game_api.shutdown();

	for * g: old_game_apis {
		unload_game_api(g);
	}

	array_free(old_game_apis);

	unload_game_api(*game_api);
}

load :: (path: string, verbose := false) -> *void {
    #if OS == .WINDOWS {
        #import "Basic";
        #import "Windows";
        #import "Windows_Utf8";

        ptr := LoadLibraryW(utf8_to_wide(path,, allocator = temp));
		assert(ptr != null, "Couldn't load library at path: %. Error: %.", path, GetLastError());

        return ptr;
    } else {
        #import "Basic";
        #import "POSIX";

        ptr := dlopen(to_c_string(path,, allocator = temp), RTLD_NOW);
		assert(ptr != null, "Couldn't load library at path: %. Error: %.", path, GetLastError());

        return ptr;
    }
}

unload :: (ptr: *void, verbose := false) -> bool {
    assert(ptr != null);

    #if OS == .WINDOWS {
        #import "Basic";
        #import "Windows";

        result := FreeLibrary(ptr);
        if result == 0 && verbose {
            log_error("Couldn't unload library.\n%.", GetLastError());
        }

        return cast(bool, result);
    } else {
        #import "Basic";
        #import "POSIX";

        result := dlclose(ptr);
        if result != 0 && verbose {
            log_error("Couldn't unload library.\n%.", to_string(dlerror()));
        }

        return result == 0;
    }
}

symbol_address :: (library: *void, symbol_name: string, verbose := false) -> *void {
    #if OS == .WINDOWS {
        #import "Basic";
        #import "Windows";

        ptr := GetProcAddress(library, to_c_string(symbol_name,, temp));

		assert(ptr != null, "Couldn't load library symbol: %.\n%.", symbol_name, GetLastError());

        return ptr;
    } else {
        #import "Basic";
        #import "POSIX";

		ptr := dlsym(library, to_c_string(symbol_name,, temp));
        if ptr == null && verbose {
            log_error("Couldn't load library symbol: get_memory.\n%.", to_string(dlerror()));
        }

		assert(ptr != null, "Couldn't load library symbol: %.\n%.", symbol_name, GetLastError());

        return ptr;
    }
}

#import "File";
#import "File_Utilities";
#import "Windows";

#load "../src/main.jai";
