#import "Basic";
#import "Print_Color";
#load "../src/main.jai";

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

	game_init(*context.deletion_queue);

	window_open := true;
	while window_open {
		window_open = game_update();
		reset_temporary_storage();
	}

	reset_temporary_storage();
	game_shutdown();
}
