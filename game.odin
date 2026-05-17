package main

import k2 "../../SDKs/karl2d"
import "core:fmt"
import "core:math/linalg"

Vec2i :: [2]i32
Vec2u :: [2]u32

Game_State :: struct {
	player_pos: Position_Data,
}

World :: struct {
	tilemap_dimension:   Vec2i,
	tile_size_per_meter: f32,
	tile_size_per_pixel: i32, // real world unit
	meters_to_pixels:    f32,
	offset_x_in_pixels:  f32, // todo: convert to vec2i
	offset_y_in_pixels:  f32, // todo: convert to vec2i
	tilemaps:            ^[WORLD_DIMENSION.x][WORLD_DIMENSION.y]Tilemap,
}

Tilemap :: struct {
	tiles: []i32,
}

Position_Data :: struct {
	tilemap_pos:          Vec2i, // tilemap grid position (which tilemap are we on)
	tile_pos:             Vec2i, // tile (cell) position
	position_inside_tile: k2.Vec2, // relative to bottom left corner of tile (in meters)

	// Packed tilepositions - low bits are for the tile index, and high bits are for the tile page/chunk
	_tile_pos:            Vec2u,
}

DEBUG :: true

MOVE_SPEED :: 6.0 // meters/s
WORLD_DIMENSION :: Vec2i{2, 2}

game_state: Game_State
fps_smoothed: f32 = 60

main :: proc() {
	k2.init(
		940,
		540,
		"Odinmade K2D Hero",
		options = {window_mode = .Windowed, anti_alias = true, disable_auto_scale_hint = true},
	)

	tilemaps: [WORLD_DIMENSION.x][WORLD_DIMENSION.y]Tilemap = {}

	world := World {
		tilemap_dimension   = {17, 9},
		tile_size_per_meter = 1.4,
		tile_size_per_pixel = 50,
		tilemaps            = &tilemaps,
	}

	world.offset_x_in_pixels = f32(world.tile_size_per_pixel) * 0.5
	world.offset_y_in_pixels =
		f32(world.tile_size_per_pixel * world.tilemap_dimension.y) +
		f32(world.tile_size_per_pixel) * 0.5
	world.meters_to_pixels = f32(world.tile_size_per_pixel) / f32(world.tile_size_per_meter)

	tilemaps[0][0].tiles = TILES_00
	tilemaps[0][1].tiles = TILES_01
	tilemaps[1][1].tiles = TILES_11
	tilemaps[1][0].tiles = TILES_10

	current_tilemap, ok := get_tilemap(&world, 0, 0)

	if !ok {
		fmt.println("Error, no tilemap was found.")
		return
	}

	game_state = {
		player_pos = {tilemap_pos = {0, 0}, tile_pos = {1, 1}, position_inside_tile = {1.0, 1.0}},
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
		next_position.position_inside_tile += input * MOVE_SPEED * delta_time
		next_position = calculate_position_data(&world, next_position)

		left := next_position
		left.position_inside_tile.x -= player_width * 0.5
		left = calculate_position_data(&world, left)

		right := next_position
		right.position_inside_tile.x += player_width * 0.5
		right = calculate_position_data(&world, right)

		if is_tilemap_world_position_empty(&world, next_position) &&
		   is_tilemap_world_position_empty(&world, left) &&
		   is_tilemap_world_position_empty(&world, right) {
			game_state.player_pos = next_position
		}

		// DRAW
		k2.clear(k2.BLACK)

		for y in 0 ..< world.tilemap_dimension.y {
			for x in 0 ..< world.tilemap_dimension.x {
				tilemap, ok := get_tilemap(
					&world,
					game_state.player_pos.tilemap_pos.x,
					game_state.player_pos.tilemap_pos.y,
				)

				tile := get_tile_value_unchecked(&world, tilemap, x, y)

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

				tile_rect := k2.Rect {
					world.offset_x_in_pixels + position.x,
					world.offset_y_in_pixels - position.y,
					f32(world.tile_size_per_pixel),
					f32(world.tile_size_per_pixel),
				}

				if DEBUG {
					if game_state.player_pos.tile_pos.x == x &&
					   game_state.player_pos.tile_pos.y == y {
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

		x_pos :=
			world.offset_x_in_pixels +
			f32(world.tile_size_per_pixel) * f32(game_state.player_pos.tile_pos.x) +
			game_state.player_pos.position_inside_tile.x * world.meters_to_pixels

		y_pos :=
			world.offset_y_in_pixels -
			f32(world.tile_size_per_pixel) * f32(game_state.player_pos.tile_pos.y) -
			game_state.player_pos.position_inside_tile.y * world.meters_to_pixels

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
			k2.draw_text(
				fmt.tprint("Tilemap: ", game_state.player_pos.tilemap_pos),
				{10, 40},
				24.0,
				k2.RED,
			)
			k2.draw_text(
				fmt.tprint("Tile: ", game_state.player_pos.tile_pos),
				{10, 70},
				24.0,
				k2.RED,
			)
			k2.draw_text(
				fmt.tprint("Local Position: ", game_state.player_pos.position_inside_tile),
				{10, 100},
				24.0,
				k2.RED,
			)
		}

		k2.present()
	}

	k2.shutdown()
}

is_tilemap_position_empty :: proc(world: ^World, tilemap: ^Tilemap, tile_pos: Vec2i) -> bool {
	is_valid_move := false

	if tile_pos.x >= 0 &&
	   tile_pos.x < world.tilemap_dimension.x &&
	   tile_pos.y >= 0 &&
	   tile_pos.y < world.tilemap_dimension.y {

		tile := get_tile_value_unchecked(world, tilemap, tile_pos.x, tile_pos.y)

		is_valid_move = tile == 0
	}

	return is_valid_move
}

is_tilemap_world_position_empty :: proc(world: ^World, position_data: Position_Data) -> bool {
	empty := false

	tilemap, ok := get_tilemap(world, position_data.tilemap_pos.x, position_data.tilemap_pos.y)
	if !ok do return empty

	empty = is_tilemap_position_empty(world, tilemap, position_data.tile_pos)

	return empty
}

calculate_position_data :: proc(world: ^World, position_data: Position_Data) -> Position_Data {
	result: Position_Data = position_data

	recalculate_coordinate(
		world,
		world.tilemap_dimension.x,
		&result.tilemap_pos.x,
		&result.tile_pos.x,
		&result.position_inside_tile.x,
	)

	recalculate_coordinate(
		world,
		world.tilemap_dimension.y,
		&result.tilemap_pos.y,
		&result.tile_pos.y,
		&result.position_inside_tile.y,
	)

	return result
}

recalculate_coordinate :: proc(
	world: ^World,
	tilemap_dimension: i32,
	tilemap_pos: ^i32,
	tile_pos: ^i32,
	position_in_tile: ^f32,
) {
	// figure out how much our position could be offset from the "base" tile that we stood on
	offset: i32 = i32(linalg.floor(position_in_tile^ / f32(world.tile_size_per_meter)))
	// offset that tile position
	tile_pos^ += offset
	// recalculate the position inside the new tile, to make sure it still sits within the tile size boundary
	position_in_tile^ -= f32(offset) * f32(world.tile_size_per_meter)

	assert(position_in_tile^ >= 0)
	assert(position_in_tile^ < f32(world.tile_size_per_meter))

	// offset the tilemap itself, if we step outside the lower boundaries of it
	if tile_pos^ < 0 {
		tile_pos^ = tilemap_dimension + tile_pos^
		tilemap_pos^ -= 1
	}

	// offset the tilemap itself, if we step outside the upper boundaries of it
	if tile_pos^ >= tilemap_dimension {
		tile_pos^ = tile_pos^ - tilemap_dimension
		tilemap_pos^ += 1
	}
}

get_tile_value_unchecked :: proc(world: ^World, tilemap: ^Tilemap, x, y: i32) -> i32 {
	index := index_2d_to_1d(x, y, world.tilemap_dimension.x)
	return tilemap.tiles[index]
}

get_tilemap :: proc(world: ^World, x, y: i32) -> (^Tilemap, bool) {
	if x >= 0 && x < WORLD_DIMENSION.x && y >= 0 && y < WORLD_DIMENSION.y {
		return &world.tilemaps[x][y], true
	}

	return nil, false
}

index_2d_to_1d :: proc(x, y, x_dimension: i32) -> i32 {
	return y * x_dimension + x
}
