import { useState } from 'react';
import { X, Star, Copy, Mail, CheckCircle2, Send, Loader2 } from 'lucide-react';
import type { Lead } from '../../types';
import { sendGmail } from '../../lib/gmail';

const GOOGLE_REVIEW_URL = 'https://share.google/bUnpIGWWSyEqZuERS';

interface Props {
  lead: Lead;
  onClose: () => void;
  onMarkSent: () => void;
}

export default function ReviewRequestModal({ lead, onClose, onMarkSent }: Props) {
  const [copied, setCopied] = useState(false);
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isMyBuilder = lead.source === 'MyBuilder' && lead.myBuilderUrl;
  const firstName = lead.name.split(' ')[0];

  const emailSubject = `Thank you for choosing ProLine Roofing & Solar`;

  const emailBody = [
    `Hi ${firstName},`,
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

  const handleGmailSend = async () => {
    if (!lead.email) return;
    setSending(true);
    setError(null);
    try {
      await sendGmail(lead.email, emailSubject, emailBody);
      setSent(true);
      onMarkSent();
      setTimeout(onClose, 1500);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to send — try the email app instead');
    } finally {
      setSending(false);
    }
  };

  const handleMailtoSend = () => {
    window.location.href = mailtoHref;
    onMarkSent();
    onClose();
  };

  const handleCopy = () => {
    navigator.clipboard.writeText(emailBody).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
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

          {error && (
            <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          )}

          {lead.email && (
            <div className="flex flex-col gap-2">
              {/* Primary: send directly via Gmail */}
              <button onClick={handleGmailSend} disabled={sending || sent}
                className="flex items-center justify-center gap-2 w-full bg-orange-600 hover:bg-orange-700 disabled:opacity-70 text-white font-semibold py-3 rounded-xl transition-colors">
                {sent
                  ? <><CheckCircle2 size={16} /> Sent!</>
                  : sending
                  ? <><Loader2 size={16} className="animate-spin" /> Sending…</>
                  : <><Send size={16} /> Send via Gmail</>}
              </button>

              {/* Fallback: open email app */}
              <button onClick={handleMailtoSend}
                className="flex items-center justify-center gap-2 w-full border border-gray-200 hover:bg-gray-50 text-gray-600 font-medium py-2.5 rounded-xl transition-colors text-sm">
                <Mail size={15} />
                Open in email app instead
              </button>

              <button onClick={handleCopy}
                className="flex items-center justify-center gap-2 w-full border border-gray-200 hover:bg-gray-50 text-gray-600 font-medium py-2.5 rounded-xl transition-colors text-sm">
                {copied ? <CheckCircle2 size={15} className="text-green-500" /> : <Copy size={15} />}
                {copied ? 'Copied!' : 'Copy message'}
              </button>

              <button onClick={() => { onMarkSent(); onClose(); }}
                className="text-xs text-gray-400 hover:text-gray-600 text-center py-1 transition-colors">
                Mark as sent without sending
              </button>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
