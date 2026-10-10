/** Draws the platform (super admin) boards: node gen-platform.mjs */
import './p-queues.mjs';
import './p-companies.mjs';
import './p-people.mjs';
import './p-settings.mjs';
import './p-workspace.mjs';
import { finish } from './kit.mjs';
finish({ batch: 'platform', rows: { A: 'Platform today', B: 'Correction requests', C: 'Password requests', D: 'Companies', E: 'Company admins', F: 'All students', G: 'Platform notifications', H: 'Universities', I: 'Defaults', J: 'App versions', K: 'Inside a company' } });
