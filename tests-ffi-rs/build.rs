use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();

    let reporter_target_dir = PathBuf::from(&manifest_dir).join("..").join("reporter-ffi");
    let servermock_target_dir = PathBuf::from(&manifest_dir)
        .join("..")
        .join("servermock-ffi");
    println!(
        "cargo:rustc-link-search=native={}",
        reporter_target_dir.display()
    );
    println!(
        "cargo:rustc-link-search=native={}",
        servermock_target_dir.display()
    );
    println!(
        "cargo:rustc-link-arg=-Wl,-rpath,{}",
        reporter_target_dir.display()
    );
    println!(
        "cargo:rustc-link-arg=-Wl,-rpath,{}",
        servermock_target_dir.display()
    );
    println!("cargo:rustc-link-lib=dylib=greener_reporter");
    println!("cargo:rustc-link-lib=dylib=greener_servermock");

    let reporter_include_dir = PathBuf::from(&reporter_target_dir).join("include");
    let reporter_header = reporter_include_dir
        .join("greener_reporter")
        .join("greener_reporter.h");

    let servermock_include_dir = PathBuf::from(&servermock_target_dir).join("include");
    let servermock_header = servermock_include_dir.join("greener_servermock/greener_servermock.h");

    let bindings = bindgen::Builder::default()
        .header(reporter_header.to_string_lossy())
        .header(servermock_header.to_string_lossy())
        .clang_arg(format!("-I{}", reporter_include_dir.display()))
        .clang_arg(format!("-I{}", servermock_include_dir.display()))
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
