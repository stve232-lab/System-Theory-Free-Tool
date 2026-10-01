-- Challenge Pass Odds: lead capture
-- Creates the leads table and a single public function the page calls.
-- The page (anon key) can ONLY call submit_lead(). It cannot read, list,
-- update or delete anything in this table.

create extension if not exists citext;

create table if not exists public.leads (
  id                   uuid primary key default gen_random_uuid(),
  email                citext not null unique,

  -- GDPR: marketing consent is separate from unlocking the results
  marketing_consent    boolean not null default false,
  consent_at           timestamptz,
  consent_text         text,

  -- What they tested (used for segmenting emails later)
  firm                 text,
  account_size         integer,
  pass_rate            numeric(5,4),
  portfolio_pass_rate  numeric(5,4),
  used_example         boolean,
  report_trades        integer,
  tests_count          integer not null default 1,

  first_seen_at        timestamptz not null default now(),
  last_seen_at         timestamptz not null default now(),

  -- Kit sync bookkeeping (used by the sync-to-kit function)
  needs_sync           boolean not null default false,
  kit_synced_at        timestamptz,
  kit_error            text
);

create index if not exists leads_needs_sync_idx
  on public.leads (needs_sync) where needs_sync;

-- Lock the table down: RLS on, no policies, no grants to public roles.
alter table public.leads enable row level security;
revoke all on public.leads from anon, authenticated;

create or replace function public.submit_lead(
  p_email               text,
  p_consent             boolean,
  p_consent_text        text,
  p_firm                text,
  p_account_size        integer,
  p_pass_rate           numeric,
  p_portfolio_pass_rate numeric,
  p_used_example        boolean,
  p_report_trades       integer
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(p_email));
begin
  if v_email is null
     or length(v_email) > 254
     or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid email' using errcode = '22023';
  end if;

  insert into public.leads as l (
    email, marketing_consent, consent_at, consent_text,
    firm, account_size, pass_rate, portfolio_pass_rate,
    used_example, report_trades, needs_sync
  ) values (
    v_email,
    coalesce(p_consent, false),
    case when p_consent then now() end,
    case when p_consent then left(p_consent_text, 500) end,
    left(p_firm, 80),
    greatest(0, least(p_account_size, 10000000)),
    greatest(0, least(p_pass_rate, 1)),
    greatest(0, least(p_portfolio_pass_rate, 1)),
    p_used_example,
    greatest(0, least(p_report_trades, 1000000)),
    coalesce(p_consent, false)
  )
  on conflict (email) do update set
    -- consent can be given later but is never silently removed here;
    -- unsubscribes are handled by Kit
    marketing_consent   = l.marketing_consent or excluded.marketing_consent,
    consent_at          = coalesce(l.consent_at, excluded.consent_at),
    consent_text        = coalesce(l.consent_text, excluded.consent_text),
    firm                = excluded.firm,
    account_size        = excluded.account_size,
    pass_rate           = excluded.pass_rate,
    portfolio_pass_rate = excluded.portfolio_pass_rate,
    used_example        = excluded.used_example,
    report_trades       = excluded.report_trades,
    tests_count         = l.tests_count + 1,
    last_seen_at        = now(),
    needs_sync          = (l.marketing_consent or excluded.marketing_consent);
end;
$$;

revoke all on function public.submit_lead(text, boolean, text, text, integer, numeric, numeric, boolean, integer) from public;
grant execute on function public.submit_lead(text, boolean, text, text, integer, numeric, numeric, boolean, integer) to anon;
