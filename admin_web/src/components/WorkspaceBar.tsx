import React, { useEffect, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { ArrowRight, Building2 } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { companyStatusLabel, useAdminScope, useCompany } from '../lib/adminScope';

/**
 * Says whose workspace is open. The platform admin can also step back to the
 * platform or move to another company, staying on the same page.
 */
export const WorkspaceBar: React.FC = () => {
  const admin = useAdminScope();
  const company = useCompany();
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const [companies, setCompanies] = useState<{ id: string; name: string }[]>([]);
  const isPlatformAdmin = admin.role === 'super_admin';

  useEffect(() => {
    if (!isPlatformAdmin) return;
    void supabase.from('companies').select('id, name').order('name').then(({ data }) => setCompanies(data ?? []));
  }, [isPlatformAdmin]);

  if (!isPlatformAdmin && company.status === 'active') return null;

  const page = pathname.split('/').slice(3).join('/');
  return (
    <div className="mb-5 flex flex-wrap items-center gap-3 rounded-2xl border border-[#BFE3F3] bg-white/80 px-4 py-2.5 text-sm">
      {isPlatformAdmin && (
        <Link to="/platform/companies" className="inline-flex items-center gap-1.5 rounded-xl bg-slate-100 px-3 py-1.5 text-xs font-bold text-slate-700 hover:bg-slate-200">
          <ArrowRight className="h-3.5 w-3.5" /> العودة إلى المنصة
        </Link>
      )}
      <span className="inline-flex items-center gap-1.5 font-extrabold text-[#1F2937]">
        <Building2 className="h-4 w-4 text-[#3E8FBF]" /> {company.name}
      </span>
      {company.status !== 'active' && (
        <span className="rounded-full bg-amber-100 px-2.5 py-0.5 text-[11px] font-bold text-amber-800">{companyStatusLabel[company.status]}</span>
      )}
      {isPlatformAdmin && companies.length > 1 && (
        <select
          aria-label="الانتقال إلى شركة أخرى"
          value={company.id}
          onChange={(e) => navigate(`/c/${e.target.value}${page ? `/${page}` : ''}`)}
          className="mr-auto rounded-xl border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold"
        >
          {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      )}
    </div>
  );
};
