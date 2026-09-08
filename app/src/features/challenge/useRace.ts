import { useEffect } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/lib/supabase";
import { fetchRace } from "./challenge.api";

export function useRace(instanceId: string) {
  const qc = useQueryClient();
  const key = ["race", instanceId];
  const q = useQuery({ queryKey: key, queryFn: () => fetchRace(instanceId), refetchInterval: 5_000 });

  useEffect(() => {
    const ch = supabase.channel(`race:${instanceId}`)
      .on("postgres_changes",
          { event: "*", schema: "public", table: "challenge_attempts", filter: `instance_id=eq.${instanceId}` },
          () => qc.invalidateQueries({ queryKey: key }))
      .on("postgres_changes",
          { event: "INSERT", schema: "public", table: "challenge_attempt_steps" },
          () => qc.invalidateQueries({ queryKey: key }))
      .on("postgres_changes",
          { event: "UPDATE", schema: "public", table: "challenge_instances", filter: `id=eq.${instanceId}` },
          () => qc.invalidateQueries({ queryKey: key }))
      .subscribe();
    return () => { void supabase.removeChannel(ch); };
  }, [instanceId, qc]);

  return q;
}
