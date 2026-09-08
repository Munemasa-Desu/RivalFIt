import React from "react";
import { View } from "react-native";
import { theme } from "@/lib/theme";

// Single horizontal bar, split at me / (me + them). Zero-sum layout so a rival
// pulling ahead visibly eats your side of the bar.
export function HeadToHeadBar({ me, them }: { me: number; them: number }) {
  const total = Math.max(1, me + them);
  const mePct = Math.round((me / total) * 100);
  return (
    <View style={{ height: 12, borderRadius: theme.radius.pill, overflow: "hidden",
                   backgroundColor: theme.color.surfaceHi, flexDirection: "row" }}>
      <View style={{ width: `${mePct}%`, backgroundColor: theme.color.me }} />
      <View style={{ flex: 1, backgroundColor: theme.color.them }} />
    </View>
  );
}
