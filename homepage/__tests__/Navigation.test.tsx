import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { Navigation } from '@/components/Navigation';
import enTranslations from '@/locales/en.json';

// Mock Next.js router
jest.mock('next/router', () => ({
  useRouter: () => ({
    pathname: '/',
    push: jest.fn(),
    query: {},
  }),
}));

describe('Navigation Component', () => {
  const mockOnLocaleChange = jest.fn();

  beforeEach(() => {
    mockOnLocaleChange.mockClear();
  });

  it('should render with English translations', () => {
    render(
      <Navigation
        translations={enTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    expect(screen.getByText('avante.nvim')).toBeInTheDocument();
    expect(screen.getByText('Home')).toBeInTheDocument();
    expect(screen.getByText('Features')).toBeInTheDocument();
    expect(screen.getByText('中文')).toBeInTheDocument();
  });

  it('should toggle mobile menu', () => {
    render(
      <Navigation
        translations={enTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    const menuButton = screen.getByLabelText('Toggle menu');
    fireEvent.click(menuButton);

    // Mobile menu should be visible with navigation items
    const homeButtons = screen.getAllByText('Home');
    expect(homeButtons.length).toBeGreaterThan(1); // Desktop + Mobile
  });

  it('should call scrollIntoView when navigation item is clicked', () => {
    const mockScrollIntoView = jest.fn();
    Element.prototype.scrollIntoView = mockScrollIntoView;

    // Create a mock element for the section
    const mockSection = document.createElement('div');
    mockSection.id = 'features';
    document.body.appendChild(mockSection);

    render(
      <Navigation
        translations={enTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    const featuresButton = screen.getAllByText('Features')[0];
    fireEvent.click(featuresButton);

    expect(mockScrollIntoView).toHaveBeenCalledWith({ behavior: 'smooth' });

    // Cleanup
    document.body.removeChild(mockSection);
  });
});
