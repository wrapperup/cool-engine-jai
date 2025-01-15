// AssetType :: enum {
// 	Sound;
// 	Mesh;
// 	SkinnedMesh;
// }
//
// UUID :: int;
//
// Asset :: struct {
// 	id:          UUID;
// 	source_path: string;
// 	type:        AssetType;
// }
//
// AssetSystem :: struct {
// 	assets:      Table(UUID, Asset);
// }
//
// load_asset :: () {
// }
//
// get_asset :: (id: UUID) -> *Asset {
// 	return *game.asset_system.assets[id];
// }
