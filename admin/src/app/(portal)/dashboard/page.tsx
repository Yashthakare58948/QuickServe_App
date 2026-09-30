"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import {
  STATUS_LABELS,
  STATUS_COLORS,
  type DashboardStats,
  type ServiceRequest,
} from "@/lib/types";
import { friendlyError, formatDateTime, rpcDenial } from "@/lib/format";

const CARDS: Array<{ key: keyof DashboardStats; label: string; tone?: string }> = [
  { key: "total", label: "Total requests", tone: "text-zinc-900" },
  { key: "created", label: "New", tone: "text-zinc-700" },
  { key: "assigned", label: "Assigned", tone: "text-blue-600" },
  { key: "accepted", label: "Accepted", tone: "text-violet-600" },
  { key: "in_progress", label: "In progress", tone: "text-amber-600" },
  { key: "completed", label: "Completed", tone: "text-emerald-600" },
  { key: "cancelled", label: "Cancelled", tone: "text-red-600" },
  { key: "open_high", label: "High-priority open", tone: "text-red-600" },
];

export default function DashboardPage() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [recent, setRecent] = useState<ServiceRequest[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function load() {
    const supabase = createClient();
    try {
      const { data, error: err } = await supabase.rpc("dashboard_stats");
      if (err) throw err;
      const denial = rpcDenial(data);
      if (denial) throw new Error(denial);
      setStats(data as DashboardStats);
      setError(null);

      const { data: rows, error: reqErr } = await supabase
        .from("service_requests")
        .select(
          `id, request_id, status, priority, created_at, address,
           services(name), customer:profiles!service_requests_customer_id_fkey(full_name)`,
        )
        .order("created_at", { ascending: false })
        .limit(6);
      if (reqErr) throw reqErr;
      setRecent((rows ?? []) as unknown as ServiceRequest[]);
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setLoading(false);
    }
  }

  function refresh() {
    setLoading(true);
    setError(null);
    void load();
  }

  useEffect(() => {
    // Mount-time data fetch: load() only sets state after its first await.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, []);

  return (
    <div className="p-8">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-semibold">Dashboard</h1>
          <p className="text-sm text-zinc-500">
            Operational overview of all service requests.
          </p>
        </div>
        <button
          onClick={refresh}
          className="rounded-lg border border-zinc-300 bg-white px-4 py-2 text-sm font-medium hover:bg-zinc-50"
        >
          {loading ? "Refreshing…" : "Refresh"}
        </button>
      </div>

      {error && (
        <div className="mb-6 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      )}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        {CARDS.map((card) => (
          <div
            key={card.key}
            className="rounded-xl border border-zinc-200 bg-white p-4"
          >
            <p className="text-xs text-zinc-500">{card.label}</p>
            <p className={`mt-1 text-3xl font-semibold ${card.tone ?? ""}`}>
              {stats ? stats[card.key] : "—"}
            </p>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-3 gap-4 mb-8">
        <div className="rounded-xl border border-zinc-200 bg-white p-4">
          <p className="text-xs text-zinc-500">Customers</p>
          <p className="mt-1 text-2xl font-semibold">
            {stats?.customers ?? "—"}
          </p>
        </div>
        <div className="rounded-xl border border-zinc-200 bg-white p-4">
          <p className="text-xs text-zinc-500">Agents</p>
          <p className="mt-1 text-2xl font-semibold">{stats?.agents ?? "—"}</p>
        </div>
        <div className="rounded-xl border border-zinc-200 bg-white p-4 flex items-end">
          <Link
            href="/requests"
            className="text-sm font-medium text-blue-600 hover:underline"
          >
            Manage all requests →
          </Link>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-200 bg-white">
        <div className="px-5 py-4 border-b border-zinc-200 flex items-center justify-between">
          <h2 className="font-semibold">Latest requests</h2>
          <Link href="/requests" className="text-sm text-blue-600 hover:underline">
            View all
          </Link>
        </div>
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-zinc-500 border-b border-zinc-100">
              <th className="px-5 py-3 font-medium">Request</th>
              <th className="px-5 py-3 font-medium">Customer</th>
              <th className="px-5 py-3 font-medium">Service</th>
              <th className="px-5 py-3 font-medium">Status</th>
              <th className="px-5 py-3 font-medium">Created</th>
            </tr>
          </thead>
          <tbody>
            {recent.map((r) => (
              <tr key={r.id} className="border-b border-zinc-50 last:border-0">
                <td className="px-5 py-3 font-mono text-xs">{r.request_id}</td>
                <td className="px-5 py-3">{r.customer?.full_name ?? "—"}</td>
                <td className="px-5 py-3">{r.services?.name ?? "—"}</td>
                <td className="px-5 py-3">
                  <span
                    className={`rounded-md px-2 py-1 text-xs font-medium ${STATUS_COLORS[r.status]}`}
                  >
                    {STATUS_LABELS[r.status]}
                  </span>
                </td>
                <td className="px-5 py-3 text-zinc-500">
                  {formatDateTime(r.created_at)}
                </td>
              </tr>
            ))}
            {!loading && recent.length === 0 && (
              <tr>
                <td colSpan={5} className="px-5 py-8 text-center text-zinc-400">
                  No requests yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
