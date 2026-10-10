# Design canvas — source files

A copy of the redesign canvas as it stood when the app was built from it
(live canvas: https://claude.ai/artifact/NveQBomjGxfsYtg6W5LWdk).

- One file per artboard: `<Name>.dc.html`. `canvas.json` is the index
  (position, size and title of every board).
- The files are the canvas's own source format; they render inside the
  canvas, not as standalone pages. Sizes, colours and Arabic copy in their
  inline styles are the values the Flutter screens were built from.
- All names, prices, phone numbers and payment addresses in them are sample content.

One deliberate difference from the boards: the tab bar's ink pill follows the
selected tab instead of staying on the card (or scanner) tab.
