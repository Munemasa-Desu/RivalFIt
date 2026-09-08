// Head-to-Head — the flagship screen. Everything on it comes from ONE query
// against public.head_to_head, plus a live subscription to rivalry_scores so
// updates for either athlete refresh the same view.
import React from "react";
import { ScrollView, Text, View, ActivityIndicator, Pressable } from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useHeadToHead } from "@/features/rivalry/useHeadToHead";
import { useRivalryFeed } from "@/features/rivalry/useRivalryFeed";
import { Avatar } from "@/components/AvatarStack";
import { HeadToHeadBar } from "@/components/HeadToHeadBar";
import { StatRow } from "@/components/StatRow";
import { theme } from "@/lib/theme";
import { fmtDistance, fmtWeight } from "@/lib/format";
import { fmtDuration } from "@/lib/time";

const leader = (a: number, b: number) => a === b ? "tie" as const : a > b ? "me" as const : "them" as const;

export default function HeadToHeadScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { data: h, isLoading, error } = useHeadToHead(id!);
  const { data: feed } = useRivalryFeed(id!, 10);

  if (isLoading) return <Centered><ActivityIndicator color={theme.color.text} /></Centered>;
  if (error || !h) return <Centered><Text style={{ color: theme.color.textDim }}>Couldn't load rivalry.</Text></Centered>;

  return (
    <ScrollView style={{ flex: 1, backgroundColor: theme.color.bg }}
                contentContainerStyle={{ padding: theme.space(5), paddingBottom: theme.space(20) }}>

      {/* Header: both athletes */}
      <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between" }}>
        <Athlete side="me"   name={h.me_display_name ?? `@${h.me_handle}`} avatar={h.me_avatar_url}
                              streak={h.me_streak} points={h.me_week_points} />
        <Athlete side="them" name={h.them_display_name ?? `@${h.them_handle}`} avatar={h.them_avatar_url}
                              streak={h.them_streak} points={h.them_week_points} />
      </View>

      <View style={{ marginTop: theme.space(5) }}>
        <HeadToHeadBar me={h.me_week_points} them={h.them_week_points} />
        <Text style={{ color: theme.color.textDim, textAlign: "center",
                       marginTop: theme.space(2), ...theme.type.caption }}>
          THIS WEEK · {new Date(h.week_start).toLocaleDateString(undefined, { month: "short", day: "numeric" })}
        </Text>
      </View>

      {/* Comparison rows */}
      <View style={{ marginTop: theme.space(6), backgroundColor: theme.color.surface,
                     padding: theme.space(4), borderRadius: theme.radius.lg }}>
        <StatRow label="workouts"
                 me={String(h.me_week_workouts)}   them={String(h.them_week_workouts)}
                 leader={leader(h.me_week_workouts, h.them_week_workouts)} />
        <StatRow label="volume"
                 me={fmtWeight(h.me_week_volume_kg, "metric")}
                 them={fmtWeight(h.them_week_volume_kg, "metric")}
                 leader={leader(h.me_week_volume_kg, h.them_week_volume_kg)} />
        <StatRow label="distance"
                 me={fmtDistance(h.me_week_distance_m, "metric")}
                 them={fmtDistance(h.them_week_distance_m, "metric")}
                 leader={leader(h.me_week_distance_m, h.them_week_distance_m)} />
        <StatRow label="active time"
                 me={fmtDuration(h.me_week_duration_s)}
                 them={fmtDuration(h.them_week_duration_s)}
                 leader={leader(h.me_week_duration_s, h.them_week_duration_s)} />
        <StatRow label="wins this wk"
                 me={String(h.me_week_challenge_wins)} them={String(h.them_week_challenge_wins)}
                 leader={leader(h.me_week_challenge_wins, h.them_week_challenge_wins)} />
      </View>

      {/* Head-to-head record */}
      <View style={{ marginTop: theme.space(5), padding: theme.space(4),
                     borderRadius: theme.radius.lg, backgroundColor: theme.color.surface }}>
        <Text style={{ color: theme.color.textDim, ...theme.type.caption, textAlign: "center", letterSpacing: 1 }}>
          WEEKS WON
        </Text>
        <Text style={{ color: theme.color.text, ...theme.type.title, textAlign: "center", marginTop: theme.space(1) }}>
          <Text style={{ color: theme.color.me }}>{h.me_weeks_won}</Text>
          <Text style={{ color: theme.color.textDim }}>  vs  </Text>
          <Text style={{ color: theme.color.them }}>{h.them_weeks_won}</Text>
        </Text>
      </View>

      {/* Feed */}
      <Text style={{ color: theme.color.textDim, marginTop: theme.space(6),
                     ...theme.type.caption, letterSpacing: 1 }}>ACTIVITY</Text>
      {(feed ?? []).map((e: { id: number; kind: string; actor_handle: string | null; created_at: string; payload: Record<string, unknown> }) => (
        <View key={e.id} style={{ flexDirection: "row", paddingVertical: theme.space(3),
                                  borderBottomWidth: 1, borderBottomColor: theme.color.border }}>
          <Text style={{ color: theme.color.text, ...theme.type.body, flex: 1 }}>
            <Text style={{ fontWeight: "700" }}>@{e.actor_handle ?? "system"} </Text>
            {friendly(e.kind)}
          </Text>
          <Text style={{ color: theme.color.textDim, ...theme.type.caption }}>
            {new Date(e.created_at).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}
          </Text>
        </View>
      ))}

      <Pressable onPress={() => router.push({ pathname: "/(tabs)/challenges", params: { rivalryId: id } })}
                 style={{ marginTop: theme.space(6), padding: theme.space(4),
                          borderRadius: theme.radius.md, backgroundColor: theme.color.me,
                          alignItems: "center" }}>
        <Text style={{ color: theme.color.bg, ...theme.type.title }}>
          Challenge @{h.them_handle}
        </Text>
      </Pressable>
    </ScrollView>
  );
}

function Athlete({ side, name, avatar, streak, points }: {
  side: "me" | "them"; name: string; avatar: string | null; streak: number; points: number;
}) {
  const color = side === "me" ? theme.color.me : theme.color.them;
  return (
    <View style={{ alignItems: "center", flex: 1 }}>
      <Avatar url={avatar} name={name} size={72} ring={side} />
      <Text style={{ color: theme.color.text, ...theme.type.title, marginTop: theme.space(2) }}>{name}</Text>
      <Text style={{ color: theme.color.textDim, ...theme.type.caption }}>🔥 {streak}-day streak</Text>
      <Text style={{ color, ...theme.type.mono, marginTop: theme.space(2) }}>{points}</Text>
      <Text style={{ color: theme.color.textDim, ...theme.type.caption }}>points this week</Text>
    </View>
  );
}

function friendly(kind: string): string {
  switch (kind) {
    case "workout_logged":      return "logged a workout";
    case "pr_set":              return "set a new PR";
    case "lead_change":         return "took the lead this week";
    case "challenge_created":   return "started a challenge";
    case "challenge_completed": return "finished a challenge";
    case "challenge_decided":   return "won a challenge";
    case "taunt":               return "sent a taunt";
    case "period_closed":       return "week closed";
    default:                    return kind;
  }
}

function Centered({ children }: { children: React.ReactNode }) {
  return <View style={{ flex: 1, backgroundColor: theme.color.bg,
                        alignItems: "center", justifyContent: "center" }}>{children}</View>;
}
