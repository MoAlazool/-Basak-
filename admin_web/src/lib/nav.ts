import type { IconName } from '../ui/Icon';
import * as routes from './routes';

/**
 * The single source for grouping, labels, icons and routes
 * (docs/admin-redesign/generator/kit.mjs · NAV). A page's title equals its label.
 */
export type BadgeKey = 'receipts' | 'requests' | 'corrections';
export interface NavItem {
  id: string;
  /** Under /c/:companyId/ or /platform/ ('' = the area's first page). */
  slug: string;
  label: string;
  icon: IconName;
  badge?: BadgeKey;
  preload?: () => void;
}
export interface NavGroup { group: string | null; items: NavItem[] }

export const COMPANY_NAV: NavGroup[] = [
  { group: null, items: [{ id: 'today', slug: '', label: 'اليوم', icon: 'home', preload: routes.TodayPage.preload }] },
  { group: 'كل يوم', items: [
    { id: 'receipts', slug: 'receipts', label: 'الإيصالات', icon: 'receipt', badge: 'receipts', preload: routes.ReceiptsPage.preload },
    { id: 'password-requests', slug: 'password-requests', label: 'طلبات كلمة المرور', icon: 'key', badge: 'requests', preload: routes.PasswordRequestsPage.preload },
    { id: 'notifications', slug: 'notifications', label: 'الإشعارات', icon: 'megaphone', preload: routes.NotificationsPage.preload }] },
  { group: 'الطلاب والفريق', items: [
    { id: 'students', slug: 'students', label: 'الطلاب', icon: 'users', preload: routes.StudentsPage.preload },
    { id: 'supervisors', slug: 'supervisors', label: 'المشرفون', icon: 'scan', preload: routes.SupervisorsPage.preload },
    { id: 'team', slug: 'team', label: 'مديرو الشركة', icon: 'shield', preload: routes.TeamPage.preload }] },
  { group: 'الخطوط والرحلات', items: [
    { id: 'lines', slug: 'lines', label: 'الخطوط', icon: 'route', preload: routes.LinesPage.preload },
    { id: 'ride-confirmation', slug: 'ride-confirmation', label: 'تأكيد الركوب', icon: 'clock', preload: routes.RideConfirmationPage.preload },
    { id: 'governorates', slug: 'governorates', label: 'المحافظات', icon: 'pin', preload: routes.GovernoratesPage.preload }] },
  { group: 'الاشتراكات والمدفوعات', items: [
    { id: 'subscription-periods', slug: 'subscription-periods', label: 'مواعيد الاشتراك', icon: 'calendar', preload: routes.SubscriptionPeriodsPage.preload },
    { id: 'payment-methods', slug: 'payment-methods', label: 'وسائل الدفع', icon: 'card', preload: routes.PaymentMethodsPage.preload },
    { id: 'reports', slug: 'reports', label: 'الإيرادات', icon: 'chart', preload: routes.ReportsPage.preload },
    { id: 'analytics', slug: 'analytics', label: 'التحليلات', icon: 'trend', preload: routes.AnalyticsPage.preload }] },
  { group: 'هوية الشركة', items: [
    { id: 'wallet-card', slug: 'wallet-card', label: 'بطاقة الطالب', icon: 'idcard', preload: routes.WalletCardPage.preload },
    { id: 'receipt-details', slug: 'receipt-details', label: 'بيانات الإيصال', icon: 'building', preload: routes.ReceiptDetailsPage.preload }] },
];

export const PLATFORM_NAV: NavGroup[] = [
  { group: null, items: [{ id: 'p-today', slug: '', label: 'اليوم', icon: 'home', preload: routes.PlatformTodayPage.preload }] },
  { group: 'المال والتحليلات', items: [
    { id: 'p-analytics', slug: 'analytics', label: 'تحليلات المنصة', icon: 'trend', preload: routes.PlatformAnalyticsPage.preload },
    { id: 'p-billing', slug: 'billing', label: 'الحسابات', icon: 'card', preload: routes.PlatformBillingPage.preload }] },
  { group: 'يحتاج قرارك', items: [
    { id: 'p-corrections', slug: 'corrections', label: 'طلبات تصحيح البيانات', icon: 'pencil', badge: 'corrections', preload: routes.CorrectionsPage.preload },
    { id: 'p-password-requests', slug: 'password-requests', label: 'طلبات كلمة المرور', icon: 'key', badge: 'requests', preload: routes.PlatformPasswordRequestsPage.preload }] },
  { group: 'الشركات', items: [
    { id: 'p-companies', slug: 'companies', label: 'الشركات', icon: 'building', preload: routes.CompaniesPage.preload },
    { id: 'p-admins', slug: 'admins', label: 'مديرو الشركات', icon: 'shield', preload: routes.CompanyAdminsPage.preload }] },
  { group: 'الطلاب', items: [
    { id: 'p-students', slug: 'students', label: 'كل الطلاب', icon: 'users', preload: routes.AllStudentsPage.preload },
    { id: 'p-notifications', slug: 'notifications', label: 'إشعارات المنصة', icon: 'megaphone', preload: routes.PlatformNotificationsPage.preload }] },
  { group: 'التسويق', items: [
    { id: 'p-merchants', slug: 'merchants', label: 'التجّار', icon: 'pin', preload: routes.MerchantsPage.preload },
    { id: 'p-offers', slug: 'offers', label: 'العروض', icon: 'receipt', preload: routes.OffersPage.preload }] },
  { group: 'إعدادات المنصة', items: [
    { id: 'p-universities', slug: 'universities', label: 'الجامعات والكليات', icon: 'school', preload: routes.UniversitiesPage.preload },
    { id: 'p-defaults', slug: 'defaults', label: 'الإعدادات الافتراضية', icon: 'sliders', preload: routes.PlatformDefaultsPage.preload },
    { id: 'p-recap', slug: 'recap', label: 'ملخص الفصل', icon: 'calendar', preload: routes.PlatformRecapPage.preload },
    { id: 'p-app-versions', slug: 'app-versions', label: 'إصدارات التطبيق', icon: 'smartphone', preload: routes.AppVersionsPage.preload }] },
];

/** Old addresses (bookmarks, links in e-mails and live toasts) → where that job lives now. */
export const MOVED_SLUGS: Record<string, string> = { settings: 'subscription-periods' };

/** The nav entry a path belongs to (`/c/x/lines/abc` → lines). */
export function activeItem(groups: NavGroup[], subPath: string): NavItem | undefined {
  const first = subPath.split('/').filter(Boolean)[0] ?? '';
  return groups.flatMap((g) => g.items).find((i) => i.slug === first);
}
