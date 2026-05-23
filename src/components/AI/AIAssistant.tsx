import { useState, useRef, useEffect } from 'react';
import { Bot, X, Send, Loader2, Sparkles, Key, Copy, Check, ChevronDown, Trash2, Zap } from 'lucide-react';
import { useStore } from '../../store/useStore';
import type { Stage, JobType } from '../../types';
import { formatCurrency } from '../../utils/helpers';

// ── Types ────────────────────────────────────────────────────────────────────

interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  actions?: string[];
  error?: boolean;
}

interface AnthropicMessage {
  role: 'user' | 'assistant';
  content: string | ContentBlock[];
}

interface ContentBlock {
  type: 'text' | 'tool_use' | 'tool_result';
  text?: string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
  tool_use_id?: string;
  content?: string;
}

// ── CRM Tools definition ─────────────────────────────────────────────────────

const CRM_TOOLS = [
  {
    name: 'get_pipeline',
    description: 'Get all leads and jobs in the CRM pipeline with their current stage, value and contact details. Use this first when asked about leads, jobs, revenue, pipeline status or specific customers.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'find_lead',
    description: 'Find a specific lead or job by customer name or job reference.',
    input_schema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Customer name, job ref (e.g. JOB-011), or partial name' },
      },
      required: ['query'],
    },
  },
  {
    name: 'move_to_stage',
    description: 'Move a lead or job to a different pipeline stage. Use mark_as_won instead if the stage is "Won".',
    input_schema: {
      type: 'object',
      properties: {
        lead_id: { type: 'string', description: 'The lead ID (from get_pipeline)' },
        stage: {
          type: 'string',
          enum: ['New Lead', 'Survey Booked', 'Quote Sent', 'In Progress', 'Completed', 'Paid'],
        },
      },
      required: ['lead_id', 'stage'],
    },
  },
  {
    name: 'mark_as_won',
    description: 'Mark a quote as won — moves it to the Won column and sets up the job with default tasks.',
    input_schema: {
      type: 'object',
      properties: {
        lead_id: { type: 'string', description: 'The lead ID' },
      },
      required: ['lead_id'],
    },
  },
  {
    name: 'add_note',
    description: 'Add a note to a specific lead or job.',
    input_schema: {
      type: 'object',
      properties: {
        lead_id: { type: 'string' },
        note: { type: 'string', description: 'The note content' },
      },
      required: ['lead_id', 'note'],
    },
  },
  {
    name: 'create_lead',
    description: 'Create a new lead in the CRM.',
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Customer full name' },
        phone: { type: 'string' },
        email: { type: 'string' },
        address: { type: 'string' },
        job_type: {
          type: 'string',
          enum: ['Roof Repair', 'Solar Installation', 'New Roof', 'Flat Roof', 'Solar + Battery', 'Guttering', 'Fascias & Soffits', 'Chimney Repair'],
        },
        source: { type: 'string', description: 'How they found you, e.g. Referral, Google, Website' },
        stage: { type: 'string', enum: ['New Lead', 'Survey Booked', 'Quote Sent'] },
        value: { type: 'number', description: 'Quote value in GBP (optional)' },
      },
      required: ['name', 'phone', 'job_type'],
    },
  },
  {
    name: 'add_job_task',
    description: 'Add a custom task to a specific job.',
    input_schema: {
      type: 'object',
      properties: {
        lead_id: { type: 'string' },
        task: { type: 'string', description: 'Task description' },
      },
      required: ['lead_id', 'task'],
    },
  },
  {
    name: 'add_reminder',
    description: 'Add a general reminder or to-do item not tied to a job (e.g. MOT, call supplier, renew insurance).',
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        priority: { type: 'string', enum: ['low', 'medium', 'high'] },
        category: {
          type: 'string',
          enum: ['Admin', 'Finance', 'Vehicle', 'Marketing', 'Health & Safety', 'Staff', 'Supplies', 'Other'],
        },
        due_date: { type: 'string', description: 'YYYY-MM-DD format' },
        notes: { type: 'string' },
      },
      required: ['title', 'priority', 'category'],
    },
  },
  {
    name: 'draft_message',
    description: 'Draft a professional customer message (WhatsApp, email or SMS). Returns the drafted text ready to copy.',
    input_schema: {
      type: 'object',
      properties: {
        lead_id: { type: 'string', description: 'The lead to write to (for context)' },
        channel: { type: 'string', enum: ['whatsapp', 'email', 'sms'] },
        purpose: {
          type: 'string',
          description: 'What the message is about, e.g. "confirm survey appointment on 22nd May at 10am", "follow up on quote", "job completion and payment request", "thank you and review request"',
        },
      },
      required: ['lead_id', 'channel', 'purpose'],
    },
  },
  {
    name: 'get_overdue',
    description: 'Get all leads needing follow-up, overdue surveys, and outstanding balances.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
];

// ── Tool execution (runs client-side against Zustand store) ──────────────────

function executeTool(name: string, input: Record<string, unknown>): unknown {
  const store = useStore.getState();
  const today = new Date().toISOString().split('T')[0];

  switch (name) {
    case 'get_pipeline': {
      return store.leads.map(l => ({
        id: l.id,
        jobRef: l.jobRef,
        name: l.name,
        phone: l.phone,
        email: l.email,
        address: l.address,
        jobType: l.jobType,
        stage: l.stage,
        value: l.value,
        balance: l.balance,
        depositPaid: l.depositPaid,
        progress: l.progress,
        startDate: l.startDate,
        surveyDate: l.surveyDate,
        completedDate: l.completedDate,
        paidDate: l.paidDate,
        tasksDone: l.tasks.filter(t => t.completed).length,
        tasksTotal: l.tasks.length,
        notesCount: l.notes.length,
      }));
    }

    case 'find_lead': {
      const q = (input.query as string).toLowerCase();
      const matches = store.leads.filter(
        l =>
          l.name.toLowerCase().includes(q) ||
          l.jobRef.toLowerCase().includes(q) ||
          l.phone.includes(q) ||
          l.address.toLowerCase().includes(q)
      );
      if (matches.length === 0) return { error: `No lead found matching "${input.query}"` };
      return matches.map(l => ({
        id: l.id, jobRef: l.jobRef, name: l.name, stage: l.stage,
        value: l.value, phone: l.phone, jobType: l.jobType, address: l.address,
      }));
    }

    case 'move_to_stage': {
      const lead = store.leads.find(l => l.id === input.lead_id);
      if (!lead) return { error: `Lead ${input.lead_id} not found` };
      store.moveToStage(input.lead_id as string, input.stage as Stage);
      return { success: true, message: `Moved ${lead.name} to "${input.stage}"` };
    }

    case 'mark_as_won': {
      const lead = store.leads.find(l => l.id === input.lead_id);
      if (!lead) return { error: `Lead ${input.lead_id} not found` };
      store.markAsWon(input.lead_id as string);
      return { success: true, message: `${lead.name} marked as Won! Default tasks created.` };
    }

    case 'add_note': {
      const lead = store.leads.find(l => l.id === input.lead_id);
      if (!lead) return { error: `Lead ${input.lead_id} not found` };
      store.addNote(input.lead_id as string, input.note as string);
      return { success: true, message: `Note added to ${lead.name}` };
    }

    case 'create_lead': {
      const value = (input.value as number) ?? 0;
      store.addLead({
        name: input.name as string,
        phone: input.phone as string,
        email: (input.email as string) ?? '',
        address: (input.address as string) ?? '',
        jobType: input.job_type as JobType,
        stage: (input.stage as Stage) ?? 'New Lead',
        source: (input.source as string) ?? 'AI Assistant',
        assignedTo: 'Harman',
        value,
        deposit: 0,
        depositPaid: false,
        balance: value,
        progress: 0,
      });
      return { success: true, message: `New lead created: ${input.name}` };
    }

    case 'add_job_task': {
      const lead = store.leads.find(l => l.id === input.lead_id);
      if (!lead) return { error: `Lead ${input.lead_id} not found` };
      store.addTask(input.lead_id as string, input.task as string);
      return { success: true, message: `Task added to ${lead.name}: "${input.task}"` };
    }

    case 'add_reminder': {
      store.addGeneralTask({
        title: input.title as string,
        priority: input.priority as 'low' | 'medium' | 'high',
        category: input.category as string,
        dueDate: (input.due_date as string) ?? undefined,
        notes: (input.notes as string) ?? undefined,
        assignedTo: [],
      });
      return { success: true, message: `Reminder added: "${input.title}"` };
    }

    case 'draft_message': {
      const lead = store.leads.find(l => l.id === input.lead_id);
      if (!lead) return { error: `Lead ${input.lead_id} not found` };
      // Return context for Claude to draft the message naturally
      return {
        customer: lead.name,
        phone: lead.phone,
        email: lead.email,
        jobType: lead.jobType,
        stage: lead.stage,
        value: lead.value,
        surveyDate: lead.surveyDate,
        startDate: lead.startDate,
        channel: input.channel,
        purpose: input.purpose,
        businessName: 'Proline Roofing & Solar Ltd',
        today,
      };
    }

    case 'get_overdue': {
      const overdue = {
        followUps: store.leads
          .filter(l => l.stage === 'Quote Sent')
          .map(l => ({ name: l.name, value: l.value, jobType: l.jobType, updatedAt: l.updatedAt })),
        upcomingSurveys: store.leads
          .filter(l => l.surveyDate && l.surveyDate >= today)
          .sort((a, b) => (a.surveyDate ?? '').localeCompare(b.surveyDate ?? ''))
          .slice(0, 5)
          .map(l => ({ name: l.name, surveyDate: l.surveyDate, surveyTime: l.surveyTime, jobType: l.jobType })),
        outstandingBalances: store.leads
          .filter(l => l.balance > 0 && ['In Progress', 'Completed', 'Won'].includes(l.stage))
          .map(l => ({ name: l.name, balance: l.balance, stage: l.stage, jobRef: l.jobRef })),
        overdueGeneralTasks: store.generalTasks
          .filter(t => !t.completed && t.dueDate && t.dueDate < today)
          .map(t => ({ title: t.title, dueDate: t.dueDate, priority: t.priority })),
      };
      return overdue;
    }

    default:
      return { error: `Unknown tool: ${name}` };
  }
}

// ── API call ─────────────────────────────────────────────────────────────────

async function callClaude(
  apiKey: string,
  messages: AnthropicMessage[],
  today: string
): Promise<{ content: ContentBlock[]; stop_reason: string }> {
  const systemPrompt = `You are an AI assistant built directly into Proline Roofing & Solar's CRM system. You help Harman (the business owner) manage leads, jobs, tasks and customer communications.

You have live access to the CRM data and can take real actions. When asked to do something, use your tools to actually do it — don't just describe what you'd do.

Your tools let you:
- Read the full pipeline (leads, jobs, values, stages)
- Move leads/jobs between stages
- Mark jobs as Won (sets up tasks automatically)
- Add notes and tasks to any job
- Create new leads
- Add general reminders (MOT, admin, etc.)
- Draft professional WhatsApp/email/SMS messages for customers

Pipeline stages in order: New Lead → Survey Booked → Quote Sent → Won → In Progress → Completed → Paid

Tips:
- When drafting messages, make them warm, professional and concise — use the customer's first name
- When asked about revenue/pipeline, always call get_pipeline first for live data
- Confirm what actions you've taken after using tools
- For follow-ups, use get_overdue to find what needs attention
- Today's date: ${today}
- Business: Proline Roofing & Solar Ltd, Harman (Owner), Birmingham area`;

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
      'anthropic-dangerous-direct-browser-access': 'true',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-6',
      max_tokens: 2048,
      system: systemPrompt,
      tools: CRM_TOOLS,
      messages,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error((err as { error?: { message?: string } }).error?.message ?? `API error ${res.status}`);
  }

  return res.json();
}

// ── Agentic loop ─────────────────────────────────────────────────────────────

async function runAgentLoop(
  apiKey: string,
  history: AnthropicMessage[],
  onAction: (action: string) => void
): Promise<{ text: string; actions: string[] }> {
  const today = new Date().toISOString().split('T')[0];
  const messages = [...history];
  const actions: string[] = [];

  for (let i = 0; i < 8; i++) {
    const response = await callClaude(apiKey, messages, today);

    if (response.stop_reason === 'end_turn') {
      const text = response.content
        .filter((b): b is ContentBlock & { type: 'text' } => b.type === 'text')
        .map(b => b.text ?? '')
        .join('');
      return { text, actions };
    }

    if (response.stop_reason === 'tool_use') {
      messages.push({ role: 'assistant', content: response.content });

      const toolResults: ContentBlock[] = [];
      for (const block of response.content) {
        if (block.type === 'tool_use') {
          const result = executeTool(block.name!, block.input ?? {});
          const resultStr = JSON.stringify(result);

          // Surface friendly action labels
          if (typeof result === 'object' && result !== null && 'message' in result) {
            const msg = (result as { message: string }).message;
            actions.push(msg);
            onAction(msg);
          }

          toolResults.push({
            type: 'tool_result',
            tool_use_id: block.id,
            content: resultStr,
          });
        }
      }

      messages.push({ role: 'user', content: toolResults });
      continue;
    }

    // Unexpected stop
    break;
  }

  return { text: 'Something went wrong — please try again.', actions };
}

// ── Suggestion chips ─────────────────────────────────────────────────────────

const SUGGESTIONS = [
  "What's in my pipeline today?",
  "Which quotes need following up?",
  "Show me outstanding balances",
  "Draft a WhatsApp for a survey reminder",
  "Add an MOT reminder for next month",
  "Summarise this week's jobs",
];

// ── Copy button ──────────────────────────────────────────────────────────────

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };
  return (
    <button onClick={copy} className="ml-1 text-gray-400 hover:text-gray-600 transition-colors">
      {copied ? <Check size={12} className="text-green-500" /> : <Copy size={12} />}
    </button>
  );
}

// ── Message bubble ────────────────────────────────────────────────────────────

function MessageBubble({ msg }: { msg: ChatMessage }) {
  const isUser = msg.role === 'user';
  return (
    <div className={`flex ${isUser ? 'justify-end' : 'justify-start'} mb-3`}>
      {!isUser && (
        <div className="w-7 h-7 rounded-full bg-orange-600 flex items-center justify-center shrink-0 mt-0.5 mr-2">
          <Bot size={14} className="text-white" />
        </div>
      )}
      <div className="max-w-[82%] space-y-1.5">
        <div className={`rounded-2xl px-3.5 py-2.5 text-sm leading-relaxed whitespace-pre-wrap ${
          isUser
            ? 'bg-orange-600 text-white rounded-br-sm'
            : msg.error
            ? 'bg-red-50 text-red-700 border border-red-200 rounded-bl-sm'
            : 'bg-white text-gray-800 shadow-sm border border-gray-100 rounded-bl-sm'
        }`}>
          {msg.text}
          {!isUser && !msg.error && <CopyButton text={msg.text} />}
        </div>
        {msg.actions && msg.actions.length > 0 && (
          <div className="flex flex-wrap gap-1 pl-0.5">
            {msg.actions.map((a, i) => (
              <span key={i} className="inline-flex items-center gap-1 text-xs bg-green-50 text-green-700 border border-green-200 px-2 py-0.5 rounded-full font-medium">
                <Check size={10} /> {a}
              </span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ── API key setup screen ──────────────────────────────────────────────────────

function ApiKeySetup({ onSave }: { onSave: (key: string) => void }) {
  const [value, setValue] = useState('');
  const submit = (e: React.FormEvent) => { e.preventDefault(); if (value.trim()) onSave(value.trim()); };
  return (
    <div className="flex-1 flex flex-col items-center justify-center p-5 space-y-4 text-center">
      <div className="w-14 h-14 rounded-2xl bg-orange-100 flex items-center justify-center">
        <Key size={26} className="text-orange-600" />
      </div>
      <div>
        <h3 className="font-bold text-gray-800 text-base">Connect Claude AI</h3>
        <p className="text-sm text-gray-500 mt-1">Enter your Anthropic API key to enable the AI assistant.</p>
        <a href="https://console.anthropic.com/settings/keys" target="_blank" rel="noreferrer"
          className="text-xs text-orange-500 hover:underline mt-1 inline-block">
          Get your API key →
        </a>
      </div>
      <form onSubmit={submit} className="w-full space-y-2">
        <input
          type="password" value={value} onChange={e => setValue(e.target.value)}
          placeholder="sk-ant-api03-..."
          className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
          autoFocus
        />
        <button type="submit" disabled={!value.trim()}
          className="w-full bg-orange-600 disabled:opacity-40 text-white py-2.5 rounded-xl text-sm font-bold hover:bg-orange-700 transition-colors">
          Connect
        </button>
      </form>
      <p className="text-xs text-gray-400 leading-relaxed">
        Your key is stored locally in your browser and never sent anywhere except Anthropic.
      </p>
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

export default function AIAssistant() {
  const { apiKey, setApiKey } = useStore();
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: 'welcome',
      role: 'assistant',
      text: "Hi Harman! I'm your CRM assistant. I can check your pipeline, move jobs, draft messages, add notes, create leads and more.\n\nWhat would you like to do?",
    },
  ]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [actionLabel, setActionLabel] = useState('');
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // Anthropic message history (separate from display messages)
  const historyRef = useRef<AnthropicMessage[]>([]);

  useEffect(() => {
    if (open) {
      setTimeout(() => inputRef.current?.focus(), 100);
    }
  }, [open]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, loading]);

  const addMessage = (msg: Omit<ChatMessage, 'id'>) => {
    setMessages(prev => [...prev, { ...msg, id: Math.random().toString(36).slice(2) }]);
  };

  const send = async (text: string) => {
    if (!text.trim() || loading) return;
    setInput('');

    const userText = text.trim();
    addMessage({ role: 'user', text: userText });
    historyRef.current = [...historyRef.current, { role: 'user', content: userText }];

    setLoading(true);
    setActionLabel('Thinking…');

    try {
      const { text: replyText, actions } = await runAgentLoop(
        apiKey,
        historyRef.current,
        (action) => setActionLabel(action)
      );

      historyRef.current = [
        ...historyRef.current,
        { role: 'assistant', content: replyText },
      ];

      addMessage({ role: 'assistant', text: replyText, actions });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      addMessage({ role: 'assistant', text: `Error: ${message}`, error: true });
    } finally {
      setLoading(false);
      setActionLabel('');
    }
  };

  const handleKey = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(input); }
  };

  const clearChat = () => {
    historyRef.current = [];
    setMessages([{
      id: 'welcome',
      role: 'assistant',
      text: "Chat cleared. How can I help you?",
    }]);
  };

  return (
    <>
      {/* Floating button — above bottom nav on mobile */}
      <button
        onClick={() => setOpen(o => !o)}
        className={`fixed bottom-20 right-4 sm:bottom-6 sm:right-6 z-50 w-14 h-14 rounded-full shadow-xl flex items-center justify-center transition-all ${
          open ? 'bg-gray-700 rotate-12' : 'bg-orange-600 hover:bg-orange-700 hover:scale-105'
        }`}
      >
        {open ? <X size={22} className="text-white" /> : <Sparkles size={22} className="text-white" />}
        {!open && !apiKey && (
          <span className="absolute -top-1 -right-1 w-4 h-4 bg-amber-400 rounded-full flex items-center justify-center text-[9px] font-bold text-white">!</span>
        )}
      </button>

      {/* Chat panel — full width on mobile, floating on desktop */}
      {open && (
        <div className="fixed bottom-0 left-0 right-0 sm:bottom-24 sm:left-auto sm:right-6 z-50
                        sm:w-96 sm:max-w-[calc(100vw-3rem)] sm:rounded-2xl
                        rounded-t-2xl bg-white shadow-2xl border border-gray-200 flex flex-col overflow-hidden"
          style={{ height: 'min(75dvh, 560px)' }}>

          {/* Header */}
          <div className="flex items-center gap-3 px-4 py-3 bg-orange-600 shrink-0">
            <div className="w-8 h-8 rounded-full bg-white/20 flex items-center justify-center shrink-0">
              <Bot size={16} className="text-white" />
            </div>
            <div className="flex-1">
              <p className="text-white font-bold text-sm">Proline AI Assistant</p>
              <p className="text-orange-200 text-xs flex items-center gap-1">
                <Zap size={9} /> Powered by Claude
              </p>
            </div>
            <div className="flex items-center gap-1">
              {apiKey && (
                <button onClick={clearChat} title="Clear chat"
                  className="p-1.5 rounded-lg text-white/60 hover:text-white hover:bg-white/10 transition-colors">
                  <Trash2 size={14} />
                </button>
              )}
              {apiKey && (
                <button onClick={() => setApiKey('')} title="Disconnect API key"
                  className="p-1.5 rounded-lg text-white/60 hover:text-white hover:bg-white/10 transition-colors">
                  <Key size={14} />
                </button>
              )}
              <button onClick={() => setOpen(false)}
                className="p-1.5 rounded-lg text-white/60 hover:text-white hover:bg-white/10 transition-colors">
                <ChevronDown size={16} />
              </button>
            </div>
          </div>

          {/* Body */}
          {!apiKey ? (
            <ApiKeySetup onSave={setApiKey} />
          ) : (
            <>
              {/* Messages */}
              <div className="flex-1 overflow-y-auto p-4 bg-gray-50">
                {messages.map(msg => <MessageBubble key={msg.id} msg={msg} />)}

                {loading && (
                  <div className="flex items-center gap-2 mb-3">
                    <div className="w-7 h-7 rounded-full bg-orange-600 flex items-center justify-center shrink-0">
                      <Bot size={14} className="text-white" />
                    </div>
                    <div className="bg-white border border-gray-100 rounded-2xl rounded-bl-sm px-3.5 py-2.5 shadow-sm flex items-center gap-2">
                      <Loader2 size={14} className="text-orange-500 animate-spin" />
                      <span className="text-xs text-gray-500">{actionLabel || 'Thinking…'}</span>
                    </div>
                  </div>
                )}
                <div ref={bottomRef} />
              </div>

              {/* Suggestion chips (only when first message) */}
              {messages.length <= 1 && !loading && (
                <div className="px-4 pb-2 flex flex-wrap gap-1.5 bg-gray-50 border-t border-gray-100">
                  {SUGGESTIONS.map(s => (
                    <button key={s} onClick={() => send(s)}
                      className="text-xs bg-white border border-gray-200 text-gray-600 hover:border-orange-300 hover:text-orange-600 px-2.5 py-1 rounded-full transition-colors">
                      {s}
                    </button>
                  ))}
                </div>
              )}

              {/* Input */}
              <div className="flex items-end gap-2 p-3 bg-white border-t border-gray-100 shrink-0">
                <textarea
                  ref={inputRef}
                  value={input}
                  onChange={e => setInput(e.target.value)}
                  onKeyDown={handleKey}
                  placeholder="Ask anything about your jobs…"
                  rows={1}
                  disabled={loading}
                  className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 resize-none disabled:opacity-50"
                  style={{ maxHeight: '80px' }}
                />
                <button
                  onClick={() => send(input)}
                  disabled={!input.trim() || loading}
                  className="w-9 h-9 rounded-xl bg-orange-600 disabled:opacity-40 text-white flex items-center justify-center hover:bg-orange-700 transition-colors shrink-0"
                >
                  <Send size={15} />
                </button>
              </div>

              {/* Pipeline quick stats */}
              <PipelineStats />
            </>
          )}
        </div>
      )}
    </>
  );
}

// ── Quick stats footer ────────────────────────────────────────────────────────

function PipelineStats() {
  const { leads } = useStore();
  const stats = {
    leads: leads.filter(l => ['New Lead', 'Survey Booked', 'Quote Sent'].includes(l.stage)).length,
    jobs: leads.filter(l => ['Won', 'In Progress'].includes(l.stage)).length,
    revenue: leads.filter(l => l.stage === 'Paid').reduce((s, l) => s + l.value, 0),
  };
  return (
    <div className="flex divide-x divide-gray-100 border-t border-gray-100 bg-gray-50">
      {[
        { label: 'Open leads', value: stats.leads },
        { label: 'Active jobs', value: stats.jobs },
        { label: 'Paid', value: formatCurrency(stats.revenue) },
      ].map(({ label, value }) => (
        <div key={label} className="flex-1 text-center py-1.5">
          <p className="text-xs font-bold text-gray-700">{value}</p>
          <p className="text-[10px] text-gray-400">{label}</p>
        </div>
      ))}
    </div>
  );
}
