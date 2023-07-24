#scope_file

Simp :: #import "Simp";
Input :: #import "Input";

#import "Input";
#import "Window_Creation";
#import "System";
#import "String";
#import "Math";

JBUI_Window :: struct {
    window: Window_Type;
    width: s32;
    height: s32;
}

working_directory_set := false;
jbui_font: *Simp.Dynamic_Font;
jbui: JBUI_Window;

#scope_module

Continue_Status :: enum u8 #specified {
    CONTINUE        :: 1;
    CLOSE_REQUESTED :: 2;
}

jbui_init :: () {
    #if OS == .WINDOWS {
        win32 :: #import "Windows";
        win32.SetProcessDPIAware();
        win32.timeBeginPeriod(1);
    }

    jbui.width = 800;
    jbui.height = 600;
    jbui.window = create_window(jbui.width, jbui.height, "Jaibeam");
    Simp.set_render_target(jbui.window);

    jbui_init_fonts();
}

jbui_process :: () -> Continue_Status {
    Input.update_window_events();

    for Input.get_window_resizes() {
        Simp.update_window(it.window);

        if it.window == jbui.window {
            using jbui;
            should_init := (it.width != width) || (it.height != height);

            width = it.width;
            height = it.height;

            if should_init jbui_init_fonts();
        }
    }

    for Input.events_this_frame {
        if it.type == .QUIT then return .CLOSE_REQUESTED;
    }

    jbui_render_frame();
    sleep_milliseconds(10);
    reset_temporary_storage();

    return .CONTINUE;
}

jbui_render_frame :: () {
    Simp.clear_render_target(0.16, 0.16, 0.16, 1);
    Simp.set_shader_for_color();
}

jbui_init_fonts :: () {
        if !working_directory_set {
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);
        working_directory_set = true;
    }
    
    pixel_height := jbui.height / 24;

    // @Cleanup: Don't have path + name be separate.
    jbui_font = Simp.get_font_at_size("./rom/fonts/", "OpenSans-BoldItalic.ttf", pixel_height);
    assert(jbui_font != null);
}

jbui_text_width :: (text: string) -> s64 {
    return Simp.prepare_text(jbui_font, text);
}

jbui_draw_text :: (text: string, x: s64, y: s64, color := Vector4.{1, 1, 1, 1}) -> s64 {
    text_width := Simp.prepare_text(jbui_font, text);
    // x += (jbui.width - jbui_text_width(text)) / 2;
    // y +=  jbui.height / 2 - jbui_font.character_height / 4;
    y = (jbui.height - jbui_font.character_height) - y;
    Simp.draw_prepared_text(jbui_font, x, y, color);
    return text_width;
}

jbui_swap :: () {
    Simp.swap_buffers(jbui.window);
}

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
    }
}