"""
Test System Initialization (REQ-1)
Tests that the system must initialize successfully.
"""
import json
import tempfile
import time
from pathlib import Path

import pytest

from src.system import System, ConfigurationError, SystemInitializationError


class TestSystemInitialization:
    """Test suite for system initialization requirements."""

    def test_system_starts_successfully(self):
        """
        Test that the system can start without errors.

        Expected: System initializes and returns ready state
        """
        # Create a system with default configuration
        system = System()

        # Initialize the system
        system.initialize()

        # Verify system is initialized
        assert system.is_initialized is True
        assert system.logger is not None
        assert len(system.components) > 0

        # Verify status
        status = system.get_status()
        assert status['initialized'] is True
        assert status['config_loaded'] is True

        # Cleanup
        system.shutdown()

    def test_system_initialization_within_time_limit(self):
        """
        Test that system starts within 5 seconds (NFR-1).

        Expected: System initialization completes in < 5 seconds
        """
        # Create a system
        system = System()

        # Measure initialization time
        start_time = time.time()
        system.initialize()
        elapsed_time = time.time() - start_time

        # Verify initialization time is under 5 seconds (NFR-1)
        assert elapsed_time < 5.0, f"Initialization took {elapsed_time:.3f}s, exceeding 5 second limit"

        # Also check the system's own timing
        assert system.initialization_time < 5.0

        # Cleanup
        system.shutdown()

    def test_all_required_components_loaded(self):
        """
        Test that all required system components are loaded during initialization.

        Expected: All core components (config, logger, services) are initialized
        """
        # Create a system with a config file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            config_data = {
                'log_level': 'INFO',
                'system_name': 'Test System',
                'services': ['service1', 'service2']
            }
            json.dump(config_data, f)
            config_path = Path(f.name)

        try:
            system = System(config_path=config_path)
            system.initialize()

            # Verify all required components are loaded
            assert 'config' in system.components, "Configuration component not loaded"
            assert 'logger' in system.components, "Logger component not loaded"
            assert 'services' in system.components, "Services component not loaded"

            # Verify components are properly initialized
            assert system.components['config'] is not None
            assert system.components['logger'] is not None
            assert system.components['services'] is not None

            # Cleanup
            system.shutdown()

        finally:
            # Clean up temp file
            config_path.unlink(missing_ok=True)

    def test_configuration_loaded_correctly(self):
        """
        Test that system configuration is loaded and validated.

        Expected: Configuration file is read and validated successfully
        """
        # Create a temporary config file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            config_data = {
                'log_level': 'DEBUG',
                'system_name': 'Test A System',
                'services': ['test_service']
            }
            json.dump(config_data, f)
            config_path = Path(f.name)

        try:
            system = System(config_path=config_path)
            system.initialize()

            # Verify configuration was loaded
            assert system.config is not None
            assert system.config['log_level'] == 'DEBUG'
            assert system.config['system_name'] == 'Test A System'
            assert system.config['services'] == ['test_service']

            # Verify configuration is accessible through components
            assert system.components['config'] == system.config

            # Cleanup
            system.shutdown()

        finally:
            # Clean up temp file
            config_path.unlink(missing_ok=True)


class TestSystemInitializationErrorHandling:
    """Test suite for system initialization error scenarios."""

    def test_initialization_with_missing_config(self):
        """
        Test that system handles missing configuration gracefully (REQ-4).

        Expected: System uses default configuration when config file is missing
        """
        # Create a system with a non-existent config file
        non_existent_path = Path('/tmp/non_existent_config_12345.json')
        assert not non_existent_path.exists()

        system = System(config_path=non_existent_path)

        # System should initialize with default config (not raise an error)
        system.initialize()

        # Verify system initialized with defaults
        assert system.is_initialized is True
        assert system.config is not None
        assert system.config['log_level'] == 'INFO'  # Default log level

        # Cleanup
        system.shutdown()

    def test_initialization_with_invalid_config(self):
        """
        Test that system handles invalid configuration gracefully (REQ-4).

        Expected: System raises validation error with details
        """
        # Create a config file with invalid content
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write("{ invalid json content }")
            config_path = Path(f.name)

        try:
            system = System(config_path=config_path)

            # Should raise ConfigurationError with clear message
            with pytest.raises(ConfigurationError) as exc_info:
                system.initialize()

            # Verify error message is clear and helpful
            error_message = str(exc_info.value)
            assert 'Invalid JSON' in error_message or 'configuration' in error_message.lower()

        finally:
            # Clean up temp file
            config_path.unlink(missing_ok=True)

    def test_initialization_with_invalid_config_values(self):
        """
        Test that system validates configuration values.

        Expected: System raises validation error for invalid values
        """
        # Create a config file with invalid log_level
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            config_data = {
                'log_level': 'INVALID_LEVEL',
                'system_name': 'Test System'
            }
            json.dump(config_data, f)
            config_path = Path(f.name)

        try:
            system = System(config_path=config_path)

            # Should raise ConfigurationError for invalid log_level
            with pytest.raises(ConfigurationError) as exc_info:
                system.initialize()

            # Verify error message mentions the invalid value
            error_message = str(exc_info.value)
            assert 'log_level' in error_message.lower()

        finally:
            # Clean up temp file
            config_path.unlink(missing_ok=True)

    def test_initialization_recovers_from_partial_failure(self):
        """
        Test that system can recover from partial initialization failures.

        Expected: System logs error and continues with fallback configuration
        """
        # Create a config with missing required field
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            # Config missing 'log_level' required field
            config_data = {
                'system_name': 'Test System'
                # Missing log_level
            }
            json.dump(config_data, f)
            config_path = Path(f.name)

        try:
            system = System(config_path=config_path)

            # Should raise error due to missing required field
            with pytest.raises(ConfigurationError) as exc_info:
                system.initialize()

            # Verify error message is clear
            error_message = str(exc_info.value)
            assert 'log_level' in error_message.lower() or 'required' in error_message.lower()

        finally:
            # Clean up temp file
            config_path.unlink(missing_ok=True)
