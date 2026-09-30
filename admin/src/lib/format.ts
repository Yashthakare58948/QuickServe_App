/** Small formatting helpers shared across portal pages. */

export function formatDateTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  });
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

export function initials(name: string | null | undefined): string {
  if (!name) return "?";
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]!.toUpperCase())
    .join("");
}

/**
 * Formats a PostgREST/RPC error for display. Never leaks SQL or keys.
 */
export function friendlyError(error: unknown): string {
  const raw =
    typeof error === "string"
      ? error
      : error instanceof Error
        ? error.message
        : JSON.stringify(error ?? "Unknown error");

  if (/42501|not allowed|not permitted|admins only/i.test(raw)) {
    return "You are not authorized to perform this action.";
  }
  if (/failed to fetch|networkerror|econnrefused/i.test(raw)) {
    return "Network error — could not reach the server.";
  }
  if (/rate limit/i.test(raw)) {
    return "Too many attempts. Please wait a moment.";
  }
  if (/invalid login|invalid credentials/i.test(raw)) {
    return "Incorrect email or password.";
  }
  if (/email not confirmed/i.test(raw)) {
    return "Please confirm your email first.";
  }
  if (/already registered/i.test(raw)) {
    return "An account with this email already exists.";
  }
  // Trim very long messages (they may embed server internals).
  return raw.length > 180 ? `${raw.slice(0, 180)}…` : raw;
}
