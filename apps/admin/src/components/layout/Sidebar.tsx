import React, { forwardRef } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { useAuth } from '../../lib/auth';
import { hasPermission, ROLE_LABELS_AR, type StaffPermission } from '../../lib/staff';
import {
  LayoutDashboard, MapPin, Users, ShieldCheck, Route as RouteIcon,
  BarChart3, DollarSign, User as UserIcon, ShieldAlert, Settings as CogIcon,
  LogOut, X, AlertCircle, Send, UserCog,
} from 'lucide-react';
import TempoLogo from '../common/TempoLogo';

interface NavItem {
  path: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  /**
   * RBAC (migration 0024): the permission a dashboard role needs to see this
   * item. Items without one are visible to every staff role.
   */
  permission?: StaffPermission;
  badge?: string;
  end?: boolean;
}

interface NavGroup {
  category: string;
  items: NavItem[];
}

const navGroups: NavGroup[] = [
  {
    category: 'الرئيسية',
    items: [
      { path: '/', label: 'نظرة عامة', icon: LayoutDashboard, permission: 'stats:view', end: true },
      { path: '/live', label: 'خريطة حية', icon: MapPin, permission: 'stats:view' },
    ],
  },
  {
    category: 'العمليات',
    items: [
      { path: '/safety', label: 'الاستغاثات', icon: AlertCircle, permission: 'safety:view' },
      { path: '/captains', label: 'الكباتن', icon: Users, permission: 'captains:view' },
      { path: '/verification', label: 'توثيق المستندات', icon: ShieldCheck, permission: 'documents:view', badge: 'جديد' },
      { path: '/trips', label: 'الرحلات', icon: RouteIcon, permission: 'trips:view' },
      { path: '/users', label: 'الركاب', icon: UserIcon, permission: 'users:view' },
    ],
  },
  {
    category: 'المالية والحوكمة',
    items: [
      { path: '/analytics', label: 'التحليلات', icon: BarChart3, permission: 'analytics:view' },
      { path: '/pricing', label: 'التسعير', icon: DollarSign, permission: 'pricing:manage' },
      { path: '/payouts', label: 'طلبات السحب', icon: Send, permission: 'payouts:manage' },
      { path: '/audit', label: 'سجل التدقيق', icon: ShieldAlert, permission: 'audit:view' },
      { path: '/settings', label: 'الإعدادات', icon: CogIcon, permission: 'config:manage' },
      { path: '/staff', label: 'الموظفون والأدوار', icon: UserCog, permission: 'staff:manage' },
    ],
  },
];

export interface SidebarProps {
  isOpen?: boolean;
  onClose?: () => void;
  className?: string;
}

export const Sidebar = forwardRef<HTMLDivElement, SidebarProps>(
  ({ isOpen = false, onClose, className = '' }, ref) => {
    const { user, dashboardRole, logout } = useAuth();
    const location = useLocation();

    const isActive = (path: string) => {
      if (path === '/') return location.pathname === '/';
      return location.pathname.startsWith(path);
    };

    // RBAC: hide what the role cannot open. Groups whose items are all hidden
    // disappear too, so a limited role never stares at an empty heading.
    const visibleGroups = navGroups
      .map((group) => ({
        ...group,
        items: group.items.filter((item) => !item.permission || hasPermission(dashboardRole, item.permission)),
      }))
      .filter((group) => group.items.length > 0);

    return (
      <>
        {isOpen && (
          <div className="fixed inset-0 z-30 bg-black/60 backdrop-blur-sm lg:hidden" onClick={onClose} aria-hidden="true" />
        )}

        <aside
          ref={ref}
          className={`fixed top-0 right-0 z-40 h-full w-64 bg-surface-primary border-l border-border-primary flex flex-col transition-transform duration-300 lg:translate-x-0 ${isOpen ? 'translate-x-0' : 'translate-x-full'} ${className}`}
          role="navigation"
          aria-label="القائمة الرئيسية"
        >
          {/* Brand */}
          <div className="flex items-center justify-between h-16 px-4 border-b border-border-primary flex-shrink-0">
            <NavLink to="/" className="flex items-center gap-2.5">
              <TempoLogo size="md" />
              <span className="text-[11px] px-2 py-0.5 rounded-full bg-primary-500/10 dark:bg-primary-500/20 text-primary-600 dark:text-primary-400 font-bold border border-primary-500/30 flex-shrink-0">
                لوحة التحكم
              </span>
            </NavLink>
            <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-surface-hover text-text-tertiary lg:hidden" aria-label="إغلاق القائمة">
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Navigation */}
          <nav className="flex-1 p-3 overflow-y-auto">
            {visibleGroups.map((group, idx) => (
              <div key={idx} className="mb-4">
                <h3 className="px-3 mb-1 text-xs font-semibold text-text-tertiary uppercase tracking-wider">{group.category}</h3>
                <div className="space-y-1">
                  {group.items.map((item) => {
                    const Icon = item.icon;
                    const active = isActive(item.path);
                    return (
                      <NavLink
                        key={item.path}
                        to={item.path}
                        end={item.end}
                        onClick={() => { if (window.innerWidth < 1024 && onClose) onClose(); }}
                        className={`flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors text-sm font-medium ${active ? 'bg-primary-500/10 text-primary-500' : 'text-text-secondary hover:bg-surface-hover hover:text-text-primary'}`}
                      >
                        <Icon className="w-5 h-5 flex-shrink-0" />
                        <span className="flex-1">{item.label}</span>
                        {item.badge && (
                          <span className="px-2 py-0.5 text-xs font-medium bg-primary-500/10 text-primary-500 rounded-full">{item.badge}</span>
                        )}
                      </NavLink>
                    );
                  })}
                </div>
              </div>
            ))}
          </nav>

          {/* Footer */}
          <div className="p-3 border-t border-border-primary flex-shrink-0">
            <div className="flex items-center gap-3 mb-2 px-2">
              <div className="w-10 h-10 rounded-xl bg-primary-500/10 flex items-center justify-center">
                <UserIcon className="w-5 h-5 text-primary-500" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-text-primary truncate">{user?.name || user?.email || 'المستخدم'}</p>
                <p className="text-xs text-text-tertiary">{dashboardRole ? ROLE_LABELS_AR[dashboardRole] : user?.role || ''}</p>
              </div>
            </div>
            <button onClick={logout} className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-error-main hover:bg-error-main/10 transition-colors text-sm font-medium">
              <LogOut className="w-5 h-5" />
              تسجيل الخروج
            </button>
          </div>
        </aside>
      </>
    );
  }
);

Sidebar.displayName = 'Sidebar';
export default Sidebar;