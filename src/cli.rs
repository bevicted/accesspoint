use clap::{Arg, ArgAction, ArgMatches, command, value_parser};
use std::path::PathBuf;

pub const FLAG_SILENT: &str = "silent";
pub const FLAG_VALIDATE: &str = "validate";
pub const FLAG_FILE: &str = "file";
pub const ARG_TARGET: &str = "target";

pub fn parse() -> ArgMatches {
    command!()
        .arg(
            Arg::new(FLAG_SILENT)
                .short(FLAG_SILENT.chars().next())
                .long(FLAG_SILENT)
                .action(ArgAction::SetTrue)
                .help("do not print anything"),
        )
        .arg(
            Arg::new(FLAG_VALIDATE)
                .short(FLAG_VALIDATE.chars().next())
                .long(FLAG_VALIDATE)
                .action(ArgAction::SetTrue)
                .help("validate source file and exit"),
        )
        .arg(
            Arg::new(FLAG_FILE)
                .short(FLAG_FILE.chars().next())
                .long(FLAG_FILE)
                .value_parser(value_parser!(PathBuf))
                .help("source file to parse")
                .default_value("config.toml"),
        )
        .arg(Arg::new(ARG_TARGET).help("target"))
        .get_matches()
}
