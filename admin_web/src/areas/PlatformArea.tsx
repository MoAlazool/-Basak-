import React, { Suspense } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { AppShell } from '../shell/AppShell';
import { SkeletonPage } from '../components/Skeleton';
import { PLATFORM_NAV } from '../lib/nav';
import { usePlatformSync } from '../lib/sync';
import { keys, usePageData } from '../lib/query';
import { supabase } from '../lib/supabase';
import { useAdminScope } from '../lib/adminScope';
import { useResetRequestCount, useTabCount, whoOf } from './Workspace';
import {
  AllStudentsPage, AppVersionsPage, PlatformAnalyticsPage, PlatformBillingPage, PlatformRecapPage, CompaniesPage, CompanyAdminsPage, CompanyNewPage, CorrectionsPage, PlatformDefaultsPage,
  MerchantsPage, OffersPage, PlatformNotificationsPage, PlatformPasswordRequestsPage, PlatformTodayPage, UniversitiesPage,
} from '../lib/routes';

/** Corrections companies sent that wait on the platform admin, counted by the server. */
export const useOpenCorrectionsCount = () => usePageData(keys.platform('corrections', 'count'), async () => {
  const { count, error } = await supabase.from('student_correction_requests').select('id', { head: true, count: 'exact' }).eq('status', 'pending');
  if (error) throw new Error(error.message);
  return count ?? 0;
}).data ?? 0;

/** The platform admin's area: everything that spans companies. */
export const PlatformArea: React.FC<{ onLogout: () => void }> = ({ onLogout }) => {
  usePlatformSync();
  const admin = useAdminScope();
  const corrections = useOpenCorrectionsCount();
  const requests = useResetRequestCount(null);
  useTabCount(corrections + requests);
  return (
    <AppShell role="platform" groups={PLATFORM_NAV} base="/platform" scope="إدارة المنصة" who={whoOf(admin)} onLogout={onLogout}
      badges={{ corrections, requests }}>
      {/* The frame stays; only the page area waits for a page's code the first time it is opened. */}
      <Suspense fallback={<SkeletonPage />}>
        <Routes>
          <Route index element={<PlatformTodayPage />} />
          <Route path="corrections" element={<CorrectionsPage />} />
          <Route path="password-requests" element={<PlatformPasswordRequestsPage />} />
          <Route path="companies" element={<CompaniesPage />} />
          <Route path="companies/new" element={<CompanyNewPage />} />
          <Route path="admins" element={<CompanyAdminsPage />} />
          <Route path="students" element={<AllStudentsPage />} />
          <Route path="notifications" element={<PlatformNotificationsPage />} />
          <Route path="merchants" element={<MerchantsPage />} />
          <Route path="offers" element={<OffersPage />} />
          <Route path="universities" element={<UniversitiesPage />} />
          <Route path="defaults" element={<PlatformDefaultsPage />} />
          <Route path="app-versions" element={<AppVersionsPage />} />
          <Route path="recap" element={<PlatformRecapPage />} />
          <Route path="analytics" element={<PlatformAnalyticsPage />} />
          <Route path="billing" element={<PlatformBillingPage />} />
          <Route path="*" element={<Navigate to="/platform" replace />} />
        </Routes>
      </Suspense>
    </AppShell>
  );
};
