/// FCM HTTP Legacy API (ключ из Firebase Console → Cloud Messaging → Server key).
export async function sendFcmLegacyToTokens(
  serverKey: string,
  tokens: string[],
  notification: { title: string; body: string },
  data: Record<string, string>,
): Promise<number> {
  const uniq = [...new Set(tokens.filter((t) => t && String(t).length > 10))];
  let sent = 0;
  for (const to of uniq) {
    const res = await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `key=${serverKey}`,
      },
      body: JSON.stringify({
        to,
        priority: "high",
        notification: {
          title: notification.title,
          body: notification.body,
        },
        data: {
          ...data,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
      }),
    });
    if (res.ok) {
      sent++;
    } else {
      console.error("FCM legacy error", res.status, await res.text());
    }
  }
  return sent;
}
