export type JobType =
  | 'Roof Repair'
  | 'Solar Installation'
  | 'New Roof'
  | 'Flat Roof'
  | 'Solar + Battery'
  | 'Guttering'
  | 'Fascias & Soffits'
  | 'Chimney Repair';

export type Stage =
  | 'New Lead'
  | 'Survey Booked'
  | 'Quote Sent'
  | 'Won'
  | 'In Progress'
  | 'Completed'
  | 'Paid';

export interface Task {
  id: string;
  title: string;
  completed: boolean;
  completedDate?: string;
  dueDate?: string;
}

export interface Photo {
  id: string;
  url: string;
  category: 'Before' | 'During' | 'After';
  date: string;
  caption?: string;
}

export interface Note {
  id: string;
  content: string;
  date: string;
  author: string;
}

export interface FileItem {
  id: string;
  name: string;
  type: 'pdf' | 'image' | 'document' | 'spreadsheet' | 'archive';
  size?: string;
  date: string;
}

export interface Material {
  id: string;
  name: string;
  quantity: number;
  unit: string;
  cost?: number;
  supplier?: string;
  ordered: boolean;
  delivered: boolean;
}

export interface Contact {
  id: string;
  name: string;
  phone: string;
  email: string;
  address: string;
  createdAt: string;
}

export interface Lead {
  id: string;
  name: string;
  phone: string;
  email: string;
  address: string;
  jobType: JobType;
  stage: Stage;
  jobRef: string;
  createdAt: string;
  updatedAt: string;
  surveyDate?: string;
  surveyTime?: string;
  startDate?: string;
  completedDate?: string;
  paidDate?: string;
  value: number;
  deposit: number;
  depositPaid: boolean;
  balance: number;
  progress: number;
  source: string;
  assignedTo: string;
  wonDate?: string;
  tasks: Task[];
  photos: Photo[];
  notes: Note[];
  files: FileItem[];
  materials: Material[];
}
