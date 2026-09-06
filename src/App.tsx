import { useState, useEffect } from 'react';
import Sidebar from './components/Layout/Sidebar';
import BottomNav from './components/Layout/BottomNav';
import TopBar from './components/Layout/TopBar';
import { useStore } from './store/useStore';
import { handleOAuthCallback } from './lib/monzo';
import { initNativeNotifications, syncTaskReminders } from './lib/nativeNotifications';
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
import TimesheetPage from './pages/TimesheetPage';
import CISPage from './pages/CISPage';
import BankingPage from './pages/BankingPage';
import AddLeadModal from './components/Pipeline/AddLeadModal';
import AIAssistant from './components/AI/AIAssistant';
import { isMacApp, sendDeviceNotification } from './utils/push';

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
  const { currentPage, setCurrentPage, currentUserId, users, leads, generalTasks, pushEnabled, isLoaded, loadData } = useStore();
  const isAdmin = users.find(u => u.id === currentUserId)?.role === 'admin';
  const ADMIN_ONLY_PAGES = new Set(['dashboard', 'leads', 'contacts', 'files', 'reports', 'settings', 'cis', 'banking']);
  const [showNewLead, setShowNewLead] = useState(false);

  useEffect(() => {
    handleOAuthCallback().then(wasCallback => {
      if (wasCallback) setCurrentPage('banking');
    });
    loadData();
  }, []);

  // Native app: request notification permission + register for push once logged in.
  useEffect(() => {
    if (currentUserId) initNativeNotifications(currentUserId);
  }, [currentUserId]);

  // Native app: keep on-device task reminders in sync with the task list.
  useEffect(() => {
    syncTaskReminders(generalTasks);
  }, [generalTasks]);

  useEffect(() => {
    if (!isMacApp() || !isLoaded || !currentUserId) return;
    const today = new Date().toISOString().split('T')[0];
    const surveysToday = leads.filter(lead => lead.surveyDate === today).length;
    const overdueJobs = leads.filter(lead => lead.endDate && lead.endDate < today && !['Completed', 'Paid'].includes(lead.stage)).length;
    const dueTasks = generalTasks.filter(task => !task.completed && task.dueDate && task.dueDate <= today).length;
    const badgeCount = surveysToday + overdueJobs + dueTasks;

    void import('@tauri-apps/api/window')
      .then(({ getCurrentWindow }) => getCurrentWindow().setBadgeCount(badgeCount || undefined))
      .catch(() => {});

    if (!pushEnabled || badgeCount === 0) return;
    const reminderKey = `proline-mac-reminder-${today}`;
    if (localStorage.getItem(reminderKey)) return;
    const parts = [
      surveysToday ? `${surveysToday} survey${surveysToday === 1 ? '' : 's'} today` : '',
      overdueJobs ? `${overdueJobs} overdue job${overdueJobs === 1 ? '' : 's'}` : '',
      dueTasks ? `${dueTasks} task${dueTasks === 1 ? '' : 's'} due` : '',
    ].filter(Boolean);
    void sendDeviceNotification('Your ProLine day', parts.join(' · '));
    localStorage.setItem(reminderKey, 'sent');
  }, [currentUserId, generalTasks, isLoaded, leads, pushEnabled]);

  useEffect(() => {
    if (!isMacApp()) return;
    const handleShortcut = (event: KeyboardEvent) => {
      if (!event.metaKey) return;
      if (event.key.toLowerCase() === 'n') {
        event.preventDefault();
        setShowNewLead(true);
      }
      const pageByKey: Record<string, string> = { '1': 'pipeline', '2': 'jobs', '3': 'tasks', '4': 'calendar' };
      if (pageByKey[event.key]) {
        event.preventDefault();
        setCurrentPage(pageByKey[event.key]);
      }
    };
    window.addEventListener('keydown', handleShortcut);
    return () => window.removeEventListener('keydown', handleShortcut);
  }, [setCurrentPage]);

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
    cis: <CISPage />,
    banking: <BankingPage />,
    settings: <SettingsPage />,
    timesheet: <TimesheetPage />,
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
            {(!isAdmin && ADMIN_ONLY_PAGES.has(currentPage)) ? <PipelinePage /> : (page[currentPage] ?? <PipelinePage />)}
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
