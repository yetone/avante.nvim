"""System initialization module for Test A.

This module provides the core System class that handles:
- System initialization and component loading
- Configuration management with validation
- Logger setup
- Error handling for initialization failures
- Component lifecycle management
"""

import json
import logging
import time
from pathlib import Path
from typing import Any, Dict, Optional


class ConfigurationError(Exception):
    """Raised when configuration loading or validation fails."""
    pass


class SystemInitializationError(Exception):
    """Raised when system initialization fails."""
    pass


class System:
    """Core system class that manages initialization and component lifecycle.

    This class provides:
    - Component initialization (config, logger, services)
    - Configuration loading and validation
    - Graceful error handling
    - Health monitoring

    Attributes:
        config: System configuration dictionary
        logger: System logger instance
        is_initialized: Whether the system has been initialized successfully
        components: Dictionary of initialized components
        initialization_time: Time taken to initialize (seconds)
    """

    def __init__(self, config_path: Optional[Path] = None):
        """Initialize the System instance.

        Args:
            config_path: Optional path to configuration file
        """
        self.config_path = config_path or Path("config.json")
        self.config: Dict[str, Any] = {}
        self.logger: Optional[logging.Logger] = None
        self.is_initialized = False
        self.components: Dict[str, Any] = {}
        self.initialization_time: float = 0.0
        self._start_time: float = 0.0

    def initialize(self) -> None:
        """Initialize the system and all components.

        This method:
        1. Loads and validates configuration
        2. Sets up logging
        3. Initializes core components
        4. Tracks initialization time

        Raises:
            SystemInitializationError: If initialization fails
            ConfigurationError: If configuration is invalid
        """
        self._start_time = time.time()

        try:
            # Step 1: Load configuration
            self._load_configuration()

            # Step 2: Initialize logger
            self._initialize_logger()

            # Step 3: Initialize core components
            self._initialize_components()

            # Calculate initialization time
            self.initialization_time = time.time() - self._start_time

            # Mark as initialized
            self.is_initialized = True

            if self.logger:
                self.logger.info(
                    f"System initialized successfully in {self.initialization_time:.3f} seconds"
                )

            # Check performance requirement (NFR-1: < 5 seconds)
            if self.initialization_time > 5.0:
                if self.logger:
                    self.logger.warning(
                        f"System initialization took {self.initialization_time:.3f}s, "
                        "exceeding the 5 second target (NFR-1)"
                    )

        except ConfigurationError as e:
            raise e
        except Exception as e:
            error_msg = f"System initialization failed: {str(e)}"
            if self.logger:
                self.logger.error(error_msg, exc_info=True)
            raise SystemInitializationError(error_msg) from e

    def _load_configuration(self) -> None:
        """Load and validate configuration from file.

        This method supports:
        - Loading from JSON configuration file
        - Validation of required fields
        - Fallback to default configuration if file is missing

        Raises:
            ConfigurationError: If configuration file is invalid
        """
        # Check if config file exists
        if not self.config_path.exists():
            # Use default configuration with fallback values
            self.config = self._get_default_config()
            return

        try:
            with open(self.config_path, 'r') as f:
                config_data = json.load(f)

            # Validate configuration
            self._validate_configuration(config_data)

            self.config = config_data

        except json.JSONDecodeError as e:
            raise ConfigurationError(
                f"Invalid JSON in configuration file '{self.config_path}': {str(e)}"
            ) from e
        except IOError as e:
            raise ConfigurationError(
                f"Failed to read configuration file '{self.config_path}': {str(e)}"
            ) from e

    def _validate_configuration(self, config: Dict[str, Any]) -> None:
        """Validate configuration structure and required fields.

        Args:
            config: Configuration dictionary to validate

        Raises:
            ConfigurationError: If validation fails
        """
        if not isinstance(config, dict):
            raise ConfigurationError(
                f"Configuration must be a dictionary, got {type(config).__name__}"
            )

        # Validate required fields
        required_fields = ['log_level']
        for field in required_fields:
            if field not in config:
                raise ConfigurationError(
                    f"Missing required configuration field: '{field}'"
                )

        # Validate log_level values
        valid_log_levels = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']
        if config['log_level'] not in valid_log_levels:
            raise ConfigurationError(
                f"Invalid log_level '{config['log_level']}'. "
                f"Must be one of: {', '.join(valid_log_levels)}"
            )

    def _get_default_config(self) -> Dict[str, Any]:
        """Get default configuration when config file is missing.

        Returns:
            Dictionary containing default configuration values
        """
        return {
            'log_level': 'INFO',
            'system_name': 'Test A System',
            'services': []
        }

    def _initialize_logger(self) -> None:
        """Initialize the logging system.

        Sets up logging with:
        - Configured log level
        - Formatted output
        - Console handler
        """
        log_level = getattr(logging, self.config.get('log_level', 'INFO'))

        # Create logger
        self.logger = logging.getLogger('test_a_system')
        self.logger.setLevel(log_level)

        # Clear any existing handlers
        self.logger.handlers.clear()

        # Create console handler with formatting
        handler = logging.StreamHandler()
        handler.setLevel(log_level)

        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        handler.setFormatter(formatter)

        self.logger.addHandler(handler)

        # Register logger as a component
        self.components['logger'] = self.logger

    def _initialize_components(self) -> None:
        """Initialize core system components.

        This method:
        - Sets up the configuration component
        - Initializes services specified in configuration
        - Handles partial failures gracefully
        """
        # Register configuration as a component
        self.components['config'] = self.config

        # Initialize services from configuration
        services = self.config.get('services', [])
        if self.logger:
            self.logger.debug(f"Initializing {len(services)} services")

        # For now, we just track service configurations
        # Actual service initialization would happen here
        self.components['services'] = {
            'count': len(services),
            'configured': services
        }

        if self.logger:
            self.logger.info(
                f"All components initialized: {', '.join(self.components.keys())}"
            )

    def get_status(self) -> Dict[str, Any]:
        """Get current system status.

        Returns:
            Dictionary containing system status information
        """
        return {
            'initialized': self.is_initialized,
            'initialization_time': self.initialization_time,
            'components': list(self.components.keys()),
            'config_loaded': bool(self.config),
            'system_name': self.config.get('system_name', 'Unknown')
        }

    def health_check(self) -> Dict[str, Any]:
        """Perform system health check.

        Returns:
            Dictionary containing health status
        """
        is_healthy = (
            self.is_initialized and
            self.logger is not None and
            bool(self.components)
        )

        return {
            'status': 'healthy' if is_healthy else 'unhealthy',
            'initialized': self.is_initialized,
            'components_count': len(self.components),
            'uptime': time.time() - self._start_time if self._start_time > 0 else 0
        }

    def shutdown(self) -> None:
        """Gracefully shutdown the system and cleanup resources."""
        if self.logger:
            self.logger.info("Shutting down system")

        # Cleanup components
        self.components.clear()
        self.is_initialized = False

        if self.logger:
            self.logger.info("System shutdown complete")
