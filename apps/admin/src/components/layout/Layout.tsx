import React from 'react';
import { Outlet } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { TopBar } from './TopBar';

export function Layout({ children }: { children?: React.ReactNode }) {
  const [sidebarOpen, setSidebarOpen] = React.useState(false);

  return (
    <div className="min-h-screen bg-bg-primary" dir="rtl">
      <Sidebar isOpen={sidebarOpen} onClose={() => setSidebarOpen(false)} />
      <div className="lg:mr-64 min-h-screen transition-all duration-300">
        <TopBar onMenuClick={() => setSidebarOpen(true)} />
        <main className="pt-16 min-h-screen">
          <div className="p-4 lg:p-6 max-w-[1440px] mx-auto">
            {children ?? <Outlet />}
          </div>
        </main>
      </div>
    </div>
  );
}

export default Layout;