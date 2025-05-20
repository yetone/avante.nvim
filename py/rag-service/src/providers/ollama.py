# src/providers/ollama.py

from typing import Any

from llama_index.core.base.embeddings.base import BaseEmbedding
from llama_index.core.llms.llm import LLM
from llama_index.embeddings.ollama import OllamaEmbedding
from llama_index.llms.ollama import Ollama


def initialize_embed_model(
    embed_endpoint: str,
    embed_api_key: str,
    embed_model: str,
    **embed_extra: Any,
) -> BaseEmbedding:
    """
    Initializes Ollama embedding model.

    Args:
        embed_endpoint: The API endpoint for the Ollama API.
        embed_api_key: Not be used by Ollama.
        embed_model: The name of the embedding model.

    Returns:
        The initialized embed_model.

    """
    # Ollama typically uses the endpoint directly and may not require an API key
    # We include embed_api_key in the signature to match the factory interface
    # Pass embed_api_key even if Ollama doesn't use it, to match the signature
    embed_model_instance = OllamaEmbedding(
        model_name=embed_model,
        base_url=embed_endpoint,
        **embed_extra,
    )
    return embed_model_instance


def initialize_llm_model(
    llm_endpoint: str,
    llm_api_key: str,
    llm_model: str,
    **llm_extra: Any,
) -> LLM:
    """
    Initializes Ollama LLM model.

    Args:
        llm_endpoint: The API endpoint for the Ollama API.
        llm_api_key: Not be used by Ollama.
        llm_model: The name of the LLM model.

    Returns:
        The initialized llm_model.

    """
    # Ollama typically uses the endpoint directly and may not require an API key
    # We include llm_api_key in the signature to match the factory interface
    # Pass llm_api_key even if Ollama doesn't use it, to match the signature
    llm_model_instance = Ollama(
        model=llm_model,
        base_url=llm_endpoint,
        **llm_extra,
    )
    return llm_model_instance
