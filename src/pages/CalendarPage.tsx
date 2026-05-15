import { useState } from 'react';
import { ChevronLeft, ChevronRight, Calendar } from 'lucide-react';
import { useStore } from '../store/useStore';
import LeadDetailPanel from '../components/LeadDetail/LeadDetailPanel';
import type { Lead } from '../types';

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];

// Colour per lead — cycle through a palette so each job has a distinct colour
const PALETTE = [
  'bg-orange-400', 'bg-violet-400', 'bg-blue-400', 'bg-emerald-400',
  'bg-pink-400', 'bg-amber-400', 'bg-teal-400', 'bg-rose-400',
  'bg-indigo-400', 'bg-cyan-400',
];

export default function CalendarPage() {
  const { leads, selectedId, setSelectedId } = useStore();
  const [current, setCurrent] = useState(() => {
    const d = new Date();
    return { year: d.getFullYear(), month: d.getMonth() };
  });

  const today = new Date();
  const isToday = (day: number) =>
    day === today.getDate() && current.month === today.getMonth() && current.year === today.getFullYear();

  const firstDay = new Date(current.year, current.month, 1).getDay();
  const daysInMonth = new Date(current.year, current.month + 1, 0).getDate();
  const cells: (number | null)[] = Array.from({ length: firstDay + daysInMonth }, (_, i) =>
    i < firstDay ? null : i - firstDay + 1
  );
  while (cells.length % 7 !== 0) cells.push(null);

  const dateStr = (day: number) =>
    `${current.year}-${String(current.month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;

  // Surveys on a specific day
  const getSurveys = (day: number) =>
    leads.filter(l => l.surveyDate === dateStr(day));

  // Jobs that span this day (have start date, end date, or are between them)
  type JobEvent = { lead: Lead; position: 'start' | 'middle' | 'end' | 'single'; colorIdx: number };

  // Build a stable colour index per lead
  const leadColorIdx = Object.fromEntries(
    [...leads]
      .filter(l => l.startDate || l.endDate)
      .map((l, i) => [l.id, i % PALETTE.length])
  );

  const getJobEvents = (day: number): JobEvent[] => {
    const date = dateStr(day);
    const events: JobEvent[] = [];
    for (const lead of leads) {
      if (!lead.startDate) continue;
      const start = lead.startDate;
      const end = lead.endDate ?? lead.startDate; // single-day if no end date
      if (date < start || date > end) continue;
      const position = start === end ? 'single'
        : date === start ? 'start'
        : date === end   ? 'end'
        : 'middle';
      events.push({ lead, position, colorIdx: leadColorIdx[lead.id] ?? 0 });
    }
    return events;
  };

  // Upcoming events list for this month
  const prefix = `${current.year}-${String(current.month + 1).padStart(2, '0')}`;
  const upcomingEvents: { date: string; lead: Lead; type: 'survey' | 'job-start' | 'job-end' }[] = leads
    .flatMap(lead => {
      const evts: { date: string; lead: Lead; type: 'survey' | 'job-start' | 'job-end' }[] = [];
      if (lead.surveyDate?.startsWith(prefix)) evts.push({ date: lead.surveyDate, lead, type: 'survey' });
      if (lead.startDate?.startsWith(prefix))  evts.push({ date: lead.startDate, lead, type: 'job-start' });
      if (lead.endDate?.startsWith(prefix) && lead.endDate !== lead.startDate)
        evts.push({ date: lead.endDate, lead, type: 'job-end' });
      return evts;
    })
    .sort((a, b) => a.date.localeCompare(b.date));

  return (
    <div className="flex flex-col h-full bg-white overflow-hidden">
      <div className="flex-1 overflow-auto p-4 space-y-4">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">

          {/* Header */}
          <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
            <div className="flex items-center gap-2">
              <Calendar size={18} className="text-orange-500" />
              <h2 className="font-bold text-gray-800 text-lg">{MONTHS[current.month]} {current.year}</h2>
            </div>
            {/* Legend */}
            <div className="hidden sm:flex items-center gap-3 text-xs text-gray-500">
              <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-violet-400 inline-block" /> Survey</span>
              <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded bg-orange-400 inline-block" /> Job booked</span>
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
              const surveys  = day ? getSurveys(day) : [];
              const jobEvts  = day ? getJobEvents(day) : [];
              const isWeekStart = i % 7 === 0;
              const isWeekEnd   = i % 7 === 6;

              return (
                <div key={i}
                  className={`min-h-20 sm:min-h-24 border-r border-b border-gray-50 ${!day ? 'bg-gray-50/40' : isToday(day) ? 'bg-orange-50/30' : 'hover:bg-gray-50/50'}`}>
                  {day && (
                    <>
                      {/* Day number */}
                      <div className="px-1.5 pt-1">
                        <span className={`text-xs font-semibold w-6 h-6 flex items-center justify-center rounded-full ${
                          isToday(day) ? 'bg-orange-600 text-white' : 'text-gray-500'
                        }`}>{day}</span>
                      </div>

                      {/* Surveys — pill inside cell */}
                      <div className="px-1 space-y-0.5 mt-0.5">
                        {surveys.slice(0, 1).map(ev => (
                          <button key={ev.id} onClick={() => setSelectedId(ev.id)}
                            className="w-full text-left text-[10px] px-1.5 py-0.5 rounded-full font-semibold truncate bg-violet-100 text-violet-700 hover:bg-violet-200">
                            <span className="hidden sm:inline">{ev.name} · Survey</span>
                            <span className="sm:hidden">{ev.name.split(' ')[0]}</span>
                          </button>
                        ))}

                        {/* Job bars — edge-to-edge, continuous across days */}
                        {jobEvts.slice(0, surveys.length > 0 ? 2 : 3).map((ev, j) => {
                          const color = PALETTE[ev.colorIdx];
                          const isStart  = ev.position === 'start'  || ev.position === 'single';
                          const isEnd    = ev.position === 'end'    || ev.position === 'single';
                          const atLeft   = isStart || isWeekStart;
                          const atRight  = isEnd   || isWeekEnd;
                          return (
                            <button key={j}
                              onClick={() => setSelectedId(ev.lead.id)}
                              className={`
                                w-full text-left text-[10px] py-0.5 font-semibold text-white
                                ${color} hover:opacity-80 transition-opacity
                                ${atLeft  ? 'pl-1.5 rounded-l-full' : 'pl-0.5 -ml-0'}
                                ${atRight ? 'pr-1.5 rounded-r-full' : 'pr-0'}
                              `}
                              style={{
                                marginLeft:  isStart || isWeekStart  ? undefined : '-1px',
                                marginRight: isEnd   || isWeekEnd    ? undefined : '-1px',
                              }}
                            >
                              {(isStart || isWeekStart) ? (
                                <span className="truncate block">
                                  <span className="hidden sm:inline">{ev.lead.name}</span>
                                  <span className="sm:hidden">{ev.lead.name.split(' ')[0]}</span>
                                </span>
                              ) : (
                                <span className="opacity-0 select-none">·</span>
                              )}
                            </button>
                          );
                        })}

                        {(surveys.length + jobEvts.length) > 3 && (
                          <p className="text-[9px] text-gray-400 pl-1.5">+{surveys.length + jobEvts.length - 3} more</p>
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
                <div className={`w-10 h-10 rounded-xl flex flex-col items-center justify-center shrink-0 ${type === 'survey' ? 'bg-violet-50 text-violet-700' : 'bg-orange-50 text-orange-700'}`}>
                  <span className="text-sm font-bold leading-none">{date.split('-')[2]}</span>
                  <span className="text-xs opacity-70">{MONTHS[parseInt(date.split('-')[1]) - 1].slice(0, 3)}</span>
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-gray-800 truncate">{lead.name}</p>
                  <p className="text-xs text-gray-400">{lead.jobType} · {lead.stage}</p>
                </div>
                <span className={`text-xs font-semibold px-2 py-0.5 rounded-full shrink-0 ${
                  type === 'survey'   ? 'bg-violet-100 text-violet-700' :
                  type === 'job-start' ? 'bg-green-100 text-green-700' :
                  'bg-red-100 text-red-600'
                }`}>
                  {type === 'survey' ? 'Survey' : type === 'job-start' ? 'Starts' : 'Ends'}
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
