package main

import k2 "../../SDKs/karl2d"
import "core:fmt"
import "core:math/linalg"

Game_State :: struct {
	player_pos: k2.Vec2,
}

ROWS :: 9
COLUMNS :: 17
TILE_WIDTH :: 54
TILE_HEIGHT :: 54
OFFSET_X :: 10
OFFSET_Y :: 10
MOVE_SPEED :: 180.0

tilemap: [ROWS][COLUMNS]u32 = {
	{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
	{1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1},
	{1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1},
	{0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0},
	{1, 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1},
	{1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1},
}

game_state: Game_State
fps_smoothed: f32 = 60

main :: proc() {
	k2.init(
		940,
		540,
		"Odinmade Hero K2D",
		options = {window_mode = .Windowed, anti_alias = true, disable_auto_scale_hint = true},
	)

	game_state = {
		player_pos = {OFFSET_X + TILE_WIDTH * 4, OFFSET_Y + TILE_HEIGHT * 3},
	}

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

		game_state.player_pos += velocity * MOVE_SPEED * delta_time

		k2.clear(k2.BLACK)

		for row in 0 ..< ROWS {
			for col in 0 ..< COLUMNS {
				tile := tilemap[row][col]

				color: k2.Color
				switch tile {
				case 0:
					color = k2.GRAY
				case 1:
					color = k2.WHITE
				}

				position := k2.Vec2{f32(col * TILE_WIDTH), f32(row * TILE_HEIGHT)}
				tile_rect := k2.Rect {
					OFFSET_X + position.x,
					OFFSET_Y + position.y,
					TILE_WIDTH,
					TILE_HEIGHT,
				}

				k2.draw_rect(tile_rect, color)
			}
		}

		PLAYER_WIDTH :: TILE_WIDTH * 0.75
		player_rect: k2.Rect = {
			game_state.player_pos.x,
			game_state.player_pos.y,
			PLAYER_WIDTH,
			TILE_HEIGHT,
		}

		k2.draw_rect(player_rect, k2.GREEN)

		k2.draw_text(fmt.tprintf("FPS: %.0f", fps_smoothed), {10, 10}, 24.0, k2.GREEN)
		k2.present()
	}

	k2.shutdown()
}
