import { useState } from 'react';
import { Ruler, Triangle, Info } from 'lucide-react';
import { battenGauge, roofPitch } from '../lib/roofTools';

const input = 'mt-1 w-full rounded-xl border border-gray-300 bg-white px-3 py-2.5 text-base outline-none focus:ring-2 focus:ring-orange-500';
const number = (value: string) => Number(value.replace(',', '.'));

function Field({ label, value, onChange, placeholder }: { label: string; value: string; onChange: (value: string) => void; placeholder: string }) {
  return <label className="block text-sm font-medium text-gray-700">{label}<input className={input} inputMode="decimal" type="text" value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder} /></label>;
}

export default function ToolsPage() {
  const [tool, setTool] = useState<'pitch' | 'gauge'>('pitch');
  const [rise, setRise] = useState(''); const [run, setRun] = useState('');
  const [length, setLength] = useState(''); const [left, setLeft] = useState(''); const [centre, setCentre] = useState(''); const [right, setRight] = useState('');
  const [uneven, setUneven] = useState(false); const [setback, setSetback] = useState(''); const [min, setMin] = useState(''); const [max, setMax] = useState('');
  const r = number(rise), h = number(run);
  const pitch = rise && run ? roofPitch(r, h) : null;
  const measured = uneven ? [left, centre, right] : [length];
  const distances = measured.map(number); const top = number(setback); const minGauge = number(min), maxGauge = number(max);
  const result = measured.every(v => v.trim() !== '') && setback.trim() !== '' && min.trim() !== '' && max.trim() !== '' ? battenGauge(distances, top, minGauge, maxGauge) : null;
  const valid = result !== null;
  const courseCount = result?.courses ?? 0, shortest = result?.shortest ?? 0, longest = result?.longest ?? 0, outOfRange = result?.outOfRange ?? false;

  return <div className="h-full overflow-y-auto bg-gray-50 px-4 py-6 sm:px-8"><div className="mx-auto max-w-3xl space-y-5">
    <div><h2 className="text-2xl font-bold text-gray-900">Roofing tools</h2><p className="mt-1 text-sm text-gray-600">Quick site calculations on your phone or computer.</p></div>
    <div className="grid grid-cols-2 gap-2 rounded-xl bg-gray-200 p-1" role="group" aria-label="Roofing tool">
      <button onClick={() => setTool('pitch')} aria-pressed={tool === 'pitch'} className={`flex items-center justify-center gap-2 rounded-lg px-3 py-2.5 text-sm font-semibold ${tool === 'pitch' ? 'bg-white text-orange-700 shadow-sm' : 'text-gray-600'}`}><Triangle size={17}/>Pitch finder</button>
      <button onClick={() => setTool('gauge')} aria-pressed={tool === 'gauge'} className={`flex items-center justify-center gap-2 rounded-lg px-3 py-2.5 text-sm font-semibold ${tool === 'gauge' ? 'bg-white text-orange-700 shadow-sm' : 'text-gray-600'}`}><Ruler size={17}/>Batten gauger</button>
    </div>
    {tool === 'pitch' ? <section className="space-y-5 rounded-2xl border border-gray-200 bg-white p-5 sm:p-6"><div><h3 className="text-lg font-bold">Calculate roof pitch</h3><p className="mt-1 text-sm text-gray-600">Measure the vertical rise and horizontal run using the same units.</p></div><div className="grid grid-cols-2 gap-3"><Field label="Rise (mm)" placeholder="1200" value={rise} onChange={setRise}/><Field label="Run (mm)" placeholder="2400" value={run} onChange={setRun}/></div>{pitch !== null ? <div role="status" className="rounded-xl bg-orange-50 p-4"><p className="text-xs font-bold uppercase tracking-wide text-orange-800">Calculated pitch</p><p className="mt-1 text-3xl font-bold text-orange-700">{pitch.toFixed(1)}°</p><p className="mt-1 text-sm text-gray-700">Rise to run: 1 : {(h / r).toFixed(2)}</p></div> : <p className="text-sm text-gray-500">Enter a rise and run greater than zero.</p>}<p className="flex gap-2 text-xs text-gray-500"><Info size={16} className="shrink-0"/>The live phone level is available in the iPhone app.</p></section> : <section className="space-y-5 rounded-2xl border border-gray-200 bg-white p-5 sm:p-6"><div><h3 className="text-lg font-bold">Set out the battens</h3><p className="mt-1 text-sm text-gray-600">Enter the permitted gauge for your actual tile and roof pitch, then measure from the first batten line to the apex.</p></div><label className="flex items-center gap-2 text-sm font-medium"><input type="checkbox" checked={uneven} onChange={e => setUneven(e.target.checked)} className="h-4 w-4 accent-orange-600"/>Roof is not square</label><div className={`grid gap-3 ${uneven ? 'sm:grid-cols-3' : ''}`}>{uneven ? <><Field label="Left measurement (mm)" placeholder="4980" value={left} onChange={setLeft}/><Field label="Centre measurement (mm)" placeholder="5000" value={centre} onChange={setCentre}/><Field label="Right measurement (mm)" placeholder="5020" value={right} onChange={setRight}/></> : <Field label="First batten to apex (mm)" placeholder="5000" value={length} onChange={setLength}/>}</div><Field label="Top batten down from apex (mm)" placeholder="100" value={setback} onChange={setSetback}/><div className="grid grid-cols-2 gap-3"><Field label="Minimum gauge (mm)" placeholder="320" value={min} onChange={setMin}/><Field label="Maximum gauge (mm)" placeholder="345" value={max} onChange={setMax}/></div>{valid ? <div role="status" className={`rounded-xl p-4 ${outOfRange ? 'bg-red-50 text-red-900' : 'bg-orange-50 text-gray-900'}`}><p className="text-sm font-semibold">{courseCount} equal courses</p><p className="mt-1 text-2xl font-bold">{uneven ? `${shortest.toFixed(1)}–${longest.toFixed(1)}` : longest.toFixed(1)} mm</p><p className="mt-2 text-sm">{outOfRange ? 'At least one gauge is outside the range entered. Adjust the set-out before fixing battens.' : 'Calculated between the first and top batten lines.'}</p></div> : <p className="text-sm text-gray-500">Enter all measurements and a valid permitted gauge range.</p>}<p className="text-xs text-gray-500">Use the tile and ridge manufacturers’ details for the permitted gauge, headlap and top-batten position. This calculator does not select or verify a tile specification.</p></section>}
  </div></div>;
}
