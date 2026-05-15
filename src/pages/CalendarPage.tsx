import { useState } from 'react';
import { ChevronLeft, ChevronRight, Calendar, MapPin, Hammer, ClipboardList } from 'lucide-react';
import { useStore } from '../store/useStore';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';
import type { Lead } from '../types';

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];

type CalEvent = { lead: Lead; type: 'survey' | 'job-start' | 'job-active' | 'job-end' };

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

  const dateStr = (day: number) =>
    `${current.year}-${String(current.month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;

  const getEvents = (day: number): CalEvent[] => {
    const date = dateStr(day);
    const events: CalEvent[] = [];
    for (const lead of leads) {
      if (lead.surveyDate === date) events.push({ lead, type: 'survey' });
      if (lead.startDate === date) events.push({ lead, type: 'job-start' });
      else if (lead.endDate === date) events.push({ lead, type: 'job-end' });
      else if (lead.startDate && lead.endDate && date > lead.startDate && date < lead.endDate) {
        events.push({ lead, type: 'job-active' });
      }
    }
    return events;
  };

  const today = new Date();
  const isToday = (day: number) =>
    day === today.getDate() && current.month === today.getMonth() && current.year === today.getFullYear();

  const eventStyle = (type: CalEvent['type']) => {
    switch (type) {
      case 'survey':     return 'bg-violet-100 text-violet-700';
      case 'job-start':  return 'bg-green-100 text-green-700';
      case 'job-active': return 'bg-orange-50 text-orange-600';
      case 'job-end':    return 'bg-red-100 text-red-600';
    }
  };

  const eventIcon = (type: CalEvent['type']) => {
    switch (type) {
      case 'survey':     return <ClipboardList size={9} className="shrink-0" />;
      case 'job-start':  return <Hammer size={9} className="shrink-0" />;
      case 'job-active': return <Hammer size={9} className="shrink-0 opacity-50" />;
      case 'job-end':    return <MapPin size={9} className="shrink-0" />;
    }
  };

  const eventLabel = (type: CalEvent['type']) => {
    switch (type) {
      case 'survey':     return 'Survey';
      case 'job-start':  return 'Starts';
      case 'job-active': return 'Active';
      case 'job-end':    return 'Ends';
    }
  };

  // Upcoming events list — surveys + job starts + job ends in this month
  const upcomingEvents = leads
    .flatMap(lead => {
      const evts: { date: string; lead: Lead; type: CalEvent['type'] }[] = [];
      const prefix = `${current.year}-${String(current.month + 1).padStart(2, '0')}`;
      if (lead.surveyDate?.startsWith(prefix)) evts.push({ date: lead.surveyDate, lead, type: 'survey' });
      if (lead.startDate?.startsWith(prefix))  evts.push({ date: lead.startDate, lead, type: 'job-start' });
      if (lead.endDate?.startsWith(prefix))    evts.push({ date: lead.endDate, lead, type: 'job-end' });
      return evts;
    })
    .sort((a, b) => a.date.localeCompare(b.date));

  return (
    <div className="flex flex-col h-full bg-white overflow-hidden">
      <div className="flex-1 overflow-auto p-4 space-y-4">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          {/* Header */}
          <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
            <div className="flex items-center gap-3">
              <div className="flex items-center gap-2">
                <Calendar size={18} className="text-orange-500" />
                <h2 className="font-bold text-gray-800 text-lg">{MONTHS[current.month]} {current.year}</h2>
              </div>
              {/* Legend */}
              <div className="hidden sm:flex items-center gap-3 ml-2">
                {(['survey','job-start','job-active','job-end'] as CalEvent['type'][]).map(t => (
                  <span key={t} className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${eventStyle(t)}`}>
                    {eventLabel(t)}
                  </span>
                ))}
              </div>
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
                <div key={i} className={`min-h-20 sm:min-h-24 border-r border-b border-gray-50 p-1 sm:p-1.5 ${!day ? 'bg-gray-50/50' : 'hover:bg-gray-50/70'}`}>
                  {day && (
                    <>
                      <span className={`text-xs font-semibold w-6 h-6 flex items-center justify-center rounded-full ${
                        isToday(day) ? 'bg-orange-600 text-white' : 'text-gray-500'
                      }`}>{day}</span>
                      <div className="mt-0.5 space-y-0.5">
                        {events.slice(0, 3).map((ev, j) => (
                          <button key={j} onClick={() => setSelectedId(ev.lead.id)}
                            className={`w-full text-left text-[10px] px-1 py-0.5 rounded flex items-center gap-0.5 font-medium truncate ${eventStyle(ev.type)}`}>
                            {eventIcon(ev.type)}
                            <span className="truncate hidden sm:inline">{ev.lead.name}</span>
                            <span className="truncate sm:hidden">{ev.lead.name.split(' ')[0]}</span>
                          </button>
                        ))}
                        {events.length > 3 && (
                          <p className="text-[9px] text-gray-400 pl-1">+{events.length - 3} more</p>
                        )}
                      </div>
                    </>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Event list */}
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="px-5 py-3 border-b border-gray-100">
            <h3 className="font-bold text-gray-800">Events — {MONTHS[current.month]} {current.year}</h3>
          </div>
          <div className="divide-y divide-gray-50">
            {upcomingEvents.map(({ date, lead, type }, i) => (
              <div key={i} className="flex items-center gap-3 px-5 py-3 hover:bg-gray-50 cursor-pointer" onClick={() => setSelectedId(lead.id)}>
                <div className="w-10 h-10 rounded-xl bg-orange-50 flex flex-col items-center justify-center text-orange-700 shrink-0">
                  <span className="text-sm font-bold leading-none">{date.split('-')[2]}</span>
                  <span className="text-xs opacity-70">{MONTHS[parseInt(date.split('-')[1]) - 1].slice(0, 3)}</span>
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-gray-800 truncate">{lead.name}</p>
                  <p className="text-xs text-gray-400 truncate">
                    {type === 'survey' ? `Survey ${lead.surveyTime ?? ''}` :
                     type === 'job-start' ? 'Job Starts' :
                     type === 'job-end' ? 'Job Ends' : 'Job Active'} · {lead.jobType}
                  </p>
                </div>
                <span className={`text-xs font-semibold px-2 py-0.5 rounded-full shrink-0 ${eventStyle(type as CalEvent['type'])}`}>
                  {eventLabel(type)}
                </span>
              </div>
            ))}
            {upcomingEvents.length === 0 && (
              <p className="text-sm text-gray-400 text-center py-6">No events this month</p>
            )}
          </div>
        </div>
      </div>

      {selectedId && <LeadDetailPanel />}
    </div>
  );
}
