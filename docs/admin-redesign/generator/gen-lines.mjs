/** Draws the `lines` batch: node gen-lines.mjs */
import './lines-a.mjs';
import './lines-b.mjs';
import './lines-c.mjs';
import './lines-d.mjs';
import { finish } from './kit.mjs';
finish({ batch: 'lines', rows: { L: 'Lines', W: 'New line and editing', R: 'Ride confirmation', S: 'Supervisors', M: 'Company managers' } });
