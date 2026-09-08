// stripe-webhook
// -------------
// Runs on: Stripe → /functions/v1/stripe-webhook (unauthenticated; we verify
// the Stripe signature ourselves).
// Idempotency: primary key on stripe_events.event_id.
// Never trust the request body until constructEventAsync succeeds.

import Stripe from "https://esm.sh/stripe@14.14.0?target=deno";
import { serviceClient, json } from "../_shared/supabase.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});
const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const sig = req.headers.get("Stripe-Signature") ?? "";
  const raw = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(raw, sig, webhookSecret);
  } catch (err) {
    return new Response(`bad signature: ${err.message}`, { status: 400 });
  }

  const sb = serviceClient();

  // Idempotency: if this event is already recorded, we're done.
  const { error: dupErr } = await sb.from("stripe_events")
    .insert({ event_id: event.id, type: event.type, payload: event as unknown as object });
  if (dupErr && dupErr.code === "23505") return json({ received: true, replayed: true });
  if (dupErr) return json({ error: dupErr.message }, { status: 500 });

  try {
    switch (event.type) {
      case "checkout.session.completed":
      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted":
        // TODO Phase 3: derive user_id from checkout.session.metadata.user_id
        // or from subscriptions[i].customer via a Stripe
        // customer.metadata.user_id; upsert public.subscriptions with tier,
        // price_id, status, current_period_end, cancel_at_period_end,
        // trial_end.
        break;
      case "invoice.payment_failed":
        // TODO Phase 3: downgrade tier to 'free' once past the grace window.
        break;
    }
    await sb.from("stripe_events").update({ processed_at: new Date().toISOString() })
      .eq("event_id", event.id);
  } catch (err) {
    await sb.from("stripe_events").update({ error: String(err) }).eq("event_id", event.id);
    return json({ error: String(err) }, { status: 500 });
  }

  return json({ received: true });
});
