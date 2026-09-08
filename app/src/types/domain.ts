// Hand-authored view models. Generated Postgres types live in database.ts.
export type UnitSystem = "metric" | "imperial";
export type RivalryStatus = "pending" | "active" | "paused" | "declined" | "ended";
export type ScoringType = "time_asc" | "reps_desc" | "load_desc" | "distance_desc" | "points_desc";
export type ChallengeState = "open" | "live" | "decided" | "expired" | "cancelled";
export type AttemptState = "not_started" | "in_progress" | "completed" | "dnf" | "abandoned";

// Shape of one row of public.head_to_head; matches the view exactly.
export interface HeadToHeadRow {
  rivalry_id: string;
  status: RivalryStatus;
  me_id: string;
  them_id: string;
  me_handle: string; me_display_name: string | null; me_avatar_url: string | null;
  me_streak: number; me_total_workouts: number;
  them_handle: string; them_display_name: string | null; them_avatar_url: string | null;
  them_streak: number; them_total_workouts: number;
  me_week_points: number; them_week_points: number;
  me_week_workouts: number; them_week_workouts: number;
  me_week_volume_kg: number; them_week_volume_kg: number;
  me_week_distance_m: number; them_week_distance_m: number;
  me_week_duration_s: number; them_week_duration_s: number;
  me_week_challenge_wins: number; them_week_challenge_wins: number;
  me_all_points: number; them_all_points: number;
  me_all_challenge_wins: number; them_all_challenge_wins: number;
  me_weeks_won: number; them_weeks_won: number;
  week_start: string;
}

export interface HeadToHeadChallengeRow {
  instance_id: string;
  rivalry_id: string;
  template_id: string;
  template_version: number;
  state: ChallengeState;
  opens_at: string;
  deadline: string;
  winner_user_id: string | null;
  decision_reason: string | null;
  template_name: string;
  category: string;
  scoring_type: ScoringType;
  score_unit: string;
  time_cap_s: number | null;
  me_id: string;
  me_state: AttemptState; me_started_at: string | null; me_completed_at: string | null;
  me_elapsed_s: number | null; me_score: number | null; me_steps_done: number;
  them_id: string;
  them_state: AttemptState; them_started_at: string | null; them_completed_at: string | null;
  them_elapsed_s: number | null; them_score: number | null; them_steps_done: number;
}
