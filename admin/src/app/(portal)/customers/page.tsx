"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Profile } from "@/lib/types";
import { formatDate, friendlyError, initials } from "@/lib/format";

export default function CustomersPage() {
  const [rows, setRows] = useState<Profile[]>([]);
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
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
    })();
  }, []);

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold">Customers</h1>
        <p className="text-sm text-zinc-500">Registered customers and their request counts.</p>
      </div>

      {error && (
        <div className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>
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
              </tr>
            ))}
            {!loading && rows.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-10 text-center text-zinc-400">
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
