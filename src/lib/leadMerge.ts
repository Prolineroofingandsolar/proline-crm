type Row = Record<string, unknown>;
const equal = (a: unknown, b: unknown): boolean => {
  if (a == null || b == null) return a == null && b == null;
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((v, i) => equal(v, b[i]));
  if (typeof a === 'object' && typeof b === 'object') {
    const left = a as Row, right = b as Row;
    return [...new Set([...Object.keys(left), ...Object.keys(right)])].every(k => equal(left[k], right[k]));
  }
  return a === b;
};
export class LeadConflict extends Error {
  constructor() { super('This field changed on another device. Your draft is retained; refresh and review before saving again.'); }
}
export function mergeLead(base: Row, draft: Row, latest: Row): Row {
  if (!base.id || base.id !== draft.id || base.id !== latest.id) throw new LeadConflict();
  const result = { ...latest };
  const changed = [...new Set([...Object.keys(base), ...Object.keys(draft)])]
    .filter(k => !['id', 'created_at', 'updated_at', 'progress'].includes(k) && !equal(base[k], draft[k]));
  const money = ['value', 'deposit', 'deposit_paid', 'balance'];
  if (changed.some(k => money.includes(k)) && money.some(k => !equal(base[k], latest[k]) && !equal(draft[k], latest[k]))) throw new LeadConflict();
  for (const key of changed) {
    if (equal(base[key], latest[key]) || equal(draft[key], latest[key])) result[key] = draft[key];
    else if (['tasks', 'notes', 'photos', 'files', 'materials'].includes(key)) {
      const index = (value: unknown): Map<string, Row> => {
        if (!Array.isArray(value)) throw new LeadConflict();
        const map = new Map<string, Row>();
        for (const item of value as Row[]) {
          if (typeof item.id !== 'string' || map.has(item.id)) throw new LeadConflict();
          map.set(item.id, item);
        }
        return map;
      };
      const before = index(base[key]), edited = index(draft[key]), server = index(latest[key]);
      for (const id of new Set([...before.keys(), ...edited.keys()])) {
        if (equal(before.get(id), edited.get(id))) continue;
        if (!equal(before.get(id), server.get(id)) && !equal(edited.get(id), server.get(id))) throw new LeadConflict();
        if (edited.has(id)) server.set(id, edited.get(id)!); else server.delete(id);
      }
      result[key] = [...server.values()];
    } else throw new LeadConflict();
  }
  const tasks = result.tasks as { completed: boolean }[] | undefined;
  if (tasks) result.progress = tasks.length ? Math.round(tasks.filter(t => t.completed).length / tasks.length * 100) : 0;
  return result;
}
