#import "Hash_Table";
#import "File_Utilities";

// Entity System
// Works very similar to a ECS, except that "components" are just
// a subtype of an Entity. It's not as efficient as a normal ECS, but it's
// a lot faster than a classic OOP entity system.

// Querying subtypes is efficient, it works using an entity ID and a
// sparse set (like an ECS), and keeping subtype data dense for cache-locality.

// Entity Id is a u64 handle that contains
// the generation and index in entity array.
EntityId :: struct {
    generation: u32;
    index:      u32;
}

operator == :: (a: EntityId, b: EntityId) -> bool {
    return a.generation == b.generation && a.index == b.index;
}

entity_id_to_u64 :: (id: EntityId) -> u64 {
    return cast(*u64, *id).*;
}

entity_id_from_u64 :: (id: u64) -> EntityId {
    return cast(*EntityId, *id).*;
}

entity_id_to_ptr :: (id: EntityId) -> *void {
    return cast(**void, *id).*;
}

entity_id_from_ptr :: (ptr: *void) -> EntityId {
    return cast(*EntityId, *ptr).*;
}

// Strongly typed ID, brings some checks back to compile-time to ensure
// the entity you queried is the correct type.
TypedEntityId :: struct($T: Type) {
    using id: EntityId;
}


Sparse_Set :: struct($T: Type) {
	sparse: Table(u64, int); // id -> index in dense
	dense:  [..] T;
}

assign_at_sparse_set :: (set: *Sparse_Set($T), id: EntityId, data: T) -> *T {
    index := set.dense.count;
    array_add(*set.dense, data);

    table_set(*set.sparse, entity_id_to_u64(id), index);
    return *set.dense[index];
}

get_elem_sparse_set :: (set: *Sparse_Set($T), id: EntityId) -> *T, bool {
    index := table_find_pointer(*set.sparse, entity_id_to_u64(id));
    if index == null then return null, false;
    return *set.dense[index.*], true;
}

remove_elem_sparse_set :: (set: *Sparse_Set($T), id: EntityId) -> bool {
    assert(set.dense.count > 0);

    u64_id := entity_id_to_u64(id);
    deleted_index, found := table_find(*set.sparse, u64_id);
    if !found then return false;
    table_remove(*set.sparse, u64_id);

	// Swaps last with index
    array_unordered_remove_by_index(*set.dense, deleted_index);
    old_index := set.dense.count;

	// Fix affected mapping that was moved
	for v, k: set.sparse {
		if old_index == v {
            table_set(*set.sparse, k, deleted_index);
		}
	}

    return true;
}

// The entity struct contains very common components
// that every entity needs. The core struct is designed
// to be reasonably cache-friendly, so keep it small when
// possible.
Entity :: struct {
    id:          EntityId;
    translation: Vec3;
    velocity:    Vec3;
    rotation:    Quat;
}

MAX_ENTITY_STORAGE :: 16_777_216;

EntitySystem :: struct {
    num_entities:    u32;

	// Holds cache-friendly, common data across entities
    entities:        [MAX_ENTITY_STORAGE]Entity;

	// Maps Type of T to Sparse_Set(T). 
	//
	// Safety: NEVER use this raw, use `new_or_get_entity_subtype_system`
	// or `get_entity_subtype_system to get the correct typing.
    subtype_storage: Table(string, SubtypeStorage);
}

SubtypeStorage :: struct {
    ptr:       *void;
}

new_or_get_entity_subtype_system :: ($T: Type) -> *Sparse_Set(T) {
    info := cast(*Type_Info_Struct, T);
    assert(info.type == .STRUCT);

    name := info.name;

	if !table_contains(*game.entity_system.subtype_storage, name) {
        sparse_set := New(Sparse_Set(T));

		subtype_storage := SubtypeStorage.{
			ptr = cast(*void, sparse_set),
        };

        table_set(*game.entity_system.subtype_storage, name, subtype_storage);
	}

    return get_entity_subtype_system(T);
}

get_entity_subtype_system ::  ($T: Type) -> *Sparse_Set(T) {
    info := cast(*Type_Info_Struct) T;
    assert(info.type == .STRUCT);

    name := info.name;

    found, storage := table_find_new(*game.entity_system.subtype_storage, name);

    if !found then return null;

    return cast(*Sparse_Set(T), storage.ptr);
}

new_entity :: ($T: Type) -> *T, TypedEntityId(T) {
    subtype := new_entity_subtype(T);

    return subtype, TypedEntityId(T).{id = subtype.entity.id};
}

new_entity_subtype :: ($T: Type) -> *T {
    data := T.{};
    data.entity = new_entity_raw();

    storage := new_or_get_entity_subtype_system(T);

    return assign_at_sparse_set(storage, data.entity.id, data);
}

// Returns a pointer to a new entity. If the entity array was 
// extended, returns true, else if an entity was revived, false.
new_entity_raw :: () -> *Entity {
	created_entity := Entity.{
		id = .{generation = 0, index = game.entity_system.num_entities},
    };

    game.entity_system.entities[game.entity_system.num_entities] = created_entity;
    game.entity_system.num_entities += 1;

    return *game.entity_system.entities[game.entity_system.num_entities - 1];
}

// Get entity. Generational index ensures that the entity
// you get is a valid entity, don't persist the pointer. Can return null.
get_entity :: (id: EntityId) -> *Entity {
    entity := game.entity_system.entities[id.index];

	// Safety: Compare generation, this ensures that the entity we find isn't invalidated.
	if entity.id.generation != id.generation {
        return null;
	}

    return *game.entity_system.entities[id.index];
}

get_entity :: ($T: Type, id: EntityId) -> *T {
    storage := get_entity_subtype_system(T);
    if storage == null then return null;

    type_t, ok := get_elem_sparse_set(storage, id);
    if !ok then return null;

	if type_t.id.generation != id.generation {
        return null;
	}

    return type_t;
}

get_entity :: (id: TypedEntityId($T)) -> *T {
    return get_entity(T, id.id);
}

// Removes entity from the entities list, and invalidates all existing handles.
remove_entity :: (id: EntityId) -> bool {
    entity := *game.entity_system.entities[id.index];

	// Compare generation 
	if entity.id.generation != id.generation {
        return false;
	}

	// Invalidate all references to this entity.
    entity.id.generation += 1;

    return true;
}

remove_entity :: ($T: Type, id: EntityId) -> bool {
	// Remove the raw entity data.
	if !remove_entity_raw(id) {
        return false;
	}

    storage := get_entity_subtype_system(T);

    return remove_elem_sparse_set(storage, id);
}

remove_entity :: (id: TypedEntityId($T)) -> *T {
    return remove_entity_subtype(T, id.id);
}

entity_id_of :: (subtype_entity: *$T) -> TypedEntityId(T) {
    return TypedEntityId(T).{id = subtype_entity.entity.id};
}

get_entities :: ($T: Type) -> [] T {
    storage := get_entity_subtype_system(T);
	if storage != null {
        return storage.dense;
	} else {
        return .{};
	}
}

entities_count :: ($T: Type) -> int {
    storage := get_entity_subtype_system(T);
	if storage != null {
        return storage.dense.count;
	} else {
        return 0;
	}
}
