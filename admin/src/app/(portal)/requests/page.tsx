"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  PRIORITY_COLORS,
  STATUS_COLORS,
  STATUS_LABELS,
  TRANSITIONS,
  type HistoryEntry,
  type Profile,
  type ServiceRequest,
  type Status,
} from "@/lib/types";
import { friendlyError, formatDateTime, rpcDenial } from "@/lib/format";

const STATUSES: Status[] = [
  "created",
  "assigned",
  "accepted",
  "in_progress",
  "completed",
  "cancelled",
];

export default function RequestsPage() {
  const [rows, setRows] = useState<ServiceRequest[]>([]);
  const [agents, setAgents] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const [priority, setPriority] = useState("");
  const [page, setPage] = useState(0);
  const pageSize = 10;

  const [selected, setSelected] = useState<ServiceRequest | null>(null);
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const supabase = createClient();
    try {
      let query = supabase
        .from("service_requests")
        .select(
          `id, request_id, customer_id, agent_id, service_id, description,
           preferred_at, address, priority, status, cancel_reason,
           created_at, updated_at,
           services(name),
           customer:profiles!service_requests_customer_id_fkey(id, full_name),
           agent:profiles!service_requests_agent_id_fkey(id, full_name)`,
        )
        .order("created_at", { ascending: false });

      if (status) query = query.eq("status", status);
      if (priority) query = query.eq("priority", priority);
      if (search.trim()) {
        const term = search.trim().replace(/[%_,()]/g, "");
        query = query.or(
          `request_id.ilike.*${term}*,address.ilike.*${term}*,description.ilike.*${term}*`,
        );
      }

      const { data, error: err } = await query;
      if (err) throw err;
      setRows((data ?? []) as unknown as ServiceRequest[]);

      const { data: agentRows, error: agentErr } = await supabase
        .from("profiles")
        .select("*")
        .eq("role", "agent")
        .order("full_name");
      if (agentErr) throw agentErr;
      setAgents((agentRows ?? []) as Profile[]);
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setLoading(false);
    }
  }, [search, status, priority]);

  useEffect(() => {
    const t = setTimeout(load, search ? 300 : 0);
    return () => clearTimeout(t);
  }, [load, search]);

  async function openDetail(row: ServiceRequest) {
    setSelected(row);
    setHistory([]);
    const supabase = createClient();
    const { data } = await supabase
      .from("request_status_history")
      .select(
        `from_status, to_status, note, created_at,
         changed_by_user:profiles!request_status_history_changed_by_fkey(full_name)`,
      )
      .eq("request_id", row.id)
      .order("created_at", { ascending: true });
    setHistory((data ?? []) as unknown as HistoryEntry[]);
  }

  async function assignAgent(agentId: string) {
    if (!selected) return;
    setBusy(true);
    setNotice(null);
    setError(null);
    const supabase = createClient();
    const { data, error: err } = await supabase.rpc("assign_agent", {
      p_request_id: selected.id,
      p_agent_id: agentId,
    });
    setBusy(false);
    if (err) {
      setError(friendlyError(err));
      return;
    }
    const denial = rpcDenial(data);
    if (denial) {
      setError(denial);
      return;
    }
    setNotice(`Assigned to ${agents.find((a) => a.id === agentId)?.full_name ?? "agent"}`);
    await load();
    const updated = rows.find((r) => r.id === selected.id);
    if (updated) await openDetail({ ...updated, agent_id: agentId });
  }

  async function updateStatus(to: Status) {
    if (!selected) return;
    setBusy(true);
    setNotice(null);
    setError(null);
    const supabase = createClient();
    const { data, error: err } = await supabase.rpc("update_request_status", {
      p_request_id: selected.id,
      p_new_status: to,
      p_note: null,
    });
    setBusy(false);
    if (err) {
      setError(friendlyError(err));
      return;
    }
    const denial = rpcDenial(data);
    if (denial) {
      setError(denial);
      return;
    }
    setNotice(`Status changed to ${STATUS_LABELS[to]}`);
    await load();
    const updated = rows.find((r) => r.id === selected.id);
    if (updated) await openDetail({ ...updated, status: to });
  }

  const totalPages = Math.max(1, Math.ceil(rows.length / pageSize));
  const pageRows = rows.slice(page * pageSize, page * pageSize + pageSize);

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold">Requests</h1>
        <p className="text-sm text-zinc-500">
          Search, filter, assign agents and update statuses.
        </p>
      </div>

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}
      {notice && (
        <div className="mb-4 rounded-lg bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          {notice}
        </div>
      )}

      <div className="mb-4 flex flex-wrap gap-3">
        <input
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setPage(0);
          }}
          placeholder="Search ID, address or description…"
          className="w-72 rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm focus:border-blue-500 focus:outline-none"
        />
        <select
          value={status}
          onChange={(e) => {
            setStatus(e.target.value);
            setPage(0);
          }}
          className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm"
        >
          <option value="">All statuses</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {STATUS_LABELS[s]}
            </option>
          ))}
        </select>
        <select
          value={priority}
          onChange={(e) => {
            setPriority(e.target.value);
            setPage(0);
          }}
          className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm"
        >
          <option value="">All priorities</option>
          <option value="low">Low</option>
          <option value="medium">Medium</option>
          <option value="high">High</option>
        </select>
        {(search || status || priority) && (
          <button
            onClick={() => {
              setSearch("");
              setStatus("");
              setPriority("");
            }}
            className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm hover:bg-zinc-50"
          >
            Clear
          </button>
        )}
      </div>

      <div className="rounded-xl border border-zinc-200 bg-white overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-zinc-500 border-b border-zinc-200 bg-zinc-50">
              <th className="px-4 py-3 font-medium">Request</th>
              <th className="px-4 py-3 font-medium">Customer</th>
              <th className="px-4 py-3 font-medium">Agent</th>
              <th className="px-4 py-3 font-medium">Service</th>
              <th className="px-4 py-3 font-medium">Priority</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Created</th>
            </tr>
          </thead>
          <tbody>
            {pageRows.map((r) => (
              <tr
                key={r.id}
                onClick={() => openDetail(r)}
                className="border-b border-zinc-100 last:border-0 hover:bg-blue-50/40 cursor-pointer"
              >
                <td className="px-4 py-3 font-mono text-xs">{r.request_id}</td>
                <td className="px-4 py-3">{r.customer?.full_name ?? "—"}</td>
                <td className="px-4 py-3">{r.agent?.full_name ?? "—"}</td>
                <td className="px-4 py-3">{r.services?.name ?? "—"}</td>
                <td className="px-4 py-3">
                  <span
                    className={`rounded-md px-2 py-1 text-xs font-medium ${PRIORITY_COLORS[r.priority]}`}
                  >
                    {r.priority}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`rounded-md px-2 py-1 text-xs font-medium ${STATUS_COLORS[r.status]}`}
                  >
                    {STATUS_LABELS[r.status]}
                  </span>
                </td>
                <td className="px-4 py-3 text-zinc-500">
                  {formatDateTime(r.created_at)}
                </td>
              </tr>
            ))}
            {!loading && pageRows.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-10 text-center text-zinc-400">
                  No requests match your filters.
                </td>
              </tr>
            )}
            {loading && (
              <tr>
                <td colSpan={7} className="px-4 py-10 text-center text-zinc-400">
                  Loading…
                </td>
              </tr>
            )}
          </tbody>
        </table>

        <div className="flex items-center justify-between border-t border-zinc-200 px-4 py-3 text-sm">
          <span className="text-zinc-500">
            {rows.length} request{rows.length === 1 ? "" : "s"}
          </span>
          <div className="flex gap-2">
            <button
              disabled={page === 0}
              onClick={() => setPage((p) => p - 1)}
              className="rounded-lg border border-zinc-300 px-3 py-1.5 disabled:opacity-40"
            >
              Previous
            </button>
            <span className="px-2 py-1.5 text-zinc-500">
              {page + 1} / {totalPages}
            </span>
            <button
              disabled={page >= totalPages - 1}
              onClick={() => setPage((p) => p + 1)}
              className="rounded-lg border border-zinc-300 px-3 py-1.5 disabled:opacity-40"
            >
              Next
            </button>
          </div>
        </div>
      </div>

      {selected && (
        <DetailDrawer
          request={selected}
          agents={agents}
          history={history}
          busy={busy}
          onClose={() => setSelected(null)}
          onAssign={assignAgent}
          onStatus={updateStatus}
        />
      )}
    </div>
  );
}

function DetailDrawer({
  request,
  agents,
  history,
  busy,
  onClose,
  onAssign,
  onStatus,
}: {
  request: ServiceRequest;
  agents: Profile[];
  history: HistoryEntry[];
  busy: boolean;
  onClose: () => void;
  onAssign: (agentId: string) => void;
  onStatus: (to: Status) => void;
}) {
  const next = TRANSITIONS[request.status].filter((s) => s !== "assigned");

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-black/30" onClick={onClose} />
      <div className="relative w-full max-w-lg bg-white h-full overflow-y-auto shadow-2xl">
        <div className="sticky top-0 bg-white border-b border-zinc-200 px-6 py-4 flex items-start justify-between">
          <div>
            <p className="font-mono text-sm font-semibold">{request.request_id}</p>
            <p className="text-sm text-zinc-500">
              {request.services?.name ?? "Service"}
            </p>
          </div>
          <button
            onClick={onClose}
            className="rounded-lg border border-zinc-300 px-3 py-1.5 text-sm hover:bg-zinc-50"
          >
            Close
          </button>
        </div>

        <div className="p-6 space-y-6">
          <div className="flex gap-2">
            <span
              className={`rounded-md px-2 py-1 text-xs font-medium ${STATUS_COLORS[request.status]}`}
            >
              {STATUS_LABELS[request.status]}
            </span>
            <span
              className={`rounded-md px-2 py-1 text-xs font-medium ${PRIORITY_COLORS[request.priority]}`}
            >
              {request.priority} priority
            </span>
          </div>

          <dl className="grid grid-cols-3 gap-y-3 text-sm">
            <dt className="text-zinc-500">Customer</dt>
            <dd className="col-span-2">{request.customer?.full_name ?? "—"}</dd>
            <dt className="text-zinc-500">Agent</dt>
            <dd className="col-span-2">{request.agent?.full_name ?? "Unassigned"}</dd>
            <dt className="text-zinc-500">Preferred</dt>
            <dd className="col-span-2">{formatDateTime(request.preferred_at)}</dd>
            <dt className="text-zinc-500">Address</dt>
            <dd className="col-span-2">{request.address}</dd>
            <dt className="text-zinc-500">Created</dt>
            <dd className="col-span-2">{formatDateTime(request.created_at)}</dd>
          </dl>

          <div>
            <p className="text-xs font-medium text-zinc-500 mb-1">Description</p>
            <p className="text-sm whitespace-pre-wrap rounded-lg bg-zinc-50 p-3">
              {request.description}
            </p>
            {request.cancel_reason && (
              <p className="mt-2 text-sm text-red-600">
                Cancel reason: {request.cancel_reason}
              </p>
            )}
          </div>

          <div>
            <p className="text-xs font-medium text-zinc-500 mb-2">Assign agent</p>
            <div className="flex gap-2">
              <select
                defaultValue={request.agent_id ?? ""}
                disabled={busy}
                onChange={(e) => e.target.value && onAssign(e.target.value)}
                className="flex-1 rounded-lg border border-zinc-300 px-3 py-2 text-sm disabled:opacity-60"
              >
                <option value="" disabled>
                  Select an agent…
                </option>
                {agents.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.full_name}
                  </option>
                ))}
              </select>
            </div>
            {!["created", "assigned"].includes(request.status) && (
              <p className="mt-1 text-xs text-zinc-400">
                Assignment is only possible while a request is new or assigned.
              </p>
            )}
          </div>

          <div>
            <p className="text-xs font-medium text-zinc-500 mb-2">Update status</p>
            {next.length === 0 ? (
              <p className="text-sm text-zinc-400">
                No further transitions from {STATUS_LABELS[request.status]}.
              </p>
            ) : (
              <div className="flex flex-wrap gap-2">
                {next.map((s) => (
                  <button
                    key={s}
                    disabled={busy}
                    onClick={() => onStatus(s)}
                    className={`rounded-lg px-3 py-2 text-sm font-medium disabled:opacity-60 ${
                      s === "cancelled"
                        ? "border border-red-200 text-red-600 hover:bg-red-50"
                        : "bg-blue-600 text-white hover:bg-blue-700"
                    }`}
                  >
                    {s === "cancelled" ? "Cancel request" : STATUS_LABELS[s]}
                  </button>
                ))}
              </div>
            )}
          </div>

          <div>
            <p className="text-xs font-medium text-zinc-500 mb-2">Status history</p>
            {history.length === 0 ? (
              <p className="text-sm text-zinc-400">No history yet.</p>
            ) : (
              <ol className="space-y-3">
                {[...history].reverse().map((h, i) => (
                  <li key={i} className="border-l-2 border-zinc-200 pl-3">
                    <p className="text-sm font-medium">
                      {h.from_status
                        ? `${STATUS_LABELS[h.from_status]} → ${STATUS_LABELS[h.to_status]}`
                        : STATUS_LABELS[h.to_status]}
                    </p>
                    {h.note && <p className="text-sm text-zinc-600">{h.note}</p>}
                    <p className="text-xs text-zinc-400">
                      {h.changed_by_user?.full_name ?? "System"} ·{" "}
                      {formatDateTime(h.created_at)}
                    </p>
                  </li>
                ))}
              </ol>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
