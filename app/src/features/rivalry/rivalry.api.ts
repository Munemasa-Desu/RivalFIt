import { supabase } from "@/lib/supabase";
import type { HeadToHeadRow } from "@/types/domain";

// A single row per rivalry. The view returns exactly the columns the screen
// renders; nothing here reshapes.
export async function fetchHeadToHead(rivalryId: string): Promise<HeadToHeadRow> {
  const { data, error } = await supabase
    .from("head_to_head")
    .select("*")
    .eq("rivalry_id", rivalryId)
    .single();
  if (error) throw error;
  return data as HeadToHeadRow;
}

export async function fetchMyActiveRivalries(): Promise<HeadToHeadRow[]> {
  const { data, error } = await supabase.from("head_to_head").select("*")
    .in("status", ["active", "paused"]);
  if (error) throw error;
  return (data ?? []) as HeadToHeadRow[];
}

// Sender never populates user_a/user_b directly with respect to normalisation
// — the DB trigger reorders them. We pass (me, target) and the server sorts.
export async function requestRivalry(myId: string, targetId: string) {
  const [user_a, user_b] = [myId, targetId].sort();
  const { data, error } = await supabase.from("rivalries").insert({
    user_a, user_b, requested_by: myId, status: "pending",
  }).select().single();
  if (error) throw error;
  return data;
}

export async function acceptRivalry(rivalryId: string) {
  const { error } = await supabase.from("rivalries").update({ status: "active" }).eq("id", rivalryId);
  if (error) throw error;
}
