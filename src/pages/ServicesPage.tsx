import { useState } from 'react';
import { Home, Sun, Waves, Wrench, Pipette, PanelTop, Flame, BatteryCharging, Plus, TrendingUp, Clock, CheckCircle } from 'lucide-react';
import { useStore } from '../store/useStore';
import { JobType } from '../types';
import AddLeadModal from '../components/Pipeline/AddLeadModal';

type ServiceDef = {
  type: JobType;
  icon: React.ElementType;
  color: string;
  bg: string;
  border: string;
  tagColor: string;
  headline: string;
  description: string;
  features: string[];
  duration: string;
  category: 'Roofing' | 'Solar' | 'Exterior';
};

const SERVICES: ServiceDef[] = [
  {
    type: 'New Roof',
    icon: Home,
    color: 'text-sky-600',
    bg: 'bg-sky-50',
    border: 'border-sky-200',
    tagColor: 'bg-sky-100 text-sky-700',
    headline: 'Complete Roof Replacement',
    description: 'Full strip and re-roof using quality materials — tiles, slates, or felt. We handle everything from scaffolding to final inspection, giving your property a watertight roof built to last decades.',
    features: ['Full scaffold erection & removal', 'Structural inspection & repairs', 'Choice of tile, slate or felt', '20-year workmanship guarantee', 'LABC-registered installer'],
    duration: '3 – 7 days',
    category: 'Roofing',
  },
  {
    type: 'Roof Repair',
    icon: Wrench,
    color: 'text-orange-600',
    bg: 'bg-orange-50',
    border: 'border-orange-200',
    tagColor: 'bg-orange-100 text-orange-700',
    headline: 'Roof Repairs & Maintenance',
    description: 'From missing tiles and cracked slates to failed flashing and ridge work — we fix it fast. Emergency call-outs available with same-week appointments for most repair types.',
    features: ['Emergency call-out available', 'Tile & slate replacement', 'Flashing & valley repairs', 'Ridge & hip re-bedding', 'Lead work & sealing'],
    duration: 'Half day – 2 days',
    category: 'Roofing',
  },
  {
    type: 'Flat Roof',
    icon: PanelTop,
    color: 'text-purple-600',
    bg: 'bg-purple-50',
    border: 'border-purple-200',
    tagColor: 'bg-purple-100 text-purple-700',
    headline: 'Flat Roof Systems',
    description: 'Specialist flat roofing for extensions, garages, and commercial buildings. We install GRP fibreglass, EPDM rubber, and torch-on felt systems — all fully insulated and sealed for years of trouble-free performance.',
    features: ['GRP fibreglass systems', 'EPDM rubber membrane', 'Torch-on felt', 'Full insulation included', '10–25 year system warranties'],
    duration: '1 – 4 days',
    category: 'Roofing',
  },
  {
    type: 'Chimney Repair',
    icon: Flame,
    color: 'text-red-600',
    bg: 'bg-red-50',
    border: 'border-red-200',
    tagColor: 'bg-red-100 text-red-700',
    headline: 'Chimney Repairs & Repointing',
    description: 'Loose pots, crumbling mortar, failed flaunching — left unchecked these become costly problems. Our chimney specialists repair, repoint, and weatherproof stacks to prevent water ingress and structural damage.',
    features: ['Repointing & repointing mortar', 'Flaunching replacement', 'Chimney pot re-setting', 'Lead flashing repair', 'Full stack rebuilds'],
    duration: '1 – 3 days',
    category: 'Roofing',
  },
  {
    type: 'Solar Installation',
    icon: Sun,
    color: 'text-yellow-600',
    bg: 'bg-yellow-50',
    border: 'border-yellow-200',
    tagColor: 'bg-yellow-100 text-yellow-700',
    headline: 'Solar Panel Installation',
    description: 'Reduce your energy bills and carbon footprint with a professionally installed solar PV system. We survey your roof, design the optimal panel layout, handle all scaffolding, and commission a fully MCS-certified system.',
    features: ['MCS-certified installation', 'Full roof & electrical survey', 'Optimal panel placement design', 'DNO application handled', 'Smart export tariff setup'],
    duration: '1 – 2 days',
    category: 'Solar',
  },
  {
    type: 'Solar + Battery',
    icon: BatteryCharging,
    color: 'text-green-600',
    bg: 'bg-green-50',
    border: 'border-green-200',
    tagColor: 'bg-green-100 text-green-700',
    headline: 'Solar with Battery Storage',
    description: 'Store the excess energy you generate and use it after dark or on cloudy days. Adding a battery like the GivEnergy or Tesla Powerwall maximises your self-consumption and cuts your grid reliance dramatically.',
    features: ['GivEnergy & Tesla Powerwall options', 'Maximise self-consumption', 'EV-ready with car charger integration', 'App-based monitoring included', 'Finance options available'],
    duration: '1 – 2 days',
    category: 'Solar',
  },
  {
    type: 'Guttering',
    icon: Pipette,
    color: 'text-teal-600',
    bg: 'bg-teal-50',
    border: 'border-teal-200',
    tagColor: 'bg-teal-100 text-teal-700',
    headline: 'Guttering & Drainage',
    description: 'Blocked, cracked, or sagging gutters can send water behind your fascias and into your walls. We clear, repair, and replace uPVC and cast-iron guttering to keep rainwater flowing away from your home.',
    features: ['uPVC & cast-iron guttering', 'Gutter clearing & unblocking', 'Downpipe replacement', 'Full system replacement', 'Colour-matched products'],
    duration: 'Half day – 1 day',
    category: 'Exterior',
  },
  {
    type: 'Fascias & Soffits',
    icon: Waves,
    color: 'text-pink-600',
    bg: 'bg-pink-50',
    border: 'border-pink-200',
    tagColor: 'bg-pink-100 text-pink-700',
    headline: 'Fascias, Soffits & Bargeboards',
    description: 'Rotten or failing timber fascias and soffits let in damp and pests. We replace them with low-maintenance uPVC boards in a wide range of colours, giving your roofline a clean, fresh look that lasts for decades.',
    features: ['uPVC & woodgrain finishes', 'Wide colour range', 'Vented soffits for roof airflow', 'Full timber rot removal', 'No maintenance required'],
    duration: '1 – 2 days',
    category: 'Exterior',
  },
];

const CATEGORIES = ['All', 'Roofing', 'Solar', 'Exterior'] as const;

export default function ServicesPage() {
  const { leads, setCurrentPage, users, currentUserId } = useStore();
  const isAdmin = users.find(u => u.id === currentUserId)?.role === 'admin';
  const [activeCategory, setActiveCategory] = useState<typeof CATEGORIES[number]>('All');
  const [showNewLead, setShowNewLead] = useState(false);
  const [preselectedType, setPreselectedType] = useState<JobType | undefined>();

  const filtered = activeCategory === 'All' ? SERVICES : SERVICES.filter(s => s.category === activeCategory);

  const jobCounts = SERVICES.reduce((acc, s) => {
    acc[s.type] = leads.filter(l => l.jobType === s.type).length;
    return acc;
  }, {} as Record<string, number>);

  const totalJobs = leads.length;
  const activeJobs = leads.filter(l => l.stage === 'In Progress').length;
  const completedJobs = leads.filter(l => l.stage === 'Completed' || l.stage === 'Paid').length;

  const handleNewLead = (type: JobType) => {
    setPreselectedType(type);
    setShowNewLead(true);
  };

  return (
    <div className="flex flex-col h-full overflow-auto bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-100 px-4 sm:px-6 py-5">
        <div className="max-w-5xl mx-auto">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h1 className="text-xl sm:text-2xl font-bold text-gray-900">Our Services</h1>
              <p className="text-sm text-gray-500 mt-1">ProLine Roofing & Solar — what we do and how we can help</p>
            </div>
            {isAdmin && (
              <button
                onClick={() => { setPreselectedType(undefined); setShowNewLead(true); }}
                className="flex items-center gap-1.5 px-3 py-2 bg-orange-600 hover:bg-orange-700 text-white text-sm font-medium rounded-lg transition-colors shrink-0"
              >
                <Plus size={15} /> New Lead
              </button>
            )}
          </div>

          {/* Stats row */}
          <div className="grid grid-cols-3 gap-3 mt-4">
            <div className="bg-orange-50 rounded-xl px-4 py-3">
              <div className="flex items-center gap-2 text-orange-600 mb-0.5">
                <TrendingUp size={14} />
                <span className="text-xs font-medium uppercase tracking-wide">Total Jobs</span>
              </div>
              <p className="text-2xl font-bold text-gray-900">{totalJobs}</p>
            </div>
            <div className="bg-blue-50 rounded-xl px-4 py-3">
              <div className="flex items-center gap-2 text-blue-600 mb-0.5">
                <Clock size={14} />
                <span className="text-xs font-medium uppercase tracking-wide">Active</span>
              </div>
              <p className="text-2xl font-bold text-gray-900">{activeJobs}</p>
            </div>
            <div className="bg-green-50 rounded-xl px-4 py-3">
              <div className="flex items-center gap-2 text-green-600 mb-0.5">
                <CheckCircle size={14} />
                <span className="text-xs font-medium uppercase tracking-wide">Completed</span>
              </div>
              <p className="text-2xl font-bold text-gray-900">{completedJobs}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Category filter */}
      <div className="bg-white border-b border-gray-100 px-4 sm:px-6 py-3 sticky top-0 z-10">
        <div className="max-w-5xl mx-auto flex gap-2 overflow-x-auto pb-0.5 scrollbar-hide">
          {CATEGORIES.map(cat => (
            <button
              key={cat}
              onClick={() => setActiveCategory(cat)}
              className={`px-4 py-1.5 rounded-full text-sm font-medium whitespace-nowrap transition-colors ${
                activeCategory === cat
                  ? 'bg-orange-600 text-white'
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              {cat}
            </button>
          ))}
        </div>
      </div>

      {/* Service cards */}
      <div className="flex-1 px-4 sm:px-6 py-5">
        <div className="max-w-5xl mx-auto grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-2 gap-4">
          {filtered.map(service => {
            const Icon = service.icon;
            const count = jobCounts[service.type] ?? 0;
            return (
              <div
                key={service.type}
                className={`bg-white rounded-2xl border ${service.border} shadow-sm hover:shadow-md transition-shadow flex flex-col`}
              >
                {/* Card header */}
                <div className={`${service.bg} rounded-t-2xl px-5 py-4 flex items-start gap-4`}>
                  <div className={`w-11 h-11 rounded-xl ${service.bg} border ${service.border} flex items-center justify-center shrink-0`}>
                    <Icon size={22} className={service.color} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${service.tagColor}`}>
                        {service.category}
                      </span>
                      {count > 0 && (
                        <span className="text-[11px] text-gray-500 font-medium">{count} job{count !== 1 ? 's' : ''}</span>
                      )}
                    </div>
                    <h2 className="text-base font-bold text-gray-900 mt-1 leading-tight">{service.headline}</h2>
                    <p className="text-[11px] font-medium text-gray-500 mt-0.5">{service.type}</p>
                  </div>
                </div>

                {/* Card body */}
                <div className="px-5 py-4 flex-1 flex flex-col gap-3">
                  <p className="text-sm text-gray-600 leading-relaxed">{service.description}</p>

                  <ul className="space-y-1.5">
                    {service.features.map(f => (
                      <li key={f} className="flex items-start gap-2 text-sm text-gray-700">
                        <CheckCircle size={14} className={`${service.color} shrink-0 mt-0.5`} />
                        {f}
                      </li>
                    ))}
                  </ul>

                  <div className="flex items-center justify-between pt-2 mt-auto border-t border-gray-100">
                    <div className="flex items-center gap-1.5 text-xs text-gray-500">
                      <Clock size={12} />
                      <span>Typical duration: <strong className="text-gray-700">{service.duration}</strong></span>
                    </div>
                    {isAdmin && (
                      <button
                        onClick={() => handleNewLead(service.type)}
                        className={`flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${service.bg} ${service.color} hover:opacity-80 border ${service.border}`}
                      >
                        <Plus size={12} /> New Lead
                      </button>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        {/* Bottom CTA */}
        <div className="max-w-5xl mx-auto mt-6 bg-gray-900 rounded-2xl px-6 py-6 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div>
            <p className="text-white font-bold text-base">Not sure which service you need?</p>
            <p className="text-white/60 text-sm mt-0.5">View all active jobs or check the pipeline for pending quotes.</p>
          </div>
          <div className="flex gap-2 shrink-0">
            <button
              onClick={() => setCurrentPage('jobs')}
              className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white text-sm font-medium rounded-lg transition-colors"
            >
              View Jobs
            </button>
            <button
              onClick={() => setCurrentPage('pipeline')}
              className="px-4 py-2 bg-orange-600 hover:bg-orange-700 text-white text-sm font-medium rounded-lg transition-colors"
            >
              Open Pipeline
            </button>
          </div>
        </div>
      </div>

      {showNewLead && (
        <AddLeadModal
          onClose={() => { setShowNewLead(false); setPreselectedType(undefined); }}
          preselectedJobType={preselectedType}
        />
      )}
    </div>
  );
}
