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

/** Who is signed in. */
export function useAdminScope(): AdminProfile {
  const admin = useContext(AdminScopeContext);
  if (!admin) throw new Error('Admin scope is unavailable');
  return admin;
}

export type CompanyStatus = 'active' | 'suspended' | 'archived';

export interface CompanyScope {
  id: string;
  name: string;
  status: CompanyStatus;
}

const CompanyScopeContext = createContext<CompanyScope | null>(null);

export const CompanyScopeProvider: React.FC<{ company: CompanyScope; children: React.ReactNode }> = ({ company, children }) => (
  <CompanyScopeContext.Provider value={company}>{children}</CompanyScopeContext.Provider>
);

/**
 * The company whose workspace is open. Every workspace page reads and writes
 * this company only, whoever is signed in.
 */
export function useCompany(): CompanyScope {
  const company = useContext(CompanyScopeContext);
  if (!company) throw new Error('This page belongs to a company workspace');
  return company;
}

export const companyStatusLabel: Record<CompanyStatus, string> = {
  active: 'مفعّلة',
  suspended: 'موقوفة',
  archived: 'مؤرشفة',
};
