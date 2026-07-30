import { useState, useRef, useEffect } from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../../lib/auth';
import { useTheme } from '../../design/ThemeContext';
import { Search, Bell, Settings as CogIcon, LogOut, Menu, ChevronDown, Sun, Moon, BellOff } from 'lucide-react';
import { QuickSearchModal } from '../ui/QuickSearchModal';

export function TopBar({ onMenuClick }: { onMenuClick: () => void }) {
  const { user, logout } = useAuth();
  const { resolved, toggle } = useTheme();
  const [showNotifications, setShowNotifications] = useState(false);
  const [showUserMenu, setShowUserMenu] = useState(false);
  const [showSearch, setShowSearch] = useState(false);
  const notificationsRef = useRef<HTMLDivElement>(null);
  const userMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (showNotifications && notificationsRef.current && !notificationsRef.current.contains(e.target as Node)) {
        setShowNotifications(false);
      }
      if (showUserMenu && userMenuRef.current && !userMenuRef.current.contains(e.target as Node)) {
        setShowUserMenu(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [showNotifications, showUserMenu]);

  // Ctrl/Cmd+K opens quick search from anywhere in the dashboard. The shortcut
  // is registered here because the TopBar is mounted for the whole authenticated
  // session, and it is the element that visibly owns the search affordance.
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setShowSearch((open) => !open);
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, []);

  return (
    <header className="sticky top-0 z-30 h-16 bg-bg-primary/80 backdrop-blur-lg border-b border-border-primary flex items-center justify-between px-4 lg:px-6">
      {/* Left - Menu + Search */}
      <div className="flex items-center gap-3 lg:gap-4">
        <button onClick={onMenuClick} className="p-2 rounded-lg hover:bg-surface-hover text-text-secondary lg:hidden" aria-label="فتح القائمة">
          <Menu className="w-6 h-6" />
        </button>

        {/* A button, not an <input>. The real search UI is QuickSearchModal —
            this is the affordance that opens it. It used to be a bare text input
            that accepted keystrokes and did nothing with them, which read as a
            broken feature rather than a shortcut. */}
        <button
          onClick={() => setShowSearch(true)}
          className="hidden sm:flex items-center gap-2 w-full max-w-xs lg:max-w-md pr-3 pl-2 py-2 bg-surface-secondary border border-border-primary rounded-xl text-text-tertiary hover:border-primary-500/40 hover:text-text-secondary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/30 text-sm transition-all"
          aria-label="بحث سريع"
        >
          <Search className="w-5 h-5 shrink-0" />
          <span className="flex-1 text-right">ابحث في الرحلات، الكباتن...</span>
          <kbd className="hidden lg:inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-md bg-surface-tertiary border border-border-primary text-[10px] font-mono font-bold text-text-tertiary">
            Ctrl K
          </kbd>
        </button>

        {/* Below the sm breakpoint the labelled trigger is hidden to save room,
            so mobile gets an icon-only equivalent. Previously mobile had no way
            to reach search at all. */}
        <button
          onClick={() => setShowSearch(true)}
          className="sm:hidden p-2 rounded-lg hover:bg-surface-hover text-text-secondary"
          aria-label="بحث سريع"
        >
          <Search className="w-5 h-5" />
        </button>
      </div>

      {/* Right - Notifications + Theme + User */}
      <div className="flex items-center gap-1.5 lg:gap-2">
        {/* Status pill */}
        <div className="hidden sm:flex items-center gap-2 px-3 py-1.5 bg-success-main/10 rounded-full">
          <span className="w-2 h-2 rounded-full bg-success-main animate-pulse" />
          <span className="text-xs text-success-main font-medium">السيرفر يعمل</span>
        </div>

        {/* Theme toggle — white light / pure black dark */}
        <button
          onClick={toggle}
          className="p-2 rounded-lg hover:bg-surface-hover text-text-secondary hover:text-text-primary transition-colors"
          aria-label={resolved === 'dark' ? 'التبديل للوضع الفاتح' : 'التبديل للوضع الداكن'}
          title={resolved === 'dark' ? 'الوضع الفاتح (Ctrl+Shift+L)' : 'الوضع الداكن (Ctrl+Shift+L)'}
        >
          {resolved === 'dark' ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
        </button>

        {/* Notifications */}
        <div className="relative" ref={notificationsRef}>
          <button
            onClick={() => setShowNotifications(!showNotifications)}
            className="relative p-2 rounded-lg hover:bg-surface-hover text-text-secondary hover:text-text-primary transition-colors"
            aria-label="الإشعارات"
            aria-expanded={showNotifications}
          >
            {/* The unread badge is intentionally absent until a notifications
                endpoint exists. It previously rendered a hardcoded "2" that
                never changed, so it trained the admin to ignore the bell. */}
            <Bell className="w-5 h-5" />
          </button>

          {showNotifications && (
            <div className="absolute left-0 top-full mt-2 w-80 lg:w-96 bg-surface-primary border border-border-primary rounded-xl shadow-xl overflow-hidden z-50 animate-fade-in">
              <div className="px-4 py-3 border-b border-border-primary">
                <h3 className="font-semibold text-text-primary">الإشعارات</h3>
              </div>
              {/* Honest empty state. The two items that used to live here were
                  hardcoded sample copy ("الكابتن محمد أرفق رخصة القيادة") that
                  looked like real events. The notification_log table exists in
                  the database but has no admin endpoint yet. */}
              <div className="px-4 py-8 flex flex-col items-center text-center gap-2">
                <div className="w-10 h-10 rounded-xl bg-surface-secondary flex items-center justify-center">
                  <BellOff className="w-5 h-5 text-text-tertiary" />
                </div>
                <p className="text-sm font-medium text-text-secondary">لا توجد إشعارات</p>
                <p className="text-xs text-text-tertiary leading-relaxed max-w-[240px]">
                  الإشعارات الفورية للتوثيقات وتنبيهات الأمان قيد التطوير.
                </p>
              </div>
            </div>
          )}
        </div>

        {/* User Menu */}
        <div className="relative ml-2" ref={userMenuRef}>
          <button
            onClick={() => setShowUserMenu(!showUserMenu)}
            className="flex items-center gap-2 p-1.5 rounded-xl hover:bg-surface-hover transition-colors"
            aria-expanded={showUserMenu}
            aria-haspopup="true"
            aria-label="قائمة المستخدم"
          >
            <div className="w-8 h-8 rounded-xl bg-primary-500/10 flex items-center justify-center text-primary-500 font-semibold text-sm">
              {(user?.name || user?.email || 'A')[0].toUpperCase()}
            </div>
            <span className="hidden md:block text-sm font-medium text-text-primary truncate max-w-[140px]">
              {user?.name || user?.email || 'الأدمن'}
            </span>
            <ChevronDown className="w-4 h-4 text-text-tertiary" />
          </button>

          {showUserMenu && (
            <div className="absolute left-0 top-full mt-2 w-56 bg-surface-primary border border-border-primary rounded-xl shadow-xl overflow-hidden z-50 animate-fade-in" role="menu">
              <div className="px-3 py-2 border-b border-border-primary">
                <p className="text-sm font-medium text-text-primary truncate">{user?.name || user?.email}</p>
                <p className="text-xs text-text-tertiary capitalize">{user?.role}</p>
                {user?.email && <p className="text-xs text-text-tertiary">{user.email}</p>}
              </div>
              <div className="p-1">
                <NavLink to="/settings" className="flex items-center gap-3 px-3 py-2.5 text-sm text-text-secondary hover:bg-surface-hover hover:text-text-primary rounded-lg transition-colors" role="menuitem" onClick={() => setShowUserMenu(false)}>
                  <CogIcon className="w-4 h-4" />
                  الإعدادات
                </NavLink>
                <hr className="my-1 border-border-primary" />
                <button onClick={logout} className="w-full flex items-center gap-3 px-3 py-2.5 text-sm text-error-main hover:bg-error-main/10 rounded-lg transition-colors" role="menuitem">
                  <LogOut className="w-4 h-4" />
                  تسجيل الخروج
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* QuickSearchModal existed in the codebase but was never rendered by any
          component, so the search feature was unreachable. */}
      <QuickSearchModal isOpen={showSearch} onClose={() => setShowSearch(false)} />
    </header>
  );
}

export default TopBar;