mod cli;

fn main() {
    let cli_matches = cli::parse();

    if *cli_matches.get_one::<bool>(cli::FLAG_PANCAKE).unwrap() {
        println!("Pancake was provided");
        std::process::exit(0);
    }

    let mut siv = cursive::default();

    siv.add_global_callback('q', |s| s.quit());

    siv.run();
}
