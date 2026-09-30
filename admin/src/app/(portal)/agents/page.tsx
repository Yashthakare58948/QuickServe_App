"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { type Profile, type ServiceRequest, type Status } from "@/lib/types";
import { formatDate, friendlyError, initials, rpcDenial } from "@/lib/format";

const OPEN: Status[] = ["created", "assigned", "accepted", "in_progress"];

export default function AgentsPage() {
  const [rows, setRows] = useState<Profile[]>([]);
  const [requests, setRequests] = useState<ServiceRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const supabase = createClient();
    try {
      const { data, error: err } = await supabase
        .from("profiles")
        .select("*")
        .eq("role", "agent")
        .order("full_name");
      if (err) throw err;
      setRows((data ?? []) as Profile[]);

      const { data: reqs, error: reqErr } = await supabase
        .from("service_requests")
        .select("id, status, agent_id");
      if (reqErr) throw reqErr;
      setRequests((reqs ?? []) as unknown as ServiceRequest[]);
      setError(null);
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // Mount-time data fetch: load() only sets state after its first await.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  async function promote(profile: Profile, role: "agent" | "customer") {
    setBusy(true);
    setNotice(null);
    setError(null);
    const supabase = createClient();
    const { data, error: err } = await supabase.rpc("admin_set_role", {
      p_user_id: profile.id,
      p_role: role,
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
    setNotice(`${profile.full_name} is now a ${role}`);
    load();
  }

  const openCount = (agentId: string) =>
    requests.filter((r) => r.agent_id === agentId && OPEN.includes(r.status)).length;
  const doneCount = (agentId: string) =>
    requests.filter((r) => r.agent_id === agentId && r.status === "completed").length;

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold">Service agents</h1>
        <p className="text-sm text-zinc-500">
          Workload per agent. Use <strong>Customers</strong> → promote a user to agent if you
          need more.
        </p>
      </div>

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>
      )}
      {notice && (
        <div className="mb-4 rounded-lg bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          {notice}
        </div>
      )}

      <div className="rounded-xl border border-zinc-200 bg-white overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-zinc-500 border-b border-zinc-200 bg-zinc-50">
              <th className="px-4 py-3 font-medium">Agent</th>
              <th className="px-4 py-3 font-medium">Email</th>
              <th className="px-4 py-3 font-medium">Open jobs</th>
              <th className="px-4 py-3 font-medium">Completed</th>
              <th className="px-4 py-3 font-medium">Joined</th>
              <th className="px-4 py-3 font-medium"></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((p) => (
              <tr key={p.id} className="border-b border-zinc-100 last:border-0">
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    <div className="h-8 w-8 rounded-full bg-blue-100 text-blue-700 grid place-items-center text-xs font-semibold">
                      {initials(p.full_name)}
                    </div>
                    {p.full_name}
                  </div>
                </td>
                <td className="px-4 py-3 text-zinc-600">{p.email}</td>
                <td className="px-4 py-3 font-medium">{openCount(p.id)}</td>
                <td className="px-4 py-3 font-medium text-emerald-600">
                  {doneCount(p.id)}
                </td>
                <td className="px-4 py-3 text-zinc-500">{formatDate(p.created_at)}</td>
                <td className="px-4 py-3 text-right">
                  <button
                    disabled={busy}
                    onClick={() => promote(p, "customer")}
                    className="rounded-lg border border-zinc-300 px-3 py-1.5 text-xs hover:bg-zinc-50 disabled:opacity-50"
                  >
                    Demote to customer
                  </button>
                </td>
              </tr>
            ))}
            {!loading && rows.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-10 text-center text-zinc-400">
                  No agents yet. Promote a user from the Customers page.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
