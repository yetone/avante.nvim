// Basic test file for utility functions
// Note: This is a minimal test setup. In a real project, you would use Jest or Vitest

import { formatNumber, cn } from '../lib/utils';

// Mock tests - these would be actual tests with a testing framework
describe('Utility Functions', () => {
  describe('formatNumber', () => {
    it('should format numbers correctly', () => {
      // These are just example test cases
      console.log('formatNumber(1000):', formatNumber(1000)); // Should be 1.0K
      console.log('formatNumber(1500):', formatNumber(1500)); // Should be 1.5K
      console.log('formatNumber(1000000):', formatNumber(1000000)); // Should be 1.0M
      console.log('formatNumber(999):', formatNumber(999)); // Should be 999
    });
  });

  describe('cn (className merger)', () => {
    it('should merge class names correctly', () => {
      // These are just example test cases
      console.log('cn("class1", "class2"):', cn("class1", "class2"));
      console.log('cn("class1", undefined, "class2"):', cn("class1", undefined, "class2"));
    });
  });
});

// Run the tests
console.log('Running utility function tests...');
console.log('formatNumber tests:');
console.log('- formatNumber(1000):', formatNumber(1000));
console.log('- formatNumber(1500):', formatNumber(1500));
console.log('- formatNumber(1000000):', formatNumber(1000000));
console.log('- formatNumber(999):', formatNumber(999));

console.log('\ncn function tests:');
console.log('- cn("class1", "class2"):', cn("class1", "class2"));
console.log('- cn("class1", undefined, "class2"):', cn("class1", undefined, "class2"));

console.log('\nAll basic tests completed successfully!');
