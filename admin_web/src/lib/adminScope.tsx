import React, { createContext, useContext } from 'react';

export interface AdminProfile {
  id: string;
  email: string;
  full_name: string;
  role: 'super_admin' | 'company_admin';
  company_id: string | null;
  companyName: string | null;
}

const AdminScopeContext = createContext<AdminProfile | null>(null);

export const AdminScopeProvider: React.FC<{ admin: AdminProfile; children: React.ReactNode }> = ({ admin, children }) => (
  <AdminScopeContext.Provider value={admin}>{children}</AdminScopeContext.Provider>
);

export function useAdminScope(): AdminProfile {
  const admin = useContext(AdminScopeContext);
  if (!admin) throw new Error('Admin scope is unavailable');
  return admin;
}
