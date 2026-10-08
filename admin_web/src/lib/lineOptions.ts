/** The shapes the forms and the audience picker choose from. Loaded by `useLineOptions` (lib/reference.ts). */

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

