package main

import "base:runtime"
import "core:fmt"
import "core:os"
import win32 "core:sys/windows"

application_running: bool
bitmap_info: win32.BITMAPINFO
bitmap_memory: [^]u8
bitmap_handle: win32.HBITMAP
bitmap_device_context: win32.HDC

main :: proc() {
	instance := cast(win32.HINSTANCE)win32.GetModuleHandleW(nil) // get instance to application process
	window_class: win32.WNDCLASSW = {
		style         = win32.CS_OWNDC, // use own device context
		lpfnWndProc   = win32_window_callback, // procedure callback for windows events
		hInstance     = instance, // instance of the application
		lpszClassName = win32.utf8_to_wstring("OdinmadeHeroWindowClass"), // class name for window
	}

	// register our window to Windows (lol)
	win32.RegisterClassW(&window_class)

	window_handle := win32.CreateWindowExW(
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

	application_running = true
	// We need to manually tell windows that we want to listen for events.
	for application_running {
		message: win32.MSG
		message_result := win32.GetMessageW(&message, nil, 0, 0) // query any events Windows might send us.

		if message_result <= 0 {
			break
		}

		// send those events back to Windows
		win32.TranslateMessage(&message)
		win32.DispatchMessageW(&message)
	}

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
		client_rect: win32.RECT
		win32.GetClientRect(window_handle, &client_rect)
		width := client_rect.right - client_rect.left
		height := client_rect.bottom - client_rect.top

		win32_resize_device_independent_bitmap_section(width, height)
		break

	case win32.WM_DESTROY:
		application_running = false
		break

	case win32.WM_CLOSE:
		application_running = false
		break

	case win32.WM_PAINT:
		paint: win32.PAINTSTRUCT
		device_context: win32.HDC = win32.BeginPaint(window_handle, &paint)
		x := paint.rcPaint.left
		y := paint.rcPaint.top
		width := paint.rcPaint.right - paint.rcPaint.left
		height := paint.rcPaint.bottom - paint.rcPaint.top
		win32_update_window(device_context, x, y, width, height)
		win32.EndPaint(window_handle, &paint)
		break

	// Let Windows handle all other events as their 'default' behaviour
	case:
		result = win32.DefWindowProcW(window_handle, message, w_param, l_param)
		break
	}

	return result
}

// Invoked every time window resizes.
win32_resize_device_independent_bitmap_section :: proc(width, height: i32) {

	// Free the previous instance of the bitmap handle, if it exists.
	if bitmap_handle != nil do win32.DeleteObject(cast(win32.HGDIOBJ)bitmap_handle)
	// create bitmap device context if it doesn't exist yet.
	if bitmap_device_context == nil do bitmap_device_context = win32.CreateCompatibleDC(nil)

	bitmap_info.bmiHeader.biSize = size_of(bitmap_info)
	bitmap_info.bmiHeader.biWidth = width
	bitmap_info.bmiHeader.biHeight = height
	bitmap_info.bmiHeader.biPlanes = 1
	bitmap_info.bmiHeader.biBitCount = 32
	bitmap_info.bmiHeader.biCompression = win32.BI_RGB

	bitmap_handle = win32.CreateDIBSection(
		bitmap_device_context,
		&bitmap_info,
		win32.DIB_RGB_COLORS,
		&bitmap_memory,
		nil,
		0,
	)
}

// Invoked every time window draws
win32_update_window :: proc(device_context: win32.HDC, x, y, width, height: i32) {
	// Basically rectangle to rectangle copy
	win32.StretchDIBits(
		device_context,
		x,
		y,
		width,
		height, // ^ dest rect
		x,
		y,
		width,
		height, // ^ source rect
		bitmap_memory,
		&bitmap_info,
		win32.DIB_RGB_COLORS,
		win32.SRCCOPY, // simply copy bits from one rect to the other
	)
}
