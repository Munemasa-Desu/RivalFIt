// create-billing-portal — thin wrapper to open Stripe's portal for the caller.
import Stripe from "https://esm.sh/stripe@14.14.0?target=deno";
import { serviceClient, userClient, json } from "../_shared/supabase.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});
const RETURN_URL = Deno.env.get("APP_DEEP_LINK_BASE") ?? "rivalfit://";

Deno.serve(async (req) => {
  const { data: userRes } = await userClient(req).auth.getUser();
  if (!userRes?.user) return new Response("unauthorized", { status: 401 });

  const svc = serviceClient();
  const { data: sub } = await svc.from("subscriptions")
    .select("stripe_customer_id").eq("user_id", userRes.user.id).single();
  if (!sub?.stripe_customer_id) return new Response("no stripe customer", { status: 404 });

  const portal = await stripe.billingPortal.sessions.create({
    customer: sub.stripe_customer_id,
    return_url: `${RETURN_URL}me`,
  });
  return json({ url: portal.url });
});
