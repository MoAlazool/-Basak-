import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  root: path.resolve(__dirname),
  // Absolute asset URLs: with './' a deep link such as /reset-password/x asked for
  // /reset-password/assets/*.css, which the SPA rewrite answered with index.html.
  base: '/',
});
