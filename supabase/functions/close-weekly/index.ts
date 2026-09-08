// close-weekly — cron entry, Mondays 00:05 UTC.
// Closes any week whose UTC boundary has passed; period_closed events fanned
// out by send-push.
import { serviceClient, json } from "../_shared/supabase.ts";

Deno.serve(async () => {
  const sb = serviceClient();
  const { data, error } = await sb.rpc("close_finished_weeks");
  if (error) return json({ error: error.message }, { status: 500 });
  return json({ closed: data ?? 0 });
});
