import { useState, useRef, useEffect } from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../../lib/auth';
import { useTheme } from '../../design/ThemeContext';
import { Search, Bell, Settings as CogIcon, LogOut, Menu, ChevronDown, Sun, Moon } from 'lucide-react';

export function TopBar({ onMenuClick }: { onMenuClick: () => void }) {
  const { user, logout } = useAuth();
  const { resolved, toggle } = useTheme();
  const [showNotifications, setShowNotifications] = useState(false);
  const [showUserMenu, setShowUserMenu] = useState(false);
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

  return (
    <header className="sticky top-0 z-30 h-16 bg-bg-primary/80 backdrop-blur-lg border-b border-border-primary flex items-center justify-between px-4 lg:px-6">
      {/* Left - Menu + Search */}
      <div className="flex items-center gap-3 lg:gap-4">
        <button onClick={onMenuClick} className="p-2 rounded-lg hover:bg-surface-hover text-text-secondary lg:hidden" aria-label="فتح القائمة">
          <Menu className="w-6 h-6" />
        </button>

        <div className="relative w-full max-w-xs lg:max-w-md hidden sm:block">
          <div className="absolute right-3 top-1/2 -translate-y-1/2 text-text-tertiary pointer-events-none">
            <Search className="w-5 h-5" />
          </div>
          <input
            type="search"
            placeholder="ابحث في الرحلات، الكباتن..."
            className="w-full pl-10 pr-4 py-2 bg-surface-secondary border border-border-primary rounded-xl text-text-primary placeholder:text-text-tertiary focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 text-sm transition-all"
            autoComplete="off"
          />
        </div>
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
            <Bell className="w-5 h-5" />
            <span className="absolute -top-0.5 -left-0.5 w-4 h-4 bg-error-main text-white text-[10px] font-bold rounded-full flex items-center justify-center">2</span>
          </button>

          {showNotifications && (
            <div className="absolute left-0 top-full mt-2 w-80 lg:w-96 bg-surface-primary border border-border-primary rounded-xl shadow-xl overflow-hidden z-50 animate-fade-in">
              <div className="px-4 py-3 border-b border-border-primary flex items-center justify-between">
                <h3 className="font-semibold text-text-primary">الإشعارات</h3>
                <button className="text-sm text-text-tertiary hover:text-text-primary">الكل كمقروء</button>
              </div>
              <div className="max-h-96 overflow-y-auto">
                <div className="px-4 py-3 border-b border-border-primary hover:bg-surface-hover transition-colors cursor-pointer">
                  <p className="font-medium text-text-primary">طلب توثيق كابتن جديد</p>
                  <p className="text-sm text-text-tertiary">قام الكابتن محمد بإرفاق رخصة القيادة والفيش الجنائي.</p>
                  <p className="text-xs text-text-tertiary mt-1">منذ 5 دقائق</p>
                </div>
                <div className="px-4 py-3 border-b border-border-primary hover:bg-surface-hover transition-colors cursor-pointer">
                  <p className="font-medium text-text-primary">زيادة إجمالي GMV</p>
                  <p className="text-sm text-text-tertiary">تجاوزت الأرباح اليومية حاجز 15,000 ج.م في القاهرة.</p>
                  <p className="text-xs text-text-tertiary mt-1">منذ ساعة</p>
                </div>
              </div>
              <div className="p-3 border-t border-border-primary">
                <button className="w-full text-center text-sm text-primary-500 hover:text-primary-600 font-medium">عرض جميع الإشعارات</button>
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
    </header>
  );
}

export default TopBar;