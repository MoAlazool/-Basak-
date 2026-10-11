import React from 'react';
import { Card, Page, PageHeader } from '../ui';
import { useCompany } from '../lib/adminScope';
import { CompanyGovernoratesCard } from '../components/CompanyGovernoratesCard';

/**
 * «المحافظات»: the governorates the company serves, chosen from the list. In
 * the app a student picks theirs first and sees only the companies that serve
 * it, so a company that has chosen none is not shown under any.
 */
export const GovernoratesPage: React.FC = () => {
  const company = useCompany();
  return (
    <Page>
      <PageHeader title="المحافظات"
        sub="يختار الطالب محافظته أولاً عند الاشتراك، ثم تظهر له الشركات التي تخدمها فقط. اختر كل المحافظات التي تخدمها شركتك." />
      <Card as="section" className="flex flex-col gap-3 p-4 lg:p-6">
        <h2 className="m-0 text-card">المحافظات التي تخدمها {company.name}</h2>
        <CompanyGovernoratesCard companyId={company.id} />
      </Card>
    </Page>
  );
};
