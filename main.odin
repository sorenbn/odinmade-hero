package main

import "base:runtime"
import "core:fmt"
import "core:os"
import win32 "core:sys/windows"


main :: proc() {
	WIN32_CLASS_NAME :: "OdinmadeHeroWindowClass"
	WIN32_WINDOW_NAME :: "Odinmade Hero"
	instance := cast(win32.HINSTANCE)win32.GetModuleHandleW(nil)
	window_class: win32.WNDCLASSW = {
		style         = win32.CS_OWNDC, // use own device context
		lpfnWndProc   = wnd_proc, // proc callback for windows events
		hInstance     = instance, // instance of the application
		lpszClassName = win32.utf8_to_wstring(WIN32_CLASS_NAME), // class name for window
	}

	// register our window to Windows (lol)
	win32.RegisterClassW(&window_class)

	window_handle := win32.CreateWindowExW(
		0, // styles, none for now.
		window_class.lpszClassName, // class name for window
		win32.utf8_to_wstring(WIN32_WINDOW_NAME), // actual window name
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

	// We need to manually tell windows that we want to listen for events.
	for {
		message: win32.MSG
		message_result := win32.GetMessageW(&message, nil, 0, 0) // query any events Windows might send us.

		if message_result <= 0 {
			break
		}

		// send those events back to Windows
		win32.DispatchMessageW(&message)
	}

	fmt.println("Odinmade Hero Exited.")
}

// The callback function Windows send its events to.
wnd_proc :: proc "stdcall" (
	window_handle: win32.HWND,
	message: win32.UINT,
	w_param: win32.WPARAM,
	l_param: win32.LPARAM,
) -> win32.LRESULT {
	context = runtime.default_context()
	result: win32.LRESULT = 0

	switch message {
	// case win32.WM_SIZE:
	// 	fmt.println("WM_SIZE")
	// 	break

	// case win32.WM_DESTROY:
	// 	fmt.println("WM_DESTROY")
	// 	break

	// case win32.WM_CLOSE:
	// 	fmt.println("WM_CLOSE")
	// 	break

	// case win32.WM_ACTIVATEAPP:
	// 	fmt.println("WM_ACTIVATEAPP")
	// 	break

	case win32.WM_PAINT:
		paint: win32.PAINTSTRUCT
		device_context: win32.HDC = win32.BeginPaint(window_handle, &paint)
		x := paint.rcPaint.left
		y := paint.rcPaint.top
		width := paint.rcPaint.right - paint.rcPaint.left
		height := paint.rcPaint.bottom - paint.rcPaint.top
		win32.PatBlt(device_context, x, y, width, height, win32.WHITENESS)
		win32.EndPaint(window_handle, &paint)
		break

	// Let Windows handle all other events as their 'default' behaviour
	case:
		result = win32.DefWindowProcW(window_handle, message, w_param, l_param)
		break

	}

	return result
}
