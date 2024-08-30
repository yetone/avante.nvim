use mlua::prelude::*;

fn encode(l: &Lua, text: String) -> LuaResult<(Vec<usize>, usize, usize)> {}

#[mlua::lua_module]
pub fn avante_tokenizer(lua: &Lua) -> LuaResult<LuaTable> {
    let module = lua.create_table()?;
    module.set("encode", lua.create_function(encode)?)?;
    Ok(module)
}
