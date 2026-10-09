import { defineConfig } from 'vitest/config';

// Pure logic only: no browser, no network, no timers that depend on the clock.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
    setupFiles: ['src/test/setup.ts'],
  },
});
