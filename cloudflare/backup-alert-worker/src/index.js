const ALLOWED_SOURCE_IPS = new Set([
  "72.60.133.228",
  "2a02:4780:79:8a53::1",
]);
const MAX_BODY_BYTES = 4096;
const ALLOWED_DATABASES = new Set(["all", "identity", "stays"]);

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

async function readJsonWithinLimit(request) {
  if (!request.body) throw new Error("missing_body");

  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) throw new Error("body_too_large");
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const merged = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(new TextDecoder().decode(merged));
}

function validText(value, maxLength) {
  return typeof value === "string" && value.length > 0 && value.length <= maxLength;
}

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return jsonResponse(200, { ok: true, service: "nexa-backup-alerts" });
    }
    if (url.pathname !== "/backup-alert") {
      return jsonResponse(404, { ok: false, error: "not_found" });
    }
    if (request.method !== "POST") {
      return jsonResponse(405, { ok: false, error: "method_not_allowed" });
    }

    const sourceIp = request.headers.get("CF-Connecting-IP");
    if (!sourceIp || !ALLOWED_SOURCE_IPS.has(sourceIp)) {
      console.warn({ event: "backup_alert_rejected", reason: "source_ip", sourceIp });
      return jsonResponse(403, { ok: false, error: "forbidden" });
    }

    const contentType = request.headers.get("content-type") || "";
    if (!contentType.toLowerCase().startsWith("application/json")) {
      return jsonResponse(415, { ok: false, error: "unsupported_media_type" });
    }

    let payload;
    try {
      payload = await readJsonWithinLimit(request);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "invalid_body";
      return jsonResponse(reason === "body_too_large" ? 413 : 400, {
        ok: false,
        error: reason,
      });
    }

    const valid =
      payload &&
      payload.service === "nexa-db-backup" &&
      (payload.status === "success" || payload.status === "failure") &&
      validText(payload.timestamp, 40) &&
      ALLOWED_DATABASES.has(payload.database) &&
      validText(payload.artifact, 160) &&
      validText(payload.reason, 300);

    if (!valid) {
      return jsonResponse(422, { ok: false, error: "invalid_payload" });
    }

    console.info({
      event: "nexa_db_backup_alert",
      receivedAt: new Date().toISOString(),
      status: payload.status,
      timestamp: payload.timestamp,
      database: payload.database,
      artifact: payload.artifact,
      reason: payload.reason,
    });

    return jsonResponse(202, { ok: true, accepted: true });
  },
};
