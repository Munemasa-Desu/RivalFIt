import React from "react";
import { Text, View } from "react-native";
import { theme } from "@/lib/theme";
import { fmtDuration } from "@/lib/time";

export function RaceLane({
  side, name, avatarUrl, state, elapsedS, stepsDone, score, unit,
}: {
  side: "me" | "them"; name: string; avatarUrl: string | null;
  state: string; elapsedS: number | null; stepsDone: number;
  score: number | null; unit: string;
}) {
  const color = side === "me" ? theme.color.me : theme.color.them;
  const align = side === "me" ? "flex-start" : "flex-end";
  return (
    <View style={{ flex: 1, padding: theme.space(4), alignItems: align }}>
      <Text style={{ color, ...theme.type.caption, letterSpacing: 1 }}>
        {side === "me" ? "YOU" : "RIVAL"} · {state.toUpperCase()}
      </Text>
      <Text style={{ color: theme.color.text, ...theme.type.title, marginTop: theme.space(1) }}>{name}</Text>
      <Text style={{ color, ...theme.type.mono, marginTop: theme.space(2) }}>
        {fmtDuration(elapsedS ?? 0)}
      </Text>
      <Text style={{ color: theme.color.textDim, ...theme.type.caption, marginTop: theme.space(2) }}>
        Station {stepsDone}
      </Text>
      {score != null && (
        <Text style={{ color: theme.color.text, ...theme.type.body, marginTop: theme.space(2) }}>
          {Math.round(score)} {unit}
        </Text>
      )}
    </View>
  );
}
