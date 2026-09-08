import { useEffect } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/lib/supabase";
import { fetchHeadToHead } from "./rivalry.api";

// Reads head_to_head + subscribes to rivalry_scores changes. RLS on the
// underlying tables filters the channel — we only receive scoreboard rows
// for rivalries we participate in.
export function useHeadToHead(rivalryId: string) {
  const qc = useQueryClient();
  const key = ["head_to_head", rivalryId];
  const query = useQuery({ queryKey: key, queryFn: () => fetchHeadToHead(rivalryId) });

  useEffect(() => {
    const channel = supabase.channel(`h2h:${rivalryId}`)
      .on("postgres_changes",
          { event: "*", schema: "public", table: "rivalry_scores", filter: `rivalry_id=eq.${rivalryId}` },
          () => qc.invalidateQueries({ queryKey: key }))
      .on("postgres_changes",
          { event: "INSERT", schema: "public", table: "rivalry_events", filter: `rivalry_id=eq.${rivalryId}` },
          () => qc.invalidateQueries({ queryKey: ["rivalry_feed", rivalryId] }))
      .subscribe();

    return () => { void supabase.removeChannel(channel); };
  }, [rivalryId, qc]);

  return query;
}
