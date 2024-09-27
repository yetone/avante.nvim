use mlua::prelude::*;
use std::cell::RefCell;
use std::collections::HashMap;
use tree_sitter::{Node, Parser, Query, QueryCursor};
use tree_sitter_language::LanguageFn;

#[derive(Debug, Clone)]
pub struct Func {
    pub name: String,
    pub params: String,
    pub return_type: String,
    pub accessibility_modifier: Option<String>,
}

#[derive(Debug, Clone)]
pub struct Class {
    pub name: String,
    pub methods: Vec<Func>,
    pub properties: Vec<Variable>,
    pub visibility_modifier: Option<String>,
}

#[derive(Debug, Clone)]
pub struct Enum {
    pub name: String,
    pub items: Vec<Variable>,
}

#[derive(Debug, Clone)]
pub struct Variable {
    pub name: String,
    pub value_type: String,
}

#[derive(Debug, Clone)]
pub enum Definition {
    Func(Func),
    Class(Class),
    Enum(Enum),
    Variable(Variable),
}

fn get_ts_language(language: &str) -> Option<LanguageFn> {
    match language {
        "rust" => Some(tree_sitter_rust::LANGUAGE),
        "python" => Some(tree_sitter_python::LANGUAGE),
        "javascript" => Some(tree_sitter_javascript::LANGUAGE),
        "typescript" => Some(tree_sitter_typescript::LANGUAGE_TSX),
        "go" => Some(tree_sitter_go::LANGUAGE),
        "c" => Some(tree_sitter_c::LANGUAGE),
        "cpp" => Some(tree_sitter_cpp::LANGUAGE),
        "lua" => Some(tree_sitter_lua::LANGUAGE),
        "ruby" => Some(tree_sitter_ruby::LANGUAGE),
        _ => None,
    }
}

const C_QUERY: &str = include_str!("../queries/tree-sitter-c-defs.scm");
const CPP_QUERY: &str = include_str!("../queries/tree-sitter-cpp-defs.scm");
const GO_QUERY: &str = include_str!("../queries/tree-sitter-go-defs.scm");
const JAVASCRIPT_QUERY: &str = include_str!("../queries/tree-sitter-javascript-defs.scm");
const LUA_QUERY: &str = include_str!("../queries/tree-sitter-lua-defs.scm");
const PYTHON_QUERY: &str = include_str!("../queries/tree-sitter-python-defs.scm");
const RUST_QUERY: &str = include_str!("../queries/tree-sitter-rust-defs.scm");
const TYPESCRIPT_QUERY: &str = include_str!("../queries/tree-sitter-typescript-defs.scm");
const RUBY_QUERY: &str = include_str!("../queries/tree-sitter-ruby-defs.scm");

fn get_definitions_query(language: &str) -> Result<Query, String> {
    let ts_language = get_ts_language(language);
    if ts_language.is_none() {
        return Err(format!("Unsupported language: {language}"));
    }
    let ts_language = ts_language.unwrap();
    let contents = match language {
        "c" => C_QUERY,
        "cpp" => CPP_QUERY,
        "go" => GO_QUERY,
        "javascript" => JAVASCRIPT_QUERY,
        "lua" => LUA_QUERY,
        "python" => PYTHON_QUERY,
        "rust" => RUST_QUERY,
        "typescript" => TYPESCRIPT_QUERY,
        "ruby" => RUBY_QUERY,
        _ => return Err(format!("Unsupported language: {language}")),
    };
    let query = Query::new(&ts_language.into(), contents)
        .unwrap_or_else(|_| panic!("Failed to parse query for {language}"));
    Ok(query)
}

fn get_closest_ancestor_name(node: &Node, source: &str) -> String {
    let mut parent = node.parent();
    while let Some(parent_node) = parent {
        let name_node = parent_node.child_by_field_name("name");
        if let Some(name_node) = name_node {
            return get_node_text(&name_node, source.as_bytes()).to_string();
        }
        parent = parent_node.parent();
    }
    String::new()
}

fn find_ancestor_by_type<'a>(node: &'a Node, parent_type: &str) -> Option<Node<'a>> {
    let mut parent = node.parent();
    while let Some(parent_node) = parent {
        if parent_node.kind() == parent_type {
            return Some(parent_node);
        }
        parent = parent_node.parent();
    }
    None
}

fn find_descendant_by_type<'a>(node: &'a Node, child_type: &str) -> Option<Node<'a>> {
    let mut cursor = node.walk();
    for i in 0..node.descendant_count() {
        cursor.goto_descendant(i);
        let node = cursor.node();
        if node.kind() == child_type {
            return Some(node);
        }
    }
    None
}

fn find_child_by_type<'a>(node: &'a Node, child_type: &str) -> Option<Node<'a>> {
    node.children(&mut node.walk())
        .find(|child| child.kind() == child_type)
}

fn get_node_text<'a>(node: &'a Node, source: &'a [u8]) -> String {
    node.utf8_text(source).unwrap_or_default().to_string()
}

fn get_node_type<'a>(node: &'a Node, source: &'a [u8]) -> String {
    let predefined_type_node = find_descendant_by_type(node, "predefined_type");
    if let Some(type_node) = predefined_type_node {
        return type_node.utf8_text(source).unwrap().to_string();
    }
    let value_type_node = node.child_by_field_name("type");
    value_type_node
        .map(|n| n.utf8_text(source).unwrap().to_string())
        .unwrap_or_default()
}

fn is_first_letter_uppercase(name: &str) -> bool {
    if name.is_empty() {
        return false;
    }
    name.chars().next().unwrap().is_uppercase()
}

// Given a language, parse the given source code and return exported definitions
fn extract_definitions(language: &str, source: &str) -> Result<Vec<Definition>, String> {
    let ts_language = get_ts_language(language);

    if ts_language.is_none() {
        return Ok(vec![]);
    }

    let ts_language = ts_language.unwrap();

    let mut definitions = Vec::new();
    let mut parser = Parser::new();
    parser
        .set_language(&ts_language.into())
        .unwrap_or_else(|_| panic!("Failed to set language for {language}"));
    let tree = parser
        .parse(source, None)
        .unwrap_or_else(|| panic!("Failed to parse source code for {language}"));
    let root_node = tree.root_node();

    let query = get_definitions_query(language)?;
    let mut query_cursor = QueryCursor::new();
    let captures = query_cursor.captures(&query, root_node, source.as_bytes());

    let mut class_def_map: HashMap<String, RefCell<Class>> = HashMap::new();
    let mut enum_def_map: HashMap<String, RefCell<Enum>> = HashMap::new();

    let ensure_class_def = |name: &str, class_def_map: &mut HashMap<String, RefCell<Class>>| {
        class_def_map.entry(name.to_string()).or_insert_with(|| {
            RefCell::new(Class {
                name: name.to_string(),
                methods: vec![],
                properties: vec![],
                visibility_modifier: None,
            })
        });
    };

    let ensure_enum_def = |name: &str, enum_def_map: &mut HashMap<String, RefCell<Enum>>| {
        enum_def_map.entry(name.to_string()).or_insert_with(|| {
            RefCell::new(Enum {
                name: name.to_string(),
                items: vec![],
            })
        });
    };

    for (m, _) in captures {
        for capture in m.captures {
            let capture_name = &query.capture_names()[capture.index as usize];
            let node = capture.node;
            let name_node = node.child_by_field_name("name");
            let name = name_node
                .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                .unwrap_or("");
            match *capture_name {
                "class" => {
                    if !name.is_empty() {
                        if language == "go" && !is_first_letter_uppercase(name) {
                            continue;
                        }
                        ensure_class_def(name, &mut class_def_map);
                        let visibility_modifier_node =
                            find_child_by_type(&node, "visibility_modifier");
                        let visibility_modifier = visibility_modifier_node
                            .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                            .unwrap_or("");
                        let class_def = class_def_map.get_mut(name).unwrap();
                        class_def.borrow_mut().visibility_modifier =
                            if visibility_modifier.is_empty() {
                                None
                            } else {
                                Some(visibility_modifier.to_string())
                            };
                    }
                }
                "enum_item" => {
                    let visibility_modifier_node =
                        find_descendant_by_type(&node, "visibility_modifier");
                    let visibility_modifier = visibility_modifier_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    if language == "rust" && !visibility_modifier.contains("pub") {
                        continue;
                    }
                    let enum_name = get_closest_ancestor_name(&node, source);
                    if !enum_name.is_empty()
                        && language == "go"
                        && !is_first_letter_uppercase(&enum_name)
                    {
                        continue;
                    }
                    ensure_enum_def(&enum_name, &mut enum_def_map);
                    let enum_def = enum_def_map.get_mut(&enum_name).unwrap();
                    let enum_type_node = find_descendant_by_type(&node, "type_identifier");
                    let enum_type = enum_type_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    let variable = Variable {
                        name: name.to_string(),
                        value_type: enum_type.to_string(),
                    };
                    enum_def.borrow_mut().items.push(variable);
                }
                "method" => {
                    let visibility_modifier_node =
                        find_descendant_by_type(&node, "visibility_modifier");
                    let visibility_modifier = visibility_modifier_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    if language == "rust" && !visibility_modifier.contains("pub") {
                        continue;
                    }
                    if !name.is_empty() && language == "go" && !is_first_letter_uppercase(name) {
                        continue;
                    }
                    let params_node = node.child_by_field_name("parameters");
                    let params = params_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("()");
                    let mut return_type_node = node.child_by_field_name("return_type");
                    if return_type_node.is_none() {
                        return_type_node = node.child_by_field_name("result");
                    }
                    let mut return_type = "void".to_string();
                    if return_type_node.is_some() {
                        return_type = get_node_type(&return_type_node.unwrap(), source.as_bytes());
                        if return_type.is_empty() {
                            return_type = return_type_node
                                .unwrap()
                                .utf8_text(source.as_bytes())
                                .unwrap_or("void")
                                .to_string();
                        }
                    }

                    let impl_item_node = find_ancestor_by_type(&node, "impl_item");
                    let receiver_node = node.child_by_field_name("receiver");
                    let class_name = if let Some(impl_item) = impl_item_node {
                        let impl_type_node = impl_item.child_by_field_name("type");
                        impl_type_node
                            .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                            .unwrap_or("")
                            .to_string()
                    } else if let Some(receiver) = receiver_node {
                        let type_identifier_node =
                            find_descendant_by_type(&receiver, "type_identifier");
                        type_identifier_node
                            .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                            .unwrap_or("")
                            .to_string()
                    } else {
                        get_closest_ancestor_name(&node, source).to_string()
                    };

                    if language == "go" && !is_first_letter_uppercase(&class_name) {
                        continue;
                    }

                    ensure_class_def(&class_name, &mut class_def_map);
                    let class_def = class_def_map.get_mut(&class_name).unwrap();

                    let accessibility_modifier_node =
                        find_descendant_by_type(&node, "accessibility_modifier");
                    let accessibility_modifier = accessibility_modifier_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");

                    let func = Func {
                        name: name.to_string(),
                        params: params.to_string(),
                        return_type: return_type.to_string(),
                        accessibility_modifier: if accessibility_modifier.is_empty() {
                            None
                        } else {
                            Some(accessibility_modifier.to_string())
                        },
                    };
                    class_def.borrow_mut().methods.push(func);
                }
                "class_assignment" => {
                    let visibility_modifier_node =
                        find_descendant_by_type(&node, "visibility_modifier");
                    let visibility_modifier = visibility_modifier_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    if language == "rust" && !visibility_modifier.contains("pub") {
                        continue;
                    }
                    let left_node = node.child_by_field_name("left");
                    let left = left_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    let value_type = get_node_type(&node, source.as_bytes());
                    let class_name = get_closest_ancestor_name(&node, source);
                    if !class_name.is_empty()
                        && language == "go"
                        && !is_first_letter_uppercase(&class_name)
                    {
                        continue;
                    }
                    if class_name.is_empty() {
                        continue;
                    }
                    ensure_class_def(&class_name, &mut class_def_map);
                    let class_def = class_def_map.get_mut(&class_name).unwrap();
                    let variable = Variable {
                        name: left.to_string(),
                        value_type: value_type.to_string(),
                    };
                    class_def.borrow_mut().properties.push(variable);
                }
                "class_variable" => {
                    let visibility_modifier_node =
                        find_descendant_by_type(&node, "visibility_modifier");
                    let visibility_modifier = visibility_modifier_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    if language == "rust" && !visibility_modifier.contains("pub") {
                        continue;
                    }
                    let value_type = get_node_type(&node, source.as_bytes());
                    let class_name = get_closest_ancestor_name(&node, source);
                    if !class_name.is_empty()
                        && language == "go"
                        && !is_first_letter_uppercase(&class_name)
                    {
                        continue;
                    }
                    if class_name.is_empty() {
                        continue;
                    }
                    if !name.is_empty() && language == "go" && !is_first_letter_uppercase(name) {
                        continue;
                    }
                    ensure_class_def(&class_name, &mut class_def_map);
                    let class_def = class_def_map.get_mut(&class_name).unwrap();
                    let variable = Variable {
                        name: name.to_string(),
                        value_type: value_type.to_string(),
                    };
                    class_def.borrow_mut().properties.push(variable);
                }
                "function" | "arrow_function" => {
                    let visibility_modifier_node =
                        find_descendant_by_type(&node, "visibility_modifier");
                    let visibility_modifier = visibility_modifier_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    if language == "rust" && !visibility_modifier.contains("pub") {
                        continue;
                    }
                    if !name.is_empty() && language == "go" && !is_first_letter_uppercase(name) {
                        continue;
                    }
                    let impl_item_node = find_ancestor_by_type(&node, "impl_item");
                    if impl_item_node.is_some() {
                        continue;
                    }
                    let function_node = find_ancestor_by_type(&node, "function_declaration")
                        .or_else(|| find_ancestor_by_type(&node, "function_definition"));
                    if function_node.is_some() {
                        continue;
                    }
                    let params_node = node.child_by_field_name("parameters");
                    let params = params_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("()");
                    let mut return_type_node = node.child_by_field_name("return_type");
                    if return_type_node.is_none() {
                        return_type_node = node.child_by_field_name("result");
                    }
                    let mut return_type = "void".to_string();
                    if return_type_node.is_some() {
                        return_type = get_node_type(&return_type_node.unwrap(), source.as_bytes());
                        if return_type.is_empty() {
                            return_type = return_type_node
                                .unwrap()
                                .utf8_text(source.as_bytes())
                                .unwrap_or("void")
                                .to_string();
                        }
                    }

                    let accessibility_modifier_node =
                        find_descendant_by_type(&node, "accessibility_modifier");
                    let accessibility_modifier = accessibility_modifier_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");

                    let func = Func {
                        name: name.to_string(),
                        params: params.to_string(),
                        return_type: return_type.to_string(),
                        accessibility_modifier: if accessibility_modifier.is_empty() {
                            None
                        } else {
                            Some(accessibility_modifier.to_string())
                        },
                    };
                    definitions.push(Definition::Func(func));
                }
                "assignment" => {
                    let visibility_modifier_node =
                        find_descendant_by_type(&node, "visibility_modifier");
                    let visibility_modifier = visibility_modifier_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    if language == "rust" && !visibility_modifier.contains("pub") {
                        continue;
                    }
                    let impl_item_node = find_ancestor_by_type(&node, "impl_item")
                        .or_else(|| find_ancestor_by_type(&node, "class_declaration"))
                        .or_else(|| find_ancestor_by_type(&node, "class_definition"));
                    if impl_item_node.is_some() {
                        continue;
                    }
                    let function_node = find_ancestor_by_type(&node, "function_declaration")
                        .or_else(|| find_ancestor_by_type(&node, "function_definition"));
                    if function_node.is_some() {
                        continue;
                    }
                    let left_node = node.child_by_field_name("left");
                    let left = left_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    if !left.is_empty() && language == "go" && !is_first_letter_uppercase(left) {
                        continue;
                    }

                    let value_type = get_node_type(&node, source.as_bytes());
                    let variable = Variable {
                        name: left.to_string(),
                        value_type: value_type.to_string(),
                    };
                    definitions.push(Definition::Variable(variable));
                }
                "variable" => {
                    let visibility_modifier_node =
                        find_descendant_by_type(&node, "visibility_modifier");
                    let visibility_modifier = visibility_modifier_node
                        .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                        .unwrap_or("");
                    if language == "rust" && !visibility_modifier.contains("pub") {
                        continue;
                    }
                    let impl_item_node = find_ancestor_by_type(&node, "impl_item")
                        .or_else(|| find_ancestor_by_type(&node, "class_declaration"))
                        .or_else(|| find_ancestor_by_type(&node, "class_definition"));
                    if impl_item_node.is_some() {
                        continue;
                    }
                    let function_node = find_ancestor_by_type(&node, "function_declaration")
                        .or_else(|| find_ancestor_by_type(&node, "function_definition"));
                    if function_node.is_some() {
                        continue;
                    }
                    let value_node = node.child_by_field_name("value");
                    if value_node.is_some() {
                        let value_type = value_node.unwrap().kind();
                        if value_type == "arrow_function" {
                            let params_node = value_node.unwrap().child_by_field_name("parameters");
                            let params = params_node
                                .map(|n| n.utf8_text(source.as_bytes()).unwrap())
                                .unwrap_or("()");
                            let mut return_type = "void".to_string();
                            let return_type_node =
                                value_node.unwrap().child_by_field_name("return_type");
                            if return_type_node.is_some() {
                                return_type =
                                    get_node_type(&return_type_node.unwrap(), source.as_bytes());
                            }
                            let func = Func {
                                name: name.to_string(),
                                params: params.to_string(),
                                return_type,
                                accessibility_modifier: None,
                            };
                            definitions.push(Definition::Func(func));
                            continue;
                        }
                    }
                    let value_type = get_node_type(&node, source.as_bytes());
                    if !name.is_empty() && language == "go" && !is_first_letter_uppercase(name) {
                        continue;
                    }
                    let variable = Variable {
                        name: name.to_string(),
                        value_type: value_type.to_string(),
                    };
                    definitions.push(Definition::Variable(variable));
                }
                _ => {}
            }
        }
    }

    for (_, def) in class_def_map {
        let class_def = def.into_inner();
        if language == "rust" {
            if let Some(visibility_modifier) = &class_def.visibility_modifier {
                if visibility_modifier.contains("pub") {
                    definitions.push(Definition::Class(class_def));
                }
            }
        } else {
            definitions.push(Definition::Class(class_def));
        }
    }

    for (_, def) in enum_def_map {
        definitions.push(Definition::Enum(def.into_inner()));
    }

    Ok(definitions)
}

fn stringify_function(func: &Func) -> String {
    let mut res = format!("func {}", func.name);
    if func.params.is_empty() {
        res = format!("{res}()");
    } else {
        res = format!("{res}{}", func.params);
    }
    if !func.return_type.is_empty() {
        res = format!("{res} -> {}", func.return_type);
    }
    if let Some(modifier) = &func.accessibility_modifier {
        res = format!("{modifier} {res}");
    }
    format!("{res};")
}

fn stringify_variable(variable: &Variable) -> String {
    let mut res = format!("var {}", variable.name);
    if !variable.value_type.is_empty() {
        res = format!("{res}:{}", variable.value_type);
    }
    format!("{res};")
}

fn stringify_enum_item(item: &Variable) -> String {
    let mut res = item.name.clone();
    if !item.value_type.is_empty() {
        res = format!("{res}:{}", item.value_type);
    }
    format!("{res};")
}

fn stringify_class(class: &Class) -> String {
    let mut res = format!("class {}{{", class.name);
    for method in &class.methods {
        let method_str = stringify_function(method);
        res = format!("{res}{method_str}");
    }
    for property in &class.properties {
        let property_str = stringify_variable(property);
        res = format!("{res}{property_str}");
    }
    format!("{res}}};")
}

fn stringify_enum(enum_def: &Enum) -> String {
    let mut res = format!("enum {}{{", enum_def.name);
    for item in &enum_def.items {
        let item_str = stringify_enum_item(item);
        res = format!("{res}{item_str}");
    }
    format!("{res}}};")
}

fn stringify_definitions(definitions: &Vec<Definition>) -> String {
    let mut res = String::new();
    for definition in definitions {
        match definition {
            Definition::Class(class) => res = format!("{res}{}", stringify_class(class)),
            Definition::Enum(enum_def) => res = format!("{res}{}", stringify_enum(enum_def)),
            Definition::Func(func) => res = format!("{res}{}", stringify_function(func)),
            Definition::Variable(variable) => {
                let variable_str = stringify_variable(variable);
                res = format!("{res}{variable_str}");
            }
        }
    }
    res
}

pub fn get_definitions_string(language: &str, source: &str) -> LuaResult<String> {
    let definitions =
        extract_definitions(language, source).map_err(|e| LuaError::RuntimeError(e.to_string()))?;
    let stringified = stringify_definitions(&definitions);
    Ok(stringified)
}

#[mlua::lua_module]
fn avante_repo_map(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;
    exports.set(
        "stringify_definitions",
        lua.create_function(move |_, (language, source): (String, String)| {
            get_definitions_string(language.as_str(), source.as_str())
        })?,
    )?;
    Ok(exports)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rust() {
        let source = r#"
        // This is a test comment
        pub const TEST_CONST: u32 = 1;
        pub static TEST_STATIC: u32 = 2;
        const INNER_TEST_CONST: u32 = 3;
        static INNER_TEST_STATIC: u32 = 4;
        pub(crate) struct TestStruct {
            pub test_field: String,
            inner_test_field: String,
        }
        impl TestStruct {
            pub fn test_method(&self, a: u32, b: u32) -> u32 {
                a + b
            }
            fn inner_test_method(&self, a: u32, b: u32) -> u32 {
                a + b
            }
        }
        struct InnerTestStruct {
            pub test_field: String,
            inner_test_field: String,
        }
        impl InnerTestStruct {
            pub fn test_method(&self, a: u32, b: u32) -> u32 {
                a + b
            }
            fn inner_test_method(&self, a: u32, b: u32) -> u32 {
                a + b
            }
        }
        pub enum TestEnum {
            TestEnumField1,
            TestEnumField2,
        }
        enum InnerTestEnum {
            InnerTestEnumField1,
            InnerTestEnumField2,
        }
        pub fn test_fn(a: u32, b: u32) -> u32 {
            let inner_var_in_func = 1;
            struct InnerStructInFunc {
                c: u32,
            }
            a + b + c
        }
        fn inner_test_fn(a: u32, b: u32) -> u32 {
            a + b
        }
        "#;
        let definitions = extract_definitions("rust", source).unwrap();
        let stringified = stringify_definitions(&definitions);
        println!("{stringified}");
        let expected = "var TEST_CONST:u32;var TEST_STATIC:u32;func test_fn(a: u32, b: u32) -> u32;class TestStruct{func test_method(&self, a: u32, b: u32) -> u32;var test_field:String;};";
        assert_eq!(stringified, expected);
    }

    #[test]
    fn test_go() {
        let source = r#"
        // This is a test comment
        package main
        import "fmt"
        const TestConst string = "test"
        const innerTestConst string = "test"
        var TestVar string
        var innerTestVar string
        type TestStruct struct {
            TestField string
            innerTestField string
        }
        func (t *TestStruct) TestMethod(a int, b int) (int, error) {
            var InnerVarInFunc int = 1
            type InnerStructInFunc struct {
                C int
            }
            return a + b, nil
        }
        func (t *TestStruct) innerTestMethod(a int, b int) (int, error) {
            return a + b, nil
        }
        type innerTestStruct struct {
            innerTestField string
        }
        func (t *innerTestStruct) testMethod(a int, b int) (int, error) {
            return a + b, nil
        }
        func (t *innerTestStruct) innerTestMethod(a int, b int) (int, error) {
            return a + b, nil
        }
        func TestFunc(a int, b int) (int, error) {
            return a + b, nil
        }
        func innerTestFunc(a int, b int) (int, error) {
            return a + b, nil
        }
        "#;
        let definitions = extract_definitions("go", source).unwrap();
        let stringified = stringify_definitions(&definitions);
        println!("{stringified}");
        let expected = "var TestConst:string;var TestVar:string;func TestFunc(a int, b int) -> (int, error);class TestStruct{func TestMethod(a int, b int) -> (int, error);var TestField:string;};";
        assert_eq!(stringified, expected);
    }

    #[test]
    fn test_python() {
        let source = r#"
        # This is a test comment
        test_var: str = "test"
        class TestClass:
            def __init__(self, a, b):
                self.a = a
                self.b = b
            def test_method(self, a: int, b: int) -> int:
                inner_var_in_method: int = 1
                return a + b
        def test_func(a: int, b: int) -> int:
            inner_var_in_func: str = "test"
            class InnerClassInFunc:
                def __init__(self, a, b):
                    self.a = a
                    self.b = b
                def test_method(self, a: int, b: int) -> int:
                    return a + b
            def inne_func_in_func(a: int, b: int) -> int:
                return a + b
            return a + b
        "#;
        let definitions = extract_definitions("python", source).unwrap();
        let stringified = stringify_definitions(&definitions);
        println!("{stringified}");
        let expected = "var test_var:str;func test_func(a: int, b: int) -> int;class TestClass{func __init__(self, a, b) -> void;func test_method(self, a: int, b: int) -> int;};";
        assert_eq!(stringified, expected);
    }

    #[test]
    fn test_typescript() {
        let source = r#"
        // This is a test comment
        export const testVar: string = "test";
        const innerTestVar: string = "test";
        export class TestClass {
            a: number;
            b: number;
            constructor(a: number, b: number) {
                this.a = a;
                this.b = b;
            }
            testMethod(a: number, b: number): number {
                const innerConstInMethod: number = 1;
                function innerFuncInMethod(a: number, b: number): number {
                    return a + b;
                }
                return a + b;
            }
        }
        class InnerTestClass {
            a: number;
            b: number;
        }
        export function testFunc(a: number, b: number) {
            const innerConstInFunc: number = 1;
            function innerFuncInFunc(a: number, b: number): number {
                return a + b;
            }
            return a + b;
        }
        export const testFunc2 = (a: number, b: number) => {
            return a + b;
        }
        export const testFunc3 = (a: number, b: number): number => {
            return a + b;
        }
        function innerTestFunc(a: number, b: number) {
            return a + b;
        }
        "#;
        let definitions = extract_definitions("typescript", source).unwrap();
        let stringified = stringify_definitions(&definitions);
        println!("{stringified}");
        let expected = "var testVar:string;func testFunc(a: number, b: number) -> void;func testFunc2(a: number, b: number) -> void;func testFunc3(a: number, b: number) -> number;class TestClass{func constructor(a: number, b: number) -> void;func testMethod(a: number, b: number) -> number;var a:number;var b:number;};"
;
        assert_eq!(stringified, expected);
    }

    #[test]
    fn test_javascript() {
        let source = r#"
        // This is a test comment
        export const testVar = "test";
        const innerTestVar = "test";
        export class TestClass {
            constructor(a, b) {
                this.a = a;
                this.b = b;
            }
            testMethod(a, b) {
                const innerConstInMethod = 1;
                function innerFuncInMethod(a, b) {
                    return a + b;
                }
                return a + b;
            }
        }
        class InnerTestClass {
            constructor(a, b) {
                this.a = a;
                this.b = b;
            }
        }
        export const testFunc = function(a, b) {
            const innerConstInFunc = 1;
            function innerFuncInFunc(a, b) {
                return a + b;
            }
            return a + b;
        }
        export const testFunc2 = (a, b) => {
            return a + b;
        }
        export const testFunc3 = (a, b) => a + b;
        function innerTestFunc(a, b) {
            return a + b;
        }
        "#;
        let definitions = extract_definitions("javascript", source).unwrap();
        let stringified = stringify_definitions(&definitions);
        println!("{stringified}");
        let expected = "var testVar;var testFunc;func testFunc2(a, b) -> void;func testFunc3(a, b) -> void;class TestClass{func constructor(a, b) -> void;func testMethod(a, b) -> void;};";
        assert_eq!(stringified, expected);
    }

    #[test]
    fn test_ruby() {
        let source = r#"
        # This is a test comment
        test_var = "test"
        def test_func(a, b)
            inner_var_in_func = "test"
            class InnerClassInFunc
                attr_accessor :a, :b
                def initialize(a, b)
                    @a = a
                    @b = b
                end
                def test_method(a, b)
                    return a + b
                end
            end
            return a + b
        end
        class TestClass
            attr_accessor :a, :b
            def initialize(a, b)
                @a = a
                @b = b
            end
            def test_method(a, b)
                inner_var_in_method = 1
                def inner_func_in_method(a, b)
                    return a + b
                end
                return a + b
            end
        end
        "#;
        let definitions = extract_definitions("ruby", source).unwrap();
        let stringified = stringify_definitions(&definitions);
        println!("{stringified}");
        // FIXME:
        let expected = "var test_var;func test_func(a, b) -> void;";
        assert_eq!(stringified, expected);
    }

    #[test]
    fn test_lua() {
        let source = r#"
        -- This is a test comment
        local test_var = "test"
        function test_func(a, b)
            local inner_var_in_func = 1
            function inner_func_in_func(a, b)
                return a + b
            end
            return a + b
        end
        "#;
        let definitions = extract_definitions("lua", source).unwrap();
        let stringified = stringify_definitions(&definitions);
        println!("{stringified}");
        let expected = "var test_var;func test_func(a, b) -> void;";
        assert_eq!(stringified, expected);
    }

    #[test]
    fn test_unsupported_language() {
        let source = "print('Hello, world!')";
        let definitions = extract_definitions("unknown", source).unwrap();

        let stringified = stringify_definitions(&definitions);
        println!("{stringified}");
        let expected = "";
        assert_eq!(stringified, expected);
    }
}
