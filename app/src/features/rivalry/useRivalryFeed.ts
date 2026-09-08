import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/lib/supabase";

export function useRivalryFeed(rivalryId: string, limit = 50) {
  return useQuery({
    queryKey: ["rivalry_feed", rivalryId],
    queryFn: async () => {
      const { data, error } = await supabase.from("rivalry_feed").select("*")
        .eq("rivalry_id", rivalryId).order("created_at", { ascending: false }).limit(limit);
      if (error) throw error;
      return data ?? [];
    },
  });
}
