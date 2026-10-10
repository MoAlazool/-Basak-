import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

// The fonts load without blocking the first paint (media=print in index.html), then apply.
// Done here, not with an inline onload: the Content-Security-Policy allows no inline script.
document.getElementById('web-fonts')?.setAttribute('media', 'all');

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
