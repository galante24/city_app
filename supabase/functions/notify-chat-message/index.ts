// Пуш в чат: вызывайте из Database Webhook (INSERT chat_messages) с заголовком
// Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>.
// Секрет FCM: FCM_SERVER_KEY (Legacy server key) в secrets функции.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { sendFcmLegacyToTokens } from "../_shared/fcm_legacy.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function previewBody(raw: string | null | undefined): string {
  let s = (raw ?? "").trim();
  if (s.startsWith("!img:")) return "📷 Фото";
  if (s.startsWith("!file:b64:")) return "📎 Файл";
  if (s.length > 180) s = s.slice(0, 177) + "…";
  if (!s) return "Новое сообщение";
  return s;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const fcmKey = Deno.env.get("FCM_SERVER_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!supabaseUrl || !service || authHeader !== `Bearer ${service}`) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }
    const body = await req.json().catch(() => ({}));
    const rec = body?.record ?? body?.chat_messages ?? body;
    const conversationId = rec?.conversation_id as string | undefined;
    const senderId = rec?.sender_id as string | undefined;
    const msgBody = rec?.body as string | undefined;
    if (!conversationId || !senderId) {
      return new Response(JSON.stringify({ error: "bad_request" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const admin = createClient(supabaseUrl, service);
    const { data: parts } = await admin
      .from("conversation_participants")
      .select("user_id")
      .eq("conversation_id", conversationId);
    const recipients = (parts ?? [])
      .map((p: { user_id: string }) => p.user_id)
      .filter((uid: string) => uid && uid !== senderId);
    if (recipients.length === 0) {
      return new Response(JSON.stringify({ ok: true, recipients: 0 }), {
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const { data: profiles } = await admin
      .from("profiles")
      .select(
        "id, fcm_token, notifications_enabled, notify_chat_messages, username, first_name",
      )
      .in("id", recipients);
    const rows = profiles ?? [];
    const tokens: string[] = [];
    for (const p of rows) {
      if (
        p.notifications_enabled !== false &&
        p.notify_chat_messages !== false &&
        p.fcm_token &&
        String(p.fcm_token).length > 10
      ) {
        tokens.push(String(p.fcm_token));
      }
    }
    if (tokens.length === 0 || !fcmKey) {
      return new Response(
        JSON.stringify({
          ok: true,
          skipped: !fcmKey,
          eligible: tokens.length,
          hint: fcmKey ? null : "Set secret FCM_SERVER_KEY",
        }),
        { headers: { ...cors, "Content-Type": "application/json" } },
      );
    }

    const { data: sp } = await admin
      .from("profiles")
      .select("username, first_name")
      .eq("id", senderId)
      .maybeSingle();
    const senderTitle =
      (sp?.first_name as string)?.trim() ||
      (sp?.username as string)?.trim() ||
      "Сообщение";

    const { data: conv } = await admin
      .from("conversations")
      .select("is_group, group_name, is_direct")
      .eq("id", conversationId)
      .maybeSingle();
    let chatTitle = "Чат";
    if (conv?.is_group) {
      chatTitle = (conv.group_name as string)?.trim() || "Группа";
    } else {
      // В личном чате у получателя в шапке — имя отправителя.
      chatTitle = senderTitle;
    }

    const bodyText = previewBody(msgBody);
    const sent = await sendFcmLegacyToTokens(
      fcmKey,
      tokens,
      { title: senderTitle, body: bodyText },
      {
        type: "chat",
        conversation_id: conversationId,
        chat_title: chatTitle,
        body_preview: bodyText,
        sender_title: senderTitle,
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
