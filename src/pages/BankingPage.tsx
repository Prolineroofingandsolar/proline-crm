import { useState, useEffect, useCallback, useRef } from 'react';
import { RefreshCw, X, TrendingUp, TrendingDown, Banknote, ArrowDownLeft, ArrowUpRight, AlertCircle, Receipt, Camera, Upload, Check, Loader2, Eye, Trash2, Link2, Link2Off, CheckCircle2, CircleDashed, ChevronDown, Plug, PlugZap } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useStore } from '../store/useStore';
import { getValidToken, isConnected, startOAuthFlow, disconnect, getTokenExpiry } from '../lib/monzo';

const MONZO_ACCOUNT_ID = 'acc_0000AxBsrpiHPlsAMA5IId';
const BUCKET = 'receipts';

// ── Types ────────────────────────────────────────────────────────────────────

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
  counterparty?: { name?: string; account_number?: string; sort_code?: string; user_id?: string };
  category: string;
  notes: string;
  decline_reason?: string;
}

interface StoredReceipt {
  id: string;
  transaction_id: string;
  file_path: string;
  notes: string;
  created_at: string;
  url?: string;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

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

// ── Receipt DB helpers ────────────────────────────────────────────────────────

async function fetchReceipts(transactionIds: string[]): Promise<StoredReceipt[]> {
  if (transactionIds.length === 0) return [];
  const { data, error } = await supabase
    .from('monzo_receipts')
    .select('*')
    .in('transaction_id', transactionIds);
  if (error) { console.error('fetchReceipts:', error); return []; }
  const rows = (data ?? []) as StoredReceipt[];
  // Get signed URLs for each
  const withUrls = await Promise.all(rows.map(async r => {
    const { data: signed } = await supabase.storage.from(BUCKET).createSignedUrl(r.file_path, 3600);
    return { ...r, url: signed?.signedUrl ?? '' };
  }));
  return withUrls;
}

async function saveReceipt(transactionId: string, file: File, notes: string): Promise<StoredReceipt | null> {
  const ext = file.name.split('.').pop() ?? 'jpg';
  const path = `${transactionId}/${Date.now()}.${ext}`;
  const { error: uploadErr } = await supabase.storage.from(BUCKET).upload(path, file, { upsert: false });
  if (uploadErr) { console.error('upload:', uploadErr); return null; }
  const id = crypto.randomUUID();
  const { data, error: dbErr } = await supabase.from('monzo_receipts').insert({
    id,
    transaction_id: transactionId,
    file_path: path,
    notes,
    created_at: new Date().toISOString(),
  }).select().single();
  if (dbErr) { console.error('receipt insert:', dbErr); return null; }
  const { data: signed } = await supabase.storage.from(BUCKET).createSignedUrl(path, 3600);
  return { ...(data as StoredReceipt), url: signed?.signedUrl ?? '' };
}

async function deleteReceipt(receipt: StoredReceipt): Promise<boolean> {
  await supabase.storage.from(BUCKET).remove([receipt.file_path]);
  const { error } = await supabase.from('monzo_receipts').delete().eq('id', receipt.id);
  return !error;
}

// ── Sub-components ────────────────────────────────────────────────────────────

function ConnectScreen() {
  return (
    <div className="h-full flex items-center justify-center p-8">
      <div className="text-center max-w-xs space-y-4">
        <div className="w-16 h-16 rounded-2xl bg-orange-50 flex items-center justify-center mx-auto">
          <PlugZap size={28} className="text-orange-500" />
        </div>
        <h2 className="text-lg font-bold text-gray-900">Connect Monzo</h2>
        <p className="text-sm text-gray-500">Link your Proline Roofing &amp; Solar Monzo account to view your balance, transactions, and reconcile worker payments.</p>
        <button
          onClick={startOAuthFlow}
          className="w-full bg-orange-600 text-white font-semibold py-3 rounded-xl hover:bg-orange-700 transition-colors flex items-center justify-center gap-2"
        >
          <Plug size={16} /> Connect to Monzo
        </button>
      </div>
    </div>
  );
}

function ReceiptModal({
  transaction,
  receipts,
  onClose,
  onAdded,
  onDeleted,
}: {
  transaction: MonzoTransaction;
  receipts: StoredReceipt[];
  onClose: () => void;
  onAdded: (r: StoredReceipt) => void;
  onDeleted: (id: string) => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const cameraRef = useRef<HTMLInputElement>(null);
  const [notes, setNotes] = useState('');
  const [uploading, setUploading] = useState(false);
  const [preview, setPreview] = useState<string | null>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [viewUrl, setViewUrl] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);

  const name = transaction.merchant?.name ?? transaction.description;
  const isIn = transaction.amount > 0;

  const handleFile = (file: File) => {
    setSelectedFile(file);
    const reader = new FileReader();
    reader.onload = e => setPreview(e.target?.result as string);
    reader.readAsDataURL(file);
  };

  const upload = async () => {
    if (!selectedFile) return;
    setUploading(true);
    const saved = await saveReceipt(transaction.id, selectedFile, notes);
    setUploading(false);
    if (saved) {
      onAdded(saved);
      setSelectedFile(null);
      setPreview(null);
      setNotes('');
    }
  };

  const handleDelete = async (receipt: StoredReceipt) => {
    setDeleting(receipt.id);
    const ok = await deleteReceipt(receipt);
    setDeleting(null);
    if (ok) onDeleted(receipt.id);
  };

  return (
    <>
      <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4" style={{ background: 'rgba(0,0,0,0.5)' }}>
        <div className="bg-white rounded-t-2xl sm:rounded-2xl shadow-2xl w-full sm:max-w-md max-h-[90vh] flex flex-col">
          {/* Header */}
          <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100 shrink-0">
            <div className="min-w-0">
              <h2 className="text-base font-semibold text-gray-900 truncate">{name}</h2>
              <p className={`text-sm font-medium ${isIn ? 'text-emerald-600' : 'text-gray-500'}`}>
                {isIn ? '+' : '−'}£{pence(transaction.amount)}
              </p>
            </div>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 ml-3 shrink-0"><X size={18} /></button>
          </div>

          <div className="overflow-y-auto flex-1 p-5 space-y-4">
            {/* Existing receipts */}
            {receipts.length > 0 && (
              <div className="space-y-2">
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Saved receipts</p>
                {receipts.map(r => (
                  <div key={r.id} className="flex items-center gap-3 bg-gray-50 rounded-xl p-3">
                    {r.url && (
                      <img
                        src={r.url}
                        alt="receipt"
                        className="w-12 h-12 object-cover rounded-lg cursor-pointer border border-gray-200"
                        onClick={() => setViewUrl(r.url!)}
                      />
                    )}
                    <div className="flex-1 min-w-0">
                      {r.notes && <p className="text-sm text-gray-700 truncate">{r.notes}</p>}
                      <p className="text-xs text-gray-400">{new Date(r.created_at).toLocaleDateString('en-GB')}</p>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      {r.url && (
                        <button onClick={() => setViewUrl(r.url!)} className="p-1.5 rounded-lg text-gray-400 hover:bg-gray-200 hover:text-gray-600 transition-colors">
                          <Eye size={14} />
                        </button>
                      )}
                      <button
                        onClick={() => handleDelete(r)}
                        disabled={deleting === r.id}
                        className="p-1.5 rounded-lg text-gray-400 hover:bg-red-50 hover:text-red-500 transition-colors disabled:opacity-40"
                      >
                        {deleting === r.id ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {/* Upload new */}
            <div className="space-y-3">
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Add receipt</p>

              {/* Preview */}
              {preview ? (
                <div className="relative">
                  <img src={preview} alt="preview" className="w-full max-h-48 object-contain rounded-xl border border-gray-200 bg-gray-50" />
                  <button
                    onClick={() => { setPreview(null); setSelectedFile(null); }}
                    className="absolute top-2 right-2 bg-white rounded-full p-1 shadow text-gray-500 hover:text-red-500"
                  >
                    <X size={14} />
                  </button>
                </div>
              ) : (
                <div className="grid grid-cols-2 gap-3">
                  {/* Camera (mobile) */}
                  <button
                    onClick={() => cameraRef.current?.click()}
                    className="flex flex-col items-center gap-2 py-4 rounded-xl border-2 border-dashed border-gray-200 text-gray-400 hover:border-orange-400 hover:text-orange-500 transition-colors"
                  >
                    <Camera size={22} />
                    <span className="text-xs font-medium">Take photo</span>
                  </button>
                  {/* File pick */}
                  <button
                    onClick={() => fileRef.current?.click()}
                    className="flex flex-col items-center gap-2 py-4 rounded-xl border-2 border-dashed border-gray-200 text-gray-400 hover:border-orange-400 hover:text-orange-500 transition-colors"
                  >
                    <Upload size={22} />
                    <span className="text-xs font-medium">Upload file</span>
                  </button>
                </div>
              )}

              <input ref={fileRef} type="file" accept="image/*,application/pdf" className="hidden" onChange={e => e.target.files?.[0] && handleFile(e.target.files[0])} />
              <input ref={cameraRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={e => e.target.files?.[0] && handleFile(e.target.files[0])} />

              {/* Notes */}
              <input
                type="text"
                value={notes}
                onChange={e => setNotes(e.target.value)}
                placeholder="Notes (optional)"
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500"
              />
            </div>
          </div>

          {/* Footer */}
          <div className="px-5 py-4 border-t border-gray-100 shrink-0">
            {selectedFile ? (
              <button
                onClick={upload}
                disabled={uploading}
                className="w-full flex items-center justify-center gap-2 bg-orange-600 text-white text-sm font-medium py-2.5 rounded-xl hover:bg-orange-700 transition-colors disabled:opacity-60"
              >
                {uploading ? <><Loader2 size={15} className="animate-spin" /> Uploading…</> : <><Check size={15} /> Save Receipt</>}
              </button>
            ) : (
              <button onClick={onClose} className="w-full border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50">
                Done
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Full-screen image viewer */}
      {viewUrl && (
        <div className="fixed inset-0 z-[60] flex items-center justify-center p-4" style={{ background: 'rgba(0,0,0,0.9)' }} onClick={() => setViewUrl(null)}>
          <button className="absolute top-4 right-4 text-white/70 hover:text-white"><X size={24} /></button>
          <img src={viewUrl} alt="receipt" className="max-w-full max-h-full object-contain rounded-lg" onClick={e => e.stopPropagation()} />
        </div>
      )}
    </>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

// ── Reconcile tab ─────────────────────────────────────────────────────────────

function normaliseSort(s?: string) {
  return (s ?? '').replace(/[^0-9]/g, '');
}

function daysApart(a: string, b: string) {
  return Math.abs((new Date(a).getTime() - new Date(b).getTime()) / 86400000);
}

type MatchStrength = 'exact' | 'fuzzy' | null;

function matchStrength(
  txn: MonzoTransaction,
  payment: { amount: number; date: string; userId: string },
  worker: { bankAccountNumber?: string; bankSortCode?: string } | undefined,
): MatchStrength {
  const txnPounds = Math.abs(txn.amount) / 100;
  const amountMatch = Math.abs(txnPounds - payment.amount) < 0.01;
  const dateMatch = daysApart(txn.created, payment.date) <= 3;

  if (worker?.bankAccountNumber && txn.counterparty?.account_number) {
    const accMatch = txn.counterparty.account_number === worker.bankAccountNumber;
    const sortMatch = normaliseSort(txn.counterparty.sort_code) === normaliseSort(worker.bankSortCode);
    if (accMatch && sortMatch && amountMatch) return 'exact';
  }
  if (amountMatch && dateMatch) return 'fuzzy';
  return null;
}

interface ReconcileRowProps {
  txn: MonzoTransaction;
  linkedPayment: { id: string; amount: number; date: string; userId: string; workerName: string } | null;
  suggestions: { id: string; amount: number; date: string; userId: string; workerName: string; strength: MatchStrength }[];
  onLink: (paymentId: string) => void;
  onUnlink: () => void;
}

function ReconcileRow({ txn, linkedPayment, suggestions, onLink, onUnlink }: ReconcileRowProps) {
  const [open, setOpen] = useState(false);
  const name = txn.counterparty?.name ?? txn.merchant?.name ?? txn.description;

  return (
    <div className="bg-white rounded-xl shadow-sm overflow-hidden">
      <div className="flex items-center gap-3 px-4 py-3">
        {/* Status icon */}
        <div className="shrink-0">
          {linkedPayment
            ? <CheckCircle2 size={18} className="text-emerald-500" />
            : <CircleDashed size={18} className="text-gray-300" />
          }
        </div>

        {/* Details */}
        <div className="flex-1 min-w-0">
          <div className="text-sm font-medium text-gray-900 truncate">{name}</div>
          <div className="text-xs text-gray-400">
            {new Date(txn.created).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}
            {txn.counterparty?.account_number && (
              <span className="ml-2 font-mono">{txn.counterparty.account_number}</span>
            )}
          </div>
        </div>

        {/* Amount */}
        <div className="text-sm font-semibold text-gray-900 shrink-0">
          −£{(Math.abs(txn.amount) / 100).toFixed(2)}
        </div>

        {/* Expand */}
        <button
          onClick={() => setOpen(s => !s)}
          className="p-1.5 rounded-lg text-gray-400 hover:bg-gray-100 transition-colors shrink-0"
        >
          <ChevronDown size={14} className={`transition-transform ${open ? 'rotate-180' : ''}`} />
        </button>
      </div>

      {/* Linked payment */}
      {linkedPayment && (
        <div className="mx-4 mb-3 flex items-center gap-2 bg-emerald-50 rounded-xl px-3 py-2">
          <CheckCircle2 size={13} className="text-emerald-500 shrink-0" />
          <div className="flex-1 min-w-0 text-xs text-emerald-700">
            Matched to <span className="font-semibold">{linkedPayment.workerName}</span> — £{linkedPayment.amount.toFixed(2)} on {new Date(linkedPayment.date).toLocaleDateString('en-GB')}
          </div>
          <button
            onClick={onUnlink}
            className="shrink-0 text-xs text-emerald-600 hover:text-red-500 transition-colors flex items-center gap-1"
          >
            <Link2Off size={12} /> Unlink
          </button>
        </div>
      )}

      {/* Suggestions panel */}
      {open && (
        <div className="border-t border-gray-50 px-4 pb-3 pt-2 space-y-2">
          {suggestions.length === 0 && !linkedPayment && (
            <p className="text-xs text-gray-400 text-center py-2">No matching payments found in CRM</p>
          )}
          {suggestions.map(s => (
            <div key={s.id} className="flex items-center gap-2 py-1.5">
              <div className="flex-1 min-w-0">
                <span className="text-sm text-gray-800 font-medium">{s.workerName}</span>
                <span className="text-xs text-gray-400 ml-2">£{s.amount.toFixed(2)} · {new Date(s.date).toLocaleDateString('en-GB')}</span>
                <span className={`ml-2 text-[10px] font-semibold px-1.5 py-0.5 rounded-full ${s.strength === 'exact' ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}`}>
                  {s.strength === 'exact' ? 'Exact match' : 'Possible match'}
                </span>
              </div>
              {linkedPayment?.id === s.id ? (
                <span className="text-xs text-emerald-600 font-medium">Linked</span>
              ) : (
                <button
                  onClick={() => onLink(s.id)}
                  className="text-xs bg-orange-600 text-white px-2.5 py-1 rounded-lg hover:bg-orange-700 transition-colors flex items-center gap-1"
                >
                  <Link2 size={11} /> Link
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function ReconcileTab({ transactions }: { transactions: MonzoTransaction[] }) {
  const { workerPayments, users, linkMonzoTransaction } = useStore();

  // Only outgoing bank transfers (negative, category = transfers or no merchant)
  const outgoing = transactions.filter(t => t.amount < 0 && (t.category === 'transfers' || !t.merchant));

  // Build lookup: monzoTransactionId → paymentId
  const linkedMap = new Map(
    workerPayments.filter(p => p.monzoTransactionId).map(p => [p.monzoTransactionId!, p])
  );

  const summary = { total: outgoing.length, matched: 0 };
  outgoing.forEach(t => { if (linkedMap.has(t.id)) summary.matched++; });

  return (
    <div className="space-y-4">
      {/* Summary bar */}
      <div className="grid grid-cols-3 gap-3">
        <div className="bg-white rounded-xl p-3 shadow-sm text-center">
          <div className="text-xl font-bold text-gray-900">{summary.total}</div>
          <div className="text-xs text-gray-400 mt-0.5">Transfers out</div>
        </div>
        <div className="bg-white rounded-xl p-3 shadow-sm text-center">
          <div className="text-xl font-bold text-emerald-600">{summary.matched}</div>
          <div className="text-xs text-gray-400 mt-0.5">Matched</div>
        </div>
        <div className="bg-white rounded-xl p-3 shadow-sm text-center">
          <div className="text-xl font-bold text-amber-500">{summary.total - summary.matched}</div>
          <div className="text-xs text-gray-400 mt-0.5">Unmatched</div>
        </div>
      </div>

      {outgoing.length === 0 && (
        <div className="text-center py-12 text-gray-400 text-sm">No outgoing transfers found</div>
      )}

      {outgoing.map(txn => {
        const linked = linkedMap.get(txn.id);
        const linkedSummary = linked
          ? { id: linked.id, amount: linked.amount, date: linked.date, userId: linked.userId, workerName: users.find(u => u.id === linked.userId)?.name ?? 'Unknown' }
          : null;

        // Find suggestions from unlinked worker payments
        const suggestions = workerPayments
          .filter(p => !p.monzoTransactionId || p.monzoTransactionId === txn.id)
          .map(p => {
            const worker = users.find(u => u.id === p.userId);
            const strength = matchStrength(txn, p, worker);
            return { id: p.id, amount: p.amount, date: p.date, userId: p.userId, workerName: worker?.name ?? 'Unknown', strength };
          })
          .filter(s => s.strength !== null)
          .sort((a, b) => (a.strength === 'exact' ? -1 : 1) - (b.strength === 'exact' ? -1 : 1));

        // Auto-expand if there are exact matches and no link yet
        return (
          <ReconcileRow
            key={txn.id}
            txn={txn}
            linkedPayment={linkedSummary}
            suggestions={suggestions}
            onLink={paymentId => linkMonzoTransaction(paymentId, txn.id)}
            onUnlink={() => linked && linkMonzoTransaction(linked.id, null)}
          />
        );
      })}
    </div>
  );
}

export default function BankingPage() {
  const [connected, setConnected] = useState(isConnected);
  const [balance, setBalance] = useState<MonzoBalance | null>(null);
  const [transactions, setTransactions] = useState<MonzoTransaction[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastFetched, setLastFetched] = useState<Date | null>(null);
  const [activeTab, setActiveTab] = useState<'transactions' | 'reconcile'>('transactions');
  const [receiptsOnly, setReceiptsOnly] = useState(false);

  // receipts keyed by transaction_id
  const [receipts, setReceipts] = useState<Record<string, StoredReceipt[]>>({});
  const [activeTransaction, setActiveTransaction] = useState<MonzoTransaction | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const tok = await getValidToken();
      if (!tok) { setConnected(false); setLoading(false); return; }
      const headers = { Authorization: `Bearer ${tok}` };

      // Fetch in two passes: this month + last month, merge and deduplicate
      const now = new Date();
      const thisMonthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
      const lastMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString();

      const [balRes, txnRes1, txnRes2] = await Promise.all([
        fetch(`https://api.monzo.com/balance?account_id=${MONZO_ACCOUNT_ID}`, { headers }),
        fetch(`https://api.monzo.com/transactions?account_id=${MONZO_ACCOUNT_ID}&expand[]=merchant&since=${thisMonthStart}&limit=100`, { headers }),
        fetch(`https://api.monzo.com/transactions?account_id=${MONZO_ACCOUNT_ID}&expand[]=merchant&since=${lastMonthStart}&limit=100`, { headers }),
      ]);

      if (balRes.status === 401 || txnRes1.status === 401) {
        setConnected(false);
        setError('Session expired — please reconnect your Monzo account.');
        setLoading(false);
        return;
      }
      if (!balRes.ok) {
        const errBody = await balRes.json().catch(() => ({}));
        setError(errBody.message ?? 'Failed to load Monzo data.');
        setLoading(false);
        return;
      }

      const balData = await balRes.json();
      const [txnData1, txnData2] = await Promise.all([txnRes1.json(), txnRes2.json()]);
      setBalance(balData);

      // Merge both months, deduplicate by id, sort newest first
      const allTxns = [...(txnData1.transactions ?? []), ...(txnData2.transactions ?? [])] as MonzoTransaction[];
      const seen = new Set<string>();
      const sorted = allTxns
        .filter(t => { if (t.decline_reason || seen.has(t.id)) return false; seen.add(t.id); return true; })
        .sort((a, b) => new Date(b.created).getTime() - new Date(a.created).getTime());
      setTransactions(sorted);
      setLastFetched(new Date());

      const ids = sorted.map(t => t.id);
      const stored = await fetchReceipts(ids);
      const grouped: Record<string, StoredReceipt[]> = {};
      for (const r of stored) {
        if (!grouped[r.transaction_id]) grouped[r.transaction_id] = [];
        grouped[r.transaction_id].push(r);
      }
      setReceipts(grouped);
    } catch {
      setError('Network error — check your connection.');
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    if (connected) fetchData();
  }, [connected, fetchData]);

  const handleDisconnect = () => { disconnect(); setConnected(false); setBalance(null); setTransactions([]); };

  const handleReceiptAdded = (txnId: string, receipt: StoredReceipt) => {
    setReceipts(prev => ({ ...prev, [txnId]: [...(prev[txnId] ?? []), receipt] }));
  };

  const handleReceiptDeleted = (txnId: string, receiptId: string) => {
    setReceipts(prev => ({ ...prev, [txnId]: (prev[txnId] ?? []).filter(r => r.id !== receiptId) }));
  };

  const receiptCount = Object.keys(receipts).length;
  const visibleTransactions = receiptsOnly ? transactions.filter(t => receipts[t.id]?.length > 0) : transactions;
  const groups = groupByDate(visibleTransactions);
  const totalIn = transactions.filter(t => t.amount > 0).reduce((s, t) => s + t.amount, 0);
  const totalOut = transactions.filter(t => t.amount < 0).reduce((s, t) => s + t.amount, 0);

  if (!connected) return <ConnectScreen />;

  return (
    <div className="h-full overflow-y-auto bg-gray-50">
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">

        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold text-gray-900">Banking</h1>
            <p className="text-sm text-gray-400">
              Proline Roofing &amp; Solar Ltd
              {getTokenExpiry() && (
                <span className="ml-2 text-xs text-gray-300">· expires {getTokenExpiry()!.toLocaleDateString('en-GB')}</span>
              )}
            </p>
          </div>
          <div className="flex items-center gap-2">
            {lastFetched && (
              <span className="text-xs text-gray-400 hidden sm:block">
                Updated {lastFetched.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })}
              </span>
            )}
            <button onClick={fetchData} disabled={loading} className="p-2 rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors disabled:opacity-40" title="Refresh">
              <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
            </button>
            <button onClick={handleDisconnect} className="p-2 rounded-lg text-gray-400 hover:bg-red-50 hover:text-red-500 transition-colors" title="Disconnect Monzo">
              <Plug size={16} />
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

        {loading && !balance && (
          <div className="rounded-2xl bg-gray-200 animate-pulse h-40" />
        )}

        {/* Tabs — always visible when connected */}
        <div className="space-y-2">
          <div className="flex gap-1 bg-gray-100 rounded-xl p-1">
            {(['transactions', 'reconcile'] as const).map(tab => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`flex-1 text-sm font-medium py-1.5 rounded-lg transition-colors ${activeTab === tab ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}
              >
                {tab === 'reconcile' ? 'Reconcile Payments' : 'Transactions'}
              </button>
            ))}
          </div>
          {activeTab === 'transactions' && transactions.length > 0 && (
            <button
              onClick={() => setReceiptsOnly(s => !s)}
              className={`flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border transition-colors ${
                receiptsOnly
                  ? 'bg-orange-50 border-orange-200 text-orange-600'
                  : 'bg-white border-gray-200 text-gray-500 hover:border-orange-200 hover:text-orange-500'
              }`}
            >
              <Receipt size={12} />
              {receiptsOnly ? `Showing ${receiptCount} with receipts` : `Show receipts only${receiptCount > 0 ? ` (${receiptCount})` : ''}`}
            </button>
          )}
        </div>

        {/* Transactions tab */}
        {activeTab === 'transactions' && transactions.length > 0 && (
          <div className="space-y-4">
            {Object.entries(groups).map(([date, txns]) => (
              <div key={date}>
                <div className="text-xs font-semibold text-gray-400 mb-2 px-1">{date}</div>
                <div className="bg-white rounded-xl overflow-hidden shadow-sm divide-y divide-gray-50">
                  {txns.map(t => {
                    const name = t.merchant?.name ?? t.description;
                    const logo = t.merchant?.logo;
                    const isIn = t.amount > 0;
                    const cat = t.merchant?.category ?? t.category ?? 'general';
                    const txnReceipts = receipts[t.id] ?? [];
                    const hasReceipt = txnReceipts.length > 0;

                    return (
                      <div key={t.id} className="flex items-center gap-3 px-4 py-3">
                        {/* Merchant logo / icon */}
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
                          <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                            <span className={`text-[10px] font-medium px-1.5 py-0.5 rounded-full ${categoryColour(cat)}`}>
                              {cat.replace(/_/g, ' ')}
                            </span>
                            {hasReceipt && (
                              <span className="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-orange-50 text-orange-600 flex items-center gap-1">
                                <Receipt size={9} />
                                {txnReceipts.length} receipt{txnReceipts.length > 1 ? 's' : ''}
                              </span>
                            )}
                          </div>
                        </div>

                        {/* Amount */}
                        <div className={`text-sm font-semibold shrink-0 ${isIn ? 'text-emerald-600' : 'text-gray-900'}`}>
                          {isIn ? '+' : '−'}£{pence(t.amount)}
                        </div>

                        {/* Receipt button */}
                        <button
                          onClick={() => setActiveTransaction(t)}
                          className={`shrink-0 p-1.5 rounded-lg transition-colors ${
                            hasReceipt
                              ? 'text-orange-500 bg-orange-50 hover:bg-orange-100'
                              : 'text-gray-300 hover:text-orange-500 hover:bg-orange-50'
                          }`}
                          title="Add/view receipts"
                        >
                          <Receipt size={15} />
                        </button>
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Reconcile tab */}
        {activeTab === 'reconcile' && transactions.length > 0 && (
          <ReconcileTab transactions={transactions} />
        )}

        {!loading && activeTab === 'transactions' && transactions.length === 0 && (
          <div className="text-center py-12 text-gray-400 text-sm">
            {error ? '' : 'No transactions found'}
          </div>
        )}
        {!loading && activeTab === 'transactions' && transactions.length > 0 && visibleTransactions.length === 0 && (
          <div className="text-center py-12 text-gray-400 text-sm">No transactions with receipts yet</div>
        )}
      </div>

      {activeTransaction && (
        <ReceiptModal
          transaction={activeTransaction}
          receipts={receipts[activeTransaction.id] ?? []}
          onClose={() => setActiveTransaction(null)}
          onAdded={r => handleReceiptAdded(activeTransaction.id, r)}
          onDeleted={id => handleReceiptDeleted(activeTransaction.id, id)}
        />
      )}
    </div>
  );
}
