use minijinja::{context, path_loader, Environment};
use mlua::prelude::*;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

struct State<'a> {
    environment: Mutex<Option<Environment<'a>>>,
}

impl State<'_> {
    fn new() -> Self {
        State {
            environment: Mutex::new(None),
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct SelectedCode {
    path: String,
    content: Option<String>,
    file_type: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct SelectedFile {
    path: String,
    content: Option<String>,
    file_type: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct TemplateContext {
    ask: bool,
    code_lang: String,
    selected_files: Option<Vec<SelectedFile>>,
    selected_code: Option<SelectedCode>,
    recently_viewed_files: Option<Vec<String>>,
    relevant_files: Option<Vec<String>>,
    project_context: Option<String>,
    diagnostics: Option<String>,
    system_info: Option<String>,
    model_name: Option<String>,
    memory: Option<String>,
}

// Given the file name registered after add, the context table in Lua, resulted in a formatted
// Lua string
#[allow(clippy::needless_pass_by_value)]
fn render(state: &State, template: &str, context: TemplateContext) -> LuaResult<String> {
    let environment = state.environment.lock().unwrap();
    match environment.as_ref() {
        Some(environment) => {
            let jinja_template = environment
                .get_template(template)
                .map_err(LuaError::external)
                .unwrap();

            Ok(jinja_template
                .render(context! {
                  ask => context.ask,
                  code_lang => context.code_lang,
                  selected_files => context.selected_files,
                  selected_code => context.selected_code,
                  recently_viewed_files => context.recently_viewed_files,
                  relevant_files => context.relevant_files,
                  project_context => context.project_context,
                  diagnostics => context.diagnostics,
                  system_info => context.system_info,
                  model_name => context.model_name,
                  memory => context.memory,
                })
                .map_err(LuaError::external)
                .unwrap())
        }
        None => Err(LuaError::RuntimeError(
            "Environment not initialized".to_string(),
        )),
    }
}

fn initialize(state: &State, directory: String) {
    let mut environment_mutex = state.environment.lock().unwrap();
    // add directory as a base path for base directory template path
    let mut env = Environment::new();
    env.set_loader(path_loader(directory));
    *environment_mutex = Some(env);
}

#[mlua::lua_module]
fn avante_templates(lua: &Lua) -> LuaResult<LuaTable> {
    let core = State::new();
    let state = Arc::new(core);
    let state_clone = Arc::clone(&state);

    let exports = lua.create_table()?;
    exports.set(
        "initialize",
        lua.create_function(move |_, model: String| {
            initialize(&state, model);
            Ok(())
        })?,
    )?;
    exports.set(
        "render",
        lua.create_function_mut(move |lua, (template, context): (String, LuaValue)| {
            let ctx = lua.from_value(context)?;
            render(&state_clone, template.as_str(), ctx)
        })?,
    )?;
    Ok(exports)
}
