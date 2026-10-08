import {
  BarChart3, Bell, Building2, Bus, CalendarRange, CreditCard, FileCheck2, GraduationCap, LayoutDashboard,
  ShieldCheck, UserCheck, Users, UsersRound, Wallet, type LucideIcon,
} from 'lucide-react';
import * as routes from './routes';

export interface NavItem {
  /** Absolute path. */
  to: string;
  name: string;
  /** Label for the narrow mobile bar. */
  short: string;
  icon: LucideIcon;
  /** Match the path exactly (for an area's first page). */
  end?: boolean;
  /** Which count, if any, is shown on this item as a red badge. */
  badge?: 'receipts' | 'requests';
  /** Fetches the page's code ahead of the click (called when the entry is pointed at or focused). */
  preload?: () => void;
}

/** The platform admin's area: everything that spans companies. */
export const platformNav: NavItem[] = [
  { to: '/platform', name: 'نظرة عامة على المنصة', short: 'المنصة', icon: LayoutDashboard, end: true, preload: routes.PlatformOverviewPage.preload },
  { to: '/platform/companies', name: 'كل الشركات', short: 'الشركات', icon: Building2, preload: routes.AllCompaniesPage.preload },
  { to: '/platform/students', name: 'كل الطلاب', short: 'الطلاب', icon: Users, preload: routes.AllStudentsPage.preload },
  { to: '/platform/notifications', name: 'إشعارات المنصة', short: 'الإشعارات', icon: Bell, preload: routes.PlatformNotificationsPage.preload },
  { to: '/platform/admins', name: 'مديرو الشركات', short: 'المديرون', icon: ShieldCheck, preload: routes.CompanyAdminsPage.preload },
  { to: '/platform/universities', name: 'الجامعات والوجهات', short: 'الجامعات', icon: GraduationCap, preload: routes.UniversitiesPage.preload },
  { to: '/platform/defaults', name: 'الإعدادات الافتراضية', short: 'الافتراضي', icon: CalendarRange, preload: routes.PlatformDefaultsPage.preload },
];

/** One company's workspace. Every page under it shows that company only. */
export const workspaceNav = (companyId: string): NavItem[] => {
  const base = `/c/${companyId}`;
  return [
    { to: base, name: 'نظرة عامة', short: 'الرئيسية', icon: LayoutDashboard, end: true, preload: routes.OverviewPage.preload },
    { to: `${base}/students`, name: 'الطلاب', short: 'الطلاب', icon: Users, badge: 'requests', preload: routes.StudentsPage.preload },
    { to: `${base}/receipts`, name: 'فحص الإيصالات', short: 'الإيصالات', icon: FileCheck2, badge: 'receipts', preload: routes.ReceiptsPage.preload },
    { to: `${base}/lines`, name: 'الخطوط والمحطات', short: 'الخطوط', icon: Bus, preload: routes.LinesPage.preload },
    { to: `${base}/supervisors`, name: 'المشرفون', short: 'المشرفون', icon: UserCheck, preload: routes.SupervisorsPage.preload },
    { to: `${base}/notifications`, name: 'الإشعارات', short: 'الإشعارات', icon: Bell, preload: routes.NotificationsPage.preload },
    { to: `${base}/reports`, name: 'التقارير المالية', short: 'التقارير', icon: BarChart3, preload: routes.ReportsPage.preload },
    { to: `${base}/payment-methods`, name: 'وسائل الدفع', short: 'الدفع', icon: Wallet, preload: routes.PaymentMethodsPage.preload },
    { to: `${base}/wallet-card`, name: 'بطاقة المحفظة', short: 'البطاقة', icon: CreditCard, preload: routes.WalletCardDesignPage.preload },
    { to: `${base}/team`, name: 'فريق الإدارة', short: 'الفريق', icon: UsersRound, preload: routes.TeamPage.preload },
    { to: `${base}/settings`, name: 'إعدادات الشركة', short: 'الإعدادات', icon: CalendarRange, preload: routes.CompanySettingsPage.preload },
  ];
};
