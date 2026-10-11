/** Answers shared by many pages: the overviews, the students page, the receipts queue, reset requests. */
import { registerRpc } from '../registry';
import { COMPANY_ID, COMPANY2_ID, LINES, LINE_SUBSCRIBERS, RECEIPTS, RESET_REQUESTS, STUDENTS, TODAY, TOMORROW, tables } from '../data';

const week = Array.from({ length: 7 }, (_, i) => ({ date: new Date(Date.now() - (6 - i) * 86_400_000).toISOString().slice(0, 10), riders: [402, 455, 470, 0, 0, 488, 512][i] }));
const companyRow = (id: string) => {
  const c = tables.companies.find((x) => x.id === id)!;
  return { id: c.id, name: c.name, status: c.status, created_at: c.created_at, logo_path: c.logo_path, emblem_path: c.emblem_path };
};
const overview = (id: string) => (id === COMPANY_ID ? {
  company: companyRow(id), baseline: null, members: 718, active_subscriptions: 642, pending_receipts: RECEIPTS.length, revenue: 1_912_500,
  riders_today: 488, next_ride_date: TOMORROW, riders_next: 512, vote_closes_at: '06:00', riders_week: week, lines: LINES.length,
  active_lines: LINES.filter((l) => l.is_active).length, supervisors: 5, admins: 2,
  top_lines: LINES.slice(0, 5).map((l) => ({ id: l.id, name: l.name, is_active: l.is_active, subscribers: LINE_SUBSCRIBERS[l.id] })),
} : {
  company: companyRow(id), baseline: null, members: 212, active_subscriptions: 190, pending_receipts: 2, revenue: 610_000, riders_today: 140,
  next_ride_date: TOMORROW, riders_next: 151, vote_closes_at: '06:00', riders_week: week.map((d) => ({ ...d, riders: Math.round(d.riders / 3) })),
  lines: 3, active_lines: 3, supervisors: 2, admins: 1, top_lines: [],
});

registerRpc({
  company_overview: ({ p_company_id }) => overview(p_company_id),
  platform_overview: () => {
    const per = [overview(COMPANY_ID), overview(COMPANY2_ID)];
    return {
      companies: { total: 2, active: 2, suspended: 0, archived: 0 }, students: 930, members: 930, active_subscriptions: 832, pending_receipts: per.reduce((a, c) => a + c.pending_receipts, 0),
      revenue: 2_522_500, riders_today: 628, next_ride_date: TOMORROW, riders_next: 663, vote_closes_at: '06:00', riders_week: week, lines: 11, supervisors: 7,
      top_lines: per[0].top_lines, per_company: per.map(({ top_lines: _t, riders_week: _w, ...rest }) => rest),
    };
  },
  get_company_students_page: ({ p_search, p_limit = 25, p_offset = 0, p_with_total }) => {
    const term = (p_search ?? '').trim();
    const rows = STUDENTS.filter((s) => !term || s.full_name.includes(term) || s.phone.includes(term.replace(/\s/g, '')));
    return { rows: rows.slice(p_offset, p_offset + p_limit), has_next: p_offset + p_limit < rows.length, total: p_with_total ? rows.length : null };
  },
  get_pending_receipts_page: ({ p_limit = 50 }) => ({ rows: RECEIPTS.slice(0, p_limit), has_more: RECEIPTS.length > p_limit, total: RECEIPTS.length }),
  admin_list_password_reset_requests: () => RESET_REQUESTS,
  platform_students: ({ p_search, p_limit = 25, p_offset = 0 }) => {
    const term = (p_search ?? '').trim();
    const rows = STUDENTS.filter((s) => !term || s.full_name.includes(term) || s.phone.includes(term)).map((s) => ({
      id: s.id, full_name: s.full_name, phone: s.phone, university: s.university, created_at: s.created_at,
      memberships: [{ company_id: COMPANY_ID, company_name: 'النورس للنقل', status: 'active' }], active_subscriptions: s.subscriptions[0].status === 'active' ? 1 : 0,
    }));
    return { total: rows.length, rows: rows.slice(p_offset, p_offset + p_limit) };
  },
});
void TODAY;

// The governorates a company serves (lib/governorates.ts): replaced as a set, answered in list order.
registerRpc({
  set_company_governorates: ({ p_company_id, p_codes }) => {
    const order = new Map(tables.governorates.map((g) => [g.code, g.sort_order]));
    const codes = [...new Set<string>(p_codes ?? [])].filter((c) => order.has(c)).sort((a, b) => order.get(a)! - order.get(b)!);
    tables.company_governorates = [
      ...tables.company_governorates.filter((r) => r.company_id !== p_company_id),
      ...codes.map((governorate_code) => ({ company_id: p_company_id, governorate_code })),
    ];
    return codes;
  },
});
