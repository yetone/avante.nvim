from __future__ import annotations

import re
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from llama_index.core.schema import BaseNode

PATTERN_URI_PART = re.compile(r"(?P<uri>.+)__part_\d+")
METADATA_KEY_URI = "uri"


def uri_to_path(uri: str) -> Path:
    """Convert URI to path."""
    return Path(uri.replace("file://", ""))


def path_to_uri(file_path: Path) -> str:
    """Convert path to URI."""
    uri = file_path.as_uri()
    if file_path.is_dir():
        uri += "/"
    return uri


def is_local_uri(uri: str) -> bool:
    """Check if the URI is a path URI."""
    return uri.startswith("file://")


def is_remote_uri(uri: str) -> bool:
    """Check if the URI is an HTTPS URI or HTTP URI."""
    return uri.startswith(("https://", "http://"))


def is_path_node(node: BaseNode) -> bool:
    """Check if the node is a file node."""
    uri = get_node_uri(node)
    if not uri:
        return False
    return is_local_uri(uri)


def get_node_uri(node: BaseNode) -> str | None:
    """Get URI from node metadata."""
    uri = node.metadata.get(METADATA_KEY_URI)
    if not uri:
        doc_id = getattr(node, "doc_id", None)
        if doc_id:
            match = PATTERN_URI_PART.match(doc_id)
            uri = match.group("uri") if match else doc_id
    if uri:
        if uri.startswith("/"):
            uri = f"file://{uri}"
        return uri
    return None


def inject_uri_to_node(node: BaseNode) -> None:
    """Inject file path into node metadata."""
    if METADATA_KEY_URI in node.metadata:
        return
    uri = get_node_uri(node)
    if uri:
        node.metadata[METADATA_KEY_URI] = uri
