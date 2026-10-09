/** The financial report, a part at a time (pure helpers; the page does the asking). */

/** How many rows are asked for at a time. */
export const REPORT_PAGE = 100;

/**
 * One answer of admin_subscription_report. `rows_total` is how many rows match
 * the filters in all; a database that does not page yet leaves it out and
 * answers with every row at once.
 */
export interface ReportPart<Row, Totals> { baseline: string | null; totals: Totals; rows: Row[]; rows_total?: number | null }

/** Where the next part starts, or `undefined` when everything is loaded. */
export function nextReportOffset<Row, Totals>(parts: readonly ReportPart<Row, Totals>[]): number | undefined {
  const last = parts[parts.length - 1];
  // No count in the answer: the older function, which has already sent all it has.
  if (!last || typeof last.rows_total !== 'number' || last.rows.length === 0) return undefined;
  const loaded = parts.reduce((sum, part) => sum + part.rows.length, 0);
  return loaded < last.rows_total ? loaded : undefined;
}

/**
 * The parts as one report: the rows in order (a row that moved between two
 * parts while they were read appears once), and the totals, which always cover
 * every matching row, from the freshest part.
 */
export function mergeReport<Row extends { id: string }, Totals>(parts: readonly ReportPart<Row, Totals>[]) {
  const last = parts[parts.length - 1];
  if (!last) return null;
  const seen = new Set<string>();
  const rows = parts.flatMap((part) => part.rows).filter((row) => (seen.has(row.id) ? false : (seen.add(row.id), true)));
  return {
    baseline: last.baseline, totals: last.totals, rows,
    rowsTotal: typeof last.rows_total === 'number' ? Math.max(last.rows_total, rows.length) : rows.length,
  };
}
