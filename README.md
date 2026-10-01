# Challenge Pass Odds: setup

A free MT5 challenge simulator for thesystemtheory.com that collects emails into Supabase and, once you add a Kit API key, forwards consenting subscribers to Kit with tags.

```
index.html                                   the tool (one file, host it anywhere)
supabase/migrations/20261001000000_leads.sql leads table + submit_lead() function
supabase/functions/sync-to-kit/index.ts      forwards leads to Kit (idle until KIT_API_KEY is set)
supabase/cron_sync_to_kit.sql                runs the sync every 10 minutes
```

Use a **separate Supabase project** from your paid tool, so the free page can never touch member data.

---

## Part 1: capture emails (do this now)

**1. Create the table.** In your Supabase project, open SQL Editor, paste the contents of `supabase/migrations/20261001000000_leads.sql`, and run it.

**2. Connect the page.** Open `index.html`, search for `const CONFIG`, and fill in:

```js
supabaseUrl: 'https://YOUR-PROJECT-REF.supabase.co',   // Settings → API → Project URL
supabaseAnonKey: 'eyJ...',                             // Settings → API → anon public key
privacyUrl: 'https://thesystemtheory.com/privacy'      // your privacy policy page
```

Only use the **anon** key here. Never put the service_role key in the page.

**3. Host the page.** Any of these works:
- Base44: add a page and embed `index.html` in it, or upload it as a static page.
- Vercel or Netlify: drag the folder in and link to it from your site.
- GitHub Pages: push this folder to a repo and turn on Pages.

**4. Test it.** Open the page, enter your own email, tick the box, click "Show every firm". In Supabase go to Table Editor → `leads`. Your row should be there with `marketing_consent = true` and `needs_sync = true`.

Emails now collect in Supabase. Every consenting lead waits with `needs_sync = true` until Kit is connected.

To export anytime: Table Editor → `leads` → Export to CSV.

---

## Part 2: deploy the Kit sync (can do now, runs later)

You need the Supabase CLI (`npm i -g supabase`) and to be logged in (`supabase login`).

```bash
supabase link --project-ref YOUR-PROJECT-REF
supabase functions deploy sync-to-kit --no-verify-jwt
supabase secrets set CRON_SECRET=make-up-a-long-random-string
```

Then schedule it:
1. Database → Extensions: enable **pg_cron** and **pg_net**.
2. SQL Editor: `select vault.create_secret('the-same-long-random-string', 'cron_secret');`
3. Open `supabase/cron_sync_to_kit.sql`, replace `YOUR-PROJECT-REF`, run it.

Until a Kit key exists the function replies "KIT_API_KEY not set yet; leads are queued" and changes nothing.

---

## Part 3: switch on Kit (when you sign up)

1. In Kit: Settings → Developer → create a **v4 API key**.
2. `supabase secrets set KIT_API_KEY=your-kit-key`

That's it. Within 10 minutes, every queued lead is added to Kit with these tags:

| Tag | Use it for |
|---|---|
| `source: pass calculator` | everyone from this tool |
| `firm: FTMO · 2-Step` (etc.) | emails about the firm they tested |
| `result: likely to fail` / `coin flip` / `strong edge` | different follow-ups by result |
| `calc: own report` / `calc: example only` | people who uploaded a real EA are warmer leads |

Each run handles 20 leads. A backlog of 1,000 clears in about 8 hours. If a lead fails, the reason is saved in the `kit_error` column and it is retried on the next run.

---

## Notes

- **GDPR.** The marketing checkbox is unticked by default and separate from unlocking results. Only people who tick it are sent to Kit. The table records when they consented and the exact wording they agreed to. Mention this data in your privacy policy. Consider turning on double opt-in in Kit, since anyone can type any email into a form. (Not legal advice.)
- **Unsubscribes** happen in Kit. The sync never re-subscribes someone: it only sends leads marked `needs_sync`, which is set when they submit the form again.
- **If Supabase is down**, the visitor still sees their results. The error is logged in the browser console and that lead is lost, so check the table after launch.
- **Your portfolio data** in the page is one low/close pair per day as % of the account, shuffled, with no dates, symbols or trades.
- **Firm rules** were checked on 1 Oct 2026. Re-check them now and then; the presets are in the `FIRMS` list in `index.html`.
