#import "Basic";
#import "Socket";

#if OS == .WINDOWS {
    win32 :: #import "Windows";
    kernel32 :: #system_library "kernel32";

    LPDWORD :: *win32.DWORD;
    LPVOID :: *void;

    SetConsoleCursorPosition :: (hConsoleOutput: win32.HANDLE, dwCursorPosition : win32.COORD) -> win32.BOOL #foreign kernel32;
    WriteConsoleW :: (hConsoleOutput: win32.HANDLE, lpBuffer: *u16, nNumberOfCharsToWrite: win32.DWORD, lpNumberOfCharsWritten: LPDWORD, lpReserved: LPVOID) -> win32.BOOL #foreign kernel32;

    console_handle: win32.HANDLE;
}

BUFLEN :: 512;

PSI :: 14.504;
MPH :: 2.237;
KPH :: 3.6;

OG_SHIFT       ::     1;           // key // N/A
OG_CTRL        ::     2;           // key // N/A
OG_TURBO       ::     8192;        // show turbo gauge
OG_KM          ::     16384;       // if not set - user prefers MILES
OG_BAR         ::     32768;       // if not set - user prefers PSI

DL_SHIFT       ::     1 << 0;      // shift light
DL_FULLBEAM    ::     1 << 1;      // full beam
DL_HANDBRAKE   ::     1 << 2;      // handbrake
DL_PITSPEED    ::     1 << 3;      // pit speed limiter // N/A
DL_TC          ::     1 << 4;      // TC active or switched off
DL_SIGNAL_L    ::     1 << 5;      // left turn signal
DL_SIGNAL_R    ::     1 << 6;      // right turn signal
DL_SIGNAL_ANY  ::     1 << 7;      // shared turn signal // N/A
DL_OILWARN     ::     1 << 8;      // oil pressure warning
DL_BATTERY     ::     1 << 9;      // battery warning
DL_ABS         ::     1 << 10;     // ABS active or switched off
DL_SPARE       ::     1 << 11;     // N/A

Outguage :: struct {
	time:             u32;       // time in milliseconds (to check order)
	car:              [4]u8;     // Car name
	flags:            u16;       // Info (see OG_x below)

	gear:             u8;        // Reverse:0, Neutral:1, First:2...
	plid:             u8;        // Unique ID of viewed player (0 = none)

	speed:            float;     // M/S
	rpm:              float;     // RPM
	turbo:            float;     // BAR
	engTemp:          float;     // C
	fuel:             float;     // 0 to 1
	oilPressure:      float;     // BAR
	oilTemp:          float;     // C

	dashLights:       u32;       // Dash lights available (see DL_x below)
	showLights:       u32;       // Dash lights currently switched on

	throttle:         float;     // 0 to 1
	brake:            float;     // 0 to 1
	clutch:           float;     // 0 to 1

	display1:         [16]u8;    // Usually Fuel
	display2:         [16]u8;    // Usually Settings
	id:               u32;       // optional - only if OutGauge ID is specified
}

IS_METRIC   ::  false;

socket_release :: (s: *Socket, loc := #caller_location) {
    #if OS == .WINDOWS {
        WSACleanup();
    }

    close_and_reset(s, loc);
}

clear_console :: () -> bool {
    #if OS == .WINDOWS {
        U :: #import "Windows_Utf8";

        using win32;

        mode: DWORD;
        if !GetConsoleMode(console_handle, *mode) then return false;

        originalMode: DWORD = mode;
        mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;

        if !SetConsoleMode(console_handle, mode) then return false;

        written: DWORD = 0;
        sequence: string = "\x1b[2J";
        utf16_sequence: *u16 = U.utf8_to_wide(sequence);
        if !WriteConsoleW(console_handle, utf16_sequence, xx sequence.count, *written, null) {
            SetConsoleMode(console_handle, originalMode);
            return false;
        }

        SetConsoleMode(console_handle, originalMode);
    }

    return true;
}

write_data_to_console :: (data: Outguage) {
    #if OS == .WINDOWS {
        SetConsoleCursorPosition(console_handle, cast(win32.COORD).{0, 0});
    }

    builder: String_Builder;
    print_to_builder(*builder, "Gear: %\n", data.gear);
    print_to_builder(*builder, "RPM: %\n", data.rpm);

    if IS_METRIC {
        print_to_builder(*builder, "Speed: % KPH\n", data.speed * KPH);
        print_to_builder(*builder, "Turbo: % BAR\n", data.turbo);
        print_to_builder(*builder, "Oil Pressure: % BAR\n", data.oilPressure);
        print_to_builder(*builder, "Engine Temperature: % C\n", data.engTemp);
        print_to_builder(*builder, "Oil Temperature: % C\n", data.oilTemp);
    } else {
        print_to_builder(*builder, "Speed: % MPH\n", data.speed * MPH);
        print_to_builder(*builder, "Turbo: % PSI\n", data.turbo * PSI);
        print_to_builder(*builder, "Oil Pressure: % PSI\n", data.oilPressure * PSI);
        print_to_builder(*builder, "Engine Temperature: % F\n", (data.engTemp * 9.0 / 5.0) + 32.0);
        print_to_builder(*builder, "Oil Temperature: % F\n", (data.oilTemp * 9.0 / 5.0) + 32.0);
    }

    print_to_builder(*builder, "\nThrottle: %\n", data.throttle);
    print_to_builder(*builder, "Brake: %\n", data.brake);
    print_to_builder(*builder, "Clutch: %\n", data.clutch);

    print_to_builder(*builder, "\nShift light: %\n", data.showLights & DL_SHIFT);
    print_to_builder(*builder, "Fullbeam: %\n", data.showLights & DL_FULLBEAM);
    print_to_builder(*builder, "Handbrake: %\n", data.showLights & DL_HANDBRAKE);
    print_to_builder(*builder, "Pitspeed: %\n", data.showLights & DL_PITSPEED);
    print_to_builder(*builder, "TC: %\n", data.showLights & DL_TC);

    print_to_builder(*builder, "\nSIGNAL_L: %\n", data.showLights & DL_SIGNAL_L);
    print_to_builder(*builder, "SIGNAL_R: %\n", data.showLights & DL_SIGNAL_R);
    print_to_builder(*builder, "SIGNAL_ANY: %\n", data.showLights & DL_SIGNAL_ANY);

    print("%", builder_to_string(*builder));
}

main :: () {
    if !socket_init() then return;

    target_ip: *u8 = "127.0.0.1";
    target_port: u16 = 4444;

    host: sockaddr_in;
    host.sin_family = AF_INET;
    host.sin_port = htons(target_port);
    host.sin_addr.S_un.S_addr = inet_addr(target_ip);

    sock: Socket = socket(host.sin_family, .SOCK_DGRAM, 0);
    if sock == INVALID_SOCKET then {
        log_error("could not create socket\n");
        return;
    }
    defer socket_release(*sock);

    if bind(sock, cast(*sockaddr)*host, size_of(sockaddr_in)) == SOCKET_ERROR then {
        log_error("failed to bind socket: %\n", get_last_socket_error());
        return;
    }

    client: sockaddr_in;
    client_size := size_of(sockaddr_in);
    buf: [BUFLEN]u8;

    print("Got connection\n");

    data: Outguage;

    #if OS == .WINDOWS {
        console_handle = win32.GetStdHandle(win32.STD_OUTPUT_HANDLE);
    }

    clear_console();    

    while true {
        recv_len := recvfrom(sock, buf.data, BUFLEN, 0, cast(*sockaddr)*client, xx *client_size);
        if recv_len < 0 then {
            break;
        }

        data = cast(*Outguage)buf.data;
        write_data_to_console(data);
    }

    print("Closing...\n");
}