import { useEffect, useRef, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { useStore } from '../../store/useStore';
import { formatCurrency, jobTypeColor } from '../../utils/helpers';
import type { Lead } from '../../types';

// Fix Leaflet default marker icon broken by bundlers
delete (L.Icon.Default.prototype as unknown as Record<string, unknown>)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl:       'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl:     'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

const STAGE_COLOR: Record<string, string> = {
  'Won':         '#16a34a',
  'In Progress': '#ea580c',
  'Completed':   '#059669',
  'Paid':        '#0d9488',
};

function makeIcon(color: string) {
  return L.divIcon({
    className: '',
    html: `<div style="
      width:14px;height:14px;border-radius:50%;
      background:${color};border:2.5px solid white;
      box-shadow:0 2px 6px rgba(0,0,0,0.35);
    "></div>`,
    iconSize: [14, 14],
    iconAnchor: [7, 7],
    popupAnchor: [0, -10],
  });
}

// Auto-fit map to markers
function FitBounds({ leads }: { leads: Lead[] }) {
  const map = useMap();
  const fitted = useRef(false);
  useEffect(() => {
    const points = leads.filter(l => l.lat && l.lng).map(l => [l.lat!, l.lng!] as [number, number]);
    if (points.length > 0 && !fitted.current) {
      map.fitBounds(points, { padding: [40, 40], maxZoom: 12 });
      fitted.current = true;
    }
  }, [leads, map]);
  return null;
}

const MAP_STAGES = ['Won', 'In Progress', 'Completed', 'Paid'];

export default function JobsMap() {
  const { leads, geocodeLeads, setSelectedId } = useStore();
  const [geocodingDone, setGeocodingDone] = useState(false);

  const mapLeads = leads.filter(l => MAP_STAGES.includes(l.stage));
  const withCoords = mapLeads.filter(l => l.lat && l.lng);
  const needsGeocode = mapLeads.filter(l => !l.lat && l.address);

  const attemptedKeys = useRef<Set<string>>(new Set());
  useEffect(() => {
    const untried = needsGeocode.filter(l => !attemptedKeys.current.has(`${l.id}:${l.address}`));
    if (untried.length > 0) {
      untried.forEach(l => attemptedKeys.current.add(`${l.id}:${l.address}`));
      setGeocodingDone(false);
      geocodeLeads(untried.map(l => l.id)).then(() => setGeocodingDone(true));
    } else if (mapLeads.length > 0) {
      setGeocodingDone(true);
    }
  }, [needsGeocode.map(l => `${l.id}:${l.address}`).join(',')]);

  return (
    <div className="bg-white rounded-2xl border border-gray-100 overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-5 py-3 border-b border-gray-100">
        <div>
          <h2 className="font-bold text-gray-800 text-sm">Job Locations</h2>
          <p className="text-xs text-gray-400">
            {withCoords.length} of {mapLeads.length} jobs mapped
            {needsGeocode.length > 0 && !geocodingDone && (
              <span className="text-orange-500"> · geocoding…</span>
            )}
          </p>
        </div>
        {/* Legend */}
        <div className="flex items-center gap-3 flex-wrap justify-end">
          {MAP_STAGES.map(s => (
            <div key={s} className="flex items-center gap-1">
              <div className="w-2.5 h-2.5 rounded-full" style={{ background: STAGE_COLOR[s] }} />
              <span className="text-[10px] text-gray-500">{s}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Map */}
      <div className="h-72 relative">
        {withCoords.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-gray-400 gap-2">
            <div className="text-3xl">📍</div>
            <p className="text-sm font-medium">
              {mapLeads.length === 0
                ? 'No accepted jobs yet'
                : geocodingDone
                ? 'Could not locate addresses'
                : 'Geocoding addresses…'}
            </p>
            <p className="text-xs">
              {!geocodingDone && mapLeads.length > 0 && needsGeocode.length > 0 && 'This may take a moment'}
              {geocodingDone && withCoords.length === 0 && 'Add full addresses to jobs to see them on the map'}
            </p>
          </div>
        ) : (
          <MapContainer
            center={[53.5, -1.5]}
            zoom={6}
            style={{ height: '100%', width: '100%' }}
            scrollWheelZoom={false}
          >
            <TileLayer
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
            />
            <FitBounds leads={withCoords} />
            {withCoords.map(lead => (
              <Marker
                key={lead.id}
                position={[lead.lat!, lead.lng!]}
                icon={makeIcon(STAGE_COLOR[lead.stage] ?? '#6b7280')}
                eventHandlers={{ click: () => setSelectedId(lead.id) }}
              >
                <Popup>
                  <div className="text-sm min-w-[160px]">
                    <p className="font-bold text-gray-800">{lead.name}</p>
                    <p className="text-gray-500 text-xs mt-0.5">{lead.address}</p>
                    <div className="flex items-center gap-2 mt-1.5">
                      <span className={`text-xs px-1.5 py-0.5 rounded font-medium ${jobTypeColor(lead.jobType)}`}>{lead.jobType}</span>
                    </div>
                    <div className="flex items-center justify-between mt-1.5">
                      <span className="text-xs font-bold text-gray-700">{formatCurrency(lead.value)}</span>
                      <span className="text-xs font-semibold px-1.5 py-0.5 rounded-full"
                        style={{ background: STAGE_COLOR[lead.stage] + '20', color: STAGE_COLOR[lead.stage] }}>
                        {lead.stage}
                      </span>
                    </div>
                    <button
                      onClick={() => setSelectedId(lead.id)}
                      className="mt-2 w-full text-xs text-white rounded-lg py-1 font-medium"
                      style={{ background: '#ea580c' }}
                    >
                      View details →
                    </button>
                  </div>
                </Popup>
              </Marker>
            ))}
          </MapContainer>
        )}
      </div>
    </div>
  );
}
