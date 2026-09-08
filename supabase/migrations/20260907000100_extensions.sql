-- 0001 | Extensions
-- Supabase installs extensions into the `extensions` schema, which is already
-- on the API roles' search_path. Keeping them out of `public` means a
-- SECURITY DEFINER function pinned to `search_path = ''` never has to resolve
-- an operator it cannot see -- see the note in docs/02-DATA-MODEL.md.
--
-- Deliberately minimal: gen_random_uuid() is core in PG13+, and handle search
-- is a prefix match on a text_pattern_ops index rather than a trigram scan, so
-- nothing here is load-bearing beyond crypto helpers.

create extension if not exists pgcrypto with schema extensions;
