import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import Navigation from '@/components/Navigation';

// Mock next/router
const mockPush = jest.fn();
jest.mock('next/router', () => ({
  useRouter() {
    return {
      pathname: '/',
      push: mockPush,
    };
  },
}));

// Mock lucide-react
jest.mock('lucide-react', () => ({
  Menu: () => <div data-testid="menu-icon">Menu</div>,
  X: () => <div data-testid="x-icon">X</div>,
  Globe: () => <div data-testid="globe-icon">Globe</div>,
}));

describe('Navigation Component', () => {
  const mockTranslations = {
    nav: {
      features: 'Features',
      installation: 'Installation',
      community: 'Community',
      docs: 'Documentation',
    },
  };

  const mockOnLocaleChange = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(() => {
    // Clean up any elements added to document
    document.getElementById('features')?.remove();
    document.getElementById('installation')?.remove();
    document.getElementById('community')?.remove();
  });

  it('should render navigation with logo and title', () => {
    render(
      <Navigation
        translations={mockTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    expect(screen.getByText('avante.nvim')).toBeInTheDocument();
    expect(screen.getByText('A')).toBeInTheDocument(); // Logo letter
  });

  it('should render navigation items', () => {
    render(
      <Navigation
        translations={mockTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    // Use getAllByText and check for specific counts or contexts
    const featuresItems = screen.getAllByText('Features');
    const installationItems = screen.getAllByText('Installation');
    const communityItems = screen.getAllByText('Community');
    const documentationItems = screen.getAllByText('Documentation');

    expect(featuresItems.length).toBeGreaterThan(0);
    expect(installationItems.length).toBeGreaterThan(0);
    expect(communityItems.length).toBeGreaterThan(0);
    expect(documentationItems.length).toBeGreaterThan(0);
  });

  it('should display correct language switcher text for English locale', () => {
    render(
      <Navigation
        translations={mockTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    expect(screen.getByText('中文')).toBeInTheDocument();
  });

  it('should display correct language switcher text for Chinese locale', () => {
    render(
      <Navigation
        translations={mockTranslations}
        locale="zh"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    expect(screen.getByText('EN')).toBeInTheDocument();
  });

  it('should call onLocaleChange and router.push when language switcher is clicked', () => {
    render(
      <Navigation
        translations={mockTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    const languageButton = screen.getByText('中文');
    fireEvent.click(languageButton);

    expect(mockOnLocaleChange).toHaveBeenCalledWith('zh');
    expect(mockPush).toHaveBeenCalledWith('/?lang=zh', undefined, { shallow: true });
  });

  it('should scroll to section when navigation item is clicked', () => {
    // Mock element with scrollIntoView
    const mockElement = document.createElement('div');
    mockElement.id = 'features';
    document.body.appendChild(mockElement);

    render(
      <Navigation
        translations={mockTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    // Get the first Features button (desktop navigation)
    const featuresButtons = screen.getAllByText('Features');
    const desktopFeaturesButton = featuresButtons[0]; // First one should be desktop

    fireEvent.click(desktopFeaturesButton);

    expect(Element.prototype.scrollIntoView).toHaveBeenCalledWith({ behavior: 'smooth' });
  });

  it('should toggle mobile menu when menu button is clicked', () => {
    render(
      <Navigation
        translations={mockTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    // Initially, mobile menu should be hidden
    const mobileMenu = screen.getByRole('button', { name: /menu/i });
    expect(screen.getByTestId('menu-icon')).toBeInTheDocument();

    // Click to open mobile menu
    fireEvent.click(mobileMenu);
    expect(screen.getByTestId('x-icon')).toBeInTheDocument();

    // Click to close mobile menu
    fireEvent.click(mobileMenu);
    expect(screen.getByTestId('menu-icon')).toBeInTheDocument();
  });

  it('should close mobile menu when navigation item is clicked', async () => {
    const mockElement = document.createElement('div');
    mockElement.id = 'features';
    document.body.appendChild(mockElement);

    render(
      <Navigation
        translations={mockTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    // Open mobile menu
    const mobileMenuButton = screen.getByRole('button', { name: /menu/i });
    fireEvent.click(mobileMenuButton);
    expect(screen.getByTestId('x-icon')).toBeInTheDocument();

    // Click on a navigation item in mobile menu
    const mobileNavItems = screen.getAllByText('Features');
    const mobileFeatures = mobileNavItems.find(item =>
      item.closest('.md\\:hidden')
    );

    if (mobileFeatures) {
      fireEvent.click(mobileFeatures);

      // Menu should be closed (showing Menu icon instead of X icon)
      await waitFor(() => {
        expect(screen.getByTestId('menu-icon')).toBeInTheDocument();
      });
    }
  });

  it('should render GitHub documentation link', () => {
    render(
      <Navigation
        translations={mockTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    const docLinks = screen.getAllByText('Documentation');
    const externalDocLink = docLinks.find(link =>
      link.closest('a[href="https://github.com/yetone/avante.nvim"]')
    );

    expect(externalDocLink).toBeInTheDocument();
  });

  it('should handle non-existent section scroll gracefully', () => {
    render(
      <Navigation
        translations={mockTranslations}
        locale="en"
        onLocaleChange={mockOnLocaleChange}
      />
    );

    // Click on a section that doesn't exist
    const featuresButtons = screen.getAllByText('Features');
    const featuresButton = featuresButtons[0];
    fireEvent.click(featuresButton);

    // Should not throw an error (getElementById returns null)
    expect(true).toBe(true); // Test passes if no error is thrown
  });
});