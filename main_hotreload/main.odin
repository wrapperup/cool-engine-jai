package main

import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:sys/windows"

import "vendor:glfw"

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

// We copy the DLL because using it directly would lock it, which would prevent
// the compiler from writing to it.
copy_dll :: proc(to: string) -> bool {
	err := os2.copy_file(to, "build/debug/game" + DLL_EXT)

	if err != nil {
		fmt.printfln("Failed to copy game" + DLL_EXT + " to {0}", to)
		fmt.println(err)
		return false
	}

	return true
}

GameAPI :: struct {
	lib:               dynlib.Library,
	init:              proc(window: glfw.WindowHandle),
	init_window:       proc() -> glfw.WindowHandle,
	update:            proc() -> bool,
	shutdown:          proc(),
	memory:            proc() -> rawptr,
	memory_size:       proc() -> int,
	hot_reloaded:      proc(mem: rawptr),
	modification_time: os.File_Time,
	api_version:       int,
}

load_game_api :: proc(api_version: int) -> (api: GameAPI, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name("build/debug/game" + DLL_EXT)
	if mod_time_error != os.ERROR_NONE {
		fmt.printfln("Failed getting last write time of game" + DLL_EXT + ", error code: {1}", mod_time_error)
		return
	}

	// NOTE: this needs to be a relative path for Linux to work.
	game_dll_name := fmt.tprintf("{0}build/debug/game_{1}" + DLL_EXT, "./" when ODIN_OS != .Windows else "", api_version)
	copy_dll(game_dll_name) or_return

	// This proc matches the names of the fields in GameAPI to symbols in the
	// game DLL. It actually looks for symbols starting with `game_`, which is
	// why the argument `"game_"` is there.
	_, ok = dynlib.initialize_symbols(&api, game_dll_name, "game_", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}

unload_game_api :: proc(api: ^GameAPI) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	if os.remove(fmt.tprintf("build/debug/game_{0}" + DLL_EXT, api.api_version)) != nil {
		fmt.printfln("Failed to remove game_{0}" + DLL_EXT + " copy", api.api_version)
	}
}

main :: proc() {
	when ODIN_OS == .Windows {
		// Use UTF-8 for console output (fixes emojis/unicode/utf-8 shenanigans)
		windows.SetConsoleOutputCP(.UTF8)
	}

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
			for entry in track.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
		err := false

		for _, value in a.allocation_map {
			fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return err
	}

	game_api_version := 0
	game_api, game_api_ok := load_game_api(game_api_version)

	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	game_api_version += 1
	window := game_api.init_window()
	game_api.init(window)

	old_game_apis := make([dynamic]GameAPI)

	window_open := true
	for window_open {
		window_open = game_api.update()
		game_dll_mod, game_dll_mod_err := os.last_write_time_by_name("build/debug/game" + DLL_EXT)

		reload := game_dll_mod_err == os.ERROR_NONE && game_api.modification_time != game_dll_mod

		if reload {
			new_game_api, new_game_api_ok := load_game_api(game_api_version)

			if new_game_api_ok {
				append(&old_game_apis, game_api)
				game_memory := game_api.memory()
				game_api = new_game_api
				game_api.hot_reloaded(game_memory)

				game_api_version += 1
			}
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	game_api.shutdown()

	for &g in old_game_apis {
		unload_game_api(&g)
	}

	delete(old_game_apis)

	unload_game_api(&game_api)
}

// Make game use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
