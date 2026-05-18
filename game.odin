package main

import k2 "../../SDKs/karl2d"
import "core:fmt"
import "core:math/linalg"
import "core:mem"

Vec2i :: [2]i32
Vec2u :: [2]u32

Game_State :: struct {
	player_tilemap_position: Tilemap_Position,
}

World :: struct {
	tilemap: ^Tilemap,
}

DEBUG :: true
MOVE_SPEED :: 6.0 // meters/s
CHUNK_DIMENSION :: 256
CHUNK_COUNT_X :: 17
CHUNK_COUNT_Y :: 9

game_state: Game_State
world: World
tilemap: Tilemap
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

	tilemap = {}
	tilemap.chunk_dimension = CHUNK_DIMENSION
	tilemap.chunk_count = {1, 1}
	tilemap.tile_chunks = &tile_chunks
	tilemap.tile_size_in_meters = 1.4
	tilemap.tile_size_per_pixel = 50
	tilemap.chunk_shift = 8 // 256 x 256 tile chunks
	tilemap.chunk_mask = (1 << tilemap.chunk_shift)
	tilemap.chunk_mask = tilemap.chunk_mask - 1
	tilemap.meters_to_pixels = f32(tilemap.tile_size_per_pixel) / f32(tilemap.tile_size_in_meters)

	world = {
		tilemap = &tilemap,
	}

	offset_x_in_pixels := f32(tilemap.tile_size_per_pixel) * 0.5
	offset_y_in_pixels :=
		f32(u32(tilemap.tile_size_per_pixel) * CHUNK_COUNT_Y) +
		f32(tilemap.tile_size_per_pixel) * 0.5

	game_state = {
		player_tilemap_position = {tile_absolute_pos = {3, 3}, tile_relative_pos = {0.0, 0.0}},
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

		next_position := game_state.player_tilemap_position
		next_position.tile_relative_pos += input * MOVE_SPEED * delta_time
		next_position = calculate_position_data(&tilemap, next_position)

		left := next_position
		left.tile_relative_pos.x -= player_width * 0.5
		left = calculate_position_data(&tilemap, left)

		right := next_position
		right.tile_relative_pos.x += player_width * 0.5
		right = calculate_position_data(&tilemap, right)

		if is_position_empty(&tilemap, next_position) &&
		   is_position_empty(&tilemap, left) &&
		   is_position_empty(&tilemap, right) {
			game_state.player_tilemap_position = next_position
		}

		// DRAW
		k2.clear(k2.BLACK)

		scree_center := k2.Vec2 {
			f32(k2.get_screen_width() / 2.0),
			f32(k2.get_screen_height() / 2.0),
		}

		for y in -10 ..< 10 {
			for x in -20 ..< 20 {
				coordinate: [2]u32 = {
					u32(x) + game_state.player_tilemap_position.tile_absolute_pos.x,
					u32(y) + game_state.player_tilemap_position.tile_absolute_pos.y,
				}
				tile := get_tile_value(&tilemap, coordinate)

				color: k2.Color
				switch tile {
				case 0:
					color = k2.GRAY
				case 1:
					color = k2.WHITE
				}

				position := k2.Vec2 {
					f32(x) * f32(tilemap.tile_size_per_pixel),
					f32(y) * f32(tilemap.tile_size_per_pixel),
				}

				// scrolling the world instead of the player rect
				scrolled_position := k2.Vec2 {
					scree_center.x +
					position.x -
					tilemap.meters_to_pixels *
						game_state.player_tilemap_position.tile_relative_pos.x,
					scree_center.y -
					position.y +
					tilemap.meters_to_pixels *
						game_state.player_tilemap_position.tile_relative_pos.y,
				}

				tile_rect := k2.Rect {
					scrolled_position.x,
					scrolled_position.y,
					f32(tilemap.tile_size_per_pixel),
					f32(tilemap.tile_size_per_pixel),
				}

				if DEBUG {
					if game_state.player_tilemap_position.tile_absolute_pos.x == coordinate.x &&
					   game_state.player_tilemap_position.tile_absolute_pos.y == coordinate.y {
						color = k2.color_alpha(k2.WHITE, 127)
					}
				}
				k2.draw_rect(tile_rect, color, origin = {tile_rect.w * 0.5, tile_rect.h * 0.5})

				if DEBUG {
					// you cannot set origin from "draw_rect_outline" -> manually adjust it here
					tile_rect.y -= f32(tilemap.tile_size_per_pixel) * 0.5
					tile_rect.x -= f32(tilemap.tile_size_per_pixel) * 0.5

					k2.draw_rect_outline(tile_rect, 2, k2.GREEN)
				}
			}
		}

		x_pos := scree_center.x
		y_pos := scree_center.y

		player_rect: k2.Rect = {
			x = x_pos,
			y = y_pos,
			w = player_width * tilemap.meters_to_pixels,
			h = player_height * tilemap.meters_to_pixels,
		}

		k2.draw_rect(
			player_rect,
			k2.YELLOW,
			origin = {player_rect.w / 2, f32(tilemap.tile_size_per_pixel)},
		)

		if DEBUG {
			k2.draw_circle_outline({player_rect.x, player_rect.y}, 4.0, 2.0, k2.RED)
			k2.draw_circle_outline(
				{player_rect.x + player_width * tilemap.meters_to_pixels * 0.5, player_rect.y},
				3.0,
				2.0,
				k2.BLUE,
			)
			k2.draw_circle_outline(
				{player_rect.x - player_width * tilemap.meters_to_pixels * 0.5, player_rect.y},
				3.0,
				2.0,
				k2.BLUE,
			)

			k2.draw_text(fmt.tprintf("FPS: %.0f", fps_smoothed), {10, 10}, 24.0, k2.RED)

			chunk_pos := get_chunk_position(
				&tilemap,
				game_state.player_tilemap_position.tile_absolute_pos,
			)
			k2.draw_text(
				fmt.tprint(
					"Absolute Tile: ",
					game_state.player_tilemap_position.tile_absolute_pos,
				),
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
				fmt.tprint(
					"Local Position: ",
					game_state.player_tilemap_position.tile_relative_pos,
				),
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

index_2d_to_1d :: proc(x, y, dimension: u32) -> u32 {
	return y * dimension + x
}
