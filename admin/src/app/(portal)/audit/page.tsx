"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { AuditLog } from "@/lib/types";
import { formatDateTime, friendlyError } from "@/lib/format";

const EVENTS = [
  "LOGIN_SUCCESS",
  "LOGIN_FAILED",
  "LOGOUT",
  "REGISTER_SUCCESS",
  "PASSWORD_RESET_REQUESTED",
  "REQUEST_CREATED",
  "REQUEST_ASSIGNED",
  "REQUEST_UPDATED",
  "REQUEST_CANCELLED",
  "PROFILE_UPDATED",
  "ROLE_CHANGED",
  "AUTHORIZATION_FAILED",
  "DATABASE_ERROR",
];

const EVENT_TONES: Record<string, string> = {
  AUTHORIZATION_FAILED: "bg-red-100 text-red-700",
  DATABASE_ERROR: "bg-red-100 text-red-700",
  LOGIN_FAILED: "bg-amber-100 text-amber-800",
  REQUEST_CREATED: "bg-blue-100 text-blue-700",
  REQUEST_ASSIGNED: "bg-violet-100 text-violet-700",
  REQUEST_COMPLETED: "bg-emerald-100 text-emerald-700",
};

export default function AuditPage() {
  const [rows, setRows] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [event, setEvent] = useState("");

  const load = useCallback(
    async (eventType: string) => {
      const supabase = createClient();
      try {
        let query = supabase
          .from("audit_logs")
          .select(
            `id, actor_id, actor_role, event_type, entity_type, entity_id,
             metadata, created_at,
             actor:profiles!audit_logs_actor_id_fkey(full_name, email)`,
          )
          .order("created_at", { ascending: false })
          .limit(200);
        if (eventType) query = query.eq("event_type", eventType);

        const { data, error: err } = await query;
        if (err) throw err;
        setRows((data ?? []) as unknown as AuditLog[]);
      } catch (e) {
        setError(friendlyError(e));
      } finally {
        setLoading(false);
      }
    },
    [],
  );

  useEffect(() => {
    // Fetch on mount and whenever the event filter changes; state is only
    // touched after the request resolves.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load(event);
  }, [load, event]);

  return (
    <div className="p-8">
      <div className="mb-6 flex items-end justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Audit log</h1>
          <p className="text-sm text-zinc-500">
            Security and business events. Secrets and tokens are never recorded.
          </p>
        </div>
        <select
          value={event}
          onChange={(e) => {
            setLoading(true);
            setError(null);
            setEvent(e.target.value);
          }}
          className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm"
        >
          <option value="">All events</option>
          {EVENTS.map((ev) => (
            <option key={ev} value={ev}>
              {ev}
            </option>
          ))}
        </select>
      </div>

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>
      )}

      <div className="rounded-xl border border-zinc-200 bg-white overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-zinc-500 border-b border-zinc-200 bg-zinc-50">
              <th className="px-4 py-3 font-medium">When</th>
              <th className="px-4 py-3 font-medium">Event</th>
              <th className="px-4 py-3 font-medium">Actor</th>
              <th className="px-4 py-3 font-medium">Entity</th>
              <th className="px-4 py-3 font-medium">Details</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((log) => (
              <tr key={log.id} className="border-b border-zinc-100 last:border-0 align-top">
                <td className="px-4 py-3 text-zinc-500 whitespace-nowrap">
                  {formatDateTime(log.created_at)}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`rounded-md px-2 py-1 text-xs font-medium ${
                      EVENT_TONES[log.event_type] ?? "bg-zinc-100 text-zinc-700"
                    }`}
                  >
                    {log.event_type}
                  </span>
                </td>
                <td className="px-4 py-3">
                  {log.actor?.full_name ?? "Anonymous"}
                  <span className="block text-xs text-zinc-400">
                    {log.actor_role ?? ""}
                  </span>
                </td>
                <td className="px-4 py-3 text-xs text-zinc-500">
                  {log.entity_type ?? "—"}
                  {log.entity_id && (
                    <span className="block font-mono">
                      {log.entity_id.slice(0, 8)}…
                    </span>
                  )}
                </td>
                <td className="px-4 py-3">
                  {Object.keys(log.metadata ?? {}).length > 0 ? (
                    <code className="text-xs text-zinc-600">
                      {JSON.stringify(log.metadata)}
                    </code>
                  ) : (
                    "—"
                  )}
                </td>
              </tr>
            ))}
            {!loading && rows.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-10 text-center text-zinc-400">
                  No audit events yet.
                </td>
              </tr>
            )}
            {loading && (
              <tr>
                <td colSpan={5} className="px-4 py-10 text-center text-zinc-400">
                  Loading…
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
