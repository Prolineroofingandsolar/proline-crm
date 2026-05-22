import { useState } from 'react';
import { Printer, ChevronDown, ChevronUp, FileText } from 'lucide-react';
import { useStore } from '../store/useStore';
import { formatCurrency } from '../utils/helpers';
import type { AppUser, TimesheetEntry } from '../types';

const MONTHS = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December',
];

function formatDateStr(s: string) {
  const [y, m, d] = s.split('-');
  return `${d}/${m}/${y}`;
}

type WorkerRow = {
  user: AppUser;
  entries: TimesheetEntry[];
  gross: number;
  cisRate: 20 | 30;
  deduction: number;
  net: number;
};

function buildStatementHtml(row: WorkerRow, leads: { id: string; address: string }[], month: number, year: number) {
  const { user, entries, cisRate, gross, deduction, net } = row;
  const entryRows = entries.map(e => {
    const lead = leads.find(l => l.id === e.leadId);
    const ded = Math.round(e.amount * cisRate) / 100;
    const n = e.amount - ded;
    return `<tr>
      <td>${formatDateStr(e.date)}</td>
      <td>${lead?.address ?? '—'}</td>
      <td>${e.type === 'full' ? 'Full Day' : 'Half Day'}</td>
      <td style="text-align:right">£${e.amount.toFixed(2)}</td>
      <td style="text-align:right;color:#dc2626">-£${ded.toFixed(2)}</td>
      <td style="text-align:right;color:#16a34a;font-weight:bold">£${n.toFixed(2)}</td>
    </tr>`;
  }).join('');

  return `<!DOCTYPE html><html><head>
<title>CIS Statement – ${user.name} – ${MONTHS[month]} ${year}</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Arial,sans-serif;padding:40px;font-size:13px;color:#1f2937}
.hdr{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:28px}
.title{font-size:22px;font-weight:bold}.subtitle{color:#6b7280;font-size:14px;margin-top:4px}
.meta{text-align:right;font-size:11px;color:#9ca3af}
.info{display:grid;grid-template-columns:1fr 1fr;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:16px;margin-bottom:24px;gap:0}
.info-item{padding:6px 12px}.info-item label{display:block;font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:#9ca3af;margin-bottom:3px}
.info-item span{font-weight:700;font-size:14px}
table{width:100%;border-collapse:collapse;margin-bottom:20px}
thead tr{background:#1f2937;color:white}
th{padding:10px 12px;text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.05em}
td{padding:10px 12px;border-bottom:1px solid #f3f4f6}
.tot{background:#1f2937;color:white;font-weight:bold}
.tot td{color:white;border:none}
.footer{margin-top:24px;font-size:11px;color:#9ca3af;border-top:1px solid #e5e7eb;padding-top:12px;line-height:1.7}
</style></head><body>
<div class="hdr">
  <div><div class="title">CIS Payment Statement</div><div class="subtitle">${MONTHS[month]} ${year}</div></div>
  <div class="meta"><div style="font-weight:bold;font-size:13px;color:#1f2937">ProLine Roofing &amp; Solar</div><div>Issued: ${new Date().toLocaleDateString('en-GB')}</div></div>
</div>
<div class="info">
  <div class="info-item"><label>Subcontractor</label><span>${user.name}</span></div>
  <div class="info-item"><label>UTR Number</label><span>${user.utrNumber ?? 'Not provided'}</span></div>
  <div class="info-item"><label>CIS Deduction Rate</label><span>${cisRate}%</span></div>
  <div class="info-item"><label>Day Rate</label><span>£${user.dayRate?.toFixed(2) ?? '0.00'}</span></div>
</div>
<table>
  <thead><tr>
    <th>Date</th><th>Job Site</th><th>Type</th>
    <th style="text-align:right">Gross</th>
    <th style="text-align:right">CIS (${cisRate}%)</th>
    <th style="text-align:right">Net Pay</th>
  </tr></thead>
  <tbody>
    ${entryRows}
    <tr class="tot">
      <td colspan="3">TOTAL</td>
      <td style="text-align:right">£${gross.toFixed(2)}</td>
      <td style="text-align:right">-£${deduction.toFixed(2)}</td>
      <td style="text-align:right">£${net.toFixed(2)}</td>
    </tr>
  </tbody>
</table>
<div class="footer">
  This statement is issued under the Construction Industry Scheme (CIS) as required by HMRC. The CIS deduction of £${deduction.toFixed(2)} has been withheld from your gross payment and will be paid to HMRC on your behalf. Offset this against your Income Tax and National Insurance when completing your Self Assessment, or contact HMRC to claim a refund.
</div>
<script>window.onload=()=>window.print()</script>
</body></html>`;
}

function buildReturnHtml(rows: WorkerRow[], totalGross: number, totalDeduction: number, totalNet: number, month: number, year: number) {
  const rowsHtml = rows.map(r => `<tr>
    <td>${r.user.name}</td>
    <td style="font-family:monospace">${r.user.utrNumber ?? '—'}</td>
    <td style="text-align:center">${r.entries.length}</td>
    <td style="text-align:right">£${r.gross.toFixed(2)}</td>
    <td style="text-align:center">${r.cisRate}%</td>
    <td style="text-align:right;color:#dc2626">-£${r.deduction.toFixed(2)}</td>
    <td style="text-align:right;color:#16a34a;font-weight:bold">£${r.net.toFixed(2)}</td>
  </tr>`).join('');

  return `<!DOCTYPE html><html><head>
<title>CIS Monthly Return – ${MONTHS[month]} ${year}</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Arial,sans-serif;padding:40px;font-size:13px;color:#1f2937}
.hdr{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:28px}
.title{font-size:22px;font-weight:bold}.subtitle{color:#6b7280;font-size:14px;margin-top:4px}
table{width:100%;border-collapse:collapse;margin-top:16px}
thead tr{background:#1f2937;color:white}
th{padding:10px 12px;text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.05em}
td{padding:10px 12px;border-bottom:1px solid #f3f4f6}
.tot{background:#1f2937;color:white;font-weight:bold}
.tot td{color:white;border:none}
.notice{margin-top:24px;font-size:11px;color:#9ca3af;border-top:1px solid #e5e7eb;padding-top:12px;line-height:1.7}
</style></head><body>
<div class="hdr">
  <div><div class="title">CIS Monthly Return</div><div class="subtitle">${MONTHS[month]} ${year}</div></div>
  <div style="text-align:right;font-size:11px;color:#9ca3af">
    <div style="font-weight:bold;font-size:13px;color:#1f2937">ProLine Roofing &amp; Solar</div>
    <div>Printed: ${new Date().toLocaleDateString('en-GB')}</div>
  </div>
</div>
<table>
  <thead><tr>
    <th>Subcontractor</th><th>UTR Number</th>
    <th style="text-align:center">Days</th>
    <th style="text-align:right">Gross Paid</th>
    <th style="text-align:center">Rate</th>
    <th style="text-align:right">CIS Deducted</th>
    <th style="text-align:right">Net Paid</th>
  </tr></thead>
  <tbody>
    ${rowsHtml}
    <tr class="tot">
      <td colspan="3">TOTAL — ${rows.length} subcontractor${rows.length !== 1 ? 's' : ''}</td>
      <td style="text-align:right">£${totalGross.toFixed(2)}</td>
      <td></td>
      <td style="text-align:right">-£${totalDeduction.toFixed(2)}</td>
      <td style="text-align:right">£${totalNet.toFixed(2)}</td>
    </tr>
  </tbody>
</table>
<div class="notice">
  Use these figures when submitting your CIS Monthly Return to HMRC via the Government Gateway. File by the 19th of the month following the tax month (which runs 6th to 5th). Keep this document for your records.
</div>
<script>window.onload=()=>window.print()</script>
</body></html>`;
}

function openPrint(html: string) {
  const w = window.open('', '_blank', 'width=900,height=700');
  if (w) { w.document.write(html); w.document.close(); }
}

export default function CISPage() {
  const { timesheetEntries, users, leads } = useStore();
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth());
  const [expanded, setExpanded] = useState<string | null>(null);

  const years = [now.getFullYear() - 1, now.getFullYear(), now.getFullYear() + 1];

  const monthEntries = timesheetEntries.filter(e => {
    const [y, m] = e.date.split('-').map(Number);
    return y === year && m - 1 === month;
  });

  const workerIds = [...new Set(monthEntries.map(e => e.userId))];
  const rows = workerIds.map(uid => {
    const user = users.find(u => u.id === uid);
    if (!user) return null;
    const entries = monthEntries.filter(e => e.userId === uid).sort((a, b) => a.date.localeCompare(b.date));
    const gross = entries.reduce((s, e) => s + e.amount, 0);
    const cisRate = user.cisRate ?? 20;
    const deduction = Math.round(gross * cisRate) / 100;
    const net = gross - deduction;
    return { user, entries, gross, cisRate, deduction, net };
  }).filter((r): r is WorkerRow => r !== null);

  const totalGross = rows.reduce((s, r) => s + r.gross, 0);
  const totalDeduction = rows.reduce((s, r) => s + r.deduction, 0);
  const totalNet = rows.reduce((s, r) => s + r.net, 0);

  const leadsForPrint = leads.map(l => ({ id: l.id, address: l.address }));

  return (
    <div className="p-4 sm:p-6 overflow-y-auto h-full bg-white space-y-5">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold text-gray-800">CIS Returns</h1>
          <p className="text-sm text-gray-500">Monthly subcontractor tax summary</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <select value={month} onChange={e => setMonth(Number(e.target.value))}
            className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
            {MONTHS.map((m, i) => <option key={m} value={i}>{m}</option>)}
          </select>
          <select value={year} onChange={e => setYear(Number(e.target.value))}
            className="border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400">
            {years.map(y => <option key={y} value={y}>{y}</option>)}
          </select>
          {rows.length > 0 && (
            <button
              onClick={() => openPrint(buildReturnHtml(rows, totalGross, totalDeduction, totalNet, month, year))}
              className="flex items-center gap-1.5 bg-orange-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-orange-700">
              <Printer size={14} /> Print Return
            </button>
          )}
        </div>
      </div>

      {/* Summary cards */}
      {rows.length > 0 && (
        <div className="grid grid-cols-3 gap-3">
          <div className="bg-gray-50 rounded-xl p-4">
            <p className="text-[10px] font-semibold text-gray-400 uppercase tracking-wide mb-1">Total Gross</p>
            <p className="text-xl font-bold text-gray-800">{formatCurrency(totalGross)}</p>
          </div>
          <div className="bg-red-50 rounded-xl p-4">
            <p className="text-[10px] font-semibold text-red-400 uppercase tracking-wide mb-1">CIS Deducted</p>
            <p className="text-xl font-bold text-red-600">{formatCurrency(totalDeduction)}</p>
          </div>
          <div className="bg-green-50 rounded-xl p-4">
            <p className="text-[10px] font-semibold text-green-600 uppercase tracking-wide mb-1">Net Paid Out</p>
            <p className="text-xl font-bold text-green-700">{formatCurrency(totalNet)}</p>
          </div>
        </div>
      )}

      {/* Worker rows */}
      {rows.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-gray-300">
          <FileText size={48} className="mb-3" />
          <p className="font-semibold text-gray-400">No entries for {MONTHS[month]} {year}</p>
          <p className="text-sm text-gray-400 mt-1">Timesheet entries will appear here once workers log time</p>
        </div>
      ) : (
        <div className="space-y-2">
          {rows.map(row => (
            <div key={row.user.id} className="border border-gray-100 rounded-xl overflow-hidden shadow-sm">
              {/* Row header */}
              <div className="flex items-center gap-3 px-4 py-3 bg-white">
                <div className="w-9 h-9 rounded-full bg-orange-100 flex items-center justify-center text-orange-700 font-bold text-sm shrink-0">
                  {row.user.name[0]}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-gray-800 text-sm">{row.user.name}</p>
                  <p className="text-xs text-gray-400">
                    UTR: {row.user.utrNumber ?? <span className="text-amber-500">Not set</span>}
                    {' · '}CIS {row.cisRate}%
                    {' · '}{row.entries.length} day{row.entries.length !== 1 ? 's' : ''}
                  </p>
                </div>
                <div className="hidden sm:flex items-center gap-5 text-right shrink-0">
                  <div>
                    <p className="text-[10px] text-gray-400 uppercase font-semibold">Gross</p>
                    <p className="text-sm font-bold text-gray-800">{formatCurrency(row.gross)}</p>
                  </div>
                  <div>
                    <p className="text-[10px] text-red-400 uppercase font-semibold">CIS ({row.cisRate}%)</p>
                    <p className="text-sm font-bold text-red-600">-{formatCurrency(row.deduction)}</p>
                  </div>
                  <div>
                    <p className="text-[10px] text-green-600 uppercase font-semibold">Net</p>
                    <p className="text-sm font-bold text-green-700">{formatCurrency(row.net)}</p>
                  </div>
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  <button
                    onClick={() => openPrint(buildStatementHtml(row, leadsForPrint, month, year))}
                    className="flex items-center gap-1 text-xs bg-gray-100 hover:bg-gray-200 text-gray-600 px-2.5 py-1.5 rounded-lg font-medium">
                    <Printer size={12} /> Statement
                  </button>
                  <button
                    onClick={() => setExpanded(expanded === row.user.id ? null : row.user.id)}
                    className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-400">
                    {expanded === row.user.id ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
                  </button>
                </div>
              </div>

              {/* Mobile value strip */}
              {expanded !== row.user.id && (
                <div className="flex sm:hidden items-center gap-4 px-4 pb-3 text-sm">
                  <span className="text-gray-700 font-semibold">{formatCurrency(row.gross)}</span>
                  <span className="text-red-500">-{formatCurrency(row.deduction)}</span>
                  <span className="text-green-700 font-bold">{formatCurrency(row.net)}</span>
                </div>
              )}

              {/* Expanded entries table */}
              {expanded === row.user.id && (
                <div className="border-t border-gray-100">
                  <table className="w-full text-sm">
                    <thead className="bg-gray-50">
                      <tr>
                        <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
                        <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide hidden sm:table-cell">Job Site</th>
                        <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
                        <th className="text-right px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gross</th>
                        <th className="text-right px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide hidden sm:table-cell">CIS</th>
                        <th className="text-right px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Net</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-50">
                      {row.entries.map(entry => {
                        const lead = leads.find(l => l.id === entry.leadId);
                        const ded = Math.round(entry.amount * row.cisRate) / 100;
                        const net = entry.amount - ded;
                        return (
                          <tr key={entry.id} className="hover:bg-gray-50">
                            <td className="px-4 py-2.5 text-gray-700 whitespace-nowrap">{formatDateStr(entry.date)}</td>
                            <td className="px-4 py-2.5 text-gray-500 text-xs hidden sm:table-cell truncate max-w-[200px]">{lead?.address ?? '—'}</td>
                            <td className="px-4 py-2.5">
                              <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${entry.type === 'full' ? 'bg-orange-100 text-orange-700' : 'bg-gray-100 text-gray-600'}`}>
                                {entry.type === 'full' ? 'Full' : 'Half'}
                              </span>
                            </td>
                            <td className="px-4 py-2.5 text-right font-medium text-gray-800">{formatCurrency(entry.amount)}</td>
                            <td className="px-4 py-2.5 text-right text-red-500 hidden sm:table-cell">-{formatCurrency(ded)}</td>
                            <td className="px-4 py-2.5 text-right font-semibold text-green-700">{formatCurrency(net)}</td>
                          </tr>
                        );
                      })}
                      <tr className="bg-gray-50 font-semibold">
                        <td className="px-4 py-2.5 text-gray-700" colSpan={2}>Total</td>
                        <td className="px-4 py-2.5 hidden sm:table-cell" />
                        <td className="px-4 py-2.5 text-right text-gray-800">{formatCurrency(row.gross)}</td>
                        <td className="px-4 py-2.5 text-right text-red-500 hidden sm:table-cell">-{formatCurrency(row.deduction)}</td>
                        <td className="px-4 py-2.5 text-right text-green-700">{formatCurrency(row.net)}</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
