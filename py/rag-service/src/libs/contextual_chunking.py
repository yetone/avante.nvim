"""Contextual chunking with structure-aware parsing and late chunking support."""

from __future__ import annotations

from llama_index.core.node_parser import CodeSplitter, SentenceSplitter
from llama_index.core.schema import Document
from tree_sitter_language_pack import SupportedLanguage, get_parser

from libs.logger import logger
from libs.utils import get_node_uri, is_path_node, uri_to_path

# Mapping of file extensions to programming languages
CODE_EXT_MAP: dict[str, SupportedLanguage] = {
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


def generate_contextual_prefix(doc: Document) -> str:
    """
    Generate contextual prefix for a document chunk.

    This implements the "Contextual Retrieval" approach where we prepend
    context to each chunk to improve retrieval accuracy.

    Args:
        doc: Document to generate context for

    Returns:
        Contextual prefix string

    """
    metadata = doc.metadata
    context_parts = []

    # Add file path context if available
    if "file_path" in metadata:
        file_path = metadata["file_path"]
        context_parts.append(f"File: {file_path}")

    # Add file name
    if "file_name" in metadata:
        file_name = metadata["file_name"]
        context_parts.append(f"Filename: {file_name}")

    # Add language context for code files
    if "language" in metadata:
        language = metadata["language"]
        context_parts.append(f"Language: {language}")

    # Add section/function context if available
    if "section" in metadata:
        section = metadata["section"]
        context_parts.append(f"Section: {section}")

    # Add chunk position context
    if "chunk_number" in metadata and "total_chunks" in metadata:
        chunk_num = metadata["chunk_number"]
        total = metadata["total_chunks"]
        context_parts.append(f"Part {chunk_num + 1} of {total}")

    if not context_parts:
        return ""

    # Join context parts
    context = " | ".join(context_parts)
    return f"[Context: {context}]\n\n"


def split_code_document(
    doc: Document,
    file_ext: str,
    chunk_lines: int = 80,
    chunk_lines_overlap: int = 15,
    max_chars: int = 512,
) -> list[Document]:
    """
    Split code document using structure-aware code splitting.

    This implements:
    - Tree-sitter based parsing for accurate code structure
    - Overlap between chunks to maintain context
    - Metadata preservation for each chunk

    Args:
        doc: Document to split
        file_ext: File extension to determine language
        chunk_lines: Maximum lines per chunk
        chunk_lines_overlap: Overlapping lines between chunks
        max_chars: Maximum characters per chunk

    Returns:
        List of split documents with contextual metadata

    """
    if file_ext not in CODE_EXT_MAP:
        return [doc]

    language = CODE_EXT_MAP[file_ext]

    try:
        parser = get_parser(language)
        code_splitter = CodeSplitter(
            language=language,
            chunk_lines=chunk_lines,
            chunk_lines_overlap=chunk_lines_overlap,
            max_chars=max_chars,
            parser=parser,
        )

        content = doc.get_content()
        texts = code_splitter.split_text(content)

        logger.debug(
            "Split code document %s into %d chunks (language: %s)",
            doc.doc_id,
            len(texts),
            language,
        )

        # Create new documents with contextual metadata
        split_docs = []
        for i, text in enumerate(texts):
            # Generate contextual prefix
            chunk_metadata = {
                **doc.metadata,
                "chunk_number": i,
                "total_chunks": len(texts),
                "language": language,
                "orig_doc_id": doc.doc_id,
                "chunking_method": "code_splitter",
            }

            # Create contextualized chunk
            contextual_prefix = generate_contextual_prefix(
                Document(text="", metadata=chunk_metadata),
            )

            new_doc = Document(
                text=contextual_prefix + text,
                doc_id=f"{doc.doc_id}__part_{i}",
                metadata=chunk_metadata,
            )
            split_docs.append(new_doc)

        return split_docs

    except ValueError as e:
        logger.warning(
            "Error splitting code document %s: %s, returning original",
            doc.doc_id,
            str(e),
        )
        return [doc]


def split_documents_with_context(
    documents: list[Document],
    chunk_lines: int = 80,
    chunk_lines_overlap: int = 15,
    max_chars: int = 512,
) -> list[Document]:
    """
    Split documents with structure-aware and contextual chunking.

    This implements the Tier 1 ingestion pipeline:
    - Structure-aware chunking (preserves code structure)
    - Contextual chunk generation (adds context to each chunk)
    - Metadata preservation and enhancement

    Args:
        documents: List of documents to split
        chunk_lines: Maximum lines per chunk for code
        chunk_lines_overlap: Overlapping lines between chunks
        max_chars: Maximum characters per chunk

    Returns:
        List of processed documents with contextual chunks

    """
    processed_documents = []

    for doc in documents:
        uri = get_node_uri(doc)
        if not uri:
            # No URI, add as-is
            processed_documents.append(doc)
            continue

        if not is_path_node(doc):
            # Not a file path, add as-is
            processed_documents.append(doc)
            continue

        # Get file extension
        file_path = uri_to_path(uri)
        file_ext = file_path.suffix.lower()

        # Update metadata with file information
        doc.metadata["file_path"] = str(file_path)
        doc.metadata["file_name"] = file_path.name
        doc.metadata["file_ext"] = file_ext

        # Split based on file type
        if file_ext in CODE_EXT_MAP:
            # Code file: use structure-aware splitting
            split_docs = split_code_document(
                doc,
                file_ext,
                chunk_lines,
                chunk_lines_overlap,
                max_chars,
            )
            processed_documents.extend(split_docs)
        else:
            # Non-code file: split aggressively to avoid exceeding embedding context length
            # Using 512 chars with 50 overlap to ensure hard cap is never exceeded
            splitter = SentenceSplitter(
                chunk_size=512,
                chunk_overlap=50,
            )

            content = doc.get_content()
            texts = splitter.split_text(content)
            total = len(texts)

            logger.debug(
                "Split non-code document %s into %d chunks (file: %s)",
                doc.doc_id,
                total,
                doc.metadata.get("file_name", "<unknown>"),
            )

            for i, text in enumerate(texts):
                chunk_metadata = {
                    **doc.metadata,
                    "orig_doc_id": doc.doc_id,
                    "chunk_number": i,
                    "total_chunks": total,
                    "chunking_method": "sentence_splitter",
                }

                contextual_prefix = generate_contextual_prefix(
                    Document(text="", metadata=chunk_metadata)
                )

                processed_documents.append(
                    Document(
                        text=contextual_prefix + text,
                        doc_id=f"{doc.doc_id}__part_{i}",
                        metadata=chunk_metadata,
                    )
                )

    logger.info(
        "Processed %d documents into %d chunks with contextual information",
        len(documents),
        len(processed_documents),
    )

    return processed_documents
