'use client';

import { usePathname, useRouter } from 'next/navigation';
import { useLocale } from 'next-intl';

export default function LanguageSwitcher() {
  const locale = useLocale();
  const router = useRouter();
  const pathname = usePathname();

  const switchLanguage = (newLocale: string) => {
    // Remove current locale from pathname and add new locale
    const segments = pathname.split('/').filter(Boolean);
    if (segments[0] === 'en' || segments[0] === 'zh') {
      segments[0] = newLocale;
    } else {
      segments.unshift(newLocale);
    }
    router.push('/' + segments.join('/'));
  };

  return (
    <div className="flex items-center space-x-2">
      <button
        onClick={() => switchLanguage('en')}
        className={`px-2 py-1 text-sm transition-colors ${
          locale === 'en'
            ? 'text-white font-semibold'
            : 'text-gray-400 hover:text-gray-300'
        }`}
      >
        English
      </button>
      <span className="text-gray-600">|</span>
      <button
        onClick={() => switchLanguage('zh')}
        className={`px-2 py-1 text-sm transition-colors ${
          locale === 'zh'
            ? 'text-white font-semibold'
            : 'text-gray-400 hover:text-gray-300'
        }`}
      >
        中文
      </button>
    </div>
  );
}
