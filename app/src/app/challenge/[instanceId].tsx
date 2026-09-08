// Race view — two lanes, live splits.
import React from "react";
import { View, Text, ScrollView, Pressable, ActivityIndicator } from "react-native";
import { useLocalSearchParams } from "expo-router";
import { useRace } from "@/features/challenge/useRace";
import { completeAttempt, startAttempt } from "@/features/challenge/challenge.api";
import { RaceLane } from "@/components/RaceLane";
import { theme } from "@/lib/theme";
import { fmtDuration } from "@/lib/time";

export default function ChallengeRaceScreen() {
  const { instanceId } = useLocalSearchParams<{ instanceId: string }>();
  const { data, isLoading } = useRace(instanceId!);

  if (isLoading || !data) {
    return <View style={{ flex:1, backgroundColor: theme.color.bg,
                          alignItems: "center", justifyContent: "center" }}>
      <ActivityIndicator color={theme.color.text} />
    </View>;
  }

  const gap = (data.me_elapsed_s ?? 0) - (data.them_elapsed_s ?? 0);
  const decided = data.state === "decided" || data.state === "expired";

  return (
    <ScrollView style={{ flex: 1, backgroundColor: theme.color.bg }}
                contentContainerStyle={{ padding: theme.space(4) }}>
      <Text style={{ color: theme.color.textDim, ...theme.type.caption, letterSpacing: 1 }}>
        {data.category.toUpperCase()} · {data.state.toUpperCase()}
      </Text>
      <Text style={{ color: theme.color.text, ...theme.type.title, marginTop: theme.space(1) }}>
        {data.template_name}
      </Text>

      <View style={{ flexDirection: "row", marginTop: theme.space(4), backgroundColor: theme.color.surface,
                     borderRadius: theme.radius.lg }}>
        <RaceLane side="me"   name="You"    avatarUrl={null}
                  state={data.me_state}   elapsedS={data.me_elapsed_s}
                  stepsDone={data.me_steps_done}   score={data.me_score}   unit={data.score_unit} />
        <View style={{ width: 1, backgroundColor: theme.color.border }} />
        <RaceLane side="them" name="Rival" avatarUrl={null}
                  state={data.them_state} elapsedS={data.them_elapsed_s}
                  stepsDone={data.them_steps_done} score={data.them_score} unit={data.score_unit} />
      </View>

      {!decided && (data.me_elapsed_s != null || data.them_elapsed_s != null) && (
        <Text style={{ color: gap < 0 ? theme.color.me : theme.color.them,
                       textAlign: "center", marginTop: theme.space(4), ...theme.type.title }}>
          {gap === 0 ? "Neck and neck" :
           gap < 0  ? `You're ${fmtDuration(-gap)} ahead`
                    : `You're ${fmtDuration(gap)} behind`}
        </Text>
      )}

      {decided && (
        <Text style={{ color: data.winner_user_id === data.me_id ? theme.color.win : theme.color.loss,
                       textAlign: "center", marginTop: theme.space(6), ...theme.type.display }}>
          {data.winner_user_id === data.me_id ? "You win" :
           data.winner_user_id                ? "Rival wins"
                                              : "Draw"}
        </Text>
      )}

      {!decided && data.me_state === "not_started" && (
        <Pressable onPress={() => startAttempt(/* attempt id from a separate fetch */"")}
                   style={{ marginTop: theme.space(6), padding: theme.space(4),
                            borderRadius: theme.radius.md, backgroundColor: theme.color.me,
                            alignItems: "center" }}>
          <Text style={{ color: theme.color.bg, ...theme.type.title }}>Start</Text>
        </Pressable>
      )}
      {!decided && data.me_state === "in_progress" && (
        <Pressable onPress={() => completeAttempt("")}
                   style={{ marginTop: theme.space(6), padding: theme.space(4),
                            borderRadius: theme.radius.md, backgroundColor: theme.color.win,
                            alignItems: "center" }}>
          <Text style={{ color: theme.color.bg, ...theme.type.title }}>Finish</Text>
        </Pressable>
      )}
    </ScrollView>
  );
}
