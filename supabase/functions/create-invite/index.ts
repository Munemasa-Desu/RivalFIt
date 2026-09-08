// create-invite — see docs/03-API-ARCHITECTURE.md.
// Phase 3 scope. This file is intentionally a stub with the contract sketched
// out; the schema is ready for it (see the seed and migration comments).
import { userClient, json } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const { data: userRes } = await userClient(req).auth.getUser();
  if (!userRes?.user) return new Response("unauthorized", { status: 401 });
  return json({ error: "not implemented" }, { status: 501 });
});
