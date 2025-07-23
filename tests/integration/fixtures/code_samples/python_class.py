class Calculator:
    """A simple calculator class for basic arithmetic operations."""

    def __init__(self):
        self.history = []

    def add(self, a, b):
        """Add two numbers and return the result."""
        result = a + b
        self.history.append(f"{a} + {b} = {result}")
        return result

    def subtract(self, a, b):
        """Subtract b from a and return the result."""
        result = a - b
        self.history.append(f"{a} - {b} = {result}")
        return result

    def get_history(self):
        """Return the calculation history."""
        return self.history.copy()


# Example usage
calc = Calculator()
print(calc.add(10, 5))
print(calc.subtract(10, 3))
