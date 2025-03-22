"""RAG Service API for managing document indexing and retrieval."""  # noqa: INP001

from __future__ import annotations

import asyncio
import fcntl
import json
import multiprocessing
import os
import re
import shutil
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import urljoin, urlparse

import chromadb
import httpx
import pathspec
from fastapi import BackgroundTasks, FastAPI, HTTPException
from libs.configs import (
    BASE_DATA_DIR,
    CHROMA_PERSIST_DIR,
)
from libs.db import init_db
from libs.logger import logger
from libs.utils import (
    get_node_uri,
    inject_uri_to_node,
    is_local_uri,
    is_path_node,
    is_remote_uri,
    path_to_uri,
    uri_to_path,
)
from llama_index.core import (
    Settings,
    SimpleDirectoryReader,
    StorageContext,
    VectorStoreIndex,
    load_index_from_storage,
)
from llama_index.core.node_parser import CodeSplitter
from llama_index.core.schema import Document
from llama_index.embeddings.ollama import OllamaEmbedding
from llama_index.embeddings.openai import OpenAIEmbedding
from llama_index.llms.ollama import Ollama
from llama_index.llms.openai import OpenAI
from llama_index.vector_stores.chroma import ChromaVectorStore
from markdownify import markdownify as md
from models.indexing_history import IndexingHistory  # noqa: TC002
from models.resource import Resource
from pydantic import BaseModel, Field
from services.indexing_history import indexing_history_service
from services.resource import resource_service
from tree_sitter_language_pack import SupportedLanguage, get_parser
from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

if TYPE_CHECKING:
    from collections.abc import AsyncGenerator

    from llama_index.core.schema import NodeWithScore, QueryBundle
    from watchdog.observers.api import BaseObserver

# Lock file for leader election
LOCK_FILE = BASE_DATA_DIR / "leader.lock"


def try_acquire_leadership() -> bool:
    """Try to acquire leadership using file lock."""
    try:
        # Ensure the lock file exists
        LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
        LOCK_FILE.touch(exist_ok=True)

        # Try to acquire an exclusive lock
        lock_fd = os.open(str(LOCK_FILE), os.O_RDWR)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

        # Write current process ID to lock file
        os.truncate(lock_fd, 0)
        os.write(lock_fd, str(os.getpid()).encode())

        return True
    except OSError:
        return False


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:  # noqa: ARG001
    """Initialize services on startup."""
    # Try to become leader if no worker_id is set

    is_leader = try_acquire_leadership()

    # Only run initialization in the leader
    if is_leader:
        logger.info("Starting RAG service as leader (PID: %d)...", os.getpid())

        # Get all active resources
        active_resources = [r for r in resource_service.get_all_resources() if r.status == "active"]
        logger.info("Found %d active resources to sync", len(active_resources))

        for resource in active_resources:
            try:
                if is_local_uri(resource.uri):
                    directory = uri_to_path(resource.uri)
                    if not directory.exists():
                        logger.error("Directory not found: %s", directory)
                        resource_service.update_resource_status(resource.uri, "error", f"Directory not found: {directory}")
                        continue

                    # Start file system watcher
                    event_handler = FileSystemHandler(directory=directory)
                    observer = Observer()
                    observer.schedule(event_handler, str(directory), recursive=True)
                    observer.start()
                    watched_resources[resource.uri] = observer

                    # Start indexing
                    await index_local_resource_async(resource)

                elif is_remote_uri(resource.uri):
                    if not is_remote_resource_exists(resource.uri):
                        logger.error("HTTPS resource not found: %s", resource.uri)
                        resource_service.update_resource_status(resource.uri, "error", "remote resource not found")
                        continue

                    # Start indexing
                    await index_remote_resource_async(resource)

                logger.debug("Successfully synced resource: %s", resource.uri)

            except (OSError, ValueError, RuntimeError) as e:
                error_msg = f"Failed to sync resource {resource.uri}: {e}"
                logger.exception(error_msg)
                resource_service.update_resource_status(resource.uri, "error", error_msg)

    yield

    # Cleanup on shutdown (only in leader)
    if is_leader:
        for observer in watched_resources.values():
            observer.stop()
            observer.join()


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
    lifespan=lifespan,
    redoc_url="/redoc",
)

# Constants
SIMILARITY_THRESHOLD = 0.95
MAX_SAMPLE_SIZE = 100
BATCH_PROCESSING_DELAY = 1

# number of cpu cores to use for parallel processing
MAX_WORKERS = multiprocessing.cpu_count()
BATCH_SIZE = 40  # Number of documents to process per batch

logger.info("data dir: %s", BASE_DATA_DIR.resolve())

# Global variables
watched_resources: dict[str, BaseObserver] = {}  # Directory path -> Observer instance mapping
file_last_modified: dict[Path, float] = {}  # File path -> Last modified time mapping
index_lock = threading.Lock()

code_ext_map: dict[str, SupportedLanguage] = {
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


def is_remote_resource_exists(url: str) -> bool:
    """Check if a URL exists."""
    try:
        response = httpx.head(url, headers=http_headers)
        return response.status_code in {httpx.codes.OK, httpx.codes.MOVED_PERMANENTLY, httpx.codes.FOUND}
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


# Initialize database
init_db()

# Initialize ChromaDB and LlamaIndex services
chroma_client = chromadb.PersistentClient(path=str(CHROMA_PERSIST_DIR))

# Check if provider or model has changed
current_provider = os.getenv("RAG_PROVIDER", "openai").lower()
current_embed_model = os.getenv("RAG_EMBED_MODEL", "")
current_llm_model = os.getenv("RAG_LLM_MODEL", "")

# Try to read previous config
config_file = BASE_DATA_DIR / "rag_config.json"
if config_file.exists():
    with Path.open(config_file, "r") as f:
        prev_config = json.load(f)
        if prev_config.get("provider") != current_provider or prev_config.get("embed_model") != current_embed_model:
            # Clear existing data if config changed
            logger.info("Detected config change, clearing existing data...")
            chroma_client.reset()

# Save current config
with Path.open(config_file, "w") as f:
    json.dump({"provider": current_provider, "embed_model": current_embed_model}, f)

chroma_collection = chroma_client.get_or_create_collection("documents")  # pyright: ignore
vector_store = ChromaVectorStore(chroma_collection=chroma_collection)
storage_context = StorageContext.from_defaults(vector_store=vector_store)

# Initialize embedding model based on provider
llm_provider = current_provider
base_url = os.getenv(llm_provider.upper() + "_API_BASE", "")
rag_embed_model = current_embed_model
rag_llm_model = current_llm_model

if llm_provider == "ollama":
    if base_url == "":
        base_url = "http://localhost:11434"
    if rag_embed_model == "":
        rag_embed_model = "nomic-embed-text"
    if rag_llm_model == "":
        rag_llm_model = "llama3"
    embed_model = OllamaEmbedding(model_name=rag_embed_model, base_url=base_url)
    llm_model = Ollama(model=rag_llm_model, base_url=base_url, request_timeout=60.0)
else:
    if base_url == "":
        base_url = "https://api.openai.com/v1"
    if rag_embed_model == "":
        rag_embed_model = "text-embedding-3-small"
    if rag_llm_model == "":
        rag_llm_model = "gpt-4o-mini"
    embed_model = OpenAIEmbedding(model=rag_embed_model, api_base=base_url)
    llm_model = OpenAI(model=rag_llm_model, api_base=base_url)

Settings.embed_model = embed_model
Settings.llm = llm_model


try:
    index = load_index_from_storage(storage_context)
except (OSError, ValueError) as e:
    logger.error("Failed to load index from storage: %s", e)
    index = VectorStoreIndex([], storage_context=storage_context)


class ResourceURIRequest(BaseModel):
    """Request model for resource operations."""

    uri: str = Field(..., description="URI of the resource to watch and index")


class ResourceRequest(ResourceURIRequest):
    """Request model for resource operations."""

    name: str = Field(..., description="Name of the resource to watch and index")


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

    def __init__(self: FileSystemHandler, directory: Path) -> None:
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

        abs_file_path = file_path
        if not Path(abs_file_path).is_absolute():
            abs_file_path = Path(self.directory, file_path)

        # Check if the file was recently processed
        if abs_file_path in file_last_modified and current_time - file_last_modified[abs_file_path] < BATCH_PROCESSING_DELAY:
            return

        file_last_modified[abs_file_path] = current_time
        threading.Thread(target=update_index_for_file, args=(self.directory, abs_file_path)).start()


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
            status_records = indexing_history_service.get_indexing_status(doc=doc)
            if status_records and status_records[0].status == "completed":
                logger.debug("Document with same hash already processed, skipping: %s", doc.doc_id)
                continue

            logger.debug("Processing document: %s", doc.doc_id)
            try:
                content = doc.get_content()

                # If content is bytes type, try to decode
                if isinstance(content, bytes):
                    try:
                        content = content.decode("utf-8", errors="replace")
                    except (UnicodeDecodeError, OSError) as e:
                        error_msg = f"Unable to decode document content: {doc_id}, error: {e!s}"
                        logger.warning(error_msg)
                        indexing_history_service.update_indexing_status(doc, "failed", error_message=error_msg)
                        invalid_documents.append(doc_id)
                        continue

                # Ensure content is string type
                content = str(content)

                if not is_valid_text(content):
                    error_msg = f"Invalid document content: {doc_id}"
                    logger.warning(error_msg)
                    indexing_history_service.update_indexing_status(doc, "failed", error_message=error_msg)
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
                indexing_history_service.update_indexing_status(doc, "indexing")

            except OSError as e:
                error_msg = f"Document processing failed: {doc_id}, error: {e!s}"
                logger.exception(error_msg)
                indexing_history_service.update_indexing_status(doc, "failed", error_message=error_msg)
                invalid_documents.append(doc_id)

        try:
            if valid_documents:
                with index_lock:
                    index.refresh_ref_docs(valid_documents)

            # Update status to completed for successfully processed documents
            for doc in valid_documents:
                indexing_history_service.update_indexing_status(
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
                indexing_history_service.update_indexing_status(doc, "failed", error_message=error_msg)
            return False

    except OSError as e:
        error_msg = f"Batch processing failed: {e!s}"
        logger.exception(error_msg)
        # Update status to failed for all documents in the batch
        for doc in documents:
            indexing_history_service.update_indexing_status(doc, "failed", error_message=error_msg)
        return False


def get_gitignore_files(directory: Path) -> list[str]:
    """Get patterns from .gitignore file."""
    patterns = [".git/"]

    # Check for .gitignore
    gitignore_path = directory / ".gitignore"
    if gitignore_path.exists():
        with gitignore_path.open("r", encoding="utf-8") as f:
            patterns.extend(f.readlines())

    return patterns


def get_gitcrypt_files(directory: Path) -> list[str]:
    """Get patterns of git-crypt encrypted files using git command."""
    git_crypt_patterns = []
    git_executable = shutil.which("git")

    if not git_executable:
        logger.warning("git command not found, git-crypt files will not be excluded")
        return git_crypt_patterns

    try:
        # Find git root directory
        git_root_cmd = subprocess.run(
            [git_executable, "-C", str(directory), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )

        if git_root_cmd.returncode != 0:
            logger.warning("Not a git repository or git command failed: %s", git_root_cmd.stderr.strip())
            return git_crypt_patterns

        git_root = Path(git_root_cmd.stdout.strip())

        # Get relative path from git root to our directory
        rel_path = directory.relative_to(git_root) if directory != git_root else Path()

        # Execute git commands separately and pipe the results
        git_ls_files = subprocess.run(
            [git_executable, "-C", str(git_root), "ls-files", "-z"],
            capture_output=True,
            text=False,
            check=False,
        )

        if git_ls_files.returncode != 0:
            return git_crypt_patterns

        # Use Python to process the output instead of xargs, grep, and cut
        git_check_attr = subprocess.run(
            [git_executable, "-C", str(git_root), "check-attr", "filter", "--stdin", "-z"],
            input=git_ls_files.stdout,
            capture_output=True,
            text=False,
            check=False,
        )

        if git_check_attr.returncode != 0:
            return git_crypt_patterns

        # Process the output in Python to find git-crypt files
        output = git_check_attr.stdout.decode("utf-8")
        lines = output.split("\0")

        for i in range(0, len(lines) - 2, 3):
            if i + 2 < len(lines) and lines[i + 2] == "git-crypt":
                file_path = lines[i]
                # Only include files that are in our directory or subdirectories
                file_path_obj = Path(file_path)
                if str(rel_path) == "." or file_path_obj.is_relative_to(rel_path):
                    git_crypt_patterns.append(file_path)

        # Log if git-crypt patterns were found
        if git_crypt_patterns:
            logger.debug("Excluding git-crypt encrypted files: %s", git_crypt_patterns)
    except (subprocess.SubprocessError, OSError) as e:
        logger.warning("Error getting git-crypt files: %s", str(e))

    return git_crypt_patterns


def get_pathspec(directory: Path) -> pathspec.PathSpec | None:
    """Get pathspec for the directory."""
    # Collect patterns from both sources
    patterns = get_gitignore_files(directory)
    patterns.extend(get_gitcrypt_files(directory))

    # Return None if no patterns were found
    if len(patterns) <= 1:  # Only .git/ is in the list
        return None

    return pathspec.GitIgnoreSpec.from_lines(patterns)


def scan_directory(directory: Path) -> list[str]:
    """Scan directory and return a list of matched files."""
    spec = get_pathspec(directory)

    binary_extensions = [
        # Images
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".bmp",
        ".ico",
        ".webp",
        ".tiff",
        ".exr",
        ".hdr",
        ".svg",
        ".psd",
        ".ai",
        ".eps",
        # Audio/Video
        ".mp3",
        ".wav",
        ".mp4",
        ".avi",
        ".mov",
        ".webm",
        ".flac",
        ".ogg",
        ".m4a",
        ".aac",
        ".wma",
        ".flv",
        ".mkv",
        ".wmv",
        # Documents
        ".pdf",
        ".doc",
        ".docx",
        ".xls",
        ".xlsx",
        ".ppt",
        ".pptx",
        ".odt",
        # Archives
        ".zip",
        ".tar",
        ".gz",
        ".7z",
        ".rar",
        ".iso",
        ".dmg",
        ".pkg",
        ".deb",
        ".rpm",
        ".msi",
        ".apk",
        ".xz",
        ".bz2",
        # Compiled
        ".exe",
        ".dll",
        ".so",
        ".dylib",
        ".class",
        ".pyc",
        ".o",
        ".obj",
        ".lib",
        ".a",
        ".out",
        ".app",
        ".apk",
        ".jar",
        # Fonts
        ".ttf",
        ".otf",
        ".woff",
        ".woff2",
        ".eot",
        # Other binary
        ".bin",
        ".dat",
        ".db",
        ".sqlite",
        ".db",
        ".DS_Store",
    ]

    matched_files = []

    for root, _, files in os.walk(directory):
        file_paths = [str(Path(root) / file) for file in files]
        for file in file_paths:
            file_ext = Path(file).suffix.lower()
            if file_ext in binary_extensions:
                logger.debug("Skipping binary file: %s", file)
                continue

            if spec and spec.match_file(os.path.relpath(file, directory)):
                logger.debug("Ignoring file: %s", file)
            else:
                matched_files.append(file)

    return matched_files


def update_index_for_file(directory: Path, abs_file_path: Path) -> None:
    """Update the index for a single file."""
    logger.debug("Starting to index file: %s", abs_file_path)

    rel_file_path = abs_file_path.relative_to(directory)

    spec = get_pathspec(directory)
    if spec and spec.match_file(rel_file_path):
        logger.debug("File is ignored, skipping: %s", abs_file_path)
        return

    resource = resource_service.get_resource(path_to_uri(directory))
    if not resource:
        logger.error("Resource not found for directory: %s", directory)
        return

    resource_service.update_resource_indexing_status(resource.uri, "indexing", "")

    documents = SimpleDirectoryReader(
        input_files=[abs_file_path],
        filename_as_id=True,
        required_exts=required_exts,
    ).load_data()

    logger.debug("Updating index: %s", abs_file_path)
    processed_documents = split_documents(documents)
    success = process_document_batch(processed_documents)

    if success:
        resource_service.update_resource_indexing_status(resource.uri, "indexed", "")
        logger.debug("File indexing completed: %s", abs_file_path)
    else:
        resource_service.update_resource_indexing_status(resource.uri, "failed", "unknown error")
        logger.error("File indexing failed: %s", abs_file_path)


def split_documents(documents: list[Document]) -> list[Document]:
    """Split documents into code and non-code documents."""
    # Create file parser configuration
    # Initialize CodeSplitter
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
            language = code_ext_map.get(file_ext, "python")
            parser = get_parser(language)
            code_splitter = CodeSplitter(
                language=language,  # Default is python, will auto-detect based on file extension
                chunk_lines=80,  # Maximum number of lines per code block
                chunk_lines_overlap=15,  # Number of overlapping lines to maintain context
                max_chars=1500,  # Maximum number of characters per block
                parser=parser,
            )
            try:
                t = doc.get_content()
                texts = code_splitter.split_text(t)
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
                        "orig_doc_id": doc.doc_id,
                    },
                )
                processed_documents.append(new_doc)
        else:
            doc.metadata["orig_doc_id"] = doc.doc_id
            # Add non-code files directly
            processed_documents.append(doc)
    return processed_documents


async def index_remote_resource_async(resource: Resource) -> None:
    """Asynchronously index a remote resource."""
    resource_service.update_resource_indexing_status(resource.uri, "indexing", "")
    url = resource.uri
    try:
        logger.debug("Loading resource content: %s", url)

        # Fetch markdown content
        markdown = fetch_markdown(url)

        link_md_pairs = [(url, markdown)]

        # Extract links from markdown
        links = markdown_to_links(url, markdown)

        logger.debug("Found %d sub links", len(links))
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

        logger.debug("Found %d documents", len(documents))
        logger.debug("Document list: %s", [doc.doc_id for doc in documents])

        # Process documents in batches
        total_documents = len(documents)
        batches = [documents[i : i + BATCH_SIZE] for i in range(0, total_documents, BATCH_SIZE)]
        logger.debug("Splitting documents into %d batches for processing", len(batches))

        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            results = await loop.run_in_executor(
                executor,
                lambda: list(executor.map(process_document_batch, batches)),
            )

        # Check processing results
        if all(results):
            logger.debug("Resource %s indexing completed", url)
            resource_service.update_resource_indexing_status(resource.uri, "indexed", "")
        else:
            failed_batches = len([r for r in results if not r])
            error_msg = f"Some batches failed processing ({failed_batches}/{len(batches)})"
            logger.error(error_msg)
            resource_service.update_resource_indexing_status(resource.uri, "indexed", error_msg)

    except OSError as e:
        error_msg = f"Resource indexing failed: {url}"
        logger.exception(error_msg)
        resource_service.update_resource_indexing_status(resource.uri, "failed", error_msg)
        raise e  # noqa: TRY201


async def index_local_resource_async(resource: Resource) -> None:
    """Asynchronously index a directory."""
    resource_service.update_resource_indexing_status(resource.uri, "indexing", "")
    directory_path = uri_to_path(resource.uri)
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
            resource_service.update_resource_indexing_status(resource.uri, "indexed", "")
        else:
            failed_batches = len([r for r in results if not r])
            error_msg = f"Some batches failed processing ({failed_batches}/{len(batches)})"
            resource_service.update_resource_indexing_status(resource.uri, "indexed", error_msg)
            logger.error(error_msg)

    except OSError as e:
        error_msg = f"Directory indexing failed: {directory_path}"
        resource_service.update_resource_indexing_status(resource.uri, "failed", error_msg)
        logger.exception(error_msg)
        raise e  # noqa: TRY201


@app.get("/api/v1/readyz")
async def readiness_probe() -> dict[str, str]:
    """Readiness probe endpoint."""
    return {"status": "ok"}


@app.post(
    "/api/v1/add_resource",
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
async def add_resource(request: ResourceRequest, background_tasks: BackgroundTasks):  # noqa: D103, ANN201, C901
    # Check if resource already exists
    resource = resource_service.get_resource(request.uri)
    if resource and resource.status == "active":
        return {
            "status": "success",
            "message": f"Resource {request.uri} added and indexing started in background",
        }

    resource_type = "local"

    async def background_task(resource: Resource) -> None:
        pass

    if is_local_uri(request.uri):
        directory = uri_to_path(request.uri)
        if not directory.exists():
            raise HTTPException(status_code=404, detail=f"Directory not found: {directory}")

        if not directory.is_dir():
            raise HTTPException(status_code=400, detail=f"{directory} is not a directory")

        git_directory = directory / ".git"
        if not git_directory.exists() or not git_directory.is_dir():
            raise HTTPException(status_code=400, detail=f"{git_directory} ia not a git repository")

        # Create observer
        event_handler = FileSystemHandler(directory=directory)
        observer = Observer()
        observer.schedule(event_handler, str(directory), recursive=True)
        observer.start()
        watched_resources[request.uri] = observer

        background_task = index_local_resource_async
    elif is_remote_uri(request.uri):
        if not is_remote_resource_exists(request.uri):
            raise HTTPException(status_code=404, detail="web resource not found")

        resource_type = "remote"

        background_task = index_remote_resource_async
    else:
        raise HTTPException(status_code=400, detail=f"Invalid URI: {request.uri}")

    if resource:
        if resource.name != request.name:
            raise HTTPException(status_code=400, detail=f"Resource name cannot be changed: {resource.name}")

        resource_service.update_resource_status(resource.uri, "active")
    else:
        exists_resource = resource_service.get_resource_by_name(request.name)
        if exists_resource:
            raise HTTPException(status_code=400, detail="Resource with same name already exists")
        # Add to database
        resource = Resource(
            id=None,
            name=request.name,
            uri=request.uri,
            type=resource_type,
            status="active",
            indexing_status="pending",
            indexing_status_message=None,
            indexing_started_at=None,
            last_indexed_at=None,
            last_error=None,
        )
        resource_service.add_resource_to_db(resource)
        background_tasks.add_task(background_task, resource)

    return {
        "status": "success",
        "message": f"Resource {request.uri} added and indexing started in background",
    }


@app.post(
    "/api/v1/remove_resource",
    response_model="dict[str, str]",
    summary="Remove a watched resource",
    description="Stops watching and indexing the specified resource",
    responses={
        200: {"description": "Resource successfully removed from watch list"},
        404: {"description": "Resource not found in watch list"},
    },
)
async def remove_resource(request: ResourceURIRequest):  # noqa: D103, ANN201
    resource = resource_service.get_resource(request.uri)
    if not resource or resource.status != "active":
        raise HTTPException(status_code=404, detail="Resource not being watched")

    if request.uri in watched_resources:
        # Stop watching
        observer = watched_resources[request.uri]
        observer.stop()
        observer.join()
        del watched_resources[request.uri]

    # Update database status
    resource_service.update_resource_status(request.uri, "inactive")

    return {"status": "success", "message": f"Resource {request.uri} removed"}


@app.post(
    "/api/v1/retrieve",
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
async def retrieve(request: RetrieveRequest):  # noqa: D103, ANN201, C901, PLR0915
    if is_local_uri(request.base_uri):
        directory = uri_to_path(request.base_uri)
        # Validate directory exists
        if not directory.exists():
            raise HTTPException(status_code=404, detail=f"Directory not found: {request.base_uri}")

    logger.info(
        "Received retrieval request: %s for base uri: %s",
        request.query,
        request.base_uri,
    )

    cached_file_contents = {}

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
                if not file_path.exists():
                    logger.warning("File not found: %s", file_path)
                    return False
                content = cached_file_contents.get(file_path)
                if content is None:
                    with file_path.open("r", encoding="utf-8") as f:
                        content = f.read()
                        cached_file_contents[file_path] = content
                if node.node.get_content() not in content:
                    logger.warning("File content does not match: %s", file_path)
                    return False
                return True
            except ValueError:
                return False
        if uri == request.base_uri:
            return True
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
            query_bundle: QueryBundle | None = None,  # noqa: ARG002, pyright: ignore
            query_str: str | None = None,  # noqa: ARG002, pyright: ignore
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
                logger.warning("Skipping invalid document content: %s", uri)

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
    "/api/v1/indexing-status",
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
    if is_local_uri(request.uri):
        directory = uri_to_path(request.uri).resolve()
        if not directory.exists():
            raise HTTPException(status_code=404, detail=f"Directory not found: {directory}")

    # Get indexing history records for the specific directory
    resource_files = indexing_history_service.get_indexing_status(base_uri=request.uri)

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


class ResourceListResponse(BaseModel):
    """Response model for listing resources."""

    resources: list[Resource] = Field(..., description="List of all resources")
    total_count: int = Field(..., description="Total number of resources")
    status_summary: dict[str, int] = Field(
        ...,
        description="Summary of resource statuses (count by status)",
    )


@app.get(
    "/api/v1/resources",
    response_model=ResourceListResponse,
    summary="List all resources",
    description="""
    Returns a list of all resources that have been added to the system, including:
    * Resource URI
    * Resource type (path/https)
    * Current status
    * Last indexed timestamp
    * Any errors
    """,
    responses={
        200: {"description": "Successfully retrieved resource list"},
    },
)
async def list_resources() -> ResourceListResponse:
    """Get all resources and their current status."""
    # Get all resources from database
    resources = resource_service.get_all_resources()

    # Count resources by status
    status_counts = {}
    for resource in resources:
        status_counts[resource.status] = status_counts.get(resource.status, 0) + 1

    return ResourceListResponse(
        resources=resources,
        total_count=len(resources),
        status_summary=status_counts,
    )
