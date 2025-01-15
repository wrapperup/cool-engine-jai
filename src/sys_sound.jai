#import "miniaudio-jai";

SoundSystem :: struct {
	initialized:  bool;
	sound_engine: ma_engine;
}

init_sound_system :: () {
	config := ma_engine_config_init();
	result := ma_engine_init(*config, *game.sound_system.sound_engine);
	assert(result == .SUCCESS);

	ma_engine_listener_set_cone(*game.sound_system.sound_engine, 0, 40, 60, 10);
	
	game.sound_system.initialized = true;
}

play_sound :: (path: string) {
	assert(game.sound_system.initialized);

	ma_engine_play_sound(*game.sound_system.sound_engine, temp_c_string(path), null);
}

play_sound_3d :: (path: string, position: Vec3) {
	assert(game.sound_system.initialized);

	// @LEAK We should probably pool this.
	sound := New(ma_sound);
	ma_sound_init_from_file(*game.sound_system.sound_engine, temp_c_string(path), xx ma_sound_flags.DECODE, null, null, sound);
	ma_sound_set_position(sound, position.x, position.y, position.z);
	ma_sound_set_looping(sound, 1);
	ma_sound_start(sound);
}

set_listener_position :: (position: Vec3, forward: Vec3) {
	assert(game.sound_system.initialized);

	ma_engine_listener_set_position(*game.sound_system.sound_engine, 0, position.x, position.y, position.z);
	ma_engine_listener_set_direction(*game.sound_system.sound_engine, 0, forward.x, forward.y, forward.z);
}
