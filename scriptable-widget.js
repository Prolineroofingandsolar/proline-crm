// ProLine CRM — Lock Screen Task Widget for Scriptable
//
// SETUP
// 1. Install the free "Scriptable" app from the App Store
// 2. Create a new script, paste this entire file in, then tap Done
// 3. Edit the CONFIG block below with your details
// 4. Long-press your iPhone lock screen → Customise → Add Widget → Scriptable
//    Choose this script and the "Rectangular" widget size
//
// HOW TO FIND YOUR USER ID
// Open the ProLine CRM app → Settings → Accounts → tap your name
// The user ID is shown at the bottom of your profile (or ask the admin)

const CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT_REF.supabase.co',
  supabaseKey: 'YOUR_SUPABASE_ANON_KEY',
  userId:      'YOUR_USER_ID',   // your ProLine CRM user ID
  isAdmin:     true,             // set false if you are not an admin
  maxItems:    4,                // max tasks to show in widget
};

// ─── Fetch helpers ──────────────────────────────────────────────────────────

const HEADERS = {
  apikey:        CONFIG.supabaseKey,
  Authorization: `Bearer ${CONFIG.supabaseKey}`,
  'Content-Type': 'application/json',
};

async function get(path) {
  const req = new Request(CONFIG.supabaseUrl + path);
  req.headers = HEADERS;
  return req.loadJSON();
}

async function post(path, body) {
  const req = new Request(CONFIG.supabaseUrl + path);
  req.headers = HEADERS;
  req.method = 'POST';
  req.body = JSON.stringify(body);
  return req.loadJSON();
}

// ─── Data fetching ──────────────────────────────────────────────────────────

async function fetchMyGeneralTasks() {
  const rows = await get(
    '/rest/v1/general_tasks?completed=eq.false&select=title,assigned_to,priority,due_date&order=created_at.desc'
  );
  if (!Array.isArray(rows)) return [];
  return rows.filter(t => {
    const a = t.assigned_to;
    return !a || a.length === 0 || a.includes(CONFIG.userId);
  });
}

async function fetchJobTasks() {
  if (!CONFIG.isAdmin) return [];
  try {
    const rows = await post('/rest/v1/rpc/get_incomplete_job_tasks', {});
    return Array.isArray(rows) ? rows : [];
  } catch {
    return [];
  }
}

// ─── Widget building ─────────────────────────────────────────────────────────

function priorityIcon(p) {
  if (p === 'high')   return '🔴';
  if (p === 'medium') return '🟡';
  return '⚪';
}

function isOverdue(dueDate) {
  if (!dueDate) return false;
  return new Date(dueDate) < new Date();
}

async function buildWidget() {
  const [general, jobTasks] = await Promise.all([
    fetchMyGeneralTasks(),
    fetchJobTasks(),
  ]);

  // Sort general tasks: overdue first, then by priority
  const priorityOrder = { high: 0, medium: 1, low: 2 };
  general.sort((a, b) => {
    if (isOverdue(a.due_date) !== isOverdue(b.due_date))
      return isOverdue(a.due_date) ? -1 : 1;
    return (priorityOrder[a.priority] ?? 2) - (priorityOrder[b.priority] ?? 2);
  });

  const totalCount = general.length + jobTasks.length;

  const widget = new ListWidget();
  widget.setPadding(6, 8, 6, 8);

  // Header
  const header = widget.addStack();
  header.layoutHorizontally();
  header.centerAlignContent();

  const title = header.addText('ProLine Tasks');
  title.font = Font.boldSystemFont(11);
  title.textColor = Color.dynamic(Color.black(), Color.white());

  header.addSpacer();

  const countLabel = header.addText(`${totalCount} pending`);
  countLabel.font = Font.systemFont(10);
  countLabel.textColor = Color.dynamic(
    new Color('#ea580c'),
    new Color('#fb923c')
  );

  widget.addSpacer(4);

  if (totalCount === 0) {
    const empty = widget.addText('✅ All caught up!');
    empty.font = Font.systemFont(11);
    empty.textOpacity = 0.7;
  } else {
    // Show general tasks first, then job tasks
    const items = [
      ...general.map(t => ({
        text: `${priorityIcon(t.priority)} ${t.title}`,
        overdue: isOverdue(t.due_date),
        isJob: false,
      })),
      ...jobTasks.map(t => ({
        text: `🔨 ${t.lead_name}: ${t.task_title}`,
        overdue: false,
        isJob: true,
      })),
    ].slice(0, CONFIG.maxItems);

    for (const item of items) {
      const row = widget.addStack();
      row.layoutHorizontally();
      row.centerAlignContent();

      const label = row.addText(item.text);
      label.font = Font.systemFont(10);
      label.lineLimit = 1;
      label.textColor = item.overdue
        ? Color.dynamic(new Color('#dc2626'), new Color('#f87171'))
        : Color.dynamic(Color.black(), Color.white());
      label.textOpacity = item.overdue ? 1 : 0.85;

      widget.addSpacer(2);
    }

    if (totalCount > CONFIG.maxItems) {
      const more = widget.addText(`+${totalCount - CONFIG.maxItems} more`);
      more.font = Font.systemFont(9);
      more.textOpacity = 0.5;
    }
  }

  return widget;
}

// ─── Entry point ─────────────────────────────────────────────────────────────

const widget = await buildWidget();

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  // Preview when run from inside Scriptable
  widget.presentMedium();
}

Script.complete();
