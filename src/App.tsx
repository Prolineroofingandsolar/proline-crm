import { useState, useEffect } from 'react';
import Sidebar from './components/Layout/Sidebar';
import BottomNav from './components/Layout/BottomNav';
import TopBar from './components/Layout/TopBar';
import { useStore } from './store/useStore';
import LoginPage from './pages/LoginPage';
import PipelinePage from './pages/PipelinePage';
import DashboardPage from './pages/DashboardPage';
import LeadsPage from './pages/LeadsPage';
import JobsPage from './pages/JobsPage';
import TasksPage from './pages/TasksPage';
import CalendarPage from './pages/CalendarPage';
import ContactsPage from './pages/ContactsPage';
import FilesPage from './pages/FilesPage';
import ReportsPage from './pages/ReportsPage';
import SettingsPage from './pages/SettingsPage';
import AddLeadModal from './components/Pipeline/AddLeadModal';
import AIAssistant from './components/AI/AIAssistant';

function Toast() {
  const { toast } = useStore();
  if (!toast) return null;
  const colors = { success: 'bg-green-600', info: 'bg-orange-600', error: 'bg-red-600' };
  return (
    <div className={`fixed bottom-20 right-4 sm:bottom-6 sm:right-6 z-[100] ${colors[toast.type]} text-white text-sm font-medium px-4 py-3 rounded-xl shadow-xl flex items-center gap-2`}>
      {toast.message}
    </div>
  );
}

function LoadingScreen() {
  return (
    <div className="flex items-center justify-center h-screen" style={{ background: '#111827' }}>
      <div className="text-center space-y-4">
        <img src="/logo.svg" alt="ProLine" className="w-20 h-20 object-contain mx-auto" />
        <div className="w-8 h-8 border-2 border-orange-500 border-t-transparent rounded-full animate-spin mx-auto" />
        <p className="text-white/40 text-sm">Loading your data…</p>
      </div>
    </div>
  );
}

export default function App() {
  const { currentPage, currentUserId, users, isLoaded, loadData } = useStore();
  const [showNewLead, setShowNewLead] = useState(false);

  useEffect(() => {
    loadData();
  }, []);

  if (!isLoaded) return <LoadingScreen />;
  if (users.length === 0) return <LoginPage mode="setup" />;
  if (!currentUserId) return <LoginPage mode="login" />;

  const page: Record<string, React.ReactNode> = {
    dashboard: <DashboardPage />,
    pipeline: <PipelinePage />,
    leads: <LeadsPage />,
    jobs: <JobsPage />,
    tasks: <TasksPage />,
    calendar: <CalendarPage />,
    contacts: <ContactsPage />,
    files: <FilesPage />,
    reports: <ReportsPage />,
    settings: <SettingsPage />,
  };

  return (
    <div className="flex h-screen overflow-hidden bg-white">
      <div className="hidden sm:flex">
        <Sidebar />
      </div>
      <div className="flex-1 flex flex-col overflow-hidden">
        <TopBar onNewLead={() => setShowNewLead(true)} />
        <main className="flex-1 overflow-hidden">
          <div className="h-full pb-16 sm:pb-0">
            {page[currentPage] ?? <PipelinePage />}
          </div>
        </main>
      </div>
      <BottomNav />
      {showNewLead && <AddLeadModal onClose={() => setShowNewLead(false)} />}
      <Toast />
      <AIAssistant />
    </div>
  );
}
