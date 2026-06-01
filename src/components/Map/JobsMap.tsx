import { useEffect, useRef, useState, useCallback } from 'react';
import { MapContainer, TileLayer, Marker, useMap, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { X } from 'lucide-react';
import { useStore } from '../../store/useStore';
import { formatCurrency, jobTypeColor } from '../../utils/helpers';
import type { Lead } from '../../types';

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

function makeIcon(color: string, active: boolean) {
  const size = active ? 18 : 14;
  return L.divIcon({
    className: '',
    html: `<div style="width:${size}px;height:${size}px;border-radius:50%;background:${color};border:${active ? '3px' : '2.5px'} solid white;box-shadow:0 2px 8px rgba(0,0,0,${active ? '0.5' : '0.35'});"></div>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
  });
}

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

// Re-syncs card pixel position when map pans/zooms
function CardPositionTracker({
  lead,
  onPixel,
}: {
  lead: Lead | null;
  onPixel: (x: number, y: number) => void;
}) {
  const map = useMap();

  const sync = useCallback(() => {
    if (!lead?.lat || !lead?.lng) return;
    const pt = map.latLngToContainerPoint([lead.lat, lead.lng]);
    onPixel(pt.x, pt.y);
  }, [lead, map, onPixel]);

  useMapEvents({ moveend: sync, zoomend: sync, move: sync });

  useEffect(() => { sync(); }, [sync]);

  return null;
}

const MAP_STAGES = ['Won', 'In Progress', 'Completed', 'Paid'];
const CARD_W = 210;
const CARD_H = 188;

export default function JobsMap() {
  const { leads, geocodeLeads, setSelectedId } = useStore();
  const [geocodingDone, setGeocodingDone] = useState(false);
  const [activeLead, setActiveLead] = useState<Lead | null>(null);
  const [cardPos, setCardPos] = useState<{ x: number; y: number } | null>(null);
  const mapContainerRef = useRef<HTMLDivElement>(null);

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

  const clampedPos = useCallback((markerX: number, markerY: number) => {
    const container = mapContainerRef.current;
    if (!container) return;
    const W = container.clientWidth;
    const H = container.clientHeight;
    let x = markerX - CARD_W / 2;
    let y = markerY - CARD_H - 18;
    x = Math.max(8, Math.min(x, W - CARD_W - 8));
    y = Math.max(8, Math.min(y, H - CARD_H - 8));
    setCardPos({ x, y });
  }, []);

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
        <div className="flex items-center gap-3 flex-wrap justify-end">
          {MAP_STAGES.map(s => (
            <div key={s} className="flex items-center gap-1">
              <div className="w-2.5 h-2.5 rounded-full" style={{ background: STAGE_COLOR[s] }} />
              <span className="text-[10px] text-gray-500">{s}</span>
            </div>
          ))}
        </div>
      </div>

      {/*
        isolation: isolate creates a new stacking context here.
        Leaflet's internal panes use z-index 200–800 but without this they
        escape into the page stacking context and paint over the fixed
        LeadDetailPanel (z-50). Isolation contains them.
      */}
      <div ref={mapContainerRef} className="h-72 relative" style={{ isolation: 'isolate' }}>
        {withCoords.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-gray-400 gap-2">
            <div className="text-3xl">📍</div>
            <p className="text-sm font-medium">
              {mapLeads.length === 0 ? 'No accepted jobs yet' : geocodingDone ? 'Could not locate addresses' : 'Geocoding addresses…'}
            </p>
            <p className="text-xs">
              {!geocodingDone && mapLeads.length > 0 && needsGeocode.length > 0 && 'This may take a moment'}
              {geocodingDone && withCoords.length === 0 && 'Add full addresses to jobs to see them on the map'}
            </p>
          </div>
        ) : (
          <>
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
              <CardPositionTracker lead={activeLead} onPixel={clampedPos} />
              {withCoords.map(lead => (
                <Marker
                  key={lead.id}
                  position={[lead.lat!, lead.lng!]}
                  icon={makeIcon(STAGE_COLOR[lead.stage] ?? '#6b7280', activeLead?.id === lead.id)}
                  eventHandlers={{
                    click: (e) => {
                      const map = e.target._map as L.Map;
                      const px = map.latLngToContainerPoint([lead.lat!, lead.lng!]);
                      clampedPos(px.x, px.y);
                      setActiveLead(prev => prev?.id === lead.id ? null : lead);
                    },
                  }}
                />
              ))}
            </MapContainer>

            {/* Card lives inside the isolated div so it shares the same stacking context */}
            {activeLead && cardPos && (
              <div
                className="absolute bg-white rounded-2xl shadow-xl border border-gray-100 p-4"
                style={{ left: cardPos.x, top: cardPos.y, width: CARD_W, zIndex: 900 }}
              >
                <div className="flex items-start justify-between gap-2 mb-2">
                  <p className="font-bold text-gray-900 text-sm leading-tight">{activeLead.name}</p>
                  <button onClick={() => setActiveLead(null)} className="text-gray-300 hover:text-gray-500 shrink-0 -mt-0.5">
                    <X size={14} />
                  </button>
                </div>
                <p className="text-gray-400 text-xs mb-2 truncate">{activeLead.address}</p>
                <div className="flex items-center gap-2 mb-2">
                  <span className={`text-xs px-1.5 py-0.5 rounded font-medium ${jobTypeColor(activeLead.jobType)}`}>
                    {activeLead.jobType}
                  </span>
                </div>
                <div className="flex items-center justify-between mb-3">
                  <span className="text-sm font-bold text-gray-800">{formatCurrency(activeLead.value)}</span>
                  <span className="text-xs font-semibold px-1.5 py-0.5 rounded-full"
                    style={{ background: (STAGE_COLOR[activeLead.stage] ?? '#6b7280') + '20', color: STAGE_COLOR[activeLead.stage] ?? '#6b7280' }}>
                    {activeLead.stage}
                  </span>
                </div>
                <button
                  onClick={() => { setSelectedId(activeLead.id); setActiveLead(null); }}
                  className="w-full text-xs text-white rounded-xl py-2 font-semibold"
                  style={{ background: '#ea580c' }}
                >
                  View details →
                </button>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
