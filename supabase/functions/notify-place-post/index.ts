// Рассылка FCM подписчикам заведения. Допишите отправку в FCM при наличии ключей.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";
    const body = await req.json().catch(() => ({}));
    const postId = body?.post_id as string | undefined;
    if (!postId || !supabaseUrl || !anon || !authHeader) {
      return new Response(JSON.stringify({ error: "bad_request" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const userClient = createClient(supabaseUrl, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: u } = await userClient.auth.getUser();
    const uid = u.user?.id;
    if (!uid) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const { data: post, error: pe } = await userClient
      .from("place_posts")
      .select("id, place_id, content, notify_subscribers")
      .eq("id", postId)
      .maybeSingle();
    if (pe || !post || !post.notify_subscribers) {
      return new Response(JSON.stringify({ ok: false, reason: "no_notify" }), {
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const placeId = post.place_id as string;

    const { data: meProf } = await userClient
      .from("profiles")
      .select("is_admin")
      .eq("id", uid)
      .maybeSingle();
    let allowed = meProf?.is_admin === true;

    if (!allowed) {
      const { data: modRow } = await userClient
        .from("place_moderators")
        .select("user_id")
        .eq("place_id", placeId)
        .eq("user_id", uid)
        .maybeSingle();
      allowed = modRow != null;
    }
    if (!allowed) {
      const { data: pl } = await userClient
        .from("places")
        .select("owner_id")
        .eq("id", placeId)
        .maybeSingle();
      allowed = pl?.owner_id === uid;
    }

    if (!allowed) {
      return new Response(JSON.stringify({ error: "forbidden" }), {
        status: 403,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    if (!service) {
      return new Response(
        JSON.stringify({
          ok: true,
          skipped: true,
          message: "SUPABASE_SERVICE_ROLE_KEY not set",
        }),
        { headers: { ...cors, "Content-Type": "application/json" } },
      );
    }

    const admin = createClient(supabaseUrl, service);
    const { data: subs } = await admin
      .from("place_subscriptions")
      .select("user_id")
      .eq("place_id", placeId);
    const userIds = (subs ?? []).map((s: { user_id: string }) => s.user_id);
    if (userIds.length === 0) {
      return new Response(JSON.stringify({ ok: true, recipients: 0 }), {
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const { data: profiles } = await admin
      .from("profiles")
      .select("fcm_token, notifications_enabled")
      .in("id", userIds);
    const tokens = (profiles ?? [])
      .filter(
        (p: { fcm_token?: string; notifications_enabled?: boolean }) =>
          p.notifications_enabled !== false &&
          p.fcm_token &&
          String(p.fcm_token).length > 10,
      )
      .map((p: { fcm_token: string }) => p.fcm_token);

    return new Response(
      JSON.stringify({
        ok: true,
        recipient_tokens: tokens.length,
        hint: "Подключите отправку FCM по токенам",
      }),
      { headers: { ...cors, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
