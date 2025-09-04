import { useEffect } from 'react';
import { useRouter } from 'next/router';

declare global {
  interface Window {
    gtag?: (...args: any[]) => void;
    dataLayer?: any[];
  }
}

interface AnalyticsProps {
  measurementId?: string;
}

const Analytics: React.FC<AnalyticsProps> = ({ measurementId }) => {
  const router = useRouter();

  useEffect(() => {
    if (!measurementId || typeof window === 'undefined') return;

    // Initialize Google Analytics
    const script1 = document.createElement('script');
    script1.src = `https://www.googletagmanager.com/gtag/js?id=${measurementId}`;
    script1.async = true;
    document.head.appendChild(script1);

    const script2 = document.createElement('script');
    script2.innerHTML = `
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', '${measurementId}', {
        page_title: document.title,
        page_location: window.location.href,
      });
    `;
    document.head.appendChild(script2);

    // Clean up
    return () => {
      document.head.removeChild(script1);
      document.head.removeChild(script2);
    };
  }, [measurementId]);

  useEffect(() => {
    if (!measurementId || typeof window === 'undefined' || !window.gtag) return;

    const handleRouteChange = (url: string) => {
      window.gtag('config', measurementId, {
        page_path: url,
      });
    };

    router.events.on('routeChangeComplete', handleRouteChange);
    return () => {
      router.events.off('routeChangeComplete', handleRouteChange);
    };
  }, [measurementId, router.events]);

  // Track Core Web Vitals
  useEffect(() => {
    if (typeof window === 'undefined') return;

    const trackWebVitals = () => {
      import('web-vitals').then(({ getCLS, getFID, getFCP, getLCP, getTTFB }) => {
        const sendToAnalytics = (metric: any) => {
          if (window.gtag && measurementId) {
            window.gtag('event', metric.name, {
              event_category: 'Web Vitals',
              value: Math.round(metric.name === 'CLS' ? metric.value * 1000 : metric.value),
              event_label: metric.id,
              non_interaction: true,
            });
          }
        };

        getCLS(sendToAnalytics);
        getFID(sendToAnalytics);
        getFCP(sendToAnalytics);
        getLCP(sendToAnalytics);
        getTTFB(sendToAnalytics);
      }).catch(() => {
        // Fallback if web-vitals package is not available
      });
    };

    trackWebVitals();
  }, [measurementId]);

  return null;
};

export default Analytics;
