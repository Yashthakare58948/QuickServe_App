"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { type Profile, type ServiceRequest, type Status } from "@/lib/types";
import { formatDate, friendlyError, initials, rpcDenial } from "@/lib/format";

const OPEN: Status[] = ["created", "assigned", "accepted", "in_progress"];

const EMPTY_FORM = { full_name: "", email: "", password: "", phone: "" };

export default function AgentsPage() {
  const [rows, setRows] = useState<Profile[]>([]);
  const [requests, setRequests] = useState<ServiceRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [showAdd, setShowAdd] = useState(false);
  const [form, setForm] = useState(EMPTY_FORM);
  const [creating, setCreating] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

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

  async function createAgent(e: React.FormEvent) {
    e.preventDefault();
    setFormError(null);

    const email = form.email.trim().toLowerCase();
    if (form.full_name.trim().length < 2) {
      setFormError("Full name must be at least 2 characters.");
      return;
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      setFormError("Enter a valid email address.");
      return;
    }
    if (form.password.length < 8) {
      setFormError("Password must be at least 8 characters.");
      return;
    }

    setCreating(true);
    const supabase = createClient();
    const { data, error: err } = await supabase.rpc("admin_create_agent", {
      p_email: email,
      p_password: form.password,
      p_full_name: form.full_name.trim(),
      p_phone: form.phone.trim() ? form.phone.trim() : null,
    });
    setCreating(false);

    if (err) {
      setFormError(friendlyError(err));
      return;
    }
    const denial = rpcDenial(data);
    if (denial) {
      setFormError(denial);
      return;
    }

    const created = data as Profile;
    setShowAdd(false);
    setForm(EMPTY_FORM);
    setNotice(
      `${created.full_name} can now sign in as an agent with ${created.email}`,
    );
    load();
  }

  const openCount = (agentId: string) =>
    requests.filter((r) => r.agent_id === agentId && OPEN.includes(r.status)).length;
  const doneCount = (agentId: string) =>
    requests.filter((r) => r.agent_id === agentId && r.status === "completed").length;

  return (
    <div className="p-8">
      <div className="mb-6 flex items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Service agents</h1>
          <p className="text-sm text-zinc-500">
            Workload per agent. Add new agents here, or promote an existing
            customer from the <strong>Customers</strong> page.
          </p>
        </div>
        <button
          onClick={() => {
            setFormError(null);
            setShowAdd(true);
          }}
          className="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white hover:bg-zinc-700"
        >
          + Add agent
        </button>
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
                  No agents yet — use “Add agent” above or promote a customer.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {showAdd && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div
            className="absolute inset-0 bg-black/30"
            onClick={() => !creating && setShowAdd(false)}
          />
          <form
            onSubmit={createAgent}
            className="relative w-full max-w-md rounded-xl bg-white p-6 shadow-2xl"
          >
            <div className="mb-4">
              <h2 className="text-lg font-semibold">Add agent</h2>
              <p className="text-sm text-zinc-500">
                Creates an account that can sign in immediately — no invitation
                email is sent.
              </p>
            </div>

            <div className="space-y-3">
              <label className="block">
                <span className="text-xs font-medium text-zinc-500">Full name</span>
                <input
                  value={form.full_name}
                  onChange={(e) => setForm({ ...form, full_name: e.target.value })}
                  autoFocus
                  required
                  className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                />
              </label>
              <label className="block">
                <span className="text-xs font-medium text-zinc-500">Email</span>
                <input
                  type="email"
                  value={form.email}
                  onChange={(e) => setForm({ ...form, email: e.target.value })}
                  required
                  className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                />
              </label>
              <label className="block">
                <span className="text-xs font-medium text-zinc-500">
                  Password (min 8 characters)
                </span>
                <input
                  type="password"
                  value={form.password}
                  onChange={(e) => setForm({ ...form, password: e.target.value })}
                  required
                  autoComplete="new-password"
                  className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                />
              </label>
              <label className="block">
                <span className="text-xs font-medium text-zinc-500">
                  Phone (optional)
                </span>
                <input
                  value={form.phone}
                  onChange={(e) => setForm({ ...form, phone: e.target.value })}
                  className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                />
              </label>
            </div>

            {formError && (
              <p className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
                {formError}
              </p>
            )}

            <div className="mt-5 flex justify-end gap-2">
              <button
                type="button"
                disabled={creating}
                onClick={() => setShowAdd(false)}
                className="rounded-lg border border-zinc-300 px-4 py-2 text-sm hover:bg-zinc-50 disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={creating}
                className="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white hover:bg-zinc-700 disabled:opacity-50"
              >
                {creating ? "Creating…" : "Create agent"}
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
