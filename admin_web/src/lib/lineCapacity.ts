/**
 * How many riders one bus of a line takes (`lines.bus_capacity`, optional).
 * The supervisor's app uses it to say how many buses a trip needs. Pure helpers
 * for the line form; the value is saved through `set_line_bus_capacity`.
 */

export const BUS_CAPACITY_MAX = 500;

export type CapacityInput = { ok: true; value: number | null } | { ok: false; message: string };

/** The field's text as a capacity: empty clears it, otherwise a whole number from 1 to 500 (Arabic digits accepted). */
export function parseBusCapacity(text: string): CapacityInput {
  const western = text.trim().replace(/[٠-٩]/g, (digit) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(digit)));
  if (western === '') return { ok: true, value: null };
  const value = Number(western);
  if (!/^\d+$/.test(western) || value < 1 || value > BUS_CAPACITY_MAX) {
    return { ok: false, message: `عدد مقاعد الباص رقم صحيح من 1 إلى ${BUS_CAPACITY_MAX}، أو اتركه فارغاً.` };
  }
  return { ok: true, value };
}

/** The saved value as the field shows it. */
export const capacityText = (capacity: number | null | undefined) => (capacity ? String(capacity) : '');
