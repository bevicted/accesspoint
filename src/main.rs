mod catalog;
mod cli;
mod ui;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = cli::parse();

    println!("{:?}", args);

    let entries = catalog::parse(&args.source_path);

    println!("{:?}", entries);

    if args.is_validation {
        std::process::exit(0);
    };

    ui::run()
}
