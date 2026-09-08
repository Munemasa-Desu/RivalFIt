// sweep-challenges — cron entry point. pg_cron calls this every ~5 min.
// Heavy lifting lives in the DB (rf.sweep_expired_challenges) so the deadline
// logic is testable without spinning up the runtime.
import { serviceClient, json } from "../_shared/supabase.ts";

Deno.serve(async () => {
  const sb = serviceClient();
  const { data, error } = await sb.rpc("sweep_expired_challenges");
  if (error) return json({ error: error.message }, { status: 500 });
  return json({ decided: data ?? 0 });
});
