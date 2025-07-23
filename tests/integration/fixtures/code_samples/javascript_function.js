function calculateSum(a, b) {
  if (typeof a !== 'number' || typeof b !== 'number') {
    throw new Error('Both arguments must be numbers');
  }
  return a + b;
}

// Example usage
const result = calculateSum(5, 3);
console.log('Sum:', result);

module.exports = { calculateSum };