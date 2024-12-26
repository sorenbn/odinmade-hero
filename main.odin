package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:mem"
import "core:os"
import win32 "core:sys/windows"

application_running: bool
back_buffer: Win32_Offscreen_Buffer

Win32_Offscreen_Buffer :: struct {
	info:   win32.BITMAPINFO,
	memory: []u32,
	width:  i32,
	height: i32,
}

Win32_Window_Dimensions :: struct {
	width:  i32,
	height: i32,
}

main :: proc() {
	context.logger = log.create_console_logger()
	default_allocator := context.allocator
	tracking_allocator := mem.Tracking_Allocator{}
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
		err := false

		for _, value in a.allocation_map {
			fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return err
	}

	instance := cast(win32.HINSTANCE)win32.GetModuleHandleW(nil) // get instance to application process
	window_class: win32.WNDCLASSW = {
		style         = win32.CS_HREDRAW | win32.CS_VREDRAW, // repaint the whole window, if resize. 
		lpfnWndProc   = win32_window_callback, // procedure callback for windows events
		hInstance     = instance, // instance of the application
		lpszClassName = win32.utf8_to_wstring("OdinmadeHeroWindowClass"), // class name for window
	}

	win32_resize_device_independent_bitmap_section(&back_buffer, 1280, 720)

	// register our window to Windows (lol)
	win32.RegisterClassW(&window_class)

	window := win32.CreateWindowExW(
		0, // styles, none for now.
		window_class.lpszClassName, // class name for window
		win32.utf8_to_wstring("Odinmade Hero"), // actual window name
		win32.WS_OVERLAPPEDWINDOW | win32.WS_VISIBLE, // actual window visual style
		win32.CW_USEDEFAULT, // pos x, default
		win32.CW_USEDEFAULT, // pos y, default
		win32.CW_USEDEFAULT, // width, default
		win32.CW_USEDEFAULT, // height, default
		nil, // handle for parent window, irrelevant if no multi-window setup 
		nil, // child window, irrelevant if no multi-window setup  
		instance, // application instance
		nil, // custom data which can be used to pass to the window events in 'wnd_proc'
	)

	device_context := win32.GetDC(window)
	application_running = true
	xOffset: i32 = 0

	// We need to manually tell windows that we want to listen for events.
	for application_running {
		message: win32.MSG
		for win32.PeekMessageW(&message, nil, 0, 0, win32.PM_REMOVE) {
			if message.message == win32.WM_QUIT {
				application_running = false
			}

			// send those events back to Windows
			win32.TranslateMessage(&message)
			win32.DispatchMessageW(&message)
		}

		draw_gradient(&back_buffer, xOffset, 0)
		xOffset += 1

		dimensions := win32_get_window_dimensions(window)
		win32_display_buffer_to_window(
			device_context,
			&back_buffer,
			dimensions.width,
			dimensions.height,
		)
	}

	// technically not necessary, since windows will clean it up automatically.
	// but tracking allocator is complaining that we're leaking memory.
	if back_buffer.memory != nil do delete(back_buffer.memory)

	reset_tracking_allocator(&tracking_allocator)
	mem.tracking_allocator_destroy(&tracking_allocator)

	fmt.println("Odinmade Hero Exited.")
}

// The callback function Windows send its events to.
win32_window_callback :: proc "stdcall" (
	window_handle: win32.HWND,
	message: win32.UINT,
	w_param: win32.WPARAM,
	l_param: win32.LPARAM,
) -> win32.LRESULT {
	context = runtime.default_context()
	result: win32.LRESULT = 0

	switch message {
	case win32.WM_ACTIVATEAPP:
		break

	case win32.WM_SIZE:
		break

	case win32.WM_DESTROY:
		application_running = false
		break

	case win32.WM_CLOSE:
		application_running = false
		break

	// Invoked every time the window is set 'dirty', i.e. when resizing, min/maximize etc.
	case win32.WM_PAINT:
		paint: win32.PAINTSTRUCT
		device_context: win32.HDC = win32.BeginPaint(window_handle, &paint)
		x := paint.rcPaint.left
		y := paint.rcPaint.top
		width := paint.rcPaint.right - paint.rcPaint.left
		height := paint.rcPaint.bottom - paint.rcPaint.top
		client_rect: win32.RECT
		dimensions := win32_get_window_dimensions(window_handle)
		win32_display_buffer_to_window(
			device_context,
			&back_buffer,
			dimensions.width,
			dimensions.height,
		)
		win32.EndPaint(window_handle, &paint)
		break

	// Let Windows handle all other events as their 'default' behaviour
	case:
		result = win32.DefWindowProcW(window_handle, message, w_param, l_param)
		break
	}

	return result
}

win32_get_window_dimensions :: proc(window_handle: win32.HWND) -> Win32_Window_Dimensions {
	client_rect: win32.RECT
	win32.GetClientRect(window_handle, &client_rect)

	return {
		width = client_rect.right - client_rect.left,
		height = client_rect.bottom - client_rect.top,
	}
}

// Invoked every time window resizes.
win32_resize_device_independent_bitmap_section :: proc(
	buffer: ^Win32_Offscreen_Buffer,
	width, height: i32,
) {
	if buffer.memory != nil do delete(buffer.memory)

	buffer.height = height
	buffer.width = width

	buffer.info.bmiHeader.biSize = size_of(buffer.info)
	buffer.info.bmiHeader.biWidth = buffer.width
	buffer.info.bmiHeader.biHeight = -buffer.height // top to bottom
	buffer.info.bmiHeader.biPlanes = 1
	buffer.info.bmiHeader.biBitCount = 32 // 8 bits per pixel (24) + padding
	buffer.info.bmiHeader.biCompression = win32.BI_RGB

	bytes_per_pixel: i32 = 4
	bitmap_memory_size := (buffer.width * buffer.height) * bytes_per_pixel
	buffer.memory = make([]u32, bitmap_memory_size)
}

// Invoked every time window draws
win32_display_buffer_to_window :: proc(
	device_context: win32.HDC,
	buffer: ^Win32_Offscreen_Buffer,
	window_width, window_height: i32,
) {
	// Basically rectangle to rectangle copy
	win32.StretchDIBits(
		device_context,
		0,
		0,
		window_width,
		window_height, // ^ dest rect
		0,
		0,
		buffer.width,
		buffer.height, // ^ source rect
		raw_data(buffer.memory),
		&buffer.info,
		win32.DIB_RGB_COLORS,
		win32.SRCCOPY, // simply copy bits from one rect to the other
	)
}

draw_gradient :: proc(buffer: ^Win32_Offscreen_Buffer, xOffset, yOffset: i32) {
	for y in 0 ..< buffer.height {
		for x in 0 ..< buffer.width {
			blue := u8(x + xOffset) // Extract the lowest bits from the 'x' use as blue color. Offset is just for animation.
			green := u8(y) // Extract the lowest bits from the 'y' use as blue color.

			// Combine green and blue into a single u32
			pixel_value := u32(green) << 8 | u32(blue)

			// Index calculation for 1D array from 2D coordinates
			index := y * buffer.width + x
			buffer.memory[index] = pixel_value
		}
	}
}
