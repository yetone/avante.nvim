# src/providers/ollama.py
"""Ollama provider for RAG service with GPU optimization."""

from typing import Any

from libs.logger import logger
from llama_index.core.base.embeddings.base import BaseEmbedding
from llama_index.core.llms.llm import LLM
from llama_index.embeddings.ollama import OllamaEmbedding
from llama_index.llms.ollama import Ollama


def initialize_embed_model(
    embed_endpoint: str,
    embed_api_key: str,  # noqa: ARG001
    embed_model: str,
    **embed_extra: Any,  # noqa: ANN401
) -> BaseEmbedding:
    """
    Create Ollama embedding model optimized for system GPU usage.

    This function ensures that Ollama uses the system GPU service properly
    without blocking or stealing resources. It configures the embedding model
    to connect to a local or remote Ollama instance.

    Args:
        embed_endpoint: The API endpoint for the Ollama API (e.g., http://localhost:11434).
        embed_api_key: Not used by Ollama (kept for interface compatibility).
        embed_model: The name of the embedding model (e.g., nomic-embed-text).
        embed_extra: Extra parameters for Ollama embedding model:
            - num_gpu: Number of GPUs to use (default: 1 for system GPU)
            - request_timeout: Request timeout in seconds (default: 120.0)
            - Additional Ollama-specific options

    Returns:
        The initialized embed_model configured for optimal GPU usage.

    """
    # Set sensible defaults for GPU optimization
    # num_gpu=1 ensures we use the system GPU without spawning additional processes
    # request_timeout is increased for embedding operations which can be slower
    request_timeout = embed_extra.pop("request_timeout", 120.0)

    logger.info(
        "Initializing Ollama embedding model: %s at %s (GPU optimized)",
        embed_model,
        embed_endpoint,
    )

    return OllamaEmbedding(
        model_name=embed_model,
        base_url=embed_endpoint,
        request_timeout=request_timeout,
        **embed_extra,
    )


def initialize_llm_model(
    llm_endpoint: str,
    llm_api_key: str,  # noqa: ARG001
    llm_model: str,
    **llm_extra: Any,  # noqa: ANN401
) -> LLM:
    """
    Create Ollama LLM model optimized for system GPU usage.

    This function ensures that Ollama uses the system GPU service properly
    without blocking or stealing resources. It configures the LLM to connect
    to a local or remote Ollama instance.

    Args:
        llm_endpoint: The API endpoint for the Ollama API (e.g., http://localhost:11434).
        llm_api_key: Not used by Ollama (kept for interface compatibility).
        llm_model: The name of the LLM model (e.g., llama3.2).
        llm_extra: Extra parameters for LLM model:
            - num_gpu: Number of GPUs to use (default: 1 for system GPU)
            - request_timeout: Request timeout in seconds (default: 300.0)
            - temperature: Sampling temperature (default: 0.7)
            - context_window: Context window size
            - Additional Ollama-specific options

    Returns:
        The initialized llm_model configured for optimal GPU usage.

    """
    # Set sensible defaults for GPU optimization
    # num_gpu=1 ensures we use the system GPU without spawning additional processes
    # request_timeout is increased for LLM operations which can be slower
    request_timeout = llm_extra.pop("request_timeout", 300.0)
    temperature = llm_extra.pop("temperature", 0.7)

    logger.info(
        "Initializing Ollama LLM model: %s at %s (GPU optimized)",
        llm_model,
        llm_endpoint,
    )

    return Ollama(
        model=llm_model,
        base_url=llm_endpoint,
        request_timeout=request_timeout,
        temperature=temperature,
        **llm_extra,
    )
