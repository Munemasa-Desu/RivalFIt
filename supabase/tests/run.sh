#!/bin/bash
set -euo pipefail
PGARGS="-h /var/tmp -p 55432 -U postgres -v ON_ERROR_STOP=1 -qtA"

psql $PGARGS -c "drop database if exists rivalfit_test;" -c "create database rivalfit_test;" >/dev/null 2>&1
psql $PGARGS -d rivalfit_test -c "SET client_min_messages TO WARNING" -f supabase/tests/00_supabase_stub.sql >/dev/null 2>&1
for f in supabase/migrations/*.sql supabase/seed/*.sql; do
  psql $PGARGS -d rivalfit_test -c "SET client_min_messages TO WARNING" -f "$f" >/dev/null 2>&1
done
for f in supabase/tests/[0-9]*.sql; do
  echo "→ $(basename $f)"
  psql $PGARGS -d rivalfit_test -c "SET client_min_messages TO WARNING" -f "$f" >/dev/null 2>&1 || { echo "  FAILED"; exit 1; }
done
echo "ALL TESTS PASSED"
