use htmd::HtmlToMarkdown;
use mlua::prelude::*;
use std::error::Error;

#[derive(Debug)]
enum MyError {
    HtmlToMd(String),
    Request(String),
}

impl std::fmt::Display for MyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MyError::HtmlToMd(e) => write!(f, "HTML to Markdown error: {e}"),
            MyError::Request(e) => write!(f, "Request error: {e}"),
        }
    }
}

impl Error for MyError {}

fn do_html2md(html: &str) -> Result<String, MyError> {
    let converter = HtmlToMarkdown::builder()
        .skip_tags(vec!["script", "style", "header", "footer"])
        .build();
    let md = converter
        .convert(html)
        .map_err(|e| MyError::HtmlToMd(e.to_string()))?;
    Ok(md)
}

fn do_fetch_md(url: &str) -> Result<String, MyError> {
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert(
        reqwest::header::USER_AGENT,
        reqwest::header::HeaderValue::from_static("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36"),
    );
    let client = reqwest::blocking::Client::builder()
        .default_headers(headers)
        .build()
        .map_err(|e| MyError::Request(e.to_string()))?;
    let response = client
        .get(url)
        .send()
        .map_err(|e| MyError::Request(e.to_string()))?;
    let body = response
        .text()
        .map_err(|e| MyError::Request(e.to_string()))?;
    let html = body.trim().to_string();
    let md = do_html2md(&html)?;
    Ok(md)
}

#[mlua::lua_module]
fn avante_html2md(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;
    exports.set(
        "fetch_md",
        lua.create_function(move |_, url: String| -> LuaResult<String> {
            do_fetch_md(&url).map_err(|e| mlua::Error::RuntimeError(e.to_string()))
        })?,
    )?;
    exports.set(
        "html2md",
        lua.create_function(move |_, html: String| -> LuaResult<String> {
            do_html2md(&html).map_err(|e| mlua::Error::RuntimeError(e.to_string()))
        })?,
    )?;
    Ok(exports)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fetch_md() {
        let md = do_fetch_md("https://github.com/yetone/avante.nvim").unwrap();
        println!("{md}");
    }
}
