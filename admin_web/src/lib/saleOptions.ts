/** The subscription options a company sells; the database decides which are on sale (line_sale_options). */
export type SaleOption = 'first' | 'second' | 'both' | 'summer';

export const SALE_OPTIONS: SaleOption[] = ['first', 'second', 'both', 'summer'];

export const optionName: Record<SaleOption, string> = {
  first: 'الفصل الأول', second: 'الفصل الثاني', both: 'الفصلان معاً', summer: 'الفصل الصيفي',
};

/** Why an option is not offered to students right now. */
export const reasonText: Record<string, string> = {
  company_inactive: 'الشركة موقوفة',
  company_not_selling: 'الشركة لا تبيع هذه الفترة',
  line_inactive: 'الخط معطّل',
  line_not_offering: 'معطّل على هذا الخط',
  no_price: 'بدون سعر',
  advance_off: 'الاشتراك المسبق معطّل',
  not_in_season: 'ليس وقته الآن',
};

export interface SaleRow {
  option: SaleOption; label: string; phase: 'current' | 'upcoming'; price?: number | null;
  available: boolean; reason: string | null; start_date: string; end_date: string;
}
