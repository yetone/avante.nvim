"""Context selection and compression for optimal LLM input."""

from __future__ import annotations

from typing import TYPE_CHECKING

from llama_index.core.schema import NodeWithScore

from libs.logger import logger

if TYPE_CHECKING:
    pass


def calculate_redundancy(text1: str, text2: str) -> float:
    """
    Calculate redundancy between two text snippets using Jaccard similarity.

    Args:
        text1: First text snippet
        text2: Second text snippet

    Returns:
        Redundancy score (0-1, higher means more redundant)

    """
    # Simple word-based Jaccard similarity
    words1 = set(text1.lower().split())
    words2 = set(text2.lower().split())

    if not words1 or not words2:
        return 0.0

    intersection = len(words1 & words2)
    union = len(words1 | words2)

    return intersection / union if union > 0 else 0.0


def calculate_coverage(nodes: list[NodeWithScore], query: str) -> float:
    """
    Calculate how well the nodes cover the query terms.

    Args:
        nodes: List of nodes
        query: Query string

    Returns:
        Coverage score (0-1)

    """
    query_words = set(query.lower().split())
    if not query_words:
        return 0.0

    # Collect all words from nodes
    covered_words = set()
    for node in nodes:
        content = node.node.get_content()
        words = set(content.lower().split())
        covered_words.update(words & query_words)

    return len(covered_words) / len(query_words)


def select_optimal_context(
    nodes: list[NodeWithScore],
    query: str,
    max_tokens: int = 4000,
    redundancy_threshold: float = 0.7,
    relevance_weight: float = 1.0,
    redundancy_penalty: float = 0.5,
    coverage_weight: float = 0.3,
) -> list[NodeWithScore]:
    """
    Select optimal context from retrieved nodes.

    This implements the context selection objective:
    C* = argmax(sum(Rel(q,d)) - λ*sum(Red(di,dj)) + γ*Cov(C))

    The algorithm uses a greedy approximation:
    1. Sort nodes by relevance score
    2. Iteratively add nodes that maximize the objective
    3. Stop when token budget is exhausted

    Args:
        nodes: Retrieved nodes with scores
        query: Query string
        max_tokens: Maximum token budget
        redundancy_threshold: Threshold for considering nodes redundant
        relevance_weight: Weight for relevance scores
        redundancy_penalty: Penalty for redundancy
        coverage_weight: Weight for query coverage

    Returns:
        Selected nodes optimized for relevance, coverage, and non-redundancy

    """
    if not nodes:
        return []

    logger.debug(
        "Selecting optimal context from %d nodes (max_tokens=%d)",
        len(nodes),
        max_tokens,
    )

    selected_nodes: list[NodeWithScore] = []
    total_tokens = 0

    # Estimate tokens per node (rough: 4 chars per token)
    def estimate_tokens(text: str) -> int:
        return len(text) // 4

    # Sort nodes by relevance score (descending)
    sorted_nodes = sorted(
        nodes,
        key=lambda n: n.score if n.score is not None else 0.0,
        reverse=True,
    )

    for node in sorted_nodes:
        content = node.node.get_content()
        node_tokens = estimate_tokens(content)

        # Check token budget
        if total_tokens + node_tokens > max_tokens:
            logger.debug(
                "Token budget exhausted: %d + %d > %d",
                total_tokens,
                node_tokens,
                max_tokens,
            )
            break

        # Calculate redundancy with already selected nodes
        max_redundancy = 0.0
        for selected_node in selected_nodes:
            selected_content = selected_node.node.get_content()
            redundancy = calculate_redundancy(content, selected_content)
            max_redundancy = max(max_redundancy, redundancy)

        # Skip if too redundant
        if max_redundancy > redundancy_threshold:
            logger.debug(
                "Skipping redundant node (redundancy=%.2f)",
                max_redundancy,
            )
            continue

        # Calculate objective score
        relevance_score = node.score if node.score is not None else 0.0
        redundancy_cost = max_redundancy * redundancy_penalty

        # Add node
        selected_nodes.append(node)
        total_tokens += node_tokens

        logger.debug(
            "Selected node (relevance=%.3f, redundancy=%.3f, tokens=%d, total=%d)",
            relevance_score,
            max_redundancy,
            node_tokens,
            total_tokens,
        )

    # Calculate final coverage
    final_coverage = calculate_coverage(selected_nodes, query)

    logger.info(
        "Selected %d/%d nodes (tokens=%d/%d, coverage=%.2f)",
        len(selected_nodes),
        len(nodes),
        total_tokens,
        max_tokens,
        final_coverage,
    )

    return selected_nodes


def order_context_for_llm(nodes: list[NodeWithScore]) -> list[NodeWithScore]:
    """
    Order context to avoid "lost in the middle" problem.

    Research shows LLMs often underuse evidence in the middle of long contexts.
    This function orders nodes to place most relevant information at the
    beginning and end.

    Strategy:
    - Place highest relevance nodes at the beginning
    - Place medium relevance nodes in the middle
    - Place secondary high-relevance nodes at the end

    Args:
        nodes: List of nodes to order

    Returns:
        Reordered list of nodes

    """
    if len(nodes) <= 2:
        return nodes

    # Sort by relevance
    sorted_nodes = sorted(
        nodes,
        key=lambda n: n.score if n.score is not None else 0.0,
        reverse=True,
    )

    # Split into three groups
    n = len(sorted_nodes)
    top_third = n // 3
    middle_third = n - (2 * top_third)

    high_relevance = sorted_nodes[:top_third]
    medium_relevance = sorted_nodes[top_third : top_third + middle_third]
    secondary_high = sorted_nodes[top_third + middle_third :]

    # Order: high -> medium -> secondary_high
    # This places important info at start and end
    ordered_nodes = high_relevance + medium_relevance + secondary_high

    logger.debug(
        "Ordered %d nodes to avoid lost-in-the-middle (high=%d, mid=%d, end=%d)",
        len(nodes),
        len(high_relevance),
        len(medium_relevance),
        len(secondary_high),
    )

    return ordered_nodes


def compress_context(
    nodes: list[NodeWithScore],
    query: str,
    max_tokens: int = 4000,
) -> list[NodeWithScore]:
    """
    Compress and optimize context for LLM input.

    This is the main entry point for context optimization, combining:
    1. Selection: Remove redundant and low-value nodes
    2. Ordering: Arrange nodes to maximize LLM attention
    3. Token management: Stay within budget

    Args:
        nodes: Retrieved nodes
        query: Query string
        max_tokens: Maximum token budget

    Returns:
        Optimized and ordered list of nodes

    """
    # Step 1: Select optimal nodes
    selected_nodes = select_optimal_context(
        nodes=nodes,
        query=query,
        max_tokens=max_tokens,
    )

    # Step 2: Order for optimal LLM processing
    ordered_nodes = order_context_for_llm(selected_nodes)

    return ordered_nodes

