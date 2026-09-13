// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // --version-file <path>: write the package version to a file and exit.
    // The release build is a GUI-subsystem binary with no attached console,
    // so --version could not print anything; a written file is what the
    // packaged smoke test verifies instead.
    let args: Vec<String> = std::env::args().collect();
    if args.len() >= 3 && args[1] == "--version-file" {
        std::fs::write(&args[2], format!("{}\n", env!("CARGO_PKG_VERSION")))
            .expect("write version file");
        return;
    }
    // --open <dir> or a bare positional path opens that project directory on
    // launch; the frontend claims it once via host_take_initial_project.
    let mut initial_project = None;
    let mut index = 1;
    while index < args.len() {
        let arg = &args[index];
        if arg == "--open" {
            if let Some(path) = args.get(index + 1) {
                initial_project = Some(std::path::PathBuf::from(path));
                index += 1;
            }
        } else if !arg.starts_with('-') && initial_project.is_none() {
            initial_project = Some(std::path::PathBuf::from(arg));
        }
        index += 1;
    }
    uxml_editor_lib::run(initial_project);
}
