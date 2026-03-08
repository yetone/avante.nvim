"""Adaptive retrieval with query rewriting, HyDE, and multi-query expansion."""

from __future__ import annotations

from typing import TYPE_CHECKING

from llama_index.core import PromptTemplate
from llama_index.core.schema import NodeWithScore, QueryBundle

from libs.hybrid_retrieval import reciprocal_rank_fusion
from libs.logger import logger

if TYPE_CHECKING:
    from llama_index.core.llms.llm import LLM
    from llama_index.core.retrievers import BaseRetriever


# Query classification prompt
QUERY_CLASSIFIER_PROMPT = PromptTemplate(
    """Classify the following query into one of these categories:
- lookup: Simple factual lookup or definition
- synthesis: Requires combining multiple pieces of information
- multi_hop: Requires following chains of reasoning across documents
- exploratory: Broad "tell me about X" questions

Query: {query}

Respond with just the category name (lookup, synthesis, multi_hop, or exploratory).""",
)

# Query rewriting prompt
QUERY_REWRITE_PROMPT = PromptTemplate(
    """Given the following query, rewrite it to be more specific and search-friendly.
Focus on key terms and concepts that would appear in relevant documents.

Original query: {query}

Rewritten query:""",
)

# Multi-query expansion prompt
MULTI_QUERY_PROMPT = PromptTemplate(
    """Generate 3 different versions of the following query to improve retrieval.
Each version should focus on different aspects or phrasings.

Original query: {query}

Alternative queries (one per line):""",
)

# HyDE (Hypothetical Document Embeddings) prompt
HYDE_PROMPT = PromptTemplate(
    """Generate a hypothetical document that would answer the following question.
Write as if you are writing the content that would appear in a relevant document.

Question: {query}

Hypothetical document:""",
)


class QueryType:
    """Query type classifications."""

    LOOKUP = "lookup"
    SYNTHESIS = "synthesis"
    MULTI_HOP = "multi_hop"
    EXPLORATORY = "exploratory"


def classify_query(query: str, llm: LLM) -> str:
    """
    Classify query type to determine retrieval strategy.

    Args:
        query: Query string to classify
        llm: LLM for classification

    Returns:
        Query type classification

    """
    prompt = QUERY_CLASSIFIER_PROMPT.format(query=query)
    response = llm.complete(prompt)
    classification = response.text.strip().lower()

    # Validate classification
    valid_types = [
        QueryType.LOOKUP,
        QueryType.SYNTHESIS,
        QueryType.MULTI_HOP,
        QueryType.EXPLORATORY,
    ]
    if classification not in valid_types:
        logger.warning(
            "Invalid query classification: %s, defaulting to lookup",
            classification,
        )
        classification = QueryType.LOOKUP

    logger.debug("Query classified as: %s", classification)
    return classification


def rewrite_query(query: str, llm: LLM) -> str:
    """
    Rewrite query to be more specific and search-friendly.

    Args:
        query: Original query
        llm: LLM for rewriting

    Returns:
        Rewritten query

    """
    prompt = QUERY_REWRITE_PROMPT.format(query=query)
    response = llm.complete(prompt)
    rewritten = response.text.strip()

    logger.debug("Query rewritten: '%s' -> '%s'", query, rewritten)
    return rewritten


def expand_query(query: str, llm: LLM) -> list[str]:
    """
    Expand query into multiple variations for better coverage.

    Args:
        query: Original query
        llm: LLM for expansion

    Returns:
        List of query variations including original

    """
    prompt = MULTI_QUERY_PROMPT.format(query=query)
    response = llm.complete(prompt)

    # Parse response into multiple queries
    queries = [q.strip() for q in response.text.strip().split("\n") if q.strip()]

    # Add original query
    queries.insert(0, query)

    logger.debug("Query expanded into %d variations", len(queries))
    return queries


def generate_hyde_document(query: str, llm: LLM) -> str:
    """
    Generate hypothetical document for HyDE retrieval.

    HyDE (Hypothetical Document Embeddings) generates a hypothetical answer
    and uses its embedding for retrieval, which can improve results for
    out-of-domain queries.

    Args:
        query: Query to generate hypothetical document for
        llm: LLM for generation

    Returns:
        Hypothetical document text

    """
    prompt = HYDE_PROMPT.format(query=query)
    response = llm.complete(prompt)
    hyde_doc = response.text.strip()

    logger.debug("Generated HyDE document (length: %d)", len(hyde_doc))
    return hyde_doc


class AdaptiveRetriever:
    """
    Adaptive retriever that selects retrieval strategy based on query type.

    This implements Tier 2 adaptive pipeline:
    - Query classification
    - Conditional query rewriting
    - Multi-query expansion for coverage-heavy questions
    - HyDE for out-of-domain queries

    """

    def __init__(
        self: AdaptiveRetriever,
        base_retriever: BaseRetriever,
        llm: LLM,
        *,
        enable_classification: bool = True,
        enable_rewriting: bool = True,
        enable_hyde: bool = False,
    ) -> None:
        """
        Initialize adaptive retriever.

        Args:
            base_retriever: Base retriever to use
            llm: LLM for query processing
            enable_classification: Enable query classification
            enable_rewriting: Enable query rewriting
            enable_hyde: Enable HyDE for difficult queries

        """
        self._base_retriever = base_retriever
        self._llm = llm
        self._enable_classification = enable_classification
        self._enable_rewriting = enable_rewriting
        self._enable_hyde = enable_hyde

        logger.info(
            "Initialized AdaptiveRetriever (classification=%s, rewriting=%s, hyde=%s)",
            enable_classification,
            enable_rewriting,
            enable_hyde,
        )

    def retrieve(self: AdaptiveRetriever, query: str, top_k: int = 10) -> list[NodeWithScore]:
        """
        Retrieve with adaptive strategy selection.

        Args:
            query: Query string
            top_k: Number of results to return

        Returns:
            Retrieved nodes with scores

        """
        logger.debug("Adaptive retrieval for query: %s", query)

        # Classify query if enabled
        query_type = QueryType.LOOKUP
        if self._enable_classification:
            query_type = classify_query(query, self._llm)

        # Select strategy based on query type
        if query_type == QueryType.LOOKUP:
            # Simple lookup: use base retriever
            return self._retrieve_simple(query, top_k)

        if query_type == QueryType.SYNTHESIS:
            # Synthesis: use query rewriting
            return self._retrieve_with_rewriting(query, top_k)

        if query_type in (QueryType.MULTI_HOP, QueryType.EXPLORATORY):
            # Multi-hop or exploratory: use multi-query expansion
            return self._retrieve_multi_query(query, top_k)

        # Default: simple retrieval
        return self._retrieve_simple(query, top_k)

    def _retrieve_simple(
        self: AdaptiveRetriever,
        query: str,
        top_k: int,
    ) -> list[NodeWithScore]:
        """Retrieve documents without modifications."""
        query_bundle = QueryBundle(query_str=query)
        return self._base_retriever.retrieve(query_bundle)[:top_k]

    def _retrieve_with_rewriting(
        self: AdaptiveRetriever,
        query: str,
        top_k: int,
    ) -> list[NodeWithScore]:
        """Retrieve documents with query rewriting."""
        rewritten_query = rewrite_query(query, self._llm) if self._enable_rewriting else query

        query_bundle = QueryBundle(query_str=rewritten_query)
        return self._base_retriever.retrieve(query_bundle)[:top_k]

    def _retrieve_multi_query(
        self: AdaptiveRetriever,
        query: str,
        top_k: int,
    ) -> list[NodeWithScore]:
        """Retrieve documents with multi-query expansion and fusion."""
        # Expand query into variations
        queries = expand_query(query, self._llm)

        # Retrieve with each query
        all_results = []
        for q in queries:
            query_bundle = QueryBundle(query_str=q)
            results = self._base_retriever.retrieve(query_bundle)
            all_results.append(results)

        # Fuse results using RRF
        fused_results = reciprocal_rank_fusion(all_results)

        return fused_results[:top_k]

    def _retrieve_with_hyde(
        self: AdaptiveRetriever,
        query: str,
        top_k: int,
    ) -> list[NodeWithScore]:
        """Retrieve documents using HyDE (Hypothetical Document Embeddings)."""
        # Generate hypothetical document
        hyde_doc = generate_hyde_document(query, self._llm)

        # Use hypothetical document for retrieval
        query_bundle = QueryBundle(query_str=hyde_doc)
        return self._base_retriever.retrieve(query_bundle)[:top_k]
