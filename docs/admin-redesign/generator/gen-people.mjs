/** Draws the `people` batch: receipts, password requests, students.  node gen-people.mjs */
import './people-receipts.mjs';
import './people-password.mjs';
import './people-students.mjs';
import { finish } from './kit.mjs';
finish({ batch: 'people', rows: { PR: 'Receipts', PP: 'Password requests', PS: 'Students' } });
