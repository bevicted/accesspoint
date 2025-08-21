use std::{
    collections::{BTreeSet, HashMap, VecDeque},
    fs,
    path::PathBuf,
};
use toml::Table;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

const TEMPLATE_STRING: &str = "STRING";
const TEMPLATE_NUMBER: &str = "NUMBER";
const RESERVED_KEYS: &[&str] = &[TEMPLATE_STRING, TEMPLATE_NUMBER];

#[derive(Clone)]
struct Template {
    var: String,
    start: usize,
    end: usize,
}

pub fn parse(path: &PathBuf) -> Result<HashMap<String, Table>> {
    let file = fs::read_to_string(path)?;
    let table = toml::from_str::<HashMap<String, Table>>(&file)?;

    for (proj_name, proj_fields) in table.iter_mut() {
        dbg!(proj_name);
        let mut proj_deps = HashMap::with_capacity(table.len());
        for (field_key, field_val) in proj_fields.iter() {
            dbg!(field_key);
            let mut field_deps = Vec::new();
            if RESERVED_KEYS.contains(&field_key.as_str()) {
                return Err("used reserved variable name".into());
            }
            let Some(s) = field_val.as_str() else {
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
                    field_deps.push(Template {
                        var: s[var_start..i + 1].to_owned(),
                        start: var_start,
                        end: i + 1,
                    });
                }
            }
            if !field_deps.is_empty() {
                proj_deps.insert(field_key, field_deps);
            }
        }

        for k in proj_deps.keys() {
            let mut visit_tree = BTreeSet::new();
            let mut queue = VecDeque::new();
            queue.push_back(*k);
            while let Some(dep) = queue.pop_front() {
                if visit_tree.contains(dep) {
                    return Err(format!("cyclic import: {} <-> {}", k, dep).into());
                }
                visit_tree.insert(dep);
                if proj_deps.contains_key(dep) {
                    for k in &proj_deps[dep] {
                        let v = &proj_fields[&k.var];
                        if !(v.is_str() || v.is_integer() || v.is_float() || v.is_bool()) {
                            return Err(format!(
                                "cant template {} of type {}",
                                k.var,
                                v.type_str()
                            )
                            .into());
                        }
                        queue.push_back(&k.var);
                    }
                }
            }

            resolve(k, &mut proj_fields, &mut proj_deps);
        }
    }
    Ok(table)
}

fn resolve(key: &String, fields: &mut Table, deps: &mut HashMap<&String, Vec<Template>>) {
    if !deps.contains_key(key) {
        return;
    };

    let mut s = String::new();
    let mut start = 0;
    let field_val = fields[key].as_str().unwrap().to_owned();

    for t in deps[key].clone() {
        resolve(&t.var, fields, deps);
        s.push_str(&field_val[start..t.start]);
        let template_val = match &fields[&t.var] {
            toml::Value::String(v) => v,
            toml::Value::Integer(v) => &v.to_string(),
            toml::Value::Float(v) => &v.to_string(),
            toml::Value::Boolean(v) => &v.to_string(),
            _ => unreachable!(),
        };
        s.push_str(template_val);
        start = t.end;
    }

    s.push_str(&field_val[start..]);
    fields[key] = s.into();
    deps.remove(key);
}
