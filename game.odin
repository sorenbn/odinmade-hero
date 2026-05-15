package main

import k2 "../../SDKs/karl2d"
import "core:fmt"
import "core:math/linalg"

Vec2i :: [2]i32

Game_State :: struct {
	player_pos:         k2.Vec2, // the world position inside that tilemap
	player_tilemap_pos: Vec2i, // the current tilemap the player is inside
}

World :: struct {
	tilemap_dimension: Vec2i,
	tile_width:        f32,
	tile_height:       f32,
	offset_x:          f32,
	offset_y:          f32,
	tilemaps:          ^[WORLD_DIMENSION.x][WORLD_DIMENSION.y]Tilemap,
}

Tilemap :: struct {
	tiles: []i32,
}

Position_Data :: struct {
	tilemap_pos:          Vec2i, // tilemap grid position (which tilemap are we on)
	tile_pos:             Vec2i, // tile (cell) position
	position_inside_tile: k2.Vec2, // relative to upper left corner of tile in pixels
}

Raw_Position_Data :: struct {
	tilemap_pos:    Vec2i, // tilemap grid position (which tilemap are we on)
	world_position: k2.Vec2, // relative to upper left corner of tilemap in pixels
}

MOVE_SPEED :: 180.0
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
		tilemap_dimension = {17, 9},
		tile_width        = 54,
		tile_height       = 54,
		offset_x          = 10,
		offset_y          = 10,
		tilemaps          = &tilemaps,
	}

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
		player_pos         = {
			world.offset_x + world.tile_width * 4,
			world.offset_y + world.tile_height * 4,
		},
		player_tilemap_pos = {0, 0},
	}

	player_width := world.tile_width * 0.75
	player_height := world.tile_height

	for k2.update() {
		if k2.key_went_down(.Escape) do break

		// calculate fps
		delta_time := linalg.max(k2.get_frame_time(), 0.000001)
		fps := 1.0 / delta_time
		// keep 90% of the old fps value, and only add 10% of the new value, to have a smooth transition between fps values instead of rapid jumping.
		fps_smoothed = fps_smoothed * 0.9 + fps * 0.1

		velocity: k2.Vec2 = {}

		if k2.key_is_held(.W) {
			velocity.y -= 1
		}

		if k2.key_is_held(.S) {
			velocity.y += 1
		}

		if k2.key_is_held(.D) {
			velocity.x += 1
		}

		if k2.key_is_held(.A) {
			velocity.x -= 1
		}

		if linalg.length2(velocity) > 1 {
			velocity = linalg.normalize(velocity)
		}

		next_pos := game_state.player_pos + velocity * MOVE_SPEED * delta_time

		center_pos := Raw_Position_Data {
			world_position = next_pos,
			tilemap_pos    = game_state.player_tilemap_pos,
		}

		left := center_pos
		left.world_position.x -= player_width * 0.5
		right := center_pos
		right.world_position.x += player_width * 0.5

		if is_tilemap_world_position_empty(&world, center_pos) &&
		   is_tilemap_world_position_empty(&world, left) &&
		   is_tilemap_world_position_empty(&world, right) {

			new_pos_data := get_position_data(&world, center_pos)

			game_state.player_tilemap_pos = new_pos_data.tilemap_pos
			game_state.player_pos = {
				world.offset_x +
				world.tile_width * f32(new_pos_data.tile_pos.x) +
				new_pos_data.position_inside_tile.x,
				world.offset_y +
				world.tile_height * f32(new_pos_data.tile_pos.y) +
				new_pos_data.position_inside_tile.y,
			}
		}

		// DRAW
		k2.clear(k2.BLACK)

		for y in 0 ..< world.tilemap_dimension.y {
			for x in 0 ..< world.tilemap_dimension.x {
				tilemap, ok := get_tilemap(
					&world,
					game_state.player_tilemap_pos.x,
					game_state.player_tilemap_pos.y,
				)

				tile := get_tile_value_unchecked(&world, tilemap, x, y)

				color: k2.Color
				switch tile {
				case 0:
					color = k2.GRAY
				case 1:
					color = k2.WHITE
				}

				position := k2.Vec2{f32(x) * world.tile_width, f32(y) * world.tile_height}

				tile_rect := k2.Rect {
					world.offset_x + position.x,
					world.offset_y + position.y,
					world.tile_width,
					world.tile_height,
				}

				k2.draw_rect(tile_rect, color)
				// k2.draw_rect_outline(tile_rect, 2, color)
			}
		}

		player_rect: k2.Rect = {
			game_state.player_pos.x,
			game_state.player_pos.y,
			player_width,
			player_height,
		}

		k2.draw_rect(player_rect, k2.GREEN, {player_rect.w / 2, world.tile_height})

		k2.draw_text(fmt.tprintf("FPS: %.0f", fps_smoothed), {10, 10}, 24.0, k2.GREEN)
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

is_tilemap_world_position_empty :: proc(world: ^World, raw_position: Raw_Position_Data) -> bool {
	empty := false

	position_data := get_position_data(world, raw_position)
	tilemap, ok := get_tilemap(world, position_data.tilemap_pos.x, position_data.tilemap_pos.y)

	if !ok do return empty

	empty = is_tilemap_position_empty(world, tilemap, position_data.tile_pos)

	return empty
}

get_position_data :: proc(world: ^World, raw_position_data: Raw_Position_Data) -> Position_Data {

	position_data: Position_Data
	position_data.tilemap_pos = raw_position_data.tilemap_pos

	// world pos relative to the tilemap itself (upper left corner minus the offset)
	world_position_x := raw_position_data.world_position.x - world.offset_x
	world_position_y := raw_position_data.world_position.y - world.offset_y

	// tile (cell) position inside the tilemap
	position_data.tile_pos = [2]i32 {
		i32(linalg.floor(world_position_x / world.tile_width)),
		i32(linalg.floor(world_position_y / world.tile_height)),
	}

	// actual position offset from the top left corner of the tile (cell) itself
	position_data.position_inside_tile = {
		world_position_x - f32(position_data.tile_pos.x) * world.tile_width,
		world_position_y - f32(position_data.tile_pos.y) * world.tile_height,
	}

	if position_data.tile_pos.x < 0 {
		position_data.tile_pos.x = world.tilemap_dimension.x + position_data.tile_pos.x
		position_data.tilemap_pos.x -= 1
	}

	if position_data.tile_pos.y < 0 {
		position_data.tile_pos.y = world.tilemap_dimension.y + position_data.tile_pos.y
		position_data.tilemap_pos.y -= 1
	}

	if position_data.tile_pos.x >= world.tilemap_dimension.x {
		position_data.tile_pos.x = position_data.tile_pos.x - world.tilemap_dimension.x
		position_data.tilemap_pos.x += 1
	}

	if position_data.tile_pos.y >= world.tilemap_dimension.y {
		position_data.tile_pos.y = position_data.tile_pos.y - world.tilemap_dimension.y
		position_data.tilemap_pos.y += 1
	}

	return position_data
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
