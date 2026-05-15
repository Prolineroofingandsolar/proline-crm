import { useState } from 'react';
import { ChevronLeft, ChevronRight, Calendar } from 'lucide-react';
import { useStore } from '../store/useStore';
import { jobTypeColor } from '../utils/helpers';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];

export default function CalendarPage() {
  const { leads, selectedId, setSelectedId } = useStore();
  const [current, setCurrent] = useState(() => {
    const d = new Date();
    return { year: d.getFullYear(), month: d.getMonth() };
  });

  const firstDay = new Date(current.year, current.month, 1).getDay();
  const daysInMonth = new Date(current.year, current.month + 1, 0).getDate();
  const cells = Array.from({ length: firstDay + daysInMonth }, (_, i) =>
    i < firstDay ? null : i - firstDay + 1
  );
  while (cells.length % 7 !== 0) cells.push(null);

  const getEvents = (day: number) => {
    const date = `${current.year}-${String(current.month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    return leads.filter(l => l.surveyDate === date || l.startDate === date);
  };

  const today = new Date();
  const isToday = (day: number) =>
    day === today.getDate() && current.month === today.getMonth() && current.year === today.getFullYear();

  return (
    <div className="flex flex-col h-full bg-white overflow-hidden">
      <div className="flex-1 overflow-auto p-4">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          {/* Header */}
          <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
            <div className="flex items-center gap-2">
              <Calendar size={18} className="text-orange-500" />
              <h2 className="font-bold text-gray-800 text-lg">{MONTHS[current.month]} {current.year}</h2>
            </div>
            <div className="flex items-center gap-1">
              <button onClick={() => setCurrent(c => { const d = new Date(c.year, c.month - 1); return { year: d.getFullYear(), month: d.getMonth() }; })}
                className="p-2 rounded-lg hover:bg-gray-100 text-gray-500"><ChevronLeft size={16} /></button>
              <button onClick={() => setCurrent({ year: today.getFullYear(), month: today.getMonth() })}
                className="px-3 py-1.5 rounded-lg text-xs font-medium bg-orange-50 text-orange-600 hover:bg-orange-100">Today</button>
              <button onClick={() => setCurrent(c => { const d = new Date(c.year, c.month + 1); return { year: d.getFullYear(), month: d.getMonth() }; })}
                className="p-2 rounded-lg hover:bg-gray-100 text-gray-500"><ChevronRight size={16} /></button>
            </div>
          </div>

          {/* Day names */}
          <div className="grid grid-cols-7 border-b border-gray-100">
            {DAYS.map(d => (
              <div key={d} className="py-2 text-center text-xs font-semibold text-gray-400 uppercase">{d}</div>
            ))}
          </div>

          {/* Grid */}
          <div className="grid grid-cols-7">
            {cells.map((day, i) => {
              const events = day ? getEvents(day) : [];
              return (
                <div key={i} className={`min-h-24 border-r border-b border-gray-50 p-1.5 ${!day ? 'bg-gray-50/50' : 'hover:bg-gray-50'}`}>
                  {day && (
                    <>
                      <span className={`text-xs font-semibold w-6 h-6 flex items-center justify-center rounded-full ${
                        isToday(day) ? 'bg-orange-600 text-white' : 'text-gray-500'
                      }`}>{day}</span>
                      <div className="mt-1 space-y-0.5">
                        {events.map(ev => (
                          <button key={ev.id} onClick={() => setSelectedId(ev.id)}
                            className={`w-full text-left text-xs px-1.5 py-0.5 rounded-md font-medium truncate ${jobTypeColor(ev.jobType)}`}>
                            {ev.name} · {ev.surveyDate ? 'Survey' : 'Start'}
                          </button>
                        ))}
                      </div>
                    </>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Event list */}
        <div className="mt-4 bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="px-5 py-3 border-b border-gray-100">
            <h3 className="font-bold text-gray-800">Upcoming Events — {MONTHS[current.month]}</h3>
          </div>
          <div className="divide-y divide-gray-50">
            {leads
              .filter(l => {
                const d = l.surveyDate ?? l.startDate ?? '';
                return d.startsWith(`${current.year}-${String(current.month + 1).padStart(2, '0')}`);
              })
              .sort((a, b) => (a.surveyDate ?? a.startDate ?? '').localeCompare(b.surveyDate ?? b.startDate ?? ''))
              .map(lead => (
                <div key={lead.id} className="flex items-center gap-3 px-5 py-3 hover:bg-gray-50 cursor-pointer" onClick={() => setSelectedId(lead.id)}>
                  <div className="w-10 h-10 rounded-xl bg-orange-50 flex flex-col items-center justify-center text-orange-700 shrink-0">
                    <span className="text-sm font-bold leading-none">{(lead.surveyDate ?? lead.startDate)?.split('-')[2]}</span>
                    <span className="text-xs opacity-70">{MONTHS[current.month].slice(0, 3)}</span>
                  </div>
                  <div className="flex-1">
                    <p className="text-sm font-semibold text-gray-800">{lead.name}</p>
                    <p className="text-xs text-gray-400">{lead.surveyDate ? `Survey ${lead.surveyTime ?? ''}` : 'Job Start'} · {lead.jobType}</p>
                  </div>
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${jobTypeColor(lead.jobType)}`}>{lead.stage}</span>
                </div>
              ))}
            {leads.filter(l => (l.surveyDate ?? l.startDate ?? '').startsWith(`${current.year}-${String(current.month + 1).padStart(2, '0')}`)).length === 0 && (
              <p className="text-sm text-gray-400 text-center py-6">No events this month</p>
            )}
          </div>
        </div>
      </div>

      {selectedId && <LeadDetailPanel />}
    </div>
  );
}
