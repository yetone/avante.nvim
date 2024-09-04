use mlua::prelude::*;
use std::sync::{Arc, Mutex};
use tiktoken_rs::{get_bpe_from_model, CoreBPE};
use tokenizers::Tokenizer;

struct Tiktoken {
    bpe: CoreBPE,
}

impl Tiktoken {
    fn new(model: &str) -> Self {
        let bpe = get_bpe_from_model(model).unwrap();
        Tiktoken { bpe }
    }

    fn encode(&self, text: &str) -> (Vec<usize>, usize, usize) {
        let tokens = self.bpe.encode_with_special_tokens(text);
        let num_tokens = tokens.len();
        let num_chars = text.chars().count();
        (tokens, num_tokens, num_chars)
    }
}

struct HuggingFaceTokenizer {
    tokenizer: Tokenizer,
}

impl HuggingFaceTokenizer {
    fn new(model: &str) -> Self {
        let tokenizer = Tokenizer::from_pretrained(model, None).unwrap();
        HuggingFaceTokenizer { tokenizer }
    }

    fn encode(&self, text: &str) -> (Vec<usize>, usize, usize) {
        let encoding = self
            .tokenizer
            .encode(text, false)
            .map_err(LuaError::external)
            .unwrap();
        let tokens: Vec<usize> = encoding.get_ids().iter().map(|x| *x as usize).collect();
        let num_tokens = tokens.len();
        let num_chars = encoding.get_offsets().last().unwrap().1;
        (tokens, num_tokens, num_chars)
    }
}

enum TokenizerType {
    Tiktoken(Tiktoken),
    HuggingFace(HuggingFaceTokenizer),
}

struct State {
    tokenizer: Mutex<Option<TokenizerType>>,
}

impl State {
    fn new() -> Self {
        State {
            tokenizer: Mutex::new(None),
        }
    }
}

fn encode(state: &State, text: &str) -> LuaResult<(Vec<usize>, usize, usize)> {
    let tokenizer = state.tokenizer.lock().unwrap();
    match tokenizer.as_ref() {
        Some(TokenizerType::Tiktoken(tokenizer)) => Ok(tokenizer.encode(text)),
        Some(TokenizerType::HuggingFace(tokenizer)) => Ok(tokenizer.encode(text)),
        None => Err(LuaError::RuntimeError(
            "Tokenizer not initialized".to_string(),
        )),
    }
}

fn from_pretrained(state: &State, model: &str) {
    let mut tokenizer_mutex = state.tokenizer.lock().unwrap();
    *tokenizer_mutex = Some(match model {
        "gpt-4o" => TokenizerType::Tiktoken(Tiktoken::new(model)),
        _ => TokenizerType::HuggingFace(HuggingFaceTokenizer::new(model)),
    });
}

#[mlua::lua_module]
fn avante_tokenizers(lua: &Lua) -> LuaResult<LuaTable> {
    let core = State::new();
    let state = Arc::new(core);
    let state_clone = Arc::clone(&state);

    let exports = lua.create_table()?;
    exports.set(
        "from_pretrained",
        lua.create_function(move |_, model: String| {
            from_pretrained(&state, model.as_str());
            Ok(())
        })?,
    )?;
    exports.set(
        "encode",
        lua.create_function(move |_, text: String| encode(&state_clone, text.as_str()))?,
    )?;
    Ok(exports)
}
