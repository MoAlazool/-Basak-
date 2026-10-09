// The cache module keeps a copy in the tab's sessionStorage as soon as it is
// imported. Tests run without a browser, so they get a plain in-memory one.
const memory = new Map<string, string>();
const tabStorage = {
  getItem: (key: string) => memory.get(key) ?? null,
  setItem: (key: string, value: string) => { memory.set(key, value); },
  removeItem: (key: string) => { memory.delete(key); },
};
const scope = globalThis as unknown as { window?: unknown };
scope.window ??= { sessionStorage: tabStorage, setTimeout, clearTimeout };
