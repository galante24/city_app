// Push при @-упоминании в комментарии к задаче. Authorization: Bearer <user JWT>.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { sendFcmLegacyToTokens } from "../_shared/fcm_legacy.ts";

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
    const fcmKey = Deno.env.get("FCM_SERVER_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";
    const body = await req.json().catch(() => ({}));
    const taskId = body?.task_id as string | undefined;
    const taskTitleRaw = (body?.task_title as string | undefined)?.trim() ?? "";
    const mentioned = body?.mentioned_user_ids as string[] | undefined;

    if (!taskId || !supabaseUrl || !anon || !authHeader) {
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

    const ids = (mentioned ?? [])
      .map((x) => String(x).trim())
      .filter((x) => x.length > 0 && x !== uid);
    if (ids.length === 0) {
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    if (!service) {
      return new Response(
        JSON.stringify({ ok: true, skipped: true, message: "no service key" }),
        { headers: { ...cors, "Content-Type": "application/json" } },
      );
    }

    const admin = createClient(supabaseUrl, service);
    const { data: recent } = await admin
      .from("task_comments")
      .select("id")
      .eq("task_id", taskId)
      .eq("user_id", uid)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!recent?.id) {
      return new Response(JSON.stringify({ error: "forbidden" }), {
        status: 403,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const title =
      taskTitleRaw.length > 0 ? taskTitleRaw.slice(0, 120) : "Задача";
    const bodyText =
      `Вас упомянули в обсуждении задачи «${title}»`.slice(0, 180);

    const { data: profiles } = await admin
      .from("profiles")
      .select("id, fcm_token, notifications_enabled")
      .in("id", ids);

    const tokens = (profiles ?? [])
      .filter(
        (p: { fcm_token?: string; notifications_enabled?: boolean }) =>
          p.notifications_enabled !== false &&
          p.fcm_token &&
          String(p.fcm_token).length > 10,
      )
      .map((p: { fcm_token: string }) => p.fcm_token);

    if (!fcmKey || tokens.length === 0) {
      return new Response(
        JSON.stringify({
          ok: true,
          eligible_tokens: tokens.length,
          skipped: !fcmKey,
        }),
        { headers: { ...cors, "Content-Type": "application/json" } },
      );
    }

    const sent = await sendFcmLegacyToTokens(
      fcmKey,
      tokens,
      { title: "Упоминание", body: bodyText },
      {
        type: "task_mention",
        task_id: taskId,
        task_title: title,
      },
    );

    return new Response(
      JSON.stringify({ ok: true, sent }),
      { headers: { ...cors, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
