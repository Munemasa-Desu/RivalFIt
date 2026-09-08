// create-checkout-session
// -----------------------
// Called by the app to send a user to Stripe Checkout. Uses the caller's JWT
// to resolve the user; never trusts a client-supplied price_id.

import Stripe from "https://esm.sh/stripe@14.14.0?target=deno";
import { serviceClient, userClient, json } from "../_shared/supabase.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});
const PRICE_MONTHLY = Deno.env.get("STRIPE_PRICE_PRO_MONTHLY")!;
const PRICE_YEARLY  = Deno.env.get("STRIPE_PRICE_PRO_YEARLY")!;
const SITE_URL      = Deno.env.get("APP_DEEP_LINK_BASE") ?? "rivalfit://";

Deno.serve(async (req) => {
  const uc = userClient(req);
  const { data: userRes } = await uc.auth.getUser();
  if (!userRes?.user) return new Response("unauthorized", { status: 401 });

  const body = await req.json().catch(() => ({}));
  const cycle = body.cycle === "yearly" ? "yearly" : "monthly";
  const price = cycle === "yearly" ? PRICE_YEARLY : PRICE_MONTHLY;

  // Look up or create the Stripe customer via the service client so we can
  // write back a stripe_customer_id even for free users.
  const svc = serviceClient();
  const { data: sub } = await svc.from("subscriptions")
    .select("stripe_customer_id").eq("user_id", userRes.user.id).single();

  let customer = sub?.stripe_customer_id ?? null;
  if (!customer) {
    const cust = await stripe.customers.create({
      email: userRes.user.email ?? undefined,
      metadata: { user_id: userRes.user.id },
    });
    customer = cust.id;
    await svc.from("subscriptions").update({ stripe_customer_id: customer })
      .eq("user_id", userRes.user.id);
  }

  const session = await stripe.checkout.sessions.create({
    mode: "subscription",
    customer,
    line_items: [{ price, quantity: 1 }],
    success_url: `${SITE_URL}billing/success`,
    cancel_url:  `${SITE_URL}billing/cancel`,
    metadata: { user_id: userRes.user.id },
  });

  return json({ url: session.url });
});
