import React, { Suspense } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { Shell } from '../components/Shell';
import { SkeletonPage } from '../components/Skeleton';
import { platformNav } from '../lib/nav';
import { usePlatformSync } from '../lib/sync';
import {
  AllCompaniesPage, AllStudentsPage, AppVersionsPage, CompanyAdminsPage, PlatformDefaultsPage, PlatformNotificationsPage,
  PlatformOverviewPage, UniversitiesPage,
} from '../lib/routes';

/** The platform admin's area: everything that spans companies. */
export const PlatformArea: React.FC<{ onLogout: () => void }> = ({ onLogout }) => {
  usePlatformSync();
  return (
    <Shell items={platformNav} areaLabel="إدارة المنصة" onLogout={onLogout}>
      {/* The frame stays; only the page area waits for a page's code the first time it is opened. */}
      <Suspense fallback={<SkeletonPage />}>
        <Routes>
          <Route index element={<PlatformOverviewPage />} />
          <Route path="companies" element={<AllCompaniesPage />} />
          <Route path="students" element={<AllStudentsPage />} />
          <Route path="notifications" element={<PlatformNotificationsPage />} />
          <Route path="admins" element={<CompanyAdminsPage />} />
          <Route path="universities" element={<UniversitiesPage />} />
          <Route path="defaults" element={<PlatformDefaultsPage />} />
          <Route path="app-versions" element={<AppVersionsPage />} />
          <Route path="*" element={<Navigate to="/platform" replace />} />
        </Routes>
      </Suspense>
    </Shell>
  );
};
