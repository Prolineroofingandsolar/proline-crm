import { useState } from 'react';
import { Plus, Trash2, Package } from 'lucide-react';
import type { Lead } from '../../types';
import { useStore } from '../../store/useStore';
import { formatCurrency } from '../../utils/helpers';

export default function MaterialsTab({ lead }: { lead: Lead }) {
  const { addMaterial, updateMaterial, deleteMaterial } = useStore();
  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState({ name: '', quantity: '', unit: 'units', cost: '', supplier: '' });

  const total = lead.materials.reduce((s, m) => s + (m.cost ?? 0) * m.quantity, 0);

  const handleAdd = () => {
    if (!form.name.trim()) return;
    addMaterial(lead.id, {
      name: form.name.trim(),
      quantity: parseFloat(form.quantity) || 1,
      unit: form.unit.trim() || 'units',
      cost: parseFloat(form.cost) || undefined,
      supplier: form.supplier.trim() || undefined,
      ordered: false,
      delivered: false,
    });
    setForm({ name: '', quantity: '', unit: 'units', cost: '', supplier: '' });
    setAdding(false);
  };

  return (
    <div className="p-4 space-y-4">
      {lead.materials.length > 0 && (
        <div className="bg-orange-50 rounded-xl p-3 text-sm">
          <span className="text-gray-600">Total materials cost: </span>
          <span className="font-bold text-orange-700">{formatCurrency(total)}</span>
        </div>
      )}

      <div className="space-y-2">
        {lead.materials.map(mat => (
          <div key={mat.id} className="flex items-center gap-3 p-2.5 rounded-xl border border-gray-100 hover:border-gray-200 bg-white group">
            <Package size={16} className="text-gray-400 shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-800 truncate">{mat.name}</p>
              <p className="text-xs text-gray-400">{mat.quantity} {mat.unit}{mat.supplier ? ` · ${mat.supplier}` : ''}</p>
            </div>
            {mat.cost && <span className="text-sm font-semibold text-gray-700 shrink-0">{formatCurrency(mat.cost * mat.quantity)}</span>}
            <div className="flex items-center gap-1.5 shrink-0">
              <button
                onClick={() => updateMaterial(lead.id, mat.id, { ordered: !mat.ordered })}
                className={`text-xs px-2 py-0.5 rounded-full font-medium transition-colors ${mat.ordered ? 'bg-orange-100 text-orange-700' : 'bg-gray-100 text-gray-500 hover:bg-orange-50'}`}
              >
                {mat.ordered ? 'Ordered' : 'Order'}
              </button>
              <button
                onClick={() => updateMaterial(lead.id, mat.id, { delivered: !mat.delivered })}
                className={`text-xs px-2 py-0.5 rounded-full font-medium transition-colors ${mat.delivered ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500 hover:bg-green-50'}`}
              >
                {mat.delivered ? 'Delivered' : 'Deliver'}
              </button>
              <button onClick={() => deleteMaterial(lead.id, mat.id)}
                className="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-red-500 transition-opacity">
                <Trash2 size={13} />
              </button>
            </div>
          </div>
        ))}
        {lead.materials.length === 0 && <p className="text-sm text-gray-400 text-center py-4">No materials added</p>}
      </div>

      {adding ? (
        <div className="border border-gray-200 rounded-xl p-3 space-y-2">
          <input value={form.name} onChange={e => setForm(p => ({ ...p, name: e.target.value }))}
            placeholder="Material name" className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          <div className="grid grid-cols-2 gap-2">
            <input value={form.quantity} onChange={e => setForm(p => ({ ...p, quantity: e.target.value }))}
              type="number" placeholder="Qty" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
            <input value={form.unit} onChange={e => setForm(p => ({ ...p, unit: e.target.value }))}
              placeholder="Unit (tiles, m, rolls…)" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
            <input value={form.cost} onChange={e => setForm(p => ({ ...p, cost: e.target.value }))}
              type="number" placeholder="Unit cost (£)" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
            <input value={form.supplier} onChange={e => setForm(p => ({ ...p, supplier: e.target.value }))}
              placeholder="Supplier" className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          </div>
          <div className="flex gap-2">
            <button onClick={() => setAdding(false)} className="flex-1 border border-gray-200 rounded-lg py-1.5 text-sm text-gray-500 hover:bg-gray-50">Cancel</button>
            <button onClick={handleAdd} className="flex-1 bg-orange-600 text-white rounded-lg py-1.5 text-sm hover:bg-orange-700">Add</button>
          </div>
        </div>
      ) : (
        <button onClick={() => setAdding(true)} className="flex items-center gap-2 text-sm text-orange-600 hover:text-orange-800 font-medium">
          <Plus size={15} /> Add Material
        </button>
      )}
    </div>
  );
}
