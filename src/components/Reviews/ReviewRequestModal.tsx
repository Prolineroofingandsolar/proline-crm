import { useState } from 'react';
import { X, Star, Copy, Mail, CheckCircle2 } from 'lucide-react';
import type { Lead } from '../../types';

const GOOGLE_REVIEW_URL = 'https://share.google/bUnpIGWWSyEqZuERS';

interface Props {
  lead: Lead;
  onClose: () => void;
  onMarkSent: () => void;
}

export default function ReviewRequestModal({ lead, onClose, onMarkSent }: Props) {
  const [copied, setCopied] = useState(false);

  const isMyBuilder = lead.source === 'MyBuilder' && lead.myBuilderUrl;

  const reviewLinks = [
    `Google Review: ${GOOGLE_REVIEW_URL}`,
    ...(isMyBuilder ? [`MyBuilder Review: ${lead.myBuilderUrl}`] : []),
  ].join('\n');

  const emailSubject = `Thank you for choosing ProLine Roofing & Solar`;

  const emailBody = [
    `Hi ${lead.name.split(' ')[0]},`,
    ``,
    `Thank you so much for choosing ProLine Roofing & Solar — it was a pleasure working on your project.`,
    ``,
    `If you're happy with the work, we'd really appreciate it if you could leave us a quick review. It only takes a minute and helps us enormously:`,
    ``,
    `⭐ Google Review: ${GOOGLE_REVIEW_URL}`,
    ...(isMyBuilder ? [`⭐ MyBuilder Review: ${lead.myBuilderUrl}`] : []),
    ``,
    `Thank you again for your support — we hope to work with you again in the future.`,
    ``,
    `Best regards,`,
    `ProLine Roofing & Solar`,
  ].join('\n');

  const mailtoHref = `mailto:${lead.email}?subject=${encodeURIComponent(emailSubject)}&body=${encodeURIComponent(emailBody)}`;

  const handleCopy = () => {
    navigator.clipboard.writeText(emailBody).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  const handleSend = () => {
    window.location.href = mailtoHref;
    onMarkSent();
    onClose();
  };

  return (
    <>
      <div className="fixed inset-0 z-[60] bg-black/40 backdrop-blur-sm" onClick={onClose} />
      <div className="fixed inset-x-4 top-1/2 -translate-y-1/2 z-[70] bg-white rounded-2xl shadow-2xl max-w-md mx-auto flex flex-col max-h-[85dvh]">

        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100 shrink-0">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-yellow-100 rounded-full flex items-center justify-center">
              <Star size={16} className="text-yellow-500 fill-yellow-400" />
            </div>
            <div>
              <h2 className="font-bold text-gray-800 text-base">Request a Review</h2>
              <p className="text-xs text-gray-400">{lead.name} · {lead.jobRef}</p>
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-400">
            <X size={18} />
          </button>
        </div>

        {/* Preview */}
        <div className="flex-1 overflow-y-auto p-5 space-y-4">
          <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Email preview</p>
          <div className="bg-gray-50 rounded-xl p-4 text-sm text-gray-700 whitespace-pre-wrap leading-relaxed border border-gray-100">
            {emailBody}
          </div>

          {!lead.email && (
            <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 text-sm text-amber-700">
              No email address saved for this customer — add one in the Info tab first.
            </div>
          )}

          <div className="flex flex-col gap-2">
            {lead.email ? (
              <button onClick={handleSend}
                className="flex items-center justify-center gap-2 w-full bg-orange-600 hover:bg-orange-700 text-white font-semibold py-3 rounded-xl transition-colors">
                <Mail size={16} />
                Open in Email App
              </button>
            ) : null}
            <button onClick={handleCopy}
              className="flex items-center justify-center gap-2 w-full border border-gray-200 hover:bg-gray-50 text-gray-700 font-medium py-2.5 rounded-xl transition-colors">
              {copied ? <CheckCircle2 size={16} className="text-green-500" /> : <Copy size={16} />}
              {copied ? 'Copied!' : 'Copy message'}
            </button>
            <button onClick={() => { onMarkSent(); onClose(); }}
              className="text-xs text-gray-400 hover:text-gray-600 text-center py-1 transition-colors">
              Mark as sent without opening email
            </button>
          </div>
        </div>
      </div>
    </>
  );
}
