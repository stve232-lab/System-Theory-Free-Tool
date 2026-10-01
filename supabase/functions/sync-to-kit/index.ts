// sync-to-kit: forwards consenting leads from Supabase to Kit, with tags.
//
// Safe to deploy before you have Kit: without KIT_API_KEY it does nothing
// and leads keep waiting (needs_sync = true) until you add the key.
//
// Secrets (Supabase dashboard → Edge Functions → Secrets):
//   CRON_SECRET   any long random string; the scheduler sends it as a header
//   KIT_API_KEY   your Kit v4 API key (add later)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "npm:@supabase/supabase-js@2";

const KIT = "https://api.kit.com/v4";
const BATCH = 20; // ~5 Kit calls per lead; keeps each run well under Kit's rate limit

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function band(p: number | null): string {
  if (p == null) return "unknown";
  if (p >= 0.6) return "strong edge";
  if (p >= 0.35) return "coin flip";
  return "likely to fail";
}

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return json({ error: "unauthorized" }, 401);
  }

  const kitKey = Deno.env.get("KIT_API_KEY");
  if (!kitKey) return json({ skipped: "KIT_API_KEY not set yet; leads are queued" });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data: leads, error } = await db
    .from("leads")
    .select("id,email,firm,pass_rate,used_example")
    .eq("needs_sync", true)
    .eq("marketing_consent", true)
    .order("last_seen_at", { ascending: true })
    .limit(BATCH);
  if (error) return json({ error: error.message }, 500);

  const kit = async (path: string, body: unknown) => {
    const r = await fetch(KIT + path, {
      method: "POST",
      headers: { "content-type": "application/json", "X-Kit-Api-Key": kitKey },
      body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error(`Kit ${path} ${r.status}: ${(await r.text()).slice(0, 200)}`);
    return r.json();
  };

  // Tag creation is idempotent in Kit (same name returns the existing tag)
  const tagIds = new Map<string, number>();
  const tagId = async (name: string) => {
    if (!tagIds.has(name)) tagIds.set(name, (await kit("/tags", { name })).tag.id);
    return tagIds.get(name)!;
  };

  let synced = 0, failed = 0;
  for (const lead of leads ?? []) {
    try {
      await kit("/subscribers", { email_address: lead.email, state: "active" });
      const tags = [
        "source: pass calculator",
        `firm: ${lead.firm ?? "unknown"}`,
        `result: ${band(lead.pass_rate)}`,
        lead.used_example ? "calc: example only" : "calc: own report",
      ];
      for (const t of tags) {
        await kit(`/tags/${await tagId(t)}/subscribers`, { email_address: lead.email });
      }
      await db.from("leads")
        .update({ needs_sync: false, kit_synced_at: new Date().toISOString(), kit_error: null })
        .eq("id", lead.id);
      synced++;
    } catch (e) {
      await db.from("leads").update({ kit_error: String(e).slice(0, 500) }).eq("id", lead.id);
      failed++;
    }
  }

  return json({ synced, failed, remaining_in_batch: (leads?.length ?? 0) - synced - failed });
});
