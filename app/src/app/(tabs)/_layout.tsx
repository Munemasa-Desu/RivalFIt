import React from "react";
import { Tabs } from "expo-router";
import { theme } from "@/lib/theme";

export default function Tabs_() {
  return (
    <Tabs screenOptions={{
      tabBarStyle: { backgroundColor: theme.color.surface, borderTopColor: theme.color.border },
      tabBarActiveTintColor: theme.color.me,
      tabBarInactiveTintColor: theme.color.textDim,
      headerStyle: { backgroundColor: theme.color.bg },
      headerTintColor: theme.color.text,
    }}>
      <Tabs.Screen name="index"      options={{ title: "Rivals" }} />
      <Tabs.Screen name="log"        options={{ title: "Log" }} />
      <Tabs.Screen name="challenges" options={{ title: "Challenges" }} />
      <Tabs.Screen name="me"         options={{ title: "Me" }} />
    </Tabs>
  );
}
