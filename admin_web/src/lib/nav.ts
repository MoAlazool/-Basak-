import {
  BarChart3, Bell, Building2, Bus, CalendarRange, CreditCard, FileCheck2, GraduationCap, LayoutDashboard,
  ShieldCheck, UserCheck, Users, UsersRound, Wallet, type LucideIcon,
} from 'lucide-react';

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
}

/** The platform admin's area: everything that spans companies. */
export const platformNav: NavItem[] = [
  { to: '/platform', name: 'نظرة عامة على المنصة', short: 'المنصة', icon: LayoutDashboard, end: true },
  { to: '/platform/companies', name: 'كل الشركات', short: 'الشركات', icon: Building2 },
  { to: '/platform/students', name: 'كل الطلاب', short: 'الطلاب', icon: Users },
  { to: '/platform/admins', name: 'مديرو الشركات', short: 'المديرون', icon: ShieldCheck },
  { to: '/platform/universities', name: 'الجامعات والوجهات', short: 'الجامعات', icon: GraduationCap },
  { to: '/platform/defaults', name: 'الإعدادات الافتراضية', short: 'الافتراضي', icon: CalendarRange },
];

/** One company's workspace. Every page under it shows that company only. */
export const workspaceNav = (companyId: string): NavItem[] => {
  const base = `/c/${companyId}`;
  return [
    { to: base, name: 'نظرة عامة', short: 'الرئيسية', icon: LayoutDashboard, end: true },
    { to: `${base}/students`, name: 'الطلاب', short: 'الطلاب', icon: Users, badge: 'requests' },
    { to: `${base}/receipts`, name: 'فحص الإيصالات', short: 'الإيصالات', icon: FileCheck2, badge: 'receipts' },
    { to: `${base}/lines`, name: 'الخطوط والمحطات', short: 'الخطوط', icon: Bus },
    { to: `${base}/supervisors`, name: 'المشرفون', short: 'المشرفون', icon: UserCheck },
    { to: `${base}/notifications`, name: 'الإشعارات', short: 'الإشعارات', icon: Bell },
    { to: `${base}/reports`, name: 'التقارير المالية', short: 'التقارير', icon: BarChart3 },
    { to: `${base}/payment-methods`, name: 'وسائل الدفع', short: 'الدفع', icon: Wallet },
    { to: `${base}/wallet-card`, name: 'بطاقة المحفظة', short: 'البطاقة', icon: CreditCard },
    { to: `${base}/team`, name: 'فريق الإدارة', short: 'الفريق', icon: UsersRound },
    { to: `${base}/settings`, name: 'إعدادات الشركة', short: 'الإعدادات', icon: CalendarRange },
  ];
};
