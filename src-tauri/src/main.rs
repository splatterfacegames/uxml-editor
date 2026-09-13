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
    uxml_editor_lib::run();
}
