use std::{fs, path::PathBuf};

pub fn parse(path: &PathBuf) -> Result<toml::Table, Box<dyn std::error::Error>> {
    Ok(fs::read_to_string(path)?.parse::<toml::Table>()?)
}
