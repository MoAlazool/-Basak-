/** Batch `money`: subscription periods, payment methods, revenue, notifications, student card, receipt details, sign-in. */
import { finish } from './kit.mjs';
const only = process.env.ONLY?.split(',');
const mods = ['m-dates', 'm-pay', 'm-revenue', 'm-notify', 'm-card', 'm-receiptinfo', 'm-signin'];
for (const m of mods) { if (only && !only.includes(m)) continue; try { await import(`./${m}.mjs`); } catch (e) { if (e.code === 'ERR_MODULE_NOT_FOUND' && String(e.message).includes(m)) continue; throw e; } }
finish({ batch: 'money', rows: { D: 'Subscription periods', E: 'Payment methods', F: 'Revenue', G: 'Notifications', H: 'Student card', I: 'Receipt details', J: 'Sign-in and global pieces' } });
