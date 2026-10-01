-- Runs sync-to-kit every 10 minutes.
-- Before running this file:
--   1. Enable the pg_cron and pg_net extensions (Database → Extensions).
--   2. Replace YOUR-PROJECT-REF below with your project ref.
--   3. Store the same CRON_SECRET you set on the function in Vault:
--        select vault.create_secret('PASTE-THE-SAME-LONG-RANDOM-STRING', 'cron_secret');

select cron.schedule(
  'sync-to-kit',
  '*/10 * * * *',
  $$
  select net.http_post(
    url     := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/sync-to-kit',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- To stop it later:  select cron.unschedule('sync-to-kit');
