// One place decides which pages only an administrator may open.
//
// Every other role (user, worker, labourer, casual) is staff and must never
// reach these. Keep this in step with apple/Shared/Views/RootView.swift — see
// AGENTS.md. This list used to be repeated in App.tsx, Sidebar.tsx and
// BottomNav.tsx, and they drifted apart: Pipeline was admin-only in two of
// them and not the third, so staff could open it.
export const ADMIN_ONLY_PAGES = new Set([
  'dashboard',
  'pipeline',
  'leads',
  'contacts',
  'files',
  'reports',
  'settings',
  'cis',
  'banking',
  'office',
]);

// Drops every admin-only page from a menu shown to staff, so no menu can
// offer a page the list above forbids, however it was written.
export function staffVisible<T extends { id: string }>(items: T[]): T[] {
  return items.filter(item => !ADMIN_ONLY_PAGES.has(item.id));
}
