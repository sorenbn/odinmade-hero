package game

import k2 "../../SDKs/karl2d"
import "core:fmt"
import "core:math/linalg"
import "core:mem"
import "core:mem/virtual"

Vec2i :: [2]i32
Vec2u :: [2]u32

kilobytes :: proc(value: $T) -> T {
	return value * 1024
}

megabytes :: proc(value: $T) -> T {
	return kilobytes(value) * 1024
}

gigabytes :: proc(value: $T) -> T {
	return megabytes(value) * 1024
}

terabytes :: proc(value: $T) -> T {
	return gigabytes(value) * 1024
}

Game_State :: struct {
	world_arena:             virtual.Arena,
	world:                   ^World,
	player_tilemap_position: Tilemap_Position,
}

World :: struct {
	tilemap: ^Tilemap,
}

Memory :: struct {
	total_size:             u64,
	permanent_storage_size: u64,
	transient_storage_size: u64,
	game_memory_block:      []byte,
	permanent_storage:      []byte,
	transient_storage:      []byte,
}

DEBUG :: true
MOVE_SPEED :: 6.0 // meters/s
TILES_COUNT_X :: 17
TILES_COUNT_Y :: 9

game_state: Game_State
fps_smoothed: f32 = 60

main :: proc() {
	k2.init(
		940,
		540,
		"Odinmade K2D Hero",
		options = {window_mode = .Windowed, anti_alias = true, disable_auto_scale_hint = true},
	)

	// move to game_state?
	player_height: f32 = 1.4
	player_width: f32 = player_height * 0.75

	memory := Memory{}
	memory.permanent_storage_size = megabytes(u64(64))
	memory.transient_storage_size = gigabytes(u64(1))
	memory.total_size = memory.permanent_storage_size + memory.transient_storage_size
	memory.game_memory_block = make([]byte, memory.total_size)
	// permanent storage takes up the initial chunk of all game memory
	memory.permanent_storage = memory.game_memory_block[:memory.permanent_storage_size]
	// transient storage then takes up the remaining storage of the game memory
	memory.transient_storage = memory.game_memory_block[memory.permanent_storage_size:]
	defer delete(memory.game_memory_block)

	game_state := (^Game_State)(raw_data(memory.permanent_storage))

	game_state.player_tilemap_position = {
		tile_absolute_pos = {2, 2},
		tile_relative_pos = {0.0, 0.0},
	}

	// initialize buffer, to the size of the rest of the storage, pass the initial Game_State memory
	if err := virtual.arena_init_buffer(
		&game_state.world_arena,
		memory.permanent_storage[size_of(Game_State):],
	); err != .None {
		panic("Failed to initialize world arena!")
	}

	// create the actual allocator based on the world_arena buffer
	allocator := virtual.arena_allocator(&game_state.world_arena)
	context.allocator = allocator

	// allocate world and tilemap in the arena
	game_state.world = new(World)
	world := game_state.world
	world.tilemap = new(Tilemap)

	tilemap := world.tilemap
	tilemap.chunk_count = {128, 128}
	tilemap.tile_size_in_meters = 1.4
	tilemap.tile_size_per_pixel = 50
	tilemap.chunk_shift = 4
	tilemap.chunk_mask = (1 << tilemap.chunk_shift)
	tilemap.chunk_mask = tilemap.chunk_mask - 1
	tilemap.chunk_dimension = (1 << tilemap.chunk_shift)
	tilemap.meters_to_pixels = f32(tilemap.tile_size_per_pixel) / f32(tilemap.tile_size_in_meters)
	tilemap.tile_chunks = make([]Tile_Chunk, u64(tilemap.chunk_count.x * tilemap.chunk_count.y))

	for y in 0 ..< tilemap.chunk_count.y {
		for x in 0 ..< tilemap.chunk_count.x {
			index := index_2d_to_1d(u32(x), u32(y), tilemap.chunk_count.x)
			tilemap.tile_chunks[index].tiles = make(
				[]u32,
				tilemap.chunk_dimension * tilemap.chunk_dimension,
			)
		}
	}

	for screen_y in 0 ..< 32 {
		for screen_x in 0 ..< 32 {
			screen_coordinate := Vec2u{u32(screen_x), u32(screen_y)}

			for tile_y in 0 ..< TILES_COUNT_Y {
				for tile_x in 0 ..< TILES_COUNT_X {
					tile_coordinate := Vec2u{u32(tile_x), u32(tile_y)}
					absolute_tile_pos := Vec2u {
						screen_coordinate.x * TILES_COUNT_X + tile_coordinate.x,
						screen_coordinate.y * TILES_COUNT_Y + tile_coordinate.y,
					}

					set_tile_value(
						world.tilemap,
						absolute_tile_pos,
						(tile_x == tile_y) && (tile_y % 2 > 0) ? 1 : 0,
					)
				}
			}
		}
	}

	offset_x_in_pixels := f32(tilemap.tile_size_per_pixel) * 0.5
	offset_y_in_pixels :=
		f32(u32(tilemap.tile_size_per_pixel) * TILES_COUNT_X) +
		f32(tilemap.tile_size_per_pixel) * 0.5

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
		next_position = calculate_position_data(world.tilemap, next_position)

		left := next_position
		left.tile_relative_pos.x -= player_width * 0.5
		left = calculate_position_data(world.tilemap, left)

		right := next_position
		right.tile_relative_pos.x += player_width * 0.5
		right = calculate_position_data(world.tilemap, right)

		if is_position_empty(world.tilemap, next_position) &&
		   is_position_empty(world.tilemap, left) &&
		   is_position_empty(world.tilemap, right) {
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
				tile := get_tile_value(world.tilemap, coordinate)

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
				world.tilemap,
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

	k2.shutdown()
}

index_2d_to_1d :: proc(x, y, dimension: u32) -> u32 {
	return y * dimension + x
}
