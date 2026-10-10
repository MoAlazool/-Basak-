/** Draws the foundation boards: node gen-foundation.mjs */
import './f-system.mjs';
import './f-components.mjs';
import './f-shell.mjs';
import './f-today.mjs';
import { finish } from './kit.mjs';
finish({ batch: 'foundation', rows: { A: 'Foundations', B: 'Shell', C: 'Today' } });
