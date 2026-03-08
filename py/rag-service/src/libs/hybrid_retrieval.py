"""Hybrid retrieval system combining BM25 and dense embeddings with RRF fusion."""

from __future__ import annotations

from typing import TYPE_CHECKING

from llama_index.core.retrievers import BaseRetriever
from llama_index.retrievers.bm25 import BM25Retriever

from libs.logger import logger

if TYPE_CHECKING:
    from llama_index.core import VectorStoreIndex
    from llama_index.core.schema import NodeWithScore, QueryBundle


def reciprocal_rank_fusion(
    results_list: list[list[NodeWithScore]],
    k: int = 60,
) -> list[NodeWithScore]:
    """
    Fuse multiple retrieval results using Reciprocal Rank Fusion (RRF).

    RRF is a robust fusion method that avoids brittle score normalization
    across different retrieval channels (BM25, dense, etc.).

    Formula: RRF(d) = sum(1 / (k + rank_m(d))) for all retrievers m

    Args:
        results_list: List of retrieval results from different retrievers
        k: Constant for RRF formula (typically 60)

    Returns:
        Fused and re-ranked list of nodes

    """
    # Build a mapping from node_id to node and its RRF score
    node_scores: dict[str, float] = {}
    node_map: dict[str, NodeWithScore] = {}

    for results in results_list:
        for rank, node_with_score in enumerate(results, start=1):
            node_id = node_with_score.node.node_id
            # RRF formula: 1 / (k + rank)
            rrf_score = 1.0 / (k + rank)

            if node_id in node_scores:
                node_scores[node_id] += rrf_score
            else:
                node_scores[node_id] = rrf_score
                node_map[node_id] = node_with_score

    # Sort by RRF score (descending)
    sorted_node_ids = sorted(node_scores.items(), key=lambda x: x[1], reverse=True)

    # Create final list with updated scores
    fused_results = []
    for node_id, score in sorted_node_ids:
        node_with_score = node_map[node_id]
        # Update the score to the RRF score
        node_with_score.score = score
        fused_results.append(node_with_score)

    logger.debug(
        "RRF fusion: Combined %d result lists into %d unique nodes",
        len(results_list),
        len(fused_results),
    )

    return fused_results


class HybridRetriever(BaseRetriever):
    """
    Hybrid retriever combining BM25 (lexical) and dense (semantic) retrieval.

    This implements the Tier 1 default pipeline from RAG research:
    - Sparse retrieval (BM25) for exact term matching
    - Dense retrieval for semantic similarity
    - Reciprocal Rank Fusion (RRF) to combine results

    Attributes:
        vector_retriever: Dense retriever from vector index
        bm25_retriever: BM25 lexical retriever
        top_k: Number of results to return
        mode: Retrieval mode ("hybrid", "dense_only", "sparse_only")

    """

    def __init__(
        self: HybridRetriever,
        index: VectorStoreIndex,
        top_k: int = 10,
        mode: str = "hybrid",
        similarity_top_k: int = 20,
    ) -> None:
        """
        Initialize hybrid retriever.

        Args:
            index: Vector store index for dense retrieval
            top_k: Number of final results to return
            mode: Retrieval mode ("hybrid", "dense_only", "sparse_only")
            similarity_top_k: Number of candidates to retrieve from each method

        """
        self._index = index
        self._top_k = top_k
        self._mode = mode
        self._similarity_top_k = similarity_top_k

        # Initialize dense retriever
        self._vector_retriever = index.as_retriever(
            similarity_top_k=similarity_top_k,
        )

        # Initialize BM25 retriever
        # Note: BM25Retriever needs nodes from the index
        nodes = list(index.docstore.docs.values())
        self._bm25_retriever = BM25Retriever.from_defaults(
            nodes=nodes,
            similarity_top_k=similarity_top_k,
        )

        logger.info(
            "Initialized HybridRetriever with mode=%s, top_k=%d, similarity_top_k=%d",
            mode,
            top_k,
            similarity_top_k,
        )

        super().__init__()

    def _retrieve(self: HybridRetriever, query_bundle: QueryBundle) -> list[NodeWithScore]:
        """
        Retrieve nodes using hybrid approach.

        Args:
            query_bundle: Query bundle containing query text

        Returns:
            List of retrieved nodes with scores

        """
        if self._mode == "dense_only":
            # Dense retrieval only
            results = self._vector_retriever.retrieve(query_bundle)
            logger.debug("Dense-only retrieval: %d results", len(results))
            return results[: self._top_k]

        if self._mode == "sparse_only":
            # BM25 retrieval only
            results = self._bm25_retriever.retrieve(query_bundle)
            logger.debug("Sparse-only retrieval: %d results", len(results))
            return results[: self._top_k]

        # Hybrid retrieval with RRF fusion
        logger.debug("Performing hybrid retrieval for query: %s", query_bundle.query_str)

        # Get results from both retrievers
        dense_results = self._vector_retriever.retrieve(query_bundle)
        sparse_results = self._bm25_retriever.retrieve(query_bundle)

        logger.debug(
            "Dense retrieval: %d results, Sparse retrieval: %d results",
            len(dense_results),
            len(sparse_results),
        )

        # Fuse results using RRF
        fused_results = reciprocal_rank_fusion([dense_results, sparse_results])

        # Return top-k results
        return fused_results[: self._top_k]

    async def _aretrieve(
        self: HybridRetriever,
        query_bundle: QueryBundle,
    ) -> list[NodeWithScore]:
        """
        Async retrieve (delegates to sync version).

        Args:
            query_bundle: Query bundle containing query text

        Returns:
            List of retrieved nodes with scores

        """
        return self._retrieve(query_bundle)

