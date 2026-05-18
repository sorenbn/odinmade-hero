package game

import k2 "../../SDKs/karl2d"
import "core:math/linalg"

Tilemap :: struct {
	chunk_dimension:     u32, // size of the chunk itself - 256
	chunk_count:         Vec2u, // amount of actual "tilemaps" / chunks
	tile_size_in_meters: f32,
	tile_size_per_pixel: i32, // real world unit
	meters_to_pixels:    f32,
	chunk_shift:         u32,
	chunk_mask:          u32,
	tile_chunks:         ^[dynamic]Tile_Chunk,
}

Tile_Chunk :: struct {
	tiles: []u32,
}

Tile_Chunk_Position :: struct {
	chunk_absolute_position: Vec2u, // the absolute chunk position
	chunk_relative_tile_pos: Vec2u, // relative tile position inside chunk
}

Tilemap_Position :: struct {
	// Packed tilepositions - low bits are for the tile index, and high bits are for the chunk
	tile_absolute_pos: Vec2u,
	// relative to bottom left corner of tile (in meters)
	tile_relative_pos: k2.Vec2,
}

get_chunk :: proc(tilemap: ^Tilemap, x, y: u32) -> (^Tile_Chunk, bool) {
	if x >= 0 && x < tilemap.chunk_count.x && y >= 0 && y < tilemap.chunk_count.y {
		index := index_2d_to_1d(x, y, tilemap.chunk_count.x)
		return &tilemap.tile_chunks[index], true
	}

	return nil, false
}

get_chunk_position :: proc(tilemap: ^Tilemap, absolute_tile_pos: [2]u32) -> Tile_Chunk_Position {
	result: Tile_Chunk_Position = {
		// shave off the first 8 bits, and only get read the remaining 24 bits
		chunk_absolute_position = {
			absolute_tile_pos.x >> tilemap.chunk_shift,
			absolute_tile_pos.y >> tilemap.chunk_shift,
		},
		// shave off the 24 bits thats storing the chunk pos, and only care about the remaining bits to tell local tile pos of the chunk
		chunk_relative_tile_pos = {
			absolute_tile_pos.x & tilemap.chunk_mask,
			absolute_tile_pos.y & tilemap.chunk_mask,
		},
	}

	return result
}

get_tile_value_from_chunk :: proc(tilemap: ^Tilemap, chunk: ^Tile_Chunk, x, y: u32) -> u32 {
	result: u32 = 0

	if chunk != nil {
		result = get_tile_value_unchecked(tilemap, chunk, x, y)
	}

	return result
}

get_tile_value_unchecked :: proc(tilemap: ^Tilemap, chunk: ^Tile_Chunk, x, y: u32) -> u32 {
	assert(chunk != nil)
	assert(x < tilemap.chunk_dimension)
	assert(y < tilemap.chunk_dimension)

	index := index_2d_to_1d(x, y, tilemap.chunk_dimension)
	return chunk.tiles[index]
}

is_position_empty :: proc(tilemap: ^Tilemap, position_data: Tilemap_Position) -> bool {
	tile_value: u32 = get_tile_value(tilemap, position_data.tile_absolute_pos)
	empty: bool = tile_value == 0

	return empty
}

get_tile_value :: proc(tilemap: ^Tilemap, absolute_tile_pos: [2]u32) -> u32 {
	tile_chunk_pos := get_chunk_position(tilemap, absolute_tile_pos)
	tile_chunk, ok := get_chunk(
		tilemap,
		tile_chunk_pos.chunk_absolute_position.x,
		tile_chunk_pos.chunk_absolute_position.y,
	)

	tile_value: u32 = get_tile_value_from_chunk(
		tilemap,
		tile_chunk,
		tile_chunk_pos.chunk_relative_tile_pos.x,
		tile_chunk_pos.chunk_relative_tile_pos.y,
	)

	return tile_value
}

calculate_position_data :: proc(
	tilemap: ^Tilemap,
	position_data: Tilemap_Position,
) -> Tilemap_Position {
	result: Tilemap_Position = position_data

	recalculate_coordinate(tilemap, &result.tile_absolute_pos.x, &result.tile_relative_pos.x)
	recalculate_coordinate(tilemap, &result.tile_absolute_pos.y, &result.tile_relative_pos.y)

	return result
}

recalculate_coordinate :: proc(tilemap: ^Tilemap, tile_pos: ^u32, position_in_tile: ^f32) {
	// figure out how much our position could be offset from the "base" tile that we stood on
	offset: int = int(linalg.round(position_in_tile^ / f32(tilemap.tile_size_in_meters)))

	// offset that tile position
	tile_pos^ += u32(offset)

	// recalculate the position inside the new tile, to make sure it still sits within the tile size boundary
	position_in_tile^ -= f32(offset) * f32(tilemap.tile_size_in_meters)

	assert(position_in_tile^ >= -0.5 * tilemap.tile_size_in_meters)
	assert(position_in_tile^ <= 0.5 * tilemap.tile_size_in_meters)
}

set_tile_value :: proc(
	arena: ^Memory_Arena,
	tilemap: ^Tilemap,
	absolute_tile_pos: [2]u32,
	value: u32,
) {
	chunk_pos := get_chunk_position(tilemap, absolute_tile_pos)
	chunk, ok := get_chunk(
		tilemap,
		chunk_pos.chunk_absolute_position.x,
		chunk_pos.chunk_absolute_position.y,
	)

	// todo: replace with "ok" return value
	assert(chunk != nil)

	set_tile_value_on_chunk(
		tilemap,
		chunk,
		chunk_pos.chunk_relative_tile_pos.x,
		chunk_pos.chunk_relative_tile_pos.y,
		value,
	)
}

set_tile_value_on_chunk :: proc(tilemap: ^Tilemap, chunk: ^Tile_Chunk, x, y: u32, value: u32) {
	if chunk != nil {
		set_tile_value_unchecked(tilemap, chunk, x, y, value)
	}
}

set_tile_value_unchecked :: proc(tilemap: ^Tilemap, chunk: ^Tile_Chunk, x, y: u32, value: u32) {
	assert(chunk != nil)
	assert(x < tilemap.chunk_dimension)
	assert(y < tilemap.chunk_dimension)

	index := index_2d_to_1d(x, y, tilemap.chunk_dimension)
	chunk.tiles[index] = value
}
