export type Role = "customer" | "agent" | "admin";
export type Priority = "low" | "medium" | "high";
export type Status =
  | "created"
  | "assigned"
  | "accepted"
  | "in_progress"
  | "completed"
  | "cancelled";

export interface Profile {
  id: string;
  email: string;
  full_name: string;
  phone: string | null;
  role: Role;
  created_at: string;
}

export interface ServiceItem {
  id: string;
  name: string;
  description: string;
  is_active: boolean;
}

export interface ServiceRequest {
  id: string;
  request_id: string;
  customer_id: string;
  agent_id: string | null;
  service_id: string;
  description: string;
  preferred_at: string;
  address: string;
  priority: Priority;
  status: Status;
  cancel_reason: string | null;
  created_at: string;
  updated_at: string;
  services?: { id: string; name: string } | null;
  customer?: { id: string; full_name: string } | null;
  agent?: { id: string; full_name: string } | null;
}

export interface HistoryEntry {
  from_status: Status | null;
  to_status: Status;
  note: string | null;
  created_at: string;
  changed_by_user?: { full_name: string } | null;
}

export interface AuditLog {
  id: string;
  actor_id: string | null;
  actor_role: Role | null;
  event_type: string;
  entity_type: string | null;
  entity_id: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  actor?: { full_name: string; email: string } | null;
}

export interface DashboardStats {
  total: number;
  created: number;
  assigned: number;
  accepted: number;
  in_progress: number;
  completed: number;
  cancelled: number;
  customers: number;
  agents: number;
  open_high: number;
}

export const STATUS_LABELS: Record<Status, string> = {
  created: "New",
  assigned: "Assigned",
  accepted: "Accepted",
  in_progress: "In progress",
  completed: "Completed",
  cancelled: "Cancelled",
};

export const STATUS_COLORS: Record<Status, string> = {
  created: "bg-zinc-100 text-zinc-700",
  assigned: "bg-blue-100 text-blue-700",
  accepted: "bg-violet-100 text-violet-700",
  in_progress: "bg-amber-100 text-amber-800",
  completed: "bg-emerald-100 text-emerald-700",
  cancelled: "bg-red-100 text-red-700",
};

export const PRIORITY_COLORS: Record<Priority, string> = {
  low: "bg-emerald-100 text-emerald-700",
  medium: "bg-amber-100 text-amber-800",
  high: "bg-red-100 text-red-700",
};

/** Next legal status transitions (mirrors the DB constraint). */
export const TRANSITIONS: Record<Status, Status[]> = {
  created: ["assigned", "cancelled"],
  assigned: ["accepted", "cancelled"],
  accepted: ["in_progress", "cancelled"],
  in_progress: ["completed", "cancelled"],
  completed: [],
  cancelled: [],
};
