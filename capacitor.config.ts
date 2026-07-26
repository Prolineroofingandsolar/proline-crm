import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.prolineroofingandsolar.crm',
  appName: 'ProLine CRM',
  // Vite builds the web app into dist/ — Capacitor bundles that into the native app.
  webDir: 'dist',
  ios: {
    // Matches the dark launch/brand background so there's no white flash on start.
    backgroundColor: '#111827',
    // Let the web content flow under the status bar / home indicator; the app
    // already handles safe-area insets in CSS.
    contentInset: 'never',
  },
};

export default config;
