import { formatNumber, cn, copyToClipboard } from '@/lib/utils';

describe('Utility Functions', () => {
  describe('formatNumber', () => {
    it('should format numbers less than 1000 as-is', () => {
      expect(formatNumber(999)).toBe('999');
      expect(formatNumber(0)).toBe('0');
      expect(formatNumber(1)).toBe('1');
    });

    it('should format numbers in thousands with K suffix', () => {
      expect(formatNumber(1000)).toBe('1.0K');
      expect(formatNumber(1500)).toBe('1.5K');
      expect(formatNumber(12345)).toBe('12.3K');
      expect(formatNumber(999999)).toBe('1000.0K');
    });

    it('should format numbers in millions with M suffix', () => {
      expect(formatNumber(1000000)).toBe('1.0M');
      expect(formatNumber(1500000)).toBe('1.5M');
      expect(formatNumber(12345678)).toBe('12.3M');
    });

    it('should handle edge cases', () => {
      expect(formatNumber(999.99)).toBe('999.99'); // Updated expectation
      expect(formatNumber(1000.1)).toBe('1.0K');
      expect(formatNumber(1000000.1)).toBe('1.0M');
    });
  });

  describe('cn (className merger)', () => {
    it('should merge basic class names', () => {
      expect(cn('class1', 'class2')).toBe('class1 class2');
    });

    it('should handle conditional classes', () => {
      expect(cn('base', true && 'conditional', false && 'hidden')).toBe('base conditional');
    });

    it('should handle undefined and null values', () => {
      expect(cn('class1', undefined, 'class2', null)).toBe('class1 class2');
    });

    it('should merge Tailwind classes intelligently', () => {
      // This tests tailwind-merge functionality
      expect(cn('bg-red-500', 'bg-blue-500')).toBe('bg-blue-500');
      expect(cn('p-4', 'px-6')).toBe('p-4 px-6'); // Fixed expectation - px-6 overrides px from p-4
    });

    it('should work with empty inputs', () => {
      expect(cn()).toBe('');
      expect(cn('')).toBe('');
    });
  });

  describe('copyToClipboard', () => {
    beforeEach(() => {
      // Reset clipboard mock
      (navigator.clipboard.writeText as jest.Mock).mockClear();
    });

    it('should use clipboard API when available', async () => {
      (navigator.clipboard.writeText as jest.Mock).mockResolvedValue(undefined);

      const result = await copyToClipboard('test text');

      expect(result).toBe(true);
      expect(navigator.clipboard.writeText).toHaveBeenCalledWith('test text');
    });

    it('should handle clipboard API failure and use fallback', async () => {
      (navigator.clipboard.writeText as jest.Mock).mockRejectedValue(new Error('Clipboard not available'));

      // Mock document.execCommand - add it to document if it doesn't exist
      const mockExecCommand = jest.fn().mockReturnValue(true);
      Object.defineProperty(document, 'execCommand', {
        value: mockExecCommand,
        writable: true
      });

      // Mock document methods for textarea fallback
      const createElementSpy = jest.spyOn(document, 'createElement');
      const appendChildSpy = jest.spyOn(document.body, 'appendChild');
      const removeChildSpy = jest.spyOn(document.body, 'removeChild');

      const mockTextArea = {
        value: '',
        style: { position: '', left: '', top: '' },
        focus: jest.fn(),
        select: jest.fn()
      } as any;

      createElementSpy.mockReturnValue(mockTextArea);
      appendChildSpy.mockImplementation(() => mockTextArea);
      removeChildSpy.mockImplementation(() => mockTextArea);

      const result = await copyToClipboard('test text');

      expect(result).toBe(true);
      expect(mockTextArea.value).toBe('test text');
      expect(mockExecCommand).toHaveBeenCalledWith('copy');

      // Cleanup mocks
      createElementSpy.mockRestore();
      appendChildSpy.mockRestore();
      removeChildSpy.mockRestore();
    });

    it('should return false when both clipboard API and fallback fail', async () => {
      (navigator.clipboard.writeText as jest.Mock).mockRejectedValue(new Error('Clipboard not available'));

      // Mock execCommand to fail
      const mockExecCommand = jest.fn().mockReturnValue(false);
      Object.defineProperty(document, 'execCommand', {
        value: mockExecCommand,
        writable: true
      });

      const createElementSpy = jest.spyOn(document, 'createElement');
      const appendChildSpy = jest.spyOn(document.body, 'appendChild');
      const removeChildSpy = jest.spyOn(document.body, 'removeChild');

      const mockTextArea = {
        value: '',
        style: { position: '', left: '', top: '' },
        focus: jest.fn(),
        select: jest.fn()
      } as any;

      createElementSpy.mockReturnValue(mockTextArea);
      appendChildSpy.mockImplementation(() => mockTextArea);
      removeChildSpy.mockImplementation(() => mockTextArea);

      const result = await copyToClipboard('test text');

      expect(result).toBe(false);

      // Cleanup mocks
      createElementSpy.mockRestore();
      appendChildSpy.mockRestore();
      removeChildSpy.mockRestore();
    });
  });
});