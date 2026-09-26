import React, { useState } from 'react';
import { Sidebar } from './components/Sidebar';
import { OverviewPage } from './pages/OverviewPage';
import { CompaniesPage } from './pages/CompaniesPage';
import { LinesPage } from './pages/LinesPage';
import { SupervisorsPage } from './pages/SupervisorsPage';
import { ReportsPage } from './pages/ReportsPage';
import { PendingReceiptsTable } from './components/PendingReceiptsTable';

export function App() {
  const [activeTab, setActiveTab] = useState<string>('overview');

  return (
    <div className="flex min-h-screen p-4 sm:p-6 gap-6" dir="rtl">
      {/* Glassmorphic Sticky Sidebar */}
      <Sidebar activeTab={activeTab} onTabChange={setActiveTab} />

      {/* Main Content View */}
      <main className="flex-1 max-w-[1400px] mx-auto pb-12 overflow-x-hidden">
        {activeTab === 'overview' && <OverviewPage />}
        {activeTab === 'companies' && <CompaniesPage />}
        {activeTab === 'lines' && <LinesPage />}
        {activeTab === 'supervisors' && <SupervisorsPage />}
        {activeTab === 'receipts' && (
          <div className="space-y-6">
            <h1 className="text-2xl font-bold text-slate-800">فحص واعتماد الإيصالات</h1>
            <PendingReceiptsTable
              receipts={[]}
              loading={false}
              onReceiptReviewed={() => {}}
            />
          </div>
        )}
        {activeTab === 'reports' && <ReportsPage />}
      </main>
    </div>
  );
}

export default App;
