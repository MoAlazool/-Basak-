import { supabase } from './supabase';

export interface UniversityOption { id: string; name: string; }

export interface StationOption {
  id: string; name: string; is_active: boolean; order_index: number;
}

export interface TripOption {
  id: string; direction: 'departure' | 'return'; label: string; start_time: string;
  university_id: string | null; is_active: boolean;
  line_trip_stops: { station_id: string; stop_time: string }[];
}

export interface LineOption {
  id: string; name: string; company_id: string; price_termly: number; price_yearly: number; price_daily: number;
  line_period_prices?: { option: string; price: number }[];
  stations: StationOption[];
  line_trips: TripOption[];
}

export interface LineOptions { universities: UniversityOption[]; lines: LineOption[]; }

/**
 * What a form chooses from: the active universities and the company's active
 * lines with their stations and trips. One loader for `keys.company(id, 'lineOptions')`,
 * so every page that needs these shares one cached copy of the same shape.
 */
export async function loadLineOptions(companyId: string): Promise<LineOptions> {
  const [uniRes, lineRes] = await Promise.all([
    supabase.from('universities').select('id, name').eq('is_active', true).order('name'),
    supabase.from('lines')
      .select('id,name,company_id,price_termly,price_yearly,price_daily,line_period_prices(option,price),stations(id,name,is_active,order_index),line_trips(id,direction,label,start_time,university_id,is_active,line_trip_stops(station_id,stop_time))')
      .eq('company_id', companyId).eq('is_active', true).order('name'),
  ]);
  if (uniRes.error) throw new Error(uniRes.error.message);
  if (lineRes.error) throw new Error(lineRes.error.message);
  return { universities: (uniRes.data || []) as UniversityOption[], lines: (lineRes.data || []) as unknown as LineOption[] };
}
