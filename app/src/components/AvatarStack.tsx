import React from "react";
import { Image, Text, View } from "react-native";
import { theme } from "@/lib/theme";

export function Avatar({ url, name, size = 72, ring }: {
  url: string | null; name: string; size?: number; ring?: "me" | "them";
}) {
  const initials = (name ?? "?").slice(0, 2).toUpperCase();
  const borderColor = ring === "me" ? theme.color.me : ring === "them" ? theme.color.them : theme.color.border;
  return (
    <View style={{ width: size, height: size, borderRadius: size / 2, borderWidth: 2,
                   borderColor, alignItems: "center", justifyContent: "center",
                   backgroundColor: theme.color.surface, overflow: "hidden" }}>
      {url ? <Image source={{ uri: url }} style={{ width: size, height: size }} />
           : <Text style={{ color: theme.color.text, ...theme.type.title }}>{initials}</Text>}
    </View>
  );
}
