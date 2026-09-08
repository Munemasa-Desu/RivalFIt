import React from "react";
import { View, Text } from "react-native";
import { theme } from "@/lib/theme";
export default function LogScreen() {
  return (
    <View style={{ flex:1, backgroundColor: theme.color.bg, padding: 16 }}>
      <Text style={{ color: theme.color.text, ...theme.type.title }}>log</Text>
      <Text style={{ color: theme.color.textDim, marginTop: 8 }}>
        Phase-1 placeholder. See docs/05-ROADMAP.md.
      </Text>
    </View>
  );
}
