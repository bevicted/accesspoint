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
struct Insert {
    reference: String,
    at: usize,
}

#[derive(Debug, Clone)]
enum Field {
    Resolved(toml::Value),
    Unresolved(toml::Value, Vec<Insert>),
    WithInput(toml::Value, Vec<Insert>),
}

pub fn parse(path: &PathBuf) -> Result<HashMap<String, Table>> {
    let file = fs::read_to_string(path)?;
    let table = toml::from_str::<HashMap<String, Table>>(&file)?;

    for (project, fields) in table.iter() {
        dbg!(project);
        let parsed_fields = parse_fields(fields)?;

        for (k, parsed_field) in parsed_fields.iter() {
            let mut visit_tree = BTreeSet::new();
            let mut queue = VecDeque::from([*k]);

            while let Some(field) = queue.pop_front() {
                if visit_tree.contains(field) {
                    return Err(format!("cyclic import: {} <-> {}", *k, field).into());
                }
                visit_tree.insert(field);

                if parsed_fields.contains_key(field) {
                    for template in &parsed_fields[field] {
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

fn parse_fields(fields: &Table) -> Result<HashMap<&String, Field>> {
    let mut parsed_fields: HashMap<&String, Field> = HashMap::new();

    for (field_key, field_val) in fields.iter() {
        dbg!(field_key);
        let mut field_templates = Vec::new();

        if RESERVED_KEYS.contains(&field_key.as_str()) {
            return Err("used reserved variable name".into());
        }

        // only strings can contain references
        let Some(s) = field_val.as_str() else {
            parsed_fields.insert(field_key, Field::Resolved(field_val.to_owned()));
            continue;
        };

        let mut in_ref = false;
        let mut last_ref_boundary: usize = 0;
        let mut cleaned_val = String::new();

        for (i, c) in s.char_indices() {
            if !in_ref && c == '{' {
                in_ref = true;
                cleaned_val.push_str(&s[last_ref_boundary..i]);
                last_ref_boundary = i;
                continue;
            }

            if in_ref && c == '}' {
                in_ref = false;
                field_templates.push(Insert {
                    reference: s[last_ref_boundary + 1..i].to_owned(),
                    at: last_ref_boundary,
                });
                last_ref_boundary = i;
            }
        }

        cleaned_val.push_str(&s[last_ref_boundary..]);

        parsed_fields.insert(
            field_key,
            if field_templates.is_empty() {
                Field::Resolved(field_val.to_owned())
            } else {
                Field::Unresolved(toml::Value::String(cleaned_val), field_templates)
            },
        );
    }

    Ok(parsed_fields)
}

fn resolve(field: &String, fields: &mut Table, templates: &mut HashMap<&String, Vec<Insert>>) {
    if !templates.contains_key(field) {
        return;
    };

    let unresolved_val = fields[field].as_str().unwrap().to_owned();
    let mut resolved_val = String::new();
    let mut from = 0;

    for template in templates.remove(field).unwrap() {
        resolve(&template.reference, fields, templates);
        resolved_val.push_str(&unresolved_val[from..template.at]);
        let template_val = match &fields[&template.reference] {
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
