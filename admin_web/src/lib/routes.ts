import { lazy, type ComponentType } from 'react';

/**
 * Every page is its own file on the wire: it is downloaded when first opened,
 * or a moment earlier when the admin points at its entry in the navigation.
 * A company admin never downloads the platform's pages, and the reverse holds
 * until a platform admin opens a company.
 */
type Loader<M> = () => Promise<M>;

/** A lazily loaded page plus `preload()` to fetch its code ahead of the click. */
function page<M, K extends keyof M>(load: Loader<M>, name: K) {
  let pending: Promise<M> | undefined;
  const once = () => (pending ??= load().catch((error) => { pending = undefined; throw error; }));
  const Component = lazy(() => once().then((module) => ({ default: module[name] as ComponentType<any> })));
  return Object.assign(Component, { preload: () => { void once().catch(() => undefined); } });
}

// The two areas and the signed-out pages.
export const PlatformArea = page(() => import('../areas/PlatformArea'), 'PlatformArea');
export const Workspace = page(() => import('../areas/Workspace'), 'Workspace');
export const LoginPage = page(() => import('../pages/LoginPage'), 'LoginPage');
export const ResetPasswordPage = page(() => import('../pages/ResetPasswordPage'), 'ResetPasswordPage');

// Platform admin.
export const PlatformOverviewPage = page(() => import('../pages/PlatformOverviewPage'), 'PlatformOverviewPage');
export const AllCompaniesPage = page(() => import('../pages/AllCompaniesPage'), 'AllCompaniesPage');
export const AllStudentsPage = page(() => import('../pages/AllStudentsPage'), 'AllStudentsPage');
export const PlatformNotificationsPage = page(() => import('../pages/PlatformNotificationsPage'), 'PlatformNotificationsPage');
export const CompanyAdminsPage = page(() => import('../pages/CompanyAdminsPage'), 'CompanyAdminsPage');
export const UniversitiesPage = page(() => import('../pages/UniversitiesPage'), 'UniversitiesPage');
export const PlatformDefaultsPage = page(() => import('../pages/SubscriptionSettingsPage'), 'PlatformDefaultsPage');

// One company's workspace.
export const OverviewPage = page(() => import('../pages/OverviewPage'), 'OverviewPage');
export const StudentsPage = page(() => import('../pages/StudentsPage'), 'StudentsPage');
export const ReceiptsPage = page(() => import('../pages/ReceiptsPage'), 'ReceiptsPage');
export const LinesPage = page(() => import('../pages/LinesPage'), 'LinesPage');
export const SupervisorsPage = page(() => import('../pages/SupervisorsPage'), 'SupervisorsPage');
export const NotificationsPage = page(() => import('../pages/NotificationsPage'), 'NotificationsPage');
export const ReportsPage = page(() => import('../pages/ReportsPage'), 'ReportsPage');
export const PaymentMethodsPage = page(() => import('../pages/PaymentMethodsPage'), 'PaymentMethodsPage');
export const WalletCardDesignPage = page(() => import('../pages/WalletCardDesignPage'), 'WalletCardDesignPage');
export const TeamPage = page(() => import('../pages/TeamPage'), 'TeamPage');
export const CompanySettingsPage = page(() => import('../pages/SubscriptionSettingsPage'), 'CompanySettingsPage');
