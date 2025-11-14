import { formatNumber, copyToClipboard } from '@/lib/utils';

describe('formatNumber', () => {
  it('should format numbers less than 1000 as-is', () => {
    expect(formatNumber(100)).toBe('100');
    expect(formatNumber(999)).toBe('999');
  });

  it('should format numbers in thousands with K suffix', () => {
    expect(formatNumber(8234)).toBe('8.2K');
    expect(formatNumber(1567)).toBe('1.6K');
    expect(formatNumber(1000)).toBe('1.0K');
  });

  it('should format numbers in millions with M suffix', () => {
    expect(formatNumber(1500000)).toBe('1.5M');
    expect(formatNumber(2345678)).toBe('2.3M');
  });
});

describe('copyToClipboard', () => {
  beforeEach(() => {
    // Reset navigator.clipboard mock
    Object.assign(navigator, {
      clipboard: {
        writeText: jest.fn(),
      },
    });
  });

  it('should copy text using modern clipboard API', async () => {
    const mockWriteText = navigator.clipboard.writeText as jest.Mock;
    mockWriteText.mockResolvedValue(undefined);

    const result = await copyToClipboard('test code');

    expect(result).toBe(true);
    expect(mockWriteText).toHaveBeenCalledWith('test code');
  });

  it('should return false when clipboard API fails', async () => {
    const mockWriteText = navigator.clipboard.writeText as jest.Mock;
    mockWriteText.mockRejectedValue(new Error('Failed'));

    // Mock document.execCommand to also fail
    document.execCommand = jest.fn(() => false);

    const result = await copyToClipboard('test code');

    expect(result).toBe(false);
  });
});
