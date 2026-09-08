// Mirror of rf.period_start. The DB is authoritative; keep this in lockstep
// so weekly-boundary UI never disagrees with the scoreboard.
export function weekStartUTC(at = new Date()): Date {
  const d = new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate()));
  // Postgres date_trunc('week') is Monday-based; JS getUTCDay is 0..6, Sun=0.
  const dow = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - dow);
  return d;
}
export function monthStartUTC(at = new Date()): Date {
  return new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), 1));
}
export function fmtDuration(seconds: number): string {
  const s = Math.max(0, Math.round(seconds));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  return h > 0 ? `${h}:${String(m).padStart(2,"0")}:${String(r).padStart(2,"0")}`
               : `${m}:${String(r).padStart(2,"0")}`;
}
