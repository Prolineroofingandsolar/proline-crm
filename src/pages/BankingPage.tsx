import { useState, useEffect, useCallback } from 'react';
import { RefreshCw, Settings, X, TrendingUp, TrendingDown, Banknote, ArrowDownLeft, ArrowUpRight, AlertCircle } from 'lucide-react';

const MONZO_ACCOUNT_ID = 'acc_0000AxBsrpiHPlsAMA5IId';
const TOKEN_KEY = 'monzo_access_token';

interface MonzoBalance {
  balance: number;
  total_balance: number;
  currency: string;
  spend_today: number;
}

interface MonzoTransaction {
  id: string;
  created: string;
  description: string;
  amount: number;
  currency: string;
  merchant: { name: string; logo: string | null; category: string } | null;
  category: string;
  notes: string;
  decline_reason?: string;
}

function pence(n: number) {
  return (Math.abs(n) / 100).toFixed(2);
}

function formatDate(iso: string) {
  const d = new Date(iso);
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  if (d.toDateString() === today.toDateString()) return 'Today';
  if (d.toDateString() === yesterday.toDateString()) return 'Yesterday';
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: d.getFullYear() !== today.getFullYear() ? 'numeric' : undefined });
}

function groupByDate(txns: MonzoTransaction[]) {
  const groups: Record<string, MonzoTransaction[]> = {};
  for (const t of txns) {
    const key = formatDate(t.created);
    if (!groups[key]) groups[key] = [];
    groups[key].push(t);
  }
  return groups;
}

function categoryColour(category: string) {
  const map: Record<string, string> = {
    transport: 'bg-blue-100 text-blue-700',
    shopping: 'bg-purple-100 text-purple-700',
    eating_out: 'bg-orange-100 text-orange-700',
    bills: 'bg-red-100 text-red-700',
    entertainment: 'bg-pink-100 text-pink-700',
    general: 'bg-gray-100 text-gray-600',
    transfers: 'bg-green-100 text-green-700',
    income: 'bg-emerald-100 text-emerald-700',
    expenses: 'bg-yellow-100 text-yellow-700',
  };
  return map[category] ?? 'bg-gray-100 text-gray-600';
}

function TokenModal({ onSave, onClose, current }: { onSave: (t: string) => void; onClose: () => void; current: string }) {
  const [val, setVal] = useState(current);
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: 'rgba(0,0,0,0.5)' }}>
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h2 className="text-base font-semibold text-gray-900">Update Monzo Token</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600"><X size={18} /></button>
        </div>
        <div className="p-5 space-y-3">
          <p className="text-sm text-gray-500">Paste your access token from the <a href="https://developers.monzo.com" target="_blank" rel="noreferrer" className="text-orange-600 underline">Monzo Developer Playground</a>. Tokens expire after a few hours.</p>
          <textarea
            value={val}
            onChange={e => setVal(e.target.value)}
            rows={4}
            className="w-full border border-gray-200 rounded-lg px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-orange-500 resize-none"
            placeholder="eyJ..."
          />
        </div>
        <div className="flex gap-3 px-5 py-4 border-t border-gray-100">
          <button onClick={onClose} className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2 rounded-xl hover:bg-gray-50">Cancel</button>
          <button onClick={() => { onSave(val.trim()); onClose(); }} className="flex-1 bg-orange-600 text-white text-sm font-medium py-2 rounded-xl hover:bg-orange-700">Save Token</button>
        </div>
      </div>
    </div>
  );
}

export default function BankingPage() {
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY) ?? '');
  const [balance, setBalance] = useState<MonzoBalance | null>(null);
  const [transactions, setTransactions] = useState<MonzoTransaction[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showTokenModal, setShowTokenModal] = useState(false);
  const [lastFetched, setLastFetched] = useState<Date | null>(null);

  const fetchData = useCallback(async (tok: string) => {
    if (!tok) { setError('No token set. Click the settings icon to add your Monzo access token.'); return; }
    setLoading(true);
    setError(null);
    try {
      const headers = { Authorization: `Bearer ${tok}` };
      const [balRes, txnRes] = await Promise.all([
        fetch(`https://api.monzo.com/balance?account_id=${MONZO_ACCOUNT_ID}`, { headers }),
        fetch(`https://api.monzo.com/transactions?account_id=${MONZO_ACCOUNT_ID}&expand[]=merchant`, { headers }),
      ]);

      if (balRes.status === 401 || txnRes.status === 401) {
        setError('Token expired or invalid. Click the settings icon to update your token.');
        setLoading(false);
        return;
      }
      if (!balRes.ok || !txnRes.ok) {
        const errBody = await (balRes.ok ? txnRes : balRes).json().catch(() => ({}));
        setError(errBody.message ?? 'Failed to load Monzo data.');
        setLoading(false);
        return;
      }

      const balData = await balRes.json();
      const txnData = await txnRes.json();
      setBalance(balData);
      const sorted = (txnData.transactions as MonzoTransaction[])
        .filter(t => !t.decline_reason)
        .sort((a, b) => new Date(b.created).getTime() - new Date(a.created).getTime());
      setTransactions(sorted);
      setLastFetched(new Date());
    } catch {
      setError('Network error — check your connection.');
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    if (token) fetchData(token);
  }, [token, fetchData]);

  const saveToken = (t: string) => {
    localStorage.setItem(TOKEN_KEY, t);
    setToken(t);
  };

  const groups = groupByDate(transactions);
  const totalIn = transactions.filter(t => t.amount > 0).reduce((s, t) => s + t.amount, 0);
  const totalOut = transactions.filter(t => t.amount < 0).reduce((s, t) => s + t.amount, 0);

  return (
    <div className="h-full overflow-y-auto bg-gray-50">
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">

        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold text-gray-900">Banking</h1>
            <p className="text-sm text-gray-400">Proline Roofing &amp; Solar Ltd</p>
          </div>
          <div className="flex items-center gap-2">
            {lastFetched && (
              <span className="text-xs text-gray-400 hidden sm:block">
                Updated {lastFetched.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })}
              </span>
            )}
            <button
              onClick={() => fetchData(token)}
              disabled={loading}
              className="p-2 rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors disabled:opacity-40"
              title="Refresh"
            >
              <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
            </button>
            <button
              onClick={() => setShowTokenModal(true)}
              className="p-2 rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors"
              title="Update token"
            >
              <Settings size={16} />
            </button>
          </div>
        </div>

        {/* Error banner */}
        {error && (
          <div className="flex items-start gap-3 bg-red-50 border border-red-100 rounded-xl px-4 py-3">
            <AlertCircle size={16} className="text-red-500 mt-0.5 shrink-0" />
            <p className="text-sm text-red-700">{error}</p>
          </div>
        )}

        {/* Balance card */}
        {balance && (
          <div className="rounded-2xl p-5 text-white" style={{ background: 'linear-gradient(135deg, #111827 0%, #1f2937 100%)' }}>
            <div className="flex items-center gap-2 mb-1">
              <Banknote size={16} className="text-orange-400" />
              <span className="text-sm text-white/60">Current Balance</span>
            </div>
            <div className="text-4xl font-bold tracking-tight mb-4">
              £{(balance.balance / 100).toLocaleString('en-GB', { minimumFractionDigits: 2 })}
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="bg-white/10 rounded-xl px-3 py-2">
                <div className="flex items-center gap-1.5 mb-0.5">
                  <ArrowDownLeft size={13} className="text-emerald-400" />
                  <span className="text-xs text-white/50">Money in</span>
                </div>
                <div className="text-sm font-semibold text-emerald-400">+£{pence(totalIn)}</div>
              </div>
              <div className="bg-white/10 rounded-xl px-3 py-2">
                <div className="flex items-center gap-1.5 mb-0.5">
                  <ArrowUpRight size={13} className="text-red-400" />
                  <span className="text-xs text-white/50">Money out</span>
                </div>
                <div className="text-sm font-semibold text-red-400">−£{pence(totalOut)}</div>
              </div>
            </div>
          </div>
        )}

        {/* Skeleton while loading with no data yet */}
        {loading && !balance && (
          <div className="rounded-2xl bg-gray-200 animate-pulse h-40" />
        )}

        {/* Transactions */}
        {transactions.length > 0 && (
          <div className="space-y-4">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wider">Transactions</h2>
            {Object.entries(groups).map(([date, txns]) => (
              <div key={date}>
                <div className="text-xs font-semibold text-gray-400 mb-2 px-1">{date}</div>
                <div className="bg-white rounded-xl overflow-hidden shadow-sm divide-y divide-gray-50">
                  {txns.map(t => {
                    const name = t.merchant?.name ?? t.description;
                    const logo = t.merchant?.logo;
                    const isIn = t.amount > 0;
                    const cat = t.merchant?.category ?? t.category ?? 'general';
                    return (
                      <div key={t.id} className="flex items-center gap-3 px-4 py-3">
                        {/* Icon / logo */}
                        <div className="w-9 h-9 rounded-full overflow-hidden bg-gray-100 flex items-center justify-center shrink-0">
                          {logo
                            ? <img src={logo} alt={name} className="w-full h-full object-cover" />
                            : isIn
                              ? <TrendingUp size={16} className="text-emerald-500" />
                              : <TrendingDown size={16} className="text-gray-400" />
                          }
                        </div>
                        {/* Details */}
                        <div className="flex-1 min-w-0">
                          <div className="text-sm font-medium text-gray-900 truncate">{name}</div>
                          <div className="flex items-center gap-2 mt-0.5">
                            <span className={`text-[10px] font-medium px-1.5 py-0.5 rounded-full ${categoryColour(cat)}`}>
                              {cat.replace(/_/g, ' ')}
                            </span>
                            {t.notes && <span className="text-xs text-gray-400 truncate">{t.notes}</span>}
                          </div>
                        </div>
                        {/* Amount */}
                        <div className={`text-sm font-semibold shrink-0 ${isIn ? 'text-emerald-600' : 'text-gray-900'}`}>
                          {isIn ? '+' : '−'}£{pence(t.amount)}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Empty state */}
        {!loading && !error && transactions.length === 0 && balance && (
          <div className="text-center py-12 text-gray-400 text-sm">No transactions found</div>
        )}

      </div>

      {showTokenModal && (
        <TokenModal current={token} onSave={saveToken} onClose={() => setShowTokenModal(false)} />
      )}
    </div>
  );
}
