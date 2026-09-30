"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Profile } from "@/lib/types";
import { initials } from "@/lib/format";

const NAV = [
  { href: "/dashboard", label: "Dashboard", icon: "▦" },
  { href: "/requests", label: "Requests", icon: "☰" },
  { href: "/customers", label: "Customers", icon: "☺" },
  { href: "/agents", label: "Agents", icon: "⚙" },
  { href: "/audit", label: "Audit log", icon: "⏱" },
];

export default function PortalLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [profile, setProfile] = useState<Profile | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase.auth.getUser().then(async ({ data: { user } }) => {
      if (!user) return;
      const { data } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", user.id)
        .maybeSingle();
      setProfile(data);
    });
  }, []);

  async function signOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <div className="min-h-screen flex">
      <aside className="w-60 shrink-0 border-r border-zinc-200 bg-white flex flex-col">
        <div className="h-16 flex items-center gap-3 px-5 border-b border-zinc-200">
          <div className="h-8 w-8 rounded-lg bg-blue-600 text-white grid place-items-center text-sm font-bold">
            Q
          </div>
          <div className="leading-tight">
            <p className="text-sm font-semibold">QuickServe</p>
            <p className="text-[11px] text-zinc-500">Admin portal</p>
          </div>
        </div>

        <nav className="flex-1 p-3 space-y-1">
          {NAV.map((item) => {
            const active = pathname.startsWith(item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition ${
                  active
                    ? "bg-blue-50 text-blue-700"
                    : "text-zinc-600 hover:bg-zinc-100"
                }`}
              >
                <span className="w-4 text-center">{item.icon}</span>
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="border-t border-zinc-200 p-3">
          <div className="flex items-center gap-3 px-2 py-2">
            <div className="h-8 w-8 rounded-full bg-zinc-200 grid place-items-center text-xs font-semibold">
              {initials(profile?.full_name)}
            </div>
            <div className="min-w-0 flex-1 leading-tight">
              <p className="truncate text-sm font-medium">
                {profile?.full_name ?? "…"}
              </p>
              <p className="truncate text-[11px] text-zinc-500">
                {profile?.email ?? ""}
              </p>
            </div>
          </div>
          <button
            onClick={signOut}
            className="mt-1 w-full rounded-lg px-3 py-2 text-left text-sm text-red-600 hover:bg-red-50"
          >
            Sign out
          </button>
        </div>
      </aside>

      <main className="flex-1 min-w-0 overflow-x-hidden">{children}</main>
    </div>
  );
}
