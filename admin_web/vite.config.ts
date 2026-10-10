import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  root: path.resolve(__dirname),
  // Absolute asset URLs: with './' a deep link such as /reset-password/x asked for
  // /reset-password/assets/*.css, which the SPA rewrite answered with index.html.
  base: '/',
  build: {
    rollupOptions: {
      output: {
        // Libraries change far less often than the pages: in their own files they
        // stay in the browser's cache across dashboard releases, and download in
        // parallel with the app's own code.
        manualChunks(id) {
          // Helpers of a few hundred bytes that many pages share: one file instead of
          // six separate requests. They import nothing of the app (only React), so
          // grouping them cannot tie two pages' code together.
          if (/\/src\/lib\/(guard|rpc|resetRequests|toasts|time|recentChanges|branding)\.ts$/.test(id)) return 'kit';
          if (!id.includes('node_modules')) return undefined;
          if (/node_modules\/(react|react-dom|scheduler|react-router|react-router-dom|@remix-run)\//.test(id)) return 'react';
          if (id.includes('node_modules/@supabase/')) return 'supabase';
          if (id.includes('node_modules/@tanstack/')) return 'query';
          // The icons each page uses are tiny; one shared file beats dozens of 0.5 kB requests.
          if (id.includes('node_modules/lucide-react/')) return 'icons';
          return undefined;
        },
      },
    },
  },
});
