// bk-storage: the only way the Balkoun client may delete or upload files in the "photos" bucket.
// verify_jwt is off because the site uses a publishable (non-JWT) key; authentication is done here
// with the site's own admin / member session tokens (bk_admin_uid / bk_member_uid).
// Deployed with the Supabase MCP deploy_edge_function tool; this copy is the source of record.
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKET = "photos";

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const deny = (why = "unauthorised") => json({ error: why }, 401);

function safePath(p: unknown): p is string {
  return typeof p === "string" && p.length > 0 && p.length < 400 && !p.includes("..") && !p.startsWith("/") && !p.includes("\\");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const { token, role, action, paths, path } = body ?? {};
  if (typeof token !== "string" || token.length < 20) return deny();

  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  let uid: string | null = null;
  let isAdmin = false;
  if (role === "admin") {
    const { data, error } = await sb.rpc("bk_admin_uid", { p_token: token });
    if (error || !data) return deny();
    uid = data as string; isAdmin = true;
  } else {
    const { data, error } = await sb.rpc("bk_member_uid", { p_token: token });
    if (error || !data) return deny();
    uid = data as string;
  }

  const list: unknown[] = action === "remove" ? (Array.isArray(paths) ? paths : []) : [path];
  if (!list.length || list.length > 200) return json({ error: "no paths" }, 400);
  for (const p of list) {
    if (!safePath(p)) return json({ error: "bad path" }, 400);
    if (isAdmin) continue;
    // members: only their own listing folders and their own avatar files
    const m = p.match(/^(photos|videos)\/listings\/(\d+)\/[^/]+$/);
    if (m) {
      const { data: l } = await sb.from("listings").select("user_id").eq("id", Number(m[1])).maybeSingle();
      if (!l || l.user_id !== uid) return deny("not yours");
      continue;
    }
    if (p.startsWith("avatars/" + uid + "-") && /^[^/]+\/[^/]+$/.test(p)) continue;
    return deny("not yours");
  }

  if (action === "remove") {
    const { data, error } = await sb.storage.from(BUCKET).remove(list as string[]);
    if (error) return json({ error: error.message }, 400);
    return json({ removed: (data ?? []).map((o: any) => o.name) });
  }
  if (action === "sign-upload") {
    const { data, error } = await sb.storage.from(BUCKET).createSignedUploadUrl(path as string, { upsert: true });
    if (error) return json({ error: error.message }, 400);
    return json({ path: data.path, token: data.token });
  }
  return json({ error: "bad action" }, 400);
});
