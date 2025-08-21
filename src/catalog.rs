use std::{collections::HashMap, fs, path::PathBuf};
use toml::Table;

const TEMPLATE_STRING: &str = "STRING";
const TEMPLATE_NUMBER: &str = "NUMBER";

pub fn parse(path: &PathBuf) -> Result<Table, Box<dyn std::error::Error>> {
    let mut table = fs::read_to_string(path)?.parse::<Table>()?;
    let mut deps = HashMap::with_capacity(table.len());
    for (k, v) in table.iter() {
        if k == TEMPLATE_STRING || k == TEMPLATE_NUMBER {
            return Err("used reserved variable name".into());
        }
        let Some(s) = v.as_str() else {
            continue;
        };

        let mut in_var = false;
        let mut var_start: usize = 0;
        for (i, c) in s.char_indices() {
            if !in_var && c == '{' {
                in_var = true;
                var_start = i;
                continue;
            }
            if in_var && c == '}' {
                in_var = false;
                deps.insert(k, s[var_start..i].to_owned());
            }
        }
    }
    println!("{:?}", deps);
    table.insert("some key".into(), "some value".into());
    Ok(table)
}
