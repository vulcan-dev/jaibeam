// This is a very early version of whatever I'm currently making and I'm very new to Jai.

#import "Socket";
#import "Thread";
#import "Basic";
#import "Atomics";

#load "jbui.jai";

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

outguage_data: Outguage;
should_exit: bool = false;

IS_METRIC   ::  false;

socket_release :: (s: *Socket, loc := #caller_location) {
    #if OS == .WINDOWS {
        WSACleanup();
    }

    close_and_reset(s, loc);
}

temp_draw :: (offset: *s64, name: string, value: $T) {
    jbui_draw_text(tprint("%: %", name, value), 0, <<offset);
    <<offset += 25;
}

render_thread_fn :: (thread: *Thread) -> s64 {
    jbui_init();

    while jbui_process() == .CONTINUE {
        can_continue: bool = true;
        atomic_swap(*can_continue, !should_exit);
        if !can_continue {
            break;
        }

        offset := 0;

        temp_draw(*offset, "Gear", outguage_data.gear);
        temp_draw(*offset, "RPM", outguage_data.rpm);
        temp_draw(*offset, "Fuel", outguage_data.fuel);

        if IS_METRIC {
            temp_draw(*offset, "Speed", outguage_data.speed * KPH);
            temp_draw(*offset, "Turbo", outguage_data.turbo);
            temp_draw(*offset, "Oil Pressure", outguage_data.oilPressure);
            temp_draw(*offset, "Engine Temperature", outguage_data.engTemp);
            temp_draw(*offset, "Oil Temperature", outguage_data.oilTemp);
        } else {
            temp_draw(*offset, "Speed", outguage_data.speed * MPH);
            temp_draw(*offset, "Turbo", outguage_data.turbo * PSI);
            temp_draw(*offset, "Oil Pressure", outguage_data.oilPressure * PSI);
            temp_draw(*offset, "Engine Temperature", (outguage_data.engTemp * 9.0 / 5.0) + 32.0);
            temp_draw(*offset, "Oil Temperature", (outguage_data.oilTemp * 9.0 / 5.0) + 32.0);
        }

        temp_draw(*offset, "Throttle", outguage_data.throttle);
        temp_draw(*offset, "Brake", outguage_data.brake);
        temp_draw(*offset, "Clutch", outguage_data.clutch);

        temp_draw(*offset, "Shift light", outguage_data.showLights & DL_SHIFT);
        temp_draw(*offset, "Fullbeam", outguage_data.showLights & DL_FULLBEAM);
        temp_draw(*offset, "Handbrake", outguage_data.showLights & DL_HANDBRAKE);
        temp_draw(*offset, "Pitspeed", outguage_data.showLights & DL_PITSPEED);
        temp_draw(*offset, "TC", outguage_data.showLights & DL_TC);

        temp_draw(*offset, "SIGNAL_L", outguage_data.showLights & DL_SIGNAL_L);
        temp_draw(*offset, "SIGNAL_R", outguage_data.showLights & DL_SIGNAL_R);
        temp_draw(*offset, "SIGNAL_ANY", outguage_data.showLights & DL_SIGNAL_ANY);

        jbui_swap();
    }

    atomic_swap(*should_exit, true);

    return 0;
}

create_socket :: () -> (sock: *Socket, host: sockaddr_in) {
    if !socket_init() then return null, .{};

    target_ip: *u8 = "127.0.0.1";
    target_port: u16 = 4444;

    host: sockaddr_in;
    host.sin_family = AF_INET;
    host.sin_port = htons(target_port);
    host.sin_addr.S_un.S_addr = inet_addr(target_ip);

    sock: Socket = socket(host.sin_family, .SOCK_DGRAM, 0);
    if sock == INVALID_SOCKET then {
        log_error("could not create socket\n");
        return null, .{};
    }
    
    return *sock, host;
}

render_thread: Thread;

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

    if bind(sock, xx cast(*sockaddr)*host, xx size_of(sockaddr_in)) == SOCKET_ERROR then {
        log_error("failed to bind socket: %\n", get_last_socket_error());
        return;
    }

    should_exit = false;
    
    {
        #if OS == .WINDOWS {
            win32 :: #import "Windows";

            if !thread_init(*render_thread, render_thread_fn) then {
                log_error("failed creating render thread\n");
                return;
            }

            log("starting render thread\n");
            thread_start(*render_thread);
        }
    }

    client: sockaddr_in;
    client_size := size_of(sockaddr_in);
    buf: [BUFLEN]u8;

    while true {
        if should_exit break;

        recv_len := recvfrom(sock, buf.data, BUFLEN, 0, cast(*sockaddr)*client, xx *client_size);
        if recv_len < 0 then {
            atomic_swap(*should_exit, true);
            break;
        }

        outguage_data = cast(*Outguage)buf.data;
    }

    log("waiting for render thread to close\n");
    while !thread_is_done(*render_thread, 10) {}; // Just wait for it to finish up, do I need while here? Fck knows, probably not. Can I be arsed looking at the docs? Nah
    thread_deinit(*render_thread);

    socket_release(*sock);
    log("exiting...\n");
}