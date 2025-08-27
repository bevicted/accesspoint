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

#[derive(Debug, Clone)]
enum TemplateType {
    Reference,
    Input,
}

#[derive(Debug, Clone)]
struct Template {
    var: String,
    start: usize,
    end: usize,
    t: TemplateType,
}

pub fn parse(path: &PathBuf) -> Result<HashMap<String, Table>> {
    let file = fs::read_to_string(path)?;
    let table = toml::from_str::<HashMap<String, Table>>(&file)?;

    for (project, fields) in table.iter() {
        dbg!(project);
        let templates = parse_templates(fields)?;

        for k in templates.keys() {
            let mut visit_tree = BTreeSet::new();
            let mut queue = VecDeque::from([*k]);

            while let Some(field) = queue.pop_front() {
                if visit_tree.contains(field) {
                    return Err(format!("cyclic import: {} <-> {}", *k, field).into());
                }
                visit_tree.insert(field);

                if templates.contains_key(field) {
                    for template in &templates[field] {
                        if matches!(template.t, TemplateType::Reference) {
                            continue;
                        }
                        dbg!(&template.var);
                        let v = &fields[&template.var];
                        if !(v.is_str() || v.is_integer() || v.is_float() || v.is_bool()) {
                            return Err(format!(
                                "cant template {} of type {}",
                                template.var,
                                v.type_str()
                            )
                            .into());
                        }
                        queue.push_back(&template.var);
                    }
                }
            }

            //resolve(k, &mut fields, &mut templates);
        }
    }
    Ok(table)
}

fn parse_templates(fields: &Table) -> Result<HashMap<&String, Vec<Template>>> {
    let mut templates = HashMap::new();
    for (field_key, field_val) in fields.iter() {
        dbg!(field_key);
        let mut field_templates = Vec::new();
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
                var_start = i + 1;
                continue;
            }
            if in_var && c == '}' {
                in_var = false;
                let var = &s[var_start..i];
                let template_type = if RESERVED_KEYS.contains(&var) {
                    TemplateType::Reference
                } else {
                    TemplateType::Input
                };
                field_templates.push(Template {
                    var: var.to_owned(),
                    start: var_start,
                    end: i + 1,
                    t: template_type,
                });
            }
        }
        if !field_templates.is_empty() {
            templates.insert(field_key, field_templates);
        }
    }

    Ok(templates)
}

fn resolve(field: &String, fields: &mut Table, templates: &mut HashMap<&String, Vec<Template>>) {
    if !templates.contains_key(field) {
        return;
    };

    let unresolved_val = fields[field].as_str().unwrap().to_owned();
    let mut resolved_val = String::new();
    let mut from = 0;

    for template in templates.remove(field).unwrap() {
        resolve(&template.var, fields, templates);
        resolved_val.push_str(&unresolved_val[from..template.start]);
        let template_val = match &fields[&template.var] {
            toml::Value::String(v) => v,
            toml::Value::Integer(v) => &v.to_string(),
            toml::Value::Float(v) => &v.to_string(),
            toml::Value::Boolean(v) => &v.to_string(),
            _ => unreachable!(),
        };
        resolved_val.push_str(template_val);
        from = template.end;
    }

    resolved_val.push_str(&unresolved_val[from..]);
    fields[field] = resolved_val.into();
}
