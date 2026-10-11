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

// Platform admin (docs/admin-redesign/generator/README.md · navigation).
export const PlatformTodayPage = page(() => import('../pages/platform/PlatformTodayPage'), 'PlatformTodayPage');
export const CorrectionsPage = page(() => import('../pages/platform/CorrectionsPage'), 'CorrectionsPage');
export const PlatformPasswordRequestsPage = page(() => import('../pages/PasswordRequestsPage'), 'PlatformPasswordRequestsPage');
export const CompaniesPage = page(() => import('../pages/platform/CompaniesPage'), 'CompaniesPage');
export const CompanyNewPage = page(() => import('../pages/platform/CompanyNewPage'), 'CompanyNewPage');
export const CompanyAdminsPage = page(() => import('../pages/platform/CompanyAdminsPage'), 'CompanyAdminsPage');
export const AllStudentsPage = page(() => import('../pages/platform/AllStudentsPage'), 'AllStudentsPage');
export const PlatformNotificationsPage = page(() => import('../pages/platform/PlatformNotificationsPage'), 'PlatformNotificationsPage');
export const UniversitiesPage = page(() => import('../pages/platform/UniversitiesPage'), 'UniversitiesPage');
export const PlatformDefaultsPage = page(() => import('../pages/platform/PlatformDefaultsPage'), 'PlatformDefaultsPage');
export const AppVersionsPage = page(() => import('../pages/platform/AppVersionsPage'), 'AppVersionsPage');
export const PlatformAnalyticsPage = page(() => import('../pages/platform/PlatformAnalyticsPage'), 'PlatformAnalyticsPage');
export const PlatformBillingPage = page(() => import('../pages/platform/PlatformBillingPage'), 'PlatformBillingPage');
export const PlatformRecapPage = page(() => import('../pages/platform/PlatformRecapPage'), 'PlatformRecapPage');

// One company's workspace.
export const TodayPage = page(() => import('../pages/TodayPage'), 'TodayPage');
export const ReceiptsPage = page(() => import('../pages/ReceiptsPage'), 'ReceiptsPage');
export const PasswordRequestsPage = page(() => import('../pages/PasswordRequestsPage'), 'PasswordRequestsPage');
export const NotificationsPage = page(() => import('../pages/NotificationsPage'), 'NotificationsPage');
export const StudentsPage = page(() => import('../pages/StudentsPage'), 'StudentsPage');
export const SupervisorsPage = page(() => import('../pages/SupervisorsPage'), 'SupervisorsPage');
export const TeamPage = page(() => import('../pages/TeamPage'), 'TeamPage');
export const LinesPage = page(() => import('../pages/LinesPage'), 'LinesPage');
export const LinePage = page(() => import('../pages/LinePage'), 'LinePage');
export const LineNewPage = page(() => import('../pages/LineNewPage'), 'LineNewPage');
export const RideConfirmationPage = page(() => import('../pages/RideConfirmationPage'), 'RideConfirmationPage');
export const GovernoratesPage = page(() => import('../pages/GovernoratesPage'), 'GovernoratesPage');
export const SubscriptionPeriodsPage = page(() => import('../pages/SubscriptionPeriodsPage'), 'SubscriptionPeriodsPage');
export const PaymentMethodsPage = page(() => import('../pages/PaymentMethodsPage'), 'PaymentMethodsPage');
export const ReportsPage = page(() => import('../pages/ReportsPage'), 'ReportsPage');
export const AnalyticsPage = page(() => import('../pages/AnalyticsPage'), 'AnalyticsPage');
export const WalletCardPage = page(() => import('../pages/WalletCardPage'), 'WalletCardPage');
export const ReceiptDetailsPage = page(() => import('../pages/ReceiptDetailsPage'), 'ReceiptDetailsPage');
