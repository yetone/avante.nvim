import type { AppProps } from 'next/app';
import { useRouter } from 'next/router';
import '@/styles/globals.css';
import ErrorBoundary from '@/components/ErrorBoundary';
import Analytics from '@/components/Analytics';

export default function App({ Component, pageProps }: AppProps) {
  const router = useRouter();
  const measurementId = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;
  
  return (
    <ErrorBoundary>
      <Analytics measurementId={measurementId} />
      <Component {...pageProps} />
    </ErrorBoundary>
  );
}