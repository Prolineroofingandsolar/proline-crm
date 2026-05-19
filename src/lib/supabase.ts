import { createClient } from '@supabase/supabase-js';
import type { Lead, Contact, AppUser, GeneralTask, TimesheetEntry } from '../types';

export const supabase = createClient(
  'https://qzvdzzvkocmulcfujyea.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF6dmR6enZrb2NtdWxjZnVqeWVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4NzIxNjUsImV4cCI6MjA5NDQ0ODE2NX0.g42AvuElukfbpgbg9Y6XImnuHQ2Po5GEaVVGMz3Siu0'
);

// ── Lead ──────────────────────────────────────────────────────────────────────

export function dbToLead(r: Record<string, unknown>): Lead {
  return {
    id: r.id as string,
    jobRef: r.job_ref as string,
    name: r.name as string,
    phone: r.phone as string,
    email: r.email as string,
    address: r.address as string,
    jobType: r.job_type as Lead['jobType'],
    stage: r.stage as Lead['stage'],
    value: r.value as number,
    deposit: r.deposit as number,
    depositPaid: r.deposit_paid as boolean,
    balance: r.balance as number,
    source: r.source as string,
    assignedTo: r.assigned_to as string,
    surveyDate: (r.survey_date as string) ?? undefined,
    surveyTime: (r.survey_time as string) ?? undefined,
    startDate: (r.start_date as string) ?? undefined,
    endDate: (r.end_date as string) ?? undefined,
    completedDate: (r.completed_date as string) ?? undefined,
    paidDate: (r.paid_date as string) ?? undefined,
    wonDate: (r.won_date as string) ?? undefined,
    progress: r.progress as number,
    lat: (r.lat as number) ?? undefined,
    lng: (r.lng as number) ?? undefined,
    myBuilderUrl: (r.mybuilder_url as string) ?? undefined,
    reviewRequestSent: (r.review_request_sent as boolean) ?? false,
    tasks: (r.tasks as Lead['tasks']) ?? [],
    photos: (r.photos as Lead['photos']) ?? [],
    notes: (r.notes as Lead['notes']) ?? [],
    files: (r.files as Lead['files']) ?? [],
    materials: (r.materials as Lead['materials']) ?? [],
    createdAt: r.created_at as string,
    updatedAt: r.updated_at as string,
  };
}

export function leadToDb(l: Lead): Record<string, unknown> {
  return {
    id: l.id,
    job_ref: l.jobRef,
    name: l.name,
    phone: l.phone,
    email: l.email,
    address: l.address,
    job_type: l.jobType,
    stage: l.stage,
    value: l.value,
    deposit: l.deposit,
    deposit_paid: l.depositPaid,
    balance: l.balance,
    source: l.source,
    assigned_to: l.assignedTo,
    survey_date: l.surveyDate ?? null,
    survey_time: l.surveyTime ?? null,
    start_date: l.startDate ?? null,
    end_date: l.endDate ?? null,
    completed_date: l.completedDate ?? null,
    paid_date: l.paidDate ?? null,
    won_date: l.wonDate ?? null,
    progress: l.progress,
    lat: l.lat ?? null,
    lng: l.lng ?? null,
    ...(l.myBuilderUrl !== undefined ? { mybuilder_url: l.myBuilderUrl } : {}),
    ...(l.reviewRequestSent !== undefined ? { review_request_sent: l.reviewRequestSent } : {}),
    tasks: l.tasks,
    photos: l.photos,
    notes: l.notes,
    files: l.files,
    materials: l.materials,
    created_at: l.createdAt,
    updated_at: l.updatedAt,
  };
}

// ── AppUser ───────────────────────────────────────────────────────────────────

export function dbToUser(r: Record<string, unknown>): AppUser {
  return {
    id: r.id as string,
    name: r.name as string,
    username: r.username as string,
    passwordHash: r.password_hash as string,
    role: r.role as AppUser['role'],
    createdAt: r.created_at as string,
    dayRate: (r.day_rate as number) ?? undefined,
    cisRate: (r.cis_rate as 20 | 30) ?? undefined,
    utrNumber: (r.utr_number as string) ?? undefined,
    bankName: (r.bank_name as string) ?? undefined,
    bankAccountNumber: (r.bank_account_number as string) ?? undefined,
    bankSortCode: (r.bank_sort_code as string) ?? undefined,
  };
}

export function userToDb(u: AppUser): Record<string, unknown> {
  return {
    id: u.id,
    name: u.name,
    username: u.username,
    password_hash: u.passwordHash,
    role: u.role,
    created_at: u.createdAt,
    // Only include payment fields when they exist — omitting keeps inserts
    // compatible with databases that haven't run the timesheet migration yet.
    ...(u.dayRate !== undefined && { day_rate: u.dayRate }),
    ...(u.cisRate !== undefined && { cis_rate: u.cisRate }),
    ...(u.utrNumber !== undefined && { utr_number: u.utrNumber }),
    ...(u.bankName !== undefined && { bank_name: u.bankName }),
    ...(u.bankAccountNumber !== undefined && { bank_account_number: u.bankAccountNumber }),
    ...(u.bankSortCode !== undefined && { bank_sort_code: u.bankSortCode }),
  };
}

// ── TimesheetEntry ─────────────────────────────────────────────────────────────

export function dbToTimesheetEntry(r: Record<string, unknown>): TimesheetEntry {
  return {
    id: r.id as string,
    userId: r.user_id as string,
    leadId: r.lead_id as string,
    date: r.date as string,
    type: r.type as TimesheetEntry['type'],
    amount: r.amount as number,
    createdAt: r.created_at as string,
  };
}

export function timesheetEntryToDb(e: TimesheetEntry): Record<string, unknown> {
  return {
    id: e.id,
    user_id: e.userId,
    lead_id: e.leadId,
    date: e.date,
    type: e.type,
    amount: e.amount,
    created_at: e.createdAt,
  };
}

// ── Contact ───────────────────────────────────────────────────────────────────

export function dbToContact(r: Record<string, unknown>): Contact {
  return {
    id: r.id as string,
    name: r.name as string,
    phone: r.phone as string,
    email: r.email as string,
    address: r.address as string,
    createdAt: r.created_at as string,
  };
}

export function contactToDb(c: Contact): Record<string, unknown> {
  return {
    id: c.id,
    name: c.name,
    phone: c.phone,
    email: c.email,
    address: c.address,
    created_at: c.createdAt,
  };
}

// ── GeneralTask ───────────────────────────────────────────────────────────────

export function dbToGeneralTask(r: Record<string, unknown>): GeneralTask {
  return {
    id: r.id as string,
    title: r.title as string,
    completed: r.completed as boolean,
    completedDate: (r.completed_date as string) ?? undefined,
    dueDate: (r.due_date as string) ?? undefined,
    priority: r.priority as GeneralTask['priority'],
    category: r.category as string,
    notes: (r.notes as string) ?? undefined,
    createdAt: r.created_at as string,
  };
}

export function generalTaskToDb(t: GeneralTask): Record<string, unknown> {
  return {
    id: t.id,
    title: t.title,
    completed: t.completed,
    completed_date: t.completedDate ?? null,
    due_date: t.dueDate ?? null,
    priority: t.priority,
    category: t.category,
    notes: t.notes ?? null,
    created_at: t.createdAt,
  };
}
