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

import chromadb
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
from llama_index.embeddings.openai import OpenAIEmbedding
from llama_index.vector_stores.chroma import ChromaVectorStore
from pydantic import BaseModel, Field
from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

if TYPE_CHECKING:
    from collections.abc import Generator

    from llama_index.core.schema import BaseNode, Document, NodeWithScore, QueryBundle
    from watchdog.observers.api import BaseObserver

app = FastAPI(
    title="RAG Service API",
    description="""
    RAG (Retrieval-Augmented Generation) Service API for managing document indexing and retrieval.

    ## Features
    * Add directories for document watching and indexing
    * Remove watched directories
    * Retrieve relevant information from indexed documents
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
METADATA_KEY_FILE_PATH = "file_path"

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
    file_path TEXT NOT NULL,
    file_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    error_message TEXT,
    document_id TEXT,
    metadata TEXT
);

CREATE INDEX IF NOT EXISTS idx_document_id ON indexing_history(document_id);
CREATE INDEX IF NOT EXISTS idx_file_path ON indexing_history(file_path);
CREATE INDEX IF NOT EXISTS idx_file_hash ON indexing_history(file_hash);
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
watched_dirs: dict[Path, BaseObserver] = {}  # Directory path -> Observer instance mapping
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
    file_path: Path = Field(..., description="Path to the indexed file")
    file_hash: str = Field(..., description="MD5 hash of the file content")
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
    file_hash = doc.hash
    file_path = get_node_file_path(doc)

    if not file_path:
        logger.warning("File path not found for document: %s", doc.doc_id)
        return

    record = IndexingHistory(
        id=None,
        file_path=file_path,
        file_hash=file_hash,
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
                SET file_hash = ?, status = ?, error_message = ?, document_id = ?, metadata = ?
                WHERE file_path = ?
                """,
                (
                    record.file_hash,
                    record.status,
                    record.error_message,
                    record.document_id,
                    json.dumps(record.metadata) if record.metadata else None,
                    str(record.file_path),
                ),
            )
        else:
            # Insert new record
            conn.execute(
                """
                INSERT INTO indexing_history
                (file_path, file_hash, status, error_message, document_id, metadata)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    str(record.file_path),
                    record.file_hash,
                    record.status,
                    record.error_message,
                    record.document_id,
                    json.dumps(record.metadata) if record.metadata else None,
                ),
            )
        conn.commit()


def get_indexing_status(doc: Document | None = None, directory: Path | None = None) -> list[IndexingHistory]:
    """Get indexing status from the database."""
    with get_db_connection() as conn:
        if doc:
            file_path = get_node_file_path(doc)
            file_hash = doc.hash
            # For a specific file, get its latest status
            query = """
                SELECT *
                FROM indexing_history
                WHERE file_path = ? and file_hash = ?
                ORDER BY timestamp DESC LIMIT 1
            """
            params = (str(file_path), file_hash)
        elif directory:
            # For files in a specific directory, get their latest status
            query = """
                WITH RankedHistory AS (
                    SELECT *,
                           ROW_NUMBER() OVER (PARTITION BY document_id ORDER BY timestamp DESC) as rn
                    FROM indexing_history
                    WHERE file_path LIKE ? || '%'
                )
                SELECT id, file_path, file_hash, status, timestamp, error_message, document_id, metadata
                FROM RankedHistory
                WHERE rn = 1
                ORDER BY timestamp DESC
            """
            params = (str(directory.resolve()) + os.path.sep,)
        else:
            # For all files, get their latest status
            query = """
                WITH RankedHistory AS (
                    SELECT *,
                           ROW_NUMBER() OVER (PARTITION BY file_path ORDER BY timestamp DESC) as rn
                    FROM indexing_history
                )
                SELECT id, file_path, file_hash, status, timestamp, error_message, document_id, metadata
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

PATTERN_FILE_PATH = re.compile(r"(?P<file_path>.+)__part_\d+")


def get_node_file_path(node: BaseNode) -> Path | None:
    """Get file path from node metadata."""
    file_path = node.metadata.get(METADATA_KEY_FILE_PATH)
    if not file_path:
        doc_id = getattr(node, "doc_id", None)
        if doc_id:
            match = PATTERN_FILE_PATH.match(doc_id)
            file_path = match.group("file_path") if match else doc_id
    if file_path:
        return Path(file_path)
    return None


def inject_file_path_to_node(node: BaseNode) -> None:
    """Inject file path into node metadata."""
    if METADATA_KEY_FILE_PATH in node.metadata:
        return
    file_path = get_node_file_path(node)
    if file_path:
        node.metadata[METADATA_KEY_FILE_PATH] = file_path


try:
    index = load_index_from_storage(storage_context)
except (OSError, ValueError) as e:
    logger.error("Failed to load index from storage: %s", e)
    index = VectorStoreIndex([], storage_context=storage_context)


class DirectoryRequest(BaseModel):
    """Request model for directory operations."""

    path: Path = Field(..., description="Absolute path to the directory to watch and index")


class SourceDocument(BaseModel):
    """Model for source document information."""

    file_path: Path = Field(..., description="Path to the source file")
    content: str = Field(..., description="Content snippet from the document")
    score: float | None = Field(None, description="Relevance score of the document")


class RetrieveRequest(BaseModel):
    """Request model for information retrieval."""

    query: str = Field(..., description="The query text to search for in the indexed documents")
    directory: Path = Field(..., description="The directory to search in")
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
                inject_file_path_to_node(new_doc)
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
        file_path = get_node_file_path(doc)
        if not file_path:
            continue
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


async def index_directory_async(directory_path: Path) -> None:
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
    "/add_directory",
    response_model="dict[str, str]",
    summary="Add a directory for watching and indexing",
    description="""
    Adds a directory to the watch list and starts indexing all existing documents in it asynchronously.
    The service will automatically detect and index any new or modified files in this directory.
    """,
    responses={
        200: {"description": "Directory successfully added and indexing started"},
        404: {"description": "Directory not found"},
        400: {"description": "Directory already being watched"},
    },
)
async def add_directory(request: DirectoryRequest, background_tasks: BackgroundTasks):  # noqa: D103, ANN201
    if not Path(request.path).exists():
        raise HTTPException(status_code=404, detail="Directory not found")

    if request.path in watched_dirs:
        raise HTTPException(status_code=400, detail="Directory already being watched")

    # Create observer
    event_handler = FileSystemHandler(directory=Path(request.path))
    observer = Observer()
    observer.schedule(event_handler, str(request.path), recursive=True)
    observer.start()
    watched_dirs[Path(request.path)] = observer

    # Start indexing in the background
    background_tasks.add_task(index_directory_async, request.path)

    return {
        "status": "success",
        "message": f"Directory {request.path} added and indexing started in background",
    }


@app.post(
    "/remove_directory",
    response_model="dict[str, str]",
    summary="Remove a watched directory",
    description="Stops watching and indexing the specified directory",
    responses={
        200: {"description": "Directory successfully removed from watch list"},
        404: {"description": "Directory not found in watch list"},
    },
)
async def remove_directory(request: DirectoryRequest):  # noqa: D103, ANN201
    directory_path = request.path
    if directory_path not in watched_dirs:
        raise HTTPException(status_code=404, detail="Directory not being watched")

    # Stop watching
    observer = watched_dirs[request.path]
    observer.stop()
    observer.join()

    del watched_dirs[request.path]
    return {"status": "success", "message": f"Directory {request.path} removed"}


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
    try:
        # Validate directory exists
        if not Path(request.directory).exists():
            raise HTTPException(status_code=404, detail=f"Directory not found: {request.directory}")

        logger.info(
            "Received retrieval request: %s for directory: %s",
            request.query,
            request.directory,
        )

        # Create a filter function to only include documents from the specified directory
        def filter_documents(node: NodeWithScore) -> bool:
            file_path = get_node_file_path(node.node)
            if not file_path:
                return False
            # Check if the file path starts with the specified directory
            try:
                file_path = file_path.resolve()
                directory = request.directory.resolve()
                # Check if directory is a parent of file_path
                try:
                    file_path.relative_to(directory)
                    return True
                except ValueError:
                    return False
            except OSError:
                return False

        from llama_index.core.postprocessor import MetadataReplacementPostProcessor

        # Create a custom post processor
        class DirectoryFilterPostProcessor(MetadataReplacementPostProcessor):
            """Post-processor for filtering nodes based on directory."""

            def __init__(self: DirectoryFilterPostProcessor) -> None:
                """Initialize the post-processor."""
                super().__init__(target_metadata_key="filtered")

            def postprocess_nodes(
                self: DirectoryFilterPostProcessor,
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
            node_postprocessors=[DirectoryFilterPostProcessor()],
        )

        logger.info("Executing retrieval query")
        response = query_engine.query(request.query)

        # If no documents were found in the specified directory
        if not response.source_nodes:
            raise HTTPException(
                status_code=404,
                detail=f"No relevant documents found in directory: {request.directory}",
            )

        # Process source documents, ensure readable text
        sources = []
        for node in response.source_nodes[: request.top_k]:
            try:
                content = node.node.get_content()

                # Get document ID and file path
                doc_id = (
                    getattr(node.node, "doc_id", None)  # Try direct doc_id
                    or getattr(node.node, "id_", None)  # Try id_
                    or getattr(node.node, "ref_doc_id", None)  # Try ref_doc_id
                    or "Unknown Source"  # Default if none found
                )

                file_path = get_node_file_path(node.node)

                # Handle byte-type content
                if isinstance(content, bytes):
                    try:
                        content = content.decode("utf-8", errors="replace")
                    except UnicodeDecodeError as e:
                        logger.warning(
                            "Unable to decode document content: %s, error: %s",
                            file_path,
                            str(e),
                        )
                        continue

                # Validate and clean text
                if is_valid_text(str(content)):
                    cleaned_content = clean_text(str(content))
                    # Add document source information with file path
                    doc_info = {
                        "file_path": file_path,
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
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as e:
        error_msg = f"Retrieval failed: {e!s}"
        logger.exception(error_msg)
        raise HTTPException(status_code=500, detail=str(e)) from e


class IndexingStatusRequest(BaseModel):
    """Request model for indexing status."""

    directory: str = Field(..., description="Directory path to get indexing status for")


class IndexingStatusResponse(BaseModel):
    """Model for indexing status response."""

    directory: Path = Field(..., description="Directory being monitored")
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
    summary="Get indexing status for a directory",
    description="""
    Returns the current indexing status for all files in the specified directory, including:
    * Whether the directory is being watched
    * Status of each file in the directory
    * Summary statistics
    """,
    responses={
        200: {"description": "Successfully retrieved indexing status"},
        404: {"description": "Directory not found"},
    },
)
async def get_indexing_status_for_directory(request: IndexingStatusRequest):  # noqa: D103, ANN201
    directory = Path(request.directory).resolve()
    if not Path(directory).exists():
        raise HTTPException(status_code=404, detail=f"Directory not found: {directory}")

    # Get indexing history records for the specific directory
    directory_files = get_indexing_status(directory=directory)

    logger.info("Found %d files in directory %s", len(directory_files), directory)
    for file in directory_files:
        logger.debug("File status: %s - %s", file.file_path, file.status)

    # Count files by status
    status_counts = {}
    for file in directory_files:
        status_counts[file.status] = status_counts.get(file.status, 0) + 1

    return IndexingStatusResponse(
        directory=directory,
        is_watched=directory in watched_dirs,
        files=directory_files,
        total_files=len(directory_files),
        status_summary=status_counts,
    )
