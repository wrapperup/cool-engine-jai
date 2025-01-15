SoundSource :: struct {
	using #as entity: *Entity;

	sound: ma_sound;
}

init :: (
	source: *SoundSource,
	file_path: string,
	loop := false,
	rolloff: f32 = 1,
	spatialization := true,
	volume: f32 = 1.0
) {
	extra_flags: ma_sound_flags = ifx spatialization then xx 0 else .NO_SPATIALIZATION;
	ma_sound_init_from_file(*game.sound_system.sound_engine, file_path.data, xx (.DECODE | extra_flags), null, null, *source.sound);
	ma_sound_set_looping(*source.sound, xx ifx loop then 1 else 0);
	ma_sound_set_rolloff(*source.sound, rolloff);
	ma_sound_set_volume(*source.sound, volume);
	ma_sound_start(*source.sound);
}

destroy_sound_source :: (source: *SoundSource) {
	ma_sound_uninit(*source.sound);
}
