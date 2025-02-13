"""RAG Service API for managing document indexing and retrieval."""  # noqa: INP001

from __future__ import annotations

import asyncio
import json
import logging
import multiprocessing
import os
import re
import sqlite3
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING, Any
from urllib.parse import urljoin, urlparse

import chromadb
import httpx
import pathspec
from fastapi import BackgroundTasks, FastAPI, HTTPException
from llama_index.core import (
    Settings,
    SimpleDirectoryReader,
    StorageContext,
    VectorStoreIndex,
    load_index_from_storage,
)
from llama_index.core.node_parser import CodeSplitter
from llama_index.core.schema import Document
from llama_index.embeddings.openai import OpenAIEmbedding
from llama_index.vector_stores.chroma import ChromaVectorStore
from markdownify import markdownify as md
from pydantic import BaseModel, Field
from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

if TYPE_CHECKING:
    from collections.abc import Generator

    from llama_index.core.schema import BaseNode, NodeWithScore, QueryBundle
    from watchdog.observers.api import BaseObserver

app = FastAPI(
    title="RAG Service API",
    description="""
    RAG (Retrieval-Augmented Generation) Service API for managing document indexing and retrieval.

    ## Features
    * Add resources for document watching and indexing
    * Remove watched resources
    * Retrieve relevant information from indexed resources
    * Monitor indexing status
    """,
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Constants
SIMILARITY_THRESHOLD = 0.95
MAX_SAMPLE_SIZE = 100
BATCH_PROCESSING_DELAY = 1
METADATA_KEY_URI = "uri"

# Configuration
BASE_DATA_DIR = Path(os.environ.get("DATA_DIR", "data"))
CHROMA_PERSIST_DIR = BASE_DATA_DIR / "chroma_db"
LOG_DIR = BASE_DATA_DIR / "logs"
DB_FILE = BASE_DATA_DIR / "sqlite" / "indexing_history.db"
# number of cpu cores to use for parallel processing
MAX_WORKERS = multiprocessing.cpu_count()
BATCH_SIZE = 40  # Number of documents to process per batch

# SQLite table schemas
CREATE_TABLES_SQL = """
CREATE TABLE IF NOT EXISTS indexing_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uri TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    error_message TEXT,
    document_id TEXT,
    metadata TEXT
);

CREATE INDEX IF NOT EXISTS idx_uri ON indexing_history(uri);
CREATE INDEX IF NOT EXISTS idx_document_id ON indexing_history(document_id);
CREATE INDEX IF NOT EXISTS idx_content_hash ON indexing_history(content_hash);
CREATE INDEX IF NOT EXISTS idx_status ON indexing_history(status);
"""

# Configure directories
BASE_DATA_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)
DB_FILE.parent.mkdir(parents=True, exist_ok=True)  # Create sqlite directory
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(
            LOG_DIR / f"rag_service_{datetime.now().astimezone().strftime('%Y%m%d')}.log",
        ),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)
CHROMA_PERSIST_DIR.mkdir(parents=True, exist_ok=True)

logger.info("data dir: %s", BASE_DATA_DIR.resolve())

# Global variables
watched_resources: dict[str, BaseObserver] = {}  # Directory path -> Observer instance mapping
file_last_modified: dict[Path, float] = {}  # File path -> Last modified time mapping
index_lock = threading.Lock()

code_ext_map = {
    ".py": "python",
    ".js": "javascript",
    ".ts": "typescript",
    ".jsx": "javascript",
    ".tsx": "typescript",
    ".vue": "vue",
    ".go": "go",
    ".java": "java",
    ".cpp": "cpp",
    ".c": "c",
    ".h": "cpp",
    ".rs": "rust",
    ".rb": "ruby",
    ".php": "php",
    ".scala": "scala",
    ".kt": "kotlin",
    ".swift": "swift",
    ".lua": "lua",
    ".pl": "perl",
    ".pm": "perl",
    ".t": "perl",
    ".pm6": "perl",
    ".m": "perl",
}

required_exts = [
    ".txt",
    ".pdf",
    ".docx",
    ".xlsx",
    ".pptx",
    ".rst",
    ".json",
    ".ini",
    ".conf",
    ".toml",
    ".md",
    ".markdown",
    ".csv",
    ".tsv",
    ".html",
    ".htm",
    ".xml",
    ".yaml",
    ".yml",
    ".css",
    ".scss",
    ".less",
    ".sass",
    ".styl",
    ".sh",
    ".bash",
    ".zsh",
    ".fish",
    ".rb",
    ".java",
    ".go",
    ".ts",
    ".tsx",
    ".js",
    ".jsx",
    ".vue",
    ".py",
    ".php",
    ".c",
    ".cpp",
    ".h",
    ".rs",
    ".swift",
    ".kt",
    ".lua",
    ".perl",
    ".pl",
    ".pm",
    ".t",
    ".pm6",
    ".m",
]


http_headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36",
}


def is_https_resource_exists(url: str) -> bool:
    """Check if a URL exists."""
    try:
        response = httpx.head(url, headers=http_headers)
        return response.status_code == httpx.codes.OK
    except (OSError, ValueError, RuntimeError) as e:
        logger.error("Error checking if URL exists %s: %s", url, e)
        return False


def fetch_markdown(url: str) -> str:
    """Fetch markdown content from a URL."""
    try:
        logger.info("Fetching markdown content from %s", url)
        response = httpx.get(url, headers=http_headers)
        if response.status_code == httpx.codes.OK:
            return md(response.text)
        return ""
    except (OSError, ValueError, RuntimeError) as e:
        logger.error("Error fetching markdown content %s: %s", url, e)
        return ""


def markdown_to_links(base_url: str, markdown: str) -> list[str]:
    """Extract links from markdown content."""
    links = []
    seek = {base_url}
    parsed_url = urlparse(base_url)
    domain = parsed_url.netloc
    scheme = parsed_url.scheme
    for match in re.finditer(r"\[(.*?)\]\((.*?)\)", markdown):
        url = match.group(2)
        if not url.startswith(scheme):
            url = urljoin(base_url, url)
        if urlparse(url).netloc != domain:
            continue
        if url in seek:
            continue
        seek.add(url)
        links.append(url)
    return links


@contextmanager
def get_db_connection() -> Generator[sqlite3.Connection, None, None]:
    """Get a database connection."""
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def init_db() -> None:
    """Initialize the SQLite database."""
    with get_db_connection() as conn:
        conn.executescript(CREATE_TABLES_SQL)
        conn.commit()


class IndexingHistory(BaseModel):
    """Model for indexing history record."""

    id: int | None = Field(None, description="Record ID")
    uri: str = Field(..., description="URI of the indexed file")
    content_hash: str = Field(..., description="MD5 hash of the file content")
    status: str = Field(..., description="Indexing status (indexing/completed/failed)")
    timestamp: datetime = Field(default_factory=datetime.now, description="Record timestamp")
    error_message: str | None = Field(None, description="Error message if failed")
    document_id: str | None = Field(None, description="Document ID in the index")
    metadata: dict[str, Any] | None = Field(None, description="Additional metadata")


def update_indexing_status(
    doc: Document,
    status: str,
    error_message: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> None:
    """Update the indexing status in the database."""
    content_hash = doc.hash

    # Get URI from metadata if available
    uri = get_node_uri(doc)
    if not uri:
        logger.warning("URI not found for document: %s", doc.doc_id)
        return

    record = IndexingHistory(
        id=None,
        uri=uri,
        content_hash=content_hash,
        status=status,
        error_message=error_message,
        document_id=doc.doc_id,
        metadata=metadata,
    )
    with get_db_connection() as conn:
        # Check if record exists
        existing = conn.execute(
            "SELECT id FROM indexing_history WHERE document_id = ?",
            (doc.doc_id,),
        ).fetchone()

        if existing:
            # Update existing record
            conn.execute(
                """
                UPDATE indexing_history
                SET content_hash = ?, status = ?, error_message = ?, document_id = ?, metadata = ?
                WHERE uri = ?
                """,
                (
                    record.content_hash,
                    record.status,
                    record.error_message,
                    record.document_id,
                    json.dumps(record.metadata) if record.metadata else None,
                    record.uri,
                ),
            )
        else:
            # Insert new record
            conn.execute(
                """
                INSERT INTO indexing_history
                (uri, content_hash, status, error_message, document_id, metadata)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    record.uri,
                    record.content_hash,
                    record.status,
                    record.error_message,
                    record.document_id,
                    json.dumps(record.metadata) if record.metadata else None,
                ),
            )
        conn.commit()


def get_indexing_status(doc: Document | None = None, base_uri: str | None = None) -> list[IndexingHistory]:
    """Get indexing status from the database."""
    with get_db_connection() as conn:
        if doc:
            uri = get_node_uri(doc)
            if not uri:
                logger.warning("URI not found for document: %s", doc.doc_id)
                return []
            content_hash = doc.hash
            # For a specific file, get its latest status
            query = """
                SELECT *
                FROM indexing_history
                WHERE uri = ? and content_hash = ?
                ORDER BY timestamp DESC LIMIT 1
            """
            params = (uri, content_hash)
        elif base_uri:
            # For files in a specific directory, get their latest status
            query = """
                WITH RankedHistory AS (
                    SELECT *,
                           ROW_NUMBER() OVER (PARTITION BY document_id ORDER BY timestamp DESC) as rn
                    FROM indexing_history
                    WHERE uri LIKE ? || '%'
                )
                SELECT id, uri, content_hash, status, timestamp, error_message, document_id, metadata
                FROM RankedHistory
                WHERE rn = 1
                ORDER BY timestamp DESC
            """
            params = (base_uri,) if base_uri.endswith(os.path.sep) else (base_uri + os.path.sep,)
        else:
            # For all files, get their latest status
            query = """
                WITH RankedHistory AS (
                    SELECT *,
                           ROW_NUMBER() OVER (PARTITION BY uri ORDER BY timestamp DESC) as rn
                    FROM indexing_history
                )
                SELECT id, uri, content_hash, status, timestamp, error_message, document_id, metadata
                FROM RankedHistory
                WHERE rn = 1
                ORDER BY timestamp DESC
            """
            params = ()

        rows = conn.execute(query, params).fetchall()

        result = []
        for row in rows:
            row_dict = dict(row)
            # Parse metadata JSON if it exists
            if row_dict.get("metadata"):
                try:
                    row_dict["metadata"] = json.loads(row_dict["metadata"])
                except json.JSONDecodeError:
                    row_dict["metadata"] = None
            # Parse timestamp string to datetime if needed
            if isinstance(row_dict.get("timestamp"), str):
                row_dict["timestamp"] = datetime.fromisoformat(
                    row_dict["timestamp"].replace("Z", "+00:00"),
                )
            result.append(IndexingHistory(**row_dict))

        return result


# Initialize database
init_db()

# Initialize ChromaDB and LlamaIndex services
chroma_client = chromadb.PersistentClient(path=str(CHROMA_PERSIST_DIR))
chroma_collection = chroma_client.get_or_create_collection("documents")
vector_store = ChromaVectorStore(chroma_collection=chroma_collection)
storage_context = StorageContext.from_defaults(vector_store=vector_store)
embed_model = OpenAIEmbedding()
Settings.embed_model = embed_model

PATTERN_URI_PART = re.compile(r"(?P<uri>.+)__part_\d+")


def uri_to_path(uri: str) -> Path:
    """Convert URI to path."""
    return Path(uri.replace("path://", ""))


def path_to_uri(file_path: Path) -> str:
    """Convert path to URI."""
    return f"path://{file_path}"


def is_path_uri(uri: str) -> bool:
    """Check if the URI is a path URI."""
    return uri.startswith("path://")


def is_https_uri(uri: str) -> bool:
    """Check if the URI is an HTTPS URI."""
    return uri.startswith("https://")


def is_path_node(node: BaseNode) -> bool:
    """Check if the node is a file node."""
    uri = get_node_uri(node)
    if not uri:
        return False
    return is_path_uri(uri)


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
            uri = f"path://{uri}"
        return uri
    return None


def inject_uri_to_node(node: BaseNode) -> None:
    """Inject file path into node metadata."""
    if METADATA_KEY_URI in node.metadata:
        return
    uri = get_node_uri(node)
    if uri:
        node.metadata[METADATA_KEY_URI] = uri


try:
    index = load_index_from_storage(storage_context)
except (OSError, ValueError) as e:
    logger.error("Failed to load index from storage: %s", e)
    index = VectorStoreIndex([], storage_context=storage_context)


class ResourceRequest(BaseModel):
    """Request model for resource operations."""

    uri: str = Field(..., description="URI of the resource to watch and index")


class SourceDocument(BaseModel):
    """Model for source document information."""

    uri: str = Field(..., description="URI of the source")
    content: str = Field(..., description="Content snippet from the document")
    score: float | None = Field(None, description="Relevance score of the document")


class RetrieveRequest(BaseModel):
    """Request model for information retrieval."""

    query: str = Field(..., description="The query text to search for in the indexed documents")
    base_uri: str = Field(..., description="The base URI to search in")
    top_k: int | None = Field(5, description="Number of top results to return", ge=1, le=20)


class RetrieveResponse(BaseModel):
    """Response model for information retrieval."""

    response: str = Field(..., description="Generated response to the query")
    sources: list[SourceDocument] = Field(..., description="List of source documents used")


class FileSystemHandler(FileSystemEventHandler):
    """Handler for file system events."""

    def __init__(self, directory: Path) -> None:
        """Initialize the handler."""
        self.directory = directory

    def on_modified(self: FileSystemHandler, event: FileSystemEvent) -> None:
        """Handle file modification events."""
        if not event.is_directory and not str(event.src_path).endswith(".tmp"):
            self.handle_file_change(Path(str(event.src_path)))

    def on_created(self: FileSystemHandler, event: FileSystemEvent) -> None:
        """Handle file creation events."""
        if not event.is_directory and not str(event.src_path).endswith(".tmp"):
            self.handle_file_change(Path(str(event.src_path)))

    def handle_file_change(self: FileSystemHandler, file_path: Path) -> None:
        """Handle changes to a file."""
        current_time = time.time()

        if Path(file_path).is_absolute():
            file_path = Path(file_path).relative_to(self.directory)

        # Check if the file was recently processed
        if file_path in file_last_modified and current_time - file_last_modified[file_path] < BATCH_PROCESSING_DELAY:
            return

        file_last_modified[file_path] = current_time
        threading.Thread(target=update_index_for_file, args=(self.directory, file_path)).start()


def is_valid_text(text: str) -> bool:
    """Check if the text is valid and readable."""
    if not text:
        logger.debug("Text content is empty")
        return False

    # Check if the text mainly contains printable characters
    printable_ratio = sum(1 for c in text if c.isprintable() or c in "\n\r\t") / len(text)
    if printable_ratio <= SIMILARITY_THRESHOLD:
        logger.debug("Printable character ratio too low: %.2f%%", printable_ratio * 100)
        # Output a small sample for analysis
        sample = text[:MAX_SAMPLE_SIZE] if len(text) > MAX_SAMPLE_SIZE else text
        logger.debug("Text sample: %r", sample)
    return printable_ratio > SIMILARITY_THRESHOLD


def clean_text(text: str) -> str:
    """Clean text content by removing non-printable characters."""
    return "".join(char for char in text if char.isprintable() or char in "\n\r\t")


def process_document_batch(documents: list[Document]) -> bool:  # noqa: PLR0915, C901, PLR0912, RUF100
    """Process a batch of documents for embedding."""
    try:
        # Filter out invalid and already processed documents
        valid_documents = []
        invalid_documents = []
        for doc in documents:
            doc_id = doc.doc_id

            # Check if document with same hash has already been successfully processed
            status_records = get_indexing_status(doc=doc)
            if status_records and status_records[0].status == "completed":
                logger.info("Document with same hash already processed, skipping: %s", doc.doc_id)
                continue

            try:
                content = doc.get_content()

                # If content is bytes type, try to decode
                if isinstance(content, bytes):
                    try:
                        content = content.decode("utf-8", errors="replace")
                    except (UnicodeDecodeError, OSError) as e:
                        error_msg = f"Unable to decode document content: {doc_id}, error: {e!s}"
                        logger.warning(error_msg)
                        update_indexing_status(doc, "failed", error_message=error_msg)
                        invalid_documents.append(doc_id)
                        continue

                # Ensure content is string type
                content = str(content)

                if not is_valid_text(content):
                    error_msg = f"Invalid document content: {doc_id}"
                    logger.warning(error_msg)
                    update_indexing_status(doc, "failed", error_message=error_msg)
                    invalid_documents.append(doc_id)
                    continue

                # Create new document object with cleaned content
                from llama_index.core.schema import Document

                cleaned_content = clean_text(content)
                metadata = getattr(doc, "metadata", {}).copy()

                new_doc = Document(
                    text=cleaned_content,
                    doc_id=doc_id,
                    metadata=metadata,
                )
                inject_uri_to_node(new_doc)
                valid_documents.append(new_doc)
                # Update status to indexing for valid documents
                update_indexing_status(doc, "indexing")

            except OSError as e:
                error_msg = f"Document processing failed: {doc_id}, error: {e!s}"
                logger.exception(error_msg)
                update_indexing_status(doc, "failed", error_message=error_msg)
                invalid_documents.append(doc_id)

        try:
            if valid_documents:
                with index_lock:
                    index.refresh_ref_docs(valid_documents)

            # Update status to completed for successfully processed documents
            for doc in valid_documents:
                update_indexing_status(
                    doc,
                    "completed",
                    metadata=doc.metadata,
                )

            return not invalid_documents

        except OSError as e:
            error_msg = f"Batch indexing failed: {e!s}"
            logger.exception(error_msg)
            # Update status to failed for all documents in the batch
            for doc in valid_documents:
                update_indexing_status(doc, "failed", error_message=error_msg)
            return False

    except OSError as e:
        error_msg = f"Batch processing failed: {e!s}"
        logger.exception(error_msg)
        # Update status to failed for all documents in the batch
        for doc in documents:
            update_indexing_status(doc, "failed", error_message=error_msg)
        return False


def get_pathspec(directory: Path) -> pathspec.PathSpec | None:
    """Get pathspec for the directory."""
    gitignore_path = directory / ".gitignore"
    if not gitignore_path.exists():
        return None

    # Read gitignore patterns
    with gitignore_path.open("r", encoding="utf-8") as f:
        return pathspec.GitIgnoreSpec.from_lines([*f.readlines(), ".git/"])


def scan_directory(directory: Path) -> list[str]:
    """Scan directory and return a list of matched files."""
    spec = get_pathspec(directory)

    matched_files = []

    for root, _, files in os.walk(directory):
        file_paths = [str(Path(root) / file) for file in files]
        if not spec:
            matched_files.extend(file_paths)
            continue
        matched_files.extend([file for file in file_paths if not spec.match_file(file)])

    return matched_files


def update_index_for_file(directory: Path, file_path: Path) -> None:
    """Update the index for a single file."""
    logger.info("Starting to index file: %s", file_path)

    spec = get_pathspec(directory)
    if spec and spec.match_file(file_path):
        logger.info("File is ignored, skipping: %s", file_path)
        return

    documents = SimpleDirectoryReader(
        input_files=[file_path],
        filename_as_id=True,
        required_exts=required_exts,
    ).load_data()

    logger.info("Updating index: %s", file_path)
    processed_documents = split_documents(documents)
    success = process_document_batch(processed_documents)

    if success:
        logger.info("File indexing completed: %s", file_path)
    else:
        logger.error("File indexing failed: %s", file_path)


def split_documents(documents: list[Document]) -> list[Document]:
    """Split documents into code and non-code documents."""
    # Create file parser configuration
    # Initialize CodeSplitter
    code_splitter = CodeSplitter(
        language="python",  # Default is python, will auto-detect based on file extension
        chunk_lines=40,  # Maximum number of lines per code block
        chunk_lines_overlap=15,  # Number of overlapping lines to maintain context
        max_chars=1500,  # Maximum number of characters per block
    )
    # Split code documents using CodeSplitter
    processed_documents = []
    for doc in documents:
        uri = get_node_uri(doc)
        if not uri:
            continue
        if not is_path_node(doc):
            processed_documents.append(doc)
            continue
        file_path = uri_to_path(uri)
        file_ext = file_path.suffix.lower()
        if file_ext in code_ext_map:
            # Apply CodeSplitter to code files
            code_splitter.language = code_ext_map.get(file_ext, "python")

            try:
                texts = code_splitter.split_text(doc.get_content())
            except ValueError as e:
                logger.error("Error splitting document: %s, so skipping split, error: %s", doc.doc_id, str(e))
                processed_documents.append(doc)
                continue

            for i, text in enumerate(texts):
                from llama_index.core.schema import Document

                new_doc = Document(
                    text=text,
                    doc_id=f"{doc.doc_id}__part_{i}",
                    metadata={
                        **doc.metadata,
                        "chunk_number": i,
                        "total_chunks": len(texts),
                        "language": code_splitter.language,
                    },
                )
                processed_documents.append(new_doc)
        else:
            # Add non-code files directly
            processed_documents.append(doc)
    return processed_documents


async def index_https_resource_async(url: str) -> None:
    """Asynchronously index a HTTPS resource."""
    try:
        logger.info("Loading resource content: %s", url)

        # Fetch markdown content
        markdown = fetch_markdown(url)

        link_md_pairs = [(url, markdown)]

        # Extract links from markdown
        links = markdown_to_links(url, markdown)

        logger.info("Found %d sub links", len(links))
        logger.debug("Link list: %s", links)

        # Use thread pool for parallel batch processing
        loop = asyncio.get_event_loop()
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            mds: list[str] = await loop.run_in_executor(
                executor,
                lambda: list(executor.map(fetch_markdown, links)),
            )

        zipped = zip(links, mds, strict=True)  # pyright: ignore
        link_md_pairs.extend(zipped)

        # Create documents from links
        documents = [Document(text=markdown, doc_id=link) for link, markdown in link_md_pairs]

        logger.info("Found %d documents", len(documents))
        logger.debug("Document list: %s", [doc.doc_id for doc in documents])

        # Process documents in batches
        total_documents = len(documents)
        batches = [documents[i : i + BATCH_SIZE] for i in range(0, total_documents, BATCH_SIZE)]
        logger.info("Splitting documents into %d batches for processing", len(batches))

        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            results = await loop.run_in_executor(
                executor,
                lambda: list(executor.map(process_document_batch, batches)),
            )

        # Check processing results
        if all(results):
            logger.info("Resource %s indexing completed", url)
        else:
            failed_batches = len([r for r in results if not r])
            error_msg = f"Some batches failed processing ({failed_batches}/{len(batches)})"
            logger.error(error_msg)

    except OSError as e:
        error_msg = f"Resource indexing failed: {url}"
        logger.exception(error_msg)
        raise e  # noqa: TRY201


async def index_path_resource_async(directory_path: Path) -> None:
    """Asynchronously index a directory."""
    try:
        logger.info("Loading directory content: %s", directory_path)

        from llama_index.core.readers.file.base import SimpleDirectoryReader

        documents = SimpleDirectoryReader(
            input_files=scan_directory(directory_path),
            filename_as_id=True,
            required_exts=required_exts,
        ).load_data()

        processed_documents = split_documents(documents)

        logger.info("Found %d documents", len(processed_documents))
        logger.debug("Document list: %s", [doc.doc_id for doc in processed_documents])

        # Process documents in batches
        total_documents = len(processed_documents)
        batches = [processed_documents[i : i + BATCH_SIZE] for i in range(0, total_documents, BATCH_SIZE)]
        logger.info("Splitting documents into %d batches for processing", len(batches))

        # Use thread pool for parallel batch processing
        loop = asyncio.get_event_loop()
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            results = await loop.run_in_executor(
                executor,
                lambda: list(executor.map(process_document_batch, batches)),
            )

        # Check processing results
        if all(results):
            logger.info("Directory %s indexing completed", directory_path)
        else:
            failed_batches = len([r for r in results if not r])
            error_msg = f"Some batches failed processing ({failed_batches}/{len(batches)})"
            logger.error(error_msg)

    except OSError as e:
        error_msg = f"Directory indexing failed: {directory_path}"
        logger.exception(error_msg)
        raise e  # noqa: TRY201


@app.post(
    "/add_resource",
    response_model="dict[str, str]",
    summary="Add a resource for watching and indexing",
    description="""
    Adds a resource to the watch list and starts indexing all existing documents in it asynchronously.
    """,
    responses={
        200: {"description": "Resource successfully added and indexing started"},
        404: {"description": "Resource not found"},
        400: {"description": "Resource already being watched"},
    },
)
async def add_resource(request: ResourceRequest, background_tasks: BackgroundTasks):  # noqa: D103, ANN201
    if is_path_uri(request.uri):
        directory = uri_to_path(request.uri)
        if not Path(directory).exists():
            raise HTTPException(status_code=404, detail="Directory not found")

        if request.uri in watched_resources:
            raise HTTPException(status_code=400, detail="Directory already being watched")

        # Create observer
        event_handler = FileSystemHandler(directory=directory)
        observer = Observer()
        observer.schedule(event_handler, str(directory), recursive=True)
        observer.start()
        watched_resources[request.uri] = observer

        # Start indexing in the background
        background_tasks.add_task(index_path_resource_async, directory)
    elif is_https_uri(request.uri):
        background_tasks.add_task(index_https_resource_async, request.uri)
    else:
        raise HTTPException(status_code=400, detail=f"Invalid URI: {request.uri}")

    return {
        "status": "success",
        "message": f"Resource {request.uri} added and indexing started in background",
    }


@app.post(
    "/remove_resource",
    response_model="dict[str, str]",
    summary="Remove a watched resource",
    description="Stops watching and indexing the specified resource",
    responses={
        200: {"description": "Resource successfully removed from watch list"},
        404: {"description": "Resource not found in watch list"},
    },
)
async def remove_resource(request: ResourceRequest):  # noqa: D103, ANN201
    if request.uri not in watched_resources:
        raise HTTPException(status_code=404, detail="Resource not being watched")

    # Stop watching
    observer = watched_resources[request.uri]
    observer.stop()
    observer.join()

    del watched_resources[request.uri]
    return {"status": "success", "message": f"Resource {request.uri} removed"}


@app.post(
    "/retrieve",
    response_model=RetrieveResponse,
    summary="Retrieve information from indexed documents",
    description="""
    Performs a semantic search over all indexed documents and returns relevant information.
    The response includes both the answer and the source documents used to generate it.
    """,
    responses={
        200: {"description": "Successfully retrieved information"},
        500: {"description": "Internal server error during retrieval"},
    },
)
async def retrieve(request: RetrieveRequest):  # noqa: D103, ANN201, C901
    if is_path_uri(request.base_uri):
        directory = uri_to_path(request.base_uri)
        # Validate directory exists
        if not directory.exists():
            raise HTTPException(status_code=404, detail=f"Directory not found: {request.base_uri}")

    logger.info(
        "Received retrieval request: %s for base uri: %s",
        request.query,
        request.base_uri,
    )

    # Create a filter function to only include documents from the specified directory
    def filter_documents(node: NodeWithScore) -> bool:
        uri = get_node_uri(node.node)
        if not uri:
            return False
        if is_path_node(node.node):
            file_path = uri_to_path(uri)
            # Check if the file path starts with the specified directory
            file_path = file_path.resolve()
            directory = uri_to_path(request.base_uri).resolve()
            # Check if directory is a parent of file_path
            try:
                file_path.relative_to(directory)
                return True
            except ValueError:
                return False
        base_uri = request.base_uri
        if not base_uri.endswith(os.path.sep):
            base_uri += os.path.sep
        return uri.startswith(base_uri)

    from llama_index.core.postprocessor import MetadataReplacementPostProcessor

    # Create a custom post processor
    class ResourceFilterPostProcessor(MetadataReplacementPostProcessor):
        """Post-processor for filtering nodes based on directory."""

        def __init__(self: ResourceFilterPostProcessor) -> None:
            """Initialize the post-processor."""
            super().__init__(target_metadata_key="filtered")

        def postprocess_nodes(
            self: ResourceFilterPostProcessor,
            nodes: list[NodeWithScore],
            query_bundle: QueryBundle | None = None,  # noqa: ARG002
            query_str: str | None = None,  # noqa: ARG002
        ) -> list[NodeWithScore]:
            """
            Filter nodes based on directory path.

            Args:
            ----
                nodes: The nodes to process
                query_bundle: Optional query bundle for the query
                query_str: Optional query string

            Returns:
            -------
                List of filtered nodes

            """
            return [node for node in nodes if filter_documents(node)]

    # Create query engine with the filter
    query_engine = index.as_query_engine(
        node_postprocessors=[ResourceFilterPostProcessor()],
    )

    logger.info("Executing retrieval query")
    response = query_engine.query(request.query)

    # If no documents were found in the specified directory
    if not response.source_nodes:
        raise HTTPException(
            status_code=404,
            detail=f"No relevant documents found in uri: {request.base_uri}",
        )

    # Process source documents, ensure readable text
    sources = []
    for node in response.source_nodes[: request.top_k]:
        try:
            content = node.node.get_content()

            doc_id = getattr(node.node, "doc_id", "unknown")

            uri = get_node_uri(node.node)

            # Handle byte-type content
            if isinstance(content, bytes):
                try:
                    content = content.decode("utf-8", errors="replace")
                except UnicodeDecodeError as e:
                    logger.warning(
                        "Unable to decode document content: %s, error: %s",
                        uri,
                        str(e),
                    )
                    continue

            # Validate and clean text
            if is_valid_text(str(content)):
                cleaned_content = clean_text(str(content))
                # Add document source information with file path
                doc_info = {
                    "uri": uri,
                    "content": cleaned_content,
                    "score": float(node.score) if hasattr(node, "score") else None,
                }
                sources.append(doc_info)
            else:
                logger.warning("Skipping invalid document content: %s", doc_id)

        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            logger.warning("Error processing source document", exc_info=True)
            continue

    logger.info("Retrieval completed, found %d relevant documents", len(sources))

    # Process response text similarly
    response_text = str(response)
    response_text = "".join(char for char in response_text if char.isprintable() or char in "\n\r\t")

    return {
        "response": response_text,
        "sources": sources,
    }


class IndexingStatusRequest(BaseModel):
    """Request model for indexing status."""

    uri: str = Field(..., description="URI of the resource to get indexing status for")


class IndexingStatusResponse(BaseModel):
    """Model for indexing status response."""

    uri: str = Field(..., description="URI of the resource being monitored")
    is_watched: bool = Field(..., description="Whether the directory is currently being watched")
    files: list[IndexingHistory] = Field(..., description="List of files and their indexing status")
    total_files: int = Field(..., description="Total number of files processed in this directory")
    status_summary: dict[str, int] = Field(
        ...,
        description="Summary of indexing statuses (count by status)",
    )


@app.post(
    "/indexing-status",
    response_model=IndexingStatusResponse,
    summary="Get indexing status for a resource",
    description="""
    Returns the current indexing status for all files in the specified resource, including:
    * Whether the resource is being watched
    * Status of each files in the resource
    """,
    responses={
        200: {"description": "Successfully retrieved indexing status"},
        404: {"description": "Resource not found"},
    },
)
async def get_indexing_status_for_resource(request: IndexingStatusRequest):  # noqa: D103, ANN201
    resource_files = []
    status_counts = {}
    if is_path_uri(request.uri):
        directory = uri_to_path(request.uri).resolve()
        if not Path(directory).exists():
            raise HTTPException(status_code=404, detail=f"Directory not found: {directory}")

    # Get indexing history records for the specific directory
    resource_files = get_indexing_status(base_uri=request.uri)

    logger.info("Found %d files in resource %s", len(resource_files), request.uri)
    for file in resource_files:
        logger.debug("File status: %s - %s", file.uri, file.status)

    # Count files by status
    for file in resource_files:
        status_counts[file.status] = status_counts.get(file.status, 0) + 1

    return IndexingStatusResponse(
        uri=request.uri,
        is_watched=request.uri in watched_resources,
        files=resource_files,
        total_files=len(resource_files),
        status_summary=status_counts,
    )
