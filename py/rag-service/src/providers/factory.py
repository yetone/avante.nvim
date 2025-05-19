import importlib
from typing import cast, Callable

from llama_index.core.base.embeddings.base import BaseEmbedding
from llama_index.core.llms.llm import LLM
from libs.logger import (
    logger,
)  # Assuming libs.logger exists and provides a logger instance


def initialize_embed_model(
    embed_provider: str,
    embed_model: str,
    embed_endpoint: str | None = None,
    embed_api_key: str | None = None,
    embed_extra: dict = {},
) -> BaseEmbedding:
    """
    Initializes embedding model based on specified provider, endpoint, API key, and model name.

    Dynamically loads the provider module based on the embed_provider parameter.

    Args:
        embed_provider: The name of the embedding provider (e.g., "openai", "ollama").
        embed_endpoint: The API endpoint for the embedding provider.
        embed_api_key: The API key for the embedding provider.
        embed_model: The name of the embedding model.

    Returns:
        The initialized embed_model.

    Raises:
        ValueError: If the specified embed_provider is not supported or module/function not found.
        RuntimeError: If model initialization fails for the selected provider.
    """
    if not embed_provider.replace("_", "").isalnum():
        raise ValueError(f"Invalid EMBED_PROVIDER specified: '{embed_provider}'. Provider name must be alphanumeric or contain underscores.")

    try:
        provider_module = importlib.import_module(f".{embed_provider}", package="providers")
        logger.debug(f"Successfully imported provider module: providers.{embed_provider}")

        initializer = cast(
            Callable[..., BaseEmbedding],
            getattr(provider_module, "initialize_embed_model", None),
        )

        if initializer is None:
            raise ValueError(f"Provider module '{embed_provider}' does not have an 'initialize_embed_model' function.")

    except ImportError:
        raise ValueError(f"Unsupported EMBED_PROVIDER specified: '{embed_provider}'. Could not find provider module 'providers.{embed_provider}'.")
    except AttributeError:
        raise ValueError(f"Provider module '{embed_provider}' does not have an 'initialize_embed_model' function.")
    except Exception as e:
        logger.error(
            f"An unexpected error occurred while loading provider '{embed_provider}': {e}",
            exc_info=True,
        )
        raise RuntimeError(f"Failed to load provider '{embed_provider}' due to an unexpected error.") from e

    logger.info(f"Initializing embedding model for provider: '{embed_provider}'")
    logger.debug(f"Args: embed_model='{embed_model}', embed_endpoint='{embed_endpoint}'")

    try:
        embedding: BaseEmbedding = initializer(embed_endpoint, embed_api_key, embed_model, **embed_extra)

        logger.info(f"Embedding model initialized successfully for '{embed_provider}'.")
    except TypeError as e:
        logger.error(
            f"Provider initializer 'initialize_embed_model' in '{embed_provider}' was called with incorrect arguments: {e}",
            exc_info=True,
        )
        raise RuntimeError(f"Provider embedding initialization failed due to incorrect function signature in '{embed_provider}'.") from e
    except Exception as e:
        logger.error(
            f"Failed to initialize embedding model for provider '{embed_provider}': {e}",
            exc_info=True,
        )
        raise RuntimeError(f"Failed to initialize embedding model for provider '{embed_provider}'") from e

    return embedding


def initialize_llm_model(
    llm_provider: str,
    llm_model: str,
    llm_endpoint: str | None = None,
    llm_api_key: str | None = None,
    llm_extra: dict = {},
) -> LLM:
    """
    Initializes LLM model based on specified provider, endpoint, API key, and model name.

    Dynamically loads the provider module based on the llm_provider parameter.

    Args:
        llm_provider: The name of the LLM provider (e.g., "openai", "ollama").
        llm_endpoint: The API endpoint for the LLM provider.
        llm_api_key: The API key for the LLM provider.
        llm_model: The name of the LLM model.

    Returns:
        The initialized llm_model.

    Raises:
        ValueError: If the specified llm_provider is not supported or module/function not found.
        RuntimeError: If model initialization fails for the selected provider.
    """
    if not llm_provider.replace("_", "").isalnum():
        raise ValueError(f"Invalid LLM_PROVIDER specified: '{llm_provider}'. Provider name must be alphanumeric or contain underscores.")

    try:
        provider_module = importlib.import_module(f".{llm_provider}", package="providers")
        logger.debug(f"Successfully imported provider module: providers.{llm_provider}")

        initializer = cast(Callable[..., LLM], getattr(provider_module, "initialize_llm_model", None))

        if initializer is None:
            raise ValueError(f"Provider module '{llm_provider}' does not have an 'initialize_llm_model' function.")

    except ImportError:
        raise ValueError(f"Unsupported LLM_PROVIDER specified: '{llm_provider}'. Could not find provider module 'providers.{llm_provider}'.")
    except AttributeError:
        raise ValueError(f"Provider module '{llm_provider}' does not have an 'initialize_llm_model' function.")
    except Exception as e:
        logger.error(
            f"An unexpected error occurred while loading provider '{llm_provider}': {e}",
            exc_info=True,
        )
        raise RuntimeError(f"Failed to load provider '{llm_provider}' due to an unexpected error.") from e

    logger.info(f"Initializing LLM model for provider: '{llm_provider}'")
    logger.debug(f"Args: llm_model='{llm_model}', llm_endpoint='{llm_endpoint}'")

    try:
        llm: LLM = initializer(llm_endpoint, llm_api_key, llm_model, **llm_extra)
        logger.info(f"LLM model initialized successfully for '{llm_provider}'.")
    except TypeError as e:
        logger.error(
            f"Provider initializer 'initialize_llm_model' in '{llm_provider}' was called with incorrect arguments: {e}",
            exc_info=True,
        )
        raise RuntimeError(f"Provider LLM initialization failed due to incorrect function signature in '{llm_provider}'.") from e
    except Exception as e:
        logger.error(
            f"Failed to initialize LLM model for provider '{llm_provider}': {e}",
            exc_info=True,
        )
        raise RuntimeError(f"Failed to initialize LLM model for provider '{llm_provider}'") from e

    return llm
