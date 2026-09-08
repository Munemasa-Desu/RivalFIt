import { supabase } from "@/lib/supabase";
import type { HeadToHeadChallengeRow } from "@/types/domain";

export async function fetchCatalogue() {
  const { data, error } = await supabase
    .from("challenge_templates")
    .select("id, slug, name, subtitle, category, scoring_type, score_unit, requires_pro, difficulty, time_cap_s, estimated_duration_s, hero_image_url, icon")
    .not("published_at", "is", null)
    .order("category").order("difficulty");
  if (error) throw error;
  return data ?? [];
}

export async function startChallenge(args: {
  rivalryId: string; templateId: string; myId: string; deadline: Date;
}) {
  const { data, error } = await supabase.from("challenge_instances").insert({
    rivalry_id: args.rivalryId,
    template_id: args.templateId,
    created_by: args.myId,
    deadline: args.deadline.toISOString(),
  }).select().single();
  if (error) throw error;
  return data;
}

export async function fetchRace(instanceId: string): Promise<HeadToHeadChallengeRow> {
  const { data, error } = await supabase
    .from("head_to_head_challenge").select("*").eq("instance_id", instanceId).single();
  if (error) throw error;
  return data as HeadToHeadChallengeRow;
}

// The client never writes score/verified/elapsed_s (when started_at exists) —
// the trigger stamps them. It writes exactly what state transitions require.
export async function startAttempt(attemptId: string) {
  const { error } = await supabase.from("challenge_attempts")
    .update({ state: "in_progress" }).eq("id", attemptId);
  if (error) throw error;
}
export async function completeAttempt(attemptId: string) {
  const { error } = await supabase.from("challenge_attempts")
    .update({ state: "completed" }).eq("id", attemptId);
  if (error) throw error;
}
export async function logSplit(args: {
  attemptId: string; stepId: string; splitS: number;
  reps?: number; distanceM?: number; weightKg?: number; durationS?: number;
}) {
  const { error } = await supabase.from("challenge_attempt_steps").insert({
    attempt_id: args.attemptId, step_id: args.stepId, split_s: args.splitS,
    reps_done: args.reps, distance_m: args.distanceM, weight_kg: args.weightKg, duration_s: args.durationS,
  });
  if (error) throw error;
}
