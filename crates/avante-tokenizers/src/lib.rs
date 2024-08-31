use mlua::prelude::*;

fn encode(l: &Lua, text: String) -> LuaResult<(Vec<usize>, usize, usize)> {}
fn from_pretrained(l: &Lua, model: String) -> LuaResult<LuaTable> {}

#[mlua::lua_module]
pub fn avante_tokenizer(lua: &Lua) -> LuaResult<LuaTable> {
    let module = lua.create_table()?;
    module.set("encode", lua.create_function(encode)?)?;
    module.set("from_pretrained", lua.create_function(from_pretrained)?)?;
    Ok(module)
}
