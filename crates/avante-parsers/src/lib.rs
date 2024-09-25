use std::error::Error;

use http_body_util::Empty;
use hyper::body::Bytes;
use hyper::Uri;
use hyper::{body::HttpBody, client::conn::http1, Body, Request, Response};
use hyper_util::rt::TokioIo;
use mlua::prelude::*;
use scraper::{Html, Selector};
use std::error::Error;
use tokio;
use tokio::io::{self, AsyncWriteExt};
use tokio::net::TcpStream;

async fn fetch_html(uri: &str) -> Result<String, Box<dyn Error + Send + Sync>> {
    let url = uri.clone().parse::<Uri>();
    let host = url.host().expect("uri has no host");
    let port = url.port_u16().unwrap_or(80);
    let address = format!("{}:{}", host, port);

    // Open a TCP connection to the remote host
    let stream = TcpStream::connect(address).await?;

    let io = TokioIo::new(stream);

    // Create the Hyper client
    let (mut sender, conn) = http1::handshake(io).await?;

    // Spawn a task to poll the connection, driving the HTTP state
    tokio::task::spawn(async move {
        if let Err(err) = conn.await {
            println!("Connection failed: {:?}", err);
        }
    });
    // The authority of our URL will be the hostname of the httpbin remote
    let authority = url.authority().unwrap().clone();

    // Create an HTTP request with an empty body and a HOST header
    let req = Request::builder()
        .uri(url)
        .method("GET")
        .header(hyper::header::HOST, authority.as_str())
        .body(Body::empty())?;

    // Await the response...
    let mut res = sender.send_request(req).await?;

    // Stream the body, concat each chunk into a single String (instead of buffering and printing at the end).
    let mut body = String::new();
    while let Some(chunk) = res.frame().await? {
        let frame = chunk?;
        if let Some(chunk) = frame.data_ref() {
            body.push_str(&String::from_utf8_lossy(&chunk));
        }
    }

    Ok(body)
}

async fn parse_html(lua: &Lua, html: &str) -> LuaResult<LuaTable> {
    let document = Html::parse_document(html);
    let selector = Selector::parse("p").unwrap();
    let mut markdown = String::new();

    for element in document.select(&selector) {
        let text = element.text().collect::<Vec<_>>().join(" ");
        markdown.push_str(&format!("- {}\n", text.trim()));
    }

    let table = lua.create_table()?;
    table.set("markdown", markdown)?;
    Ok(table)
}
