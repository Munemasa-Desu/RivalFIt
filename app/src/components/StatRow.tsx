import React from "react";
import { Text, View } from "react-native";
import { theme } from "@/lib/theme";

interface Props { label: string; me: string; them: string; leader?: "me" | "them" | "tie"; }
export function StatRow({ label, me, them, leader = "tie" }: Props) {
  const meColor   = leader === "me"   ? theme.color.me   : theme.color.textDim;
  const themColor = leader === "them" ? theme.color.them : theme.color.textDim;
  return (
    <View style={{ flexDirection: "row", alignItems: "center", paddingVertical: theme.space(3) }}>
      <Text style={{ color: meColor, ...theme.type.body, flex: 1, textAlign: "left",
                     fontWeight: leader === "me" ? "700" : "400" }}>{me}</Text>
      <Text style={{ color: theme.color.textDim, ...theme.type.caption, width: 120, textAlign: "center" }}>
        {label}
      </Text>
      <Text style={{ color: themColor, ...theme.type.body, flex: 1, textAlign: "right",
                     fontWeight: leader === "them" ? "700" : "400" }}>{them}</Text>
    </View>
  );
}
