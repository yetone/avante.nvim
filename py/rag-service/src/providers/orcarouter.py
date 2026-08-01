# src/providers/orcarouter.py

from typing import Any

from llama_index.core.base.embeddings.base import BaseEmbedding
from llama_index.core.llms.llm import LLM
from llama_index.embeddings.openai_like import OpenAILikeEmbedding
from llama_index.llms.openai_like import OpenAILike


def initialize_embed_model(
    embed_endpoint: str,
    embed_api_key: str,
    embed_model: str,
    **embed_extra: Any,  # noqa: ANN401
) -> BaseEmbedding:
    """
    Create OrcaRouter embedding model.

    Args:
        embed_model: The name of the embedding model.
        embed_endpoint: The API endpoint for the OrcaRouter API.
        embed_api_key: The API key for the OrcaRouter API.
        embed_extra: Extra parameters for the OrcaRouter API.

    Returns:
        The initialized embed_model.

    """
    # OrcaRouter exposes an OpenAI-compatible /v1/embeddings endpoint.
    return OpenAILikeEmbedding(
        model_name=embed_model,
        api_base=embed_endpoint,
        api_key=embed_api_key,
        **embed_extra,
    )


def initialize_llm_model(
    llm_endpoint: str,
    llm_api_key: str,
    llm_model: str,
    **llm_extra: Any,  # noqa: ANN401
) -> LLM:
    """
    Create OrcaRouter LLM model.

    Args:
        llm_model: The name of the LLM model, namespaced by vendor
            (e.g. "anthropic/claude-sonnet-4.6", "openai/gpt-5.1").
        llm_endpoint: The API endpoint for the OrcaRouter API.
        llm_api_key: The API key for the OrcaRouter API.
        llm_extra: Extra parameters for the OrcaRouter API. See
            https://developers.llamaindex.ai/python/framework-api-reference/llms/openai_like/

    Returns:
        The initialized llm_model.

    """
    # OrcaRouter serves chat completions only; the legacy /v1/completions route
    # that OpenAILike defaults to answers 400, so opt into the chat route here.
    llm_extra.setdefault("is_chat_model", True)
    return OpenAILike(
        model=llm_model,
        api_base=llm_endpoint,
        api_key=llm_api_key,
        **llm_extra,
    )
