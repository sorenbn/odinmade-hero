package main

import k2 "../../SDKs/karl2d"
import "core:fmt"
import "core:math/linalg"
import "core:mem"

Vec2i :: [2]i32
Vec2u :: [2]u32

Game_State :: struct {
	player_pos: Position_Data,
}

World :: struct {
	chunk_dimension:     u32, // size of the chunk itself - 256
	chunk_count:         Vec2u, // amount of actual "tilemaps" / chunks
	tile_size_per_meter: f32,
	tile_size_per_pixel: i32, // real world unit
	meters_to_pixels:    f32,
	chunk_shift:         u32,
	chunk_mask:          u32,
	tile_chunks:         ^[]Tile_Chunk,
}

Tile_Chunk :: struct {
	tiles: []u32,
}

Position_Data :: struct {
	// Packed tilepositions - low bits are for the tile index, and high bits are for the chunk
	tile_absolute_pos: Vec2u,
	// relative to bottom left corner of tile (in meters)
	tile_relative_pos: k2.Vec2,
}

Tile_Chunk_Position :: struct {
	chunk_absolute_position: Vec2u, // the absolute chunk position
	chunk_relative_tile_pos: Vec2u, // relative position inside chunk
}

DEBUG :: true
MOVE_SPEED :: 6.0 // meters/s
CHUNK_DIMENSION :: 256
CHUNK_COUNT_X :: 17
CHUNK_COUNT_Y :: 9

game_state: Game_State
world: World
tile_chunks: []Tile_Chunk
fps_smoothed: f32 = 60

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	k2.init(
		940,
		540,
		"Odinmade K2D Hero",
		options = {window_mode = .Windowed, anti_alias = true, disable_auto_scale_hint = true},
	)

	tiles := make([]u32, CHUNK_DIMENSION * CHUNK_DIMENSION)
	for row, y in test_tiles {
		for column, x in row {
			index := index_2d_to_1d(u32(x), u32(y), u32(CHUNK_DIMENSION))
			tiles[index] = column
		}
	}

	tile_chunks = {Tile_Chunk{tiles = tiles}}

	world = {}
	world.chunk_dimension = CHUNK_DIMENSION
	world.chunk_count = {1, 1}
	world.tile_chunks = &tile_chunks
	world.tile_size_per_meter = 1.4
	world.tile_size_per_pixel = 50
	world.chunk_shift = 8 // 256 x 256 tile chunks
	world.chunk_mask = (1 << world.chunk_shift)
	world.chunk_mask = world.chunk_mask - 1
	world.meters_to_pixels = f32(world.tile_size_per_pixel) / f32(world.tile_size_per_meter)

	offset_x_in_pixels := f32(world.tile_size_per_pixel) * 0.5
	offset_y_in_pixels :=
		f32(u32(world.tile_size_per_pixel) * CHUNK_COUNT_Y) + f32(world.tile_size_per_pixel) * 0.5

	game_state = {
		player_pos = {tile_absolute_pos = {3, 3}, tile_relative_pos = {0.7, 0.5}},
	}

	player_height: f32 = 1.4
	player_width: f32 = player_height * 0.75

	for k2.update() {
		if k2.key_went_down(.Escape) do break

		// calculate fps
		delta_time := linalg.max(k2.get_frame_time(), 0.000001)
		fps := 1.0 / delta_time
		// keep 90% of the old fps value, and only add 10% of the new value, to have a smooth transition between fps values instead of rapid jumping.
		fps_smoothed = fps_smoothed * 0.9 + fps * 0.1

		input: k2.Vec2 = {}

		if k2.key_is_held(.W) {
			input.y += 1
		}

		if k2.key_is_held(.S) {
			input.y -= 1
		}

		if k2.key_is_held(.D) {
			input.x += 1
		}

		if k2.key_is_held(.A) {
			input.x -= 1
		}

		if linalg.length2(input) > 1 {
			input = linalg.normalize(input)
		}

		next_position := game_state.player_pos
		next_position.tile_relative_pos += input * MOVE_SPEED * delta_time
		next_position = calculate_position_data(&world, next_position)

		left := next_position
		left.tile_relative_pos.x -= player_width * 0.5
		left = calculate_position_data(&world, left)

		right := next_position
		right.tile_relative_pos.x += player_width * 0.5
		right = calculate_position_data(&world, right)

		if is_position_empty(&world, next_position) &&
		   is_position_empty(&world, left) &&
		   is_position_empty(&world, right) {
			game_state.player_pos = next_position
		}

		// DRAW
		k2.clear(k2.BLACK)

		center := k2.Vec2{f32(k2.get_screen_width() / 2.0), f32(k2.get_screen_height() / 2.0)}

		for y in -10 ..< 10 {
			for x in -20 ..< 20 {
				coordinate: [2]u32 = {
					u32(x) + game_state.player_pos.tile_absolute_pos.x,
					u32(y) + game_state.player_pos.tile_absolute_pos.y,
				}
				tile := get_tile_value(&world, coordinate)

				color: k2.Color
				switch tile {
				case 0:
					color = k2.GRAY
				case 1:
					color = k2.WHITE
				}

				position := k2.Vec2 {
					f32(x) * f32(world.tile_size_per_pixel),
					f32(y) * f32(world.tile_size_per_pixel),
				}

				// scrolling the world instead of the player rect
				scrolled_position := k2.Vec2 {
					center.x +
					position.x -
					world.meters_to_pixels * game_state.player_pos.tile_relative_pos.x,
					center.y -
					position.y +
					world.meters_to_pixels * game_state.player_pos.tile_relative_pos.y,
				}

				tile_rect := k2.Rect {
					scrolled_position.x,
					scrolled_position.y,
					f32(world.tile_size_per_pixel),
					f32(world.tile_size_per_pixel),
				}

				if DEBUG {
					if game_state.player_pos.tile_absolute_pos.x == coordinate.x &&
					   game_state.player_pos.tile_absolute_pos.y == coordinate.y {
						color = k2.color_alpha(k2.WHITE, 127)
					}
				}
				k2.draw_rect(tile_rect, color, origin = {0, f32(world.tile_size_per_pixel)})

				if DEBUG {
					// you cannot set origin from "draw_rect_outline" -> manually adjust it here
					tile_rect.y -= f32(world.tile_size_per_pixel)
					k2.draw_rect_outline(tile_rect, 2, k2.GREEN)
				}
			}
		}

		x_pos := center.x
		y_pos := center.y

		player_rect: k2.Rect = {
			x = x_pos,
			y = y_pos,
			w = player_width * world.meters_to_pixels,
			h = player_height * world.meters_to_pixels,
		}

		k2.draw_rect(
			player_rect,
			k2.YELLOW,
			origin = {player_rect.w / 2, f32(world.tile_size_per_pixel)},
		)

		if DEBUG {

			k2.draw_circle_outline({player_rect.x, player_rect.y}, 4.0, 2.0, k2.RED)
			k2.draw_circle_outline(
				{player_rect.x + player_width * world.meters_to_pixels * 0.5, player_rect.y},
				3.0,
				2.0,
				k2.BLUE,
			)
			k2.draw_circle_outline(
				{player_rect.x - player_width * world.meters_to_pixels * 0.5, player_rect.y},
				3.0,
				2.0,
				k2.BLUE,
			)

			k2.draw_text(fmt.tprintf("FPS: %.0f", fps_smoothed), {10, 10}, 24.0, k2.RED)

			chunk_pos := get_chunk_position(&world, game_state.player_pos.tile_absolute_pos)
			k2.draw_text(
				fmt.tprint("Absolute Tile: ", game_state.player_pos.tile_absolute_pos),
				{10, 40},
				24.0,
				k2.RED,
			)
			k2.draw_text(
				fmt.tprint("Chunk: ", chunk_pos.chunk_absolute_position),
				{10, 70},
				24.0,
				k2.RED,
			)
			k2.draw_text(
				fmt.tprint("Chunk Local Position: ", chunk_pos.chunk_relative_tile_pos),
				{10, 100},
				24.0,
				k2.RED,
			)
			k2.draw_text(
				fmt.tprint("Local Position: ", game_state.player_pos.tile_relative_pos),
				{10, 130},
				24.0,
				k2.RED,
			)
		}

		k2.present()
		free_all(context.temp_allocator)
	}

	delete(tiles)
	k2.shutdown()

	if len(track.allocation_map) > 0 {
		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		}
	}
	mem.tracking_allocator_destroy(&track)
}

is_position_empty :: proc(world: ^World, position_data: Position_Data) -> bool {
	tile_value: u32 = get_tile_value(world, position_data.tile_absolute_pos)
	empty: bool = tile_value == 0

	return empty
}

get_tile_value :: proc(world: ^World, absolute_tile_pos: [2]u32) -> u32 {
	tile_chunk_pos := get_chunk_position(world, absolute_tile_pos)
	tile_chunk, ok := get_chunk(
		world,
		tile_chunk_pos.chunk_absolute_position.x,
		tile_chunk_pos.chunk_absolute_position.y,
	)

	tile_value: u32 = get_tile_value_from_chunk(
		world,
		tile_chunk,
		tile_chunk_pos.chunk_relative_tile_pos.x,
		tile_chunk_pos.chunk_relative_tile_pos.y,
	)

	return tile_value
}

get_tile_value_from_chunk :: proc(world: ^World, chunk: ^Tile_Chunk, x, y: u32) -> u32 {
	result: u32 = 0

	if chunk != nil {
		result = get_tile_value_unchecked(world, chunk, x, y)
	}

	return result
}

get_tile_value_unchecked :: proc(world: ^World, chunk: ^Tile_Chunk, x, y: u32) -> u32 {
	assert(chunk != nil)
	assert(x < world.chunk_dimension)
	assert(y < world.chunk_dimension)

	index := index_2d_to_1d(x, y, world.chunk_dimension)
	return chunk.tiles[index]
}

calculate_position_data :: proc(world: ^World, position_data: Position_Data) -> Position_Data {
	result: Position_Data = position_data

	recalculate_coordinate(world, &result.tile_absolute_pos.x, &result.tile_relative_pos.x)
	recalculate_coordinate(world, &result.tile_absolute_pos.y, &result.tile_relative_pos.y)

	return result
}

recalculate_coordinate :: proc(world: ^World, tile_pos: ^u32, position_in_tile: ^f32) {
	// figure out how much our position could be offset from the "base" tile that we stood on
	offset: int = int(linalg.floor(position_in_tile^ / f32(world.tile_size_per_meter)))

	// offset that tile position
	tile_pos^ += u32(offset)

	// recalculate the position inside the new tile, to make sure it still sits within the tile size boundary
	position_in_tile^ -= f32(offset) * f32(world.tile_size_per_meter)

	assert(position_in_tile^ >= 0)
	assert(position_in_tile^ <= f32(world.tile_size_per_meter))
}

get_chunk :: proc(world: ^World, x, y: u32) -> (^Tile_Chunk, bool) {
	if x >= 0 && x < world.chunk_count.x && y >= 0 && y < world.chunk_count.y {
		index := index_2d_to_1d(x, y, world.chunk_count.x)
		return &world.tile_chunks[index], true
	}

	return nil, false
}

get_chunk_position :: proc(world: ^World, absolute_tile_pos: [2]u32) -> Tile_Chunk_Position {
	result: Tile_Chunk_Position = {
		// shave off the first 8 bits, and only get read the remaining 24 bits
		chunk_absolute_position = {
			absolute_tile_pos.x >> world.chunk_shift,
			absolute_tile_pos.y >> world.chunk_shift,
		},
		// shave off the 24 bits thats storing the chunk pos, and only care about the remaining bits to tell local tile pos of the chunk
		chunk_relative_tile_pos = {
			absolute_tile_pos.x & world.chunk_mask,
			absolute_tile_pos.y & world.chunk_mask,
		},
	}

	return result
}

index_2d_to_1d :: proc(x, y, dimension: u32) -> u32 {
	return y * dimension + x
}
