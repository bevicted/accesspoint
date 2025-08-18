use toml::Table;

mod cli;

fn main() {
    let args = cli::parse();

    println!("{:?}", args);

    if args.is_validation {
        std::process::exit(0);
    }

    let mut siv = cursive::default();

    siv.add_global_callback('q', |s| s.quit());

    siv.run();
}
