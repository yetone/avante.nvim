# src/providers/openrouter.py

from typing import Any
from llama_index.llms.openrouter import OpenRouter
from llama_index.core.llms.llm import LLM


def initialize_llm_model(
    llm_endpoint: str,
    llm_api_key: str,
    llm_model: str,
    **llm_extra: Any,
) -> LLM:
    """
    Initializes OpenRouter LLM model.

    Args:
        llm_model: The name of the LLM model.
        llm_endpoint: The API endpoint for the OpenRouter API.
        llm_api_key: The API key for the OpenRouter API.

    Returns:
        The initialized llm_model.
    """
    # Use the provided endpoint directly.
    # We are not using llm_api_key parameter here, relying on env var as original code did.
    llm_model_instance = OpenRouter(
        model=llm_model,
        api_base=llm_endpoint,
        api_key=llm_api_key,
        **llm_extra,
    )
    return llm_model_instance
