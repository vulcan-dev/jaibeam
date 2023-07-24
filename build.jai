#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "String";
#import "Process";
#import "System";

#run {
    set_build_options_dc(.{do_output=true});
    make_directory_if_it_does_not_exist("./bin/");

    root_options := get_build_options();
    args := root_options.compile_time_command_line;
    release := array_find(args, "-release");

    import_path: [..] string;
    array_add(*import_path, .. root_options.import_path);

    {
        w := compiler_create_workspace("jaibeam");
        
        options := get_build_options(w);
        options.output_executable_name = "jaibeam";
        options.output_path = "./bin";
        options.import_path = import_path;
        
        if release set_optimization(*options, .OPTIMIZED);
        set_build_options(options, w);

        compiler_begin_intercept(w);
        add_build_file("./jaibeam/main.jai", w);
        message_loop(w);
        compiler_end_intercept(w);
    }
}

message_loop :: (w: Workspace) -> bool {
    while true {
        message := compiler_wait_for_message();
        if message.kind != .COMPLETE continue;

        complete := cast(*Message_Complete) message;
        if complete.error_code != .NONE return false;

        break;
    }

    return true;
}