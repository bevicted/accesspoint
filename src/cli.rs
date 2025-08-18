use clap::{Arg, ArgAction, command, value_parser};
use std::path::PathBuf;

pub const FLAG_SILENT: &str = "Silent";
pub const FLAG_VALIDATE: &str = "validate";
pub const FLAG_SOURCE: &str = "source";
pub const ARG_TARGET: &str = "target";

#[derive(Debug)]
pub struct Args<'a> {
    pub source_path: &'a PathBuf,
    pub target: Option<&'a String>,
    pub is_silent: bool,
    pub is_validation: bool,
}

pub fn parse<'a>() -> Args<'a> {
    let matches = command!()
        .arg(
            Arg::new(FLAG_SILENT)
                .short(FLAG_SILENT.chars().next().unwrap())
                .long(FLAG_SILENT)
                .action(ArgAction::SetTrue)
                .help("do not print anything"),
        )
        .arg(
            Arg::new(FLAG_VALIDATE)
                .short(FLAG_VALIDATE.chars().next().unwrap())
                .long(FLAG_VALIDATE)
                .action(ArgAction::SetTrue)
                .help("validate source file and exit"),
        )
        .arg(
            Arg::new(FLAG_SOURCE)
                .short(FLAG_SOURCE.chars().next().unwrap())
                .long(FLAG_SOURCE)
                .value_parser(value_parser!(PathBuf))
                .help("source file to parse")
                .default_value("config.toml"),
        )
        .arg(Arg::new(ARG_TARGET).help("target"))
        .get_matches();

    Args {
        source_path: matches.get_one::<PathBuf>(FLAG_SOURCE).unwrap(),
        target: matches.get_one::<String>(ARG_TARGET),
        is_silent: *matches.get_one::<bool>(FLAG_SILENT).unwrap(),
        is_validation: *matches.get_one::<bool>(FLAG_VALIDATE).unwrap(),
    }
}
