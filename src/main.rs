mod cli;
mod source;
mod ui;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = cli::parse();

    println!("{:?}", args);

    let source = source::parse(&args.source_path);

    println!("{:?}", source);

    if args.is_validation {
        std::process::exit(0);
    };

    ui::run()
}
