export const generateId = () => Math.random().toString(36).slice(2, 9);

export const formatCurrency = (n: number) =>
  new Intl.NumberFormat('en-GB', { style: 'currency', currency: 'GBP', maximumFractionDigits: 0 }).format(n);

export const formatDate = (d?: string) => {
  if (!d) return '';
  return new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
};

export const formatDateShort = (d?: string) => {
  if (!d) return '';
  return new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
};

export const dayLabel = (d?: string) => {
  if (!d) return '';
  const date = new Date(d);
  const now = new Date();
  const diff = Math.floor((now.getTime() - date.getTime()) / 86400000);
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Yesterday';
  if (diff === -1) return 'Tomorrow';
  return formatDateShort(d);
};

export const jobTypeColor = (jt: string): string => {
  const map: Record<string, string> = {
    'Roof Repair': 'bg-orange-100 text-orange-700',
    'Solar Installation': 'bg-yellow-100 text-yellow-700',
    'New Roof': 'bg-sky-100 text-sky-700',
    'Flat Roof': 'bg-purple-100 text-purple-700',
    'Solar + Battery': 'bg-green-100 text-green-700',
    'Guttering': 'bg-teal-100 text-teal-700',
    'Fascias & Soffits': 'bg-pink-100 text-pink-700',
    'Chimney Repair': 'bg-red-100 text-red-700',
  };
  return map[jt] ?? 'bg-gray-100 text-gray-700';
};

export const nextStage = (stage: string): string | null => {
  const order = ['New Lead', 'Survey Booked', 'Quote Sent', 'Won', 'In Progress', 'Completed', 'Paid'];
  const idx = order.indexOf(stage);
  return idx >= 0 && idx < order.length - 1 ? order[idx + 1] : null;
};
