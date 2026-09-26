export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export interface Database {
  public: {
    Tables: {
      companies: {
        Row: {
          id: string;
          name: string;
          is_active: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          is_active?: boolean;
          created_at?: string;
        };
        Update: {
          id?: string;
          name?: string;
          is_active?: boolean;
          created_at?: string;
        };
      };
      lines: {
        Row: {
          id: string;
          company_id: string;
          name: string;
          supervisor_id: string | null;
          price_termly: number;
          price_yearly: number;
          price_daily: number;
          is_active: boolean;
          created_at: string;
        };
      };
      stations: {
        Row: {
          id: string;
          line_id: string;
          name: string;
          order_index: number;
          departure_time: string;
          return_time: string;
          created_at: string;
        };
      };
      supervisors: {
        Row: {
          id: string;
          phone: string;
          full_name: string;
          company_id: string;
          created_by_admin_id: string | null;
          is_active: boolean;
          created_at: string;
        };
      };
      students: {
        Row: {
          id: string;
          phone: string;
          full_name: string;
          university: string;
          qr_code_value: string;
          created_at: string;
        };
      };
      subscriptions: {
        Row: {
          id: string;
          student_id: string;
          line_id: string;
          station_id: string;
          type: 'termly' | 'yearly' | 'daily';
          status: 'pending_payment' | 'pending_review' | 'active' | 'rejected' | 'expired';
          start_date: string | null;
          end_date: string | null;
          price: number;
          created_at: string;
        };
      };
      receipts: {
        Row: {
          id: string;
          subscription_id: string;
          image_url: string;
          status: 'pending' | 'approved' | 'rejected';
          rejection_reason: string | null;
          attempt_number: number;
          reviewed_by: string | null;
          created_at: string;
          reviewed_at: string | null;
        };
      };
      daily_ride_status: {
        Row: {
          id: string;
          student_id: string;
          ride_date: string;
          is_riding: boolean;
          toggled_at: string;
        };
      };
      chat_messages: {
        Row: {
          id: string;
          student_id: string;
          supervisor_id: string;
          sender_role: 'student' | 'supervisor';
          message: string;
          created_at: string;
        };
      };
      complaints: {
        Row: {
          id: string;
          student_id: string;
          title: string;
          message: string;
          status: 'open' | 'in_progress' | 'resolved';
          created_at: string;
        };
      };
    };
  };
}
