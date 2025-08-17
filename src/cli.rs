use clap::{Arg, ArgAction, ArgMatches, command};

pub const FLAG_PANCAKE: &str = "pancake";

pub fn parse() -> ArgMatches {
    command!()
        .arg(
            Arg::new(FLAG_PANCAKE)
                .short('p')
                .long(FLAG_PANCAKE)
                .action(ArgAction::SetTrue),
        )
        .get_matches()
}
