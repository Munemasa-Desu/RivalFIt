// send-push
// Triggered by pg_notify('rivalry_event', new_id) from rf.emit_event via a
// small LISTEN bridge (see docs/03-API-ARCHITECTURE.md §2.7). Fans out to
// Expo Push. Routing + rendering only; no business logic.
import { serviceClient, json } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const { event_id } = await req.json().catch(() => ({}));
  if (!event_id) return json({ error: "missing event_id" }, { status: 400 });

  const sb = serviceClient();
  const { data: ev } = await sb.from("rivalry_events").select("*").eq("id", event_id).single();
  if (!ev) return json({ error: "not found" }, { status: 404 });

  const { data: r } = await sb.from("rivalries").select("user_a,user_b").eq("id", ev.rivalry_id).single();
  if (!r) return json({ error: "no rivalry" }, { status: 404 });
  const receiver = (r.user_a === ev.actor_id) ? r.user_b : r.user_a;

  // TODO Phase 1/2: read the receiver's Expo push token(s) from a
  // `push_tokens` table, render copy per event kind, deep-link into the
  // right screen, POST to https://exp.host/--/api/v2/push/send.

  return json({ ok: true, sent_to: receiver, kind: ev.kind });
});
