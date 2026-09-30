"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Profile } from "@/lib/types";
import { formatDate, friendlyError, initials, rpcDenial } from "@/lib/format";

export default function CustomersPage() {
  const [rows, setRows] = useState<Profile[]>([]);
  const [counts, setCounts] = useState<Record<string, number>>({});
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
        .eq("role", "customer")
        .order("created_at", { ascending: false });
      if (err) throw err;
      setRows((data ?? []) as Profile[]);

      const { data: reqs } = await supabase
        .from("service_requests")
        .select("customer_id");
      const map: Record<string, number> = {};
      for (const r of reqs ?? []) {
        map[r.customer_id] = (map[r.customer_id] ?? 0) + 1;
      }
      setCounts(map);
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

  async function promote(profile: Profile) {
    setBusy(true);
    setNotice(null);
    setError(null);
    const supabase = createClient();
    const { data, error: err } = await supabase.rpc("admin_set_role", {
      p_user_id: profile.id,
      p_role: "agent",
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
    setNotice(
      `${profile.full_name} is now an agent — see Service agents for workload.`,
    );
    load();
  }

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold">Customers</h1>
        <p className="text-sm text-zinc-500">
          Registered customers and their request counts. Promote a customer to
          an agent, or use <strong>Service agents → Add agent</strong> to create
          a brand-new agent account.
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
              <th className="px-4 py-3 font-medium">Customer</th>
              <th className="px-4 py-3 font-medium">Email</th>
              <th className="px-4 py-3 font-medium">Phone</th>
              <th className="px-4 py-3 font-medium">Requests</th>
              <th className="px-4 py-3 font-medium">Joined</th>
              <th className="px-4 py-3 font-medium"></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((p) => (
              <tr key={p.id} className="border-b border-zinc-100 last:border-0">
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    <div className="h-8 w-8 rounded-full bg-zinc-200 grid place-items-center text-xs font-semibold">
                      {initials(p.full_name)}
                    </div>
                    {p.full_name}
                  </div>
                </td>
                <td className="px-4 py-3 text-zinc-600">{p.email}</td>
                <td className="px-4 py-3 text-zinc-600">{p.phone ?? "—"}</td>
                <td className="px-4 py-3 font-medium">{counts[p.id] ?? 0}</td>
                <td className="px-4 py-3 text-zinc-500">{formatDate(p.created_at)}</td>
                <td className="px-4 py-3 text-right">
                  <button
                    disabled={busy}
                    onClick={() => promote(p)}
                    className="rounded-lg border border-zinc-300 px-3 py-1.5 text-xs hover:bg-zinc-50 disabled:opacity-50"
                  >
                    Promote to agent
                  </button>
                </td>
              </tr>
            ))}
            {!loading && rows.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-10 text-center text-zinc-400">
                  No customers yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
