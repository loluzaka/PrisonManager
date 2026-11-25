import { timingSafeEqual } from "node:crypto";
import { createRealtime, rawSql } from "@neon/realtime/server";
import { attachDatabasePool } from "@neon/functions";
import { Pool } from "pg";

const databaseUrl = process.env.DATABASE_URL;
const realtimeSecret = process.env.PRISON_REALTIME_SECRET;
const appApiKey = process.env.PRISON_APP_API_KEY;

if (!databaseUrl || !realtimeSecret || !appApiKey) {
  const missingEnvironment = [
    !databaseUrl && "DATABASE_URL",
    !realtimeSecret && "PRISON_REALTIME_SECRET",
    !appApiKey && "PRISON_APP_API_KEY",
  ].filter(Boolean);
  throw new Error(`Required Neon Function environment is missing: ${missingEnvironment.join(", ")}`);
}

const expectedApiKey = appApiKey;
const databaseName = decodeURIComponent(new URL(databaseUrl).pathname.slice(1));
const realtime = createRealtime({ secret: realtimeSecret, db: databaseName });
const pool = new Pool({ connectionString: databaseUrl, max: 5 });
attachDatabasePool(pool);

const allowedUsers = new Set([
  "prison_u_admin",
  "prison_u_warden",
  "prison_u_warden2",
  "prison_u_frontdesk",
  "prison_u_auditor",
]);

function isAuthorized(request: Request): boolean {
  const supplied = request.headers.get("x-prison-app-key") ?? "";
  const suppliedBytes = Buffer.from(supplied);
  const expectedBytes = Buffer.from(expectedApiKey);
  return (
    suppliedBytes.length === expectedBytes.length &&
    timingSafeEqual(suppliedBytes, expectedBytes)
  );
}

function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

export default async function hello(request: Request): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") {
    try {
      await pool.query("SELECT 1");
      return jsonResponse({ status: "ok", database: "connected" });
    } catch {
      console.error("Neon Function database health check failed");
      return jsonResponse({ error: "Database unavailable" }, 503);
    }
  }

  if (request.method !== "POST" || url.pathname !== "/api/realtime/visits") {
    return jsonResponse({ error: "Not found" }, 404);
  }

  if (!isAuthorized(request)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let body: { username?: unknown; visitDate?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON" }, 400);
  }

  const username =
    typeof body.username === "string" ? body.username.toLowerCase() : "";
  const visitDate = typeof body.visitDate === "string" ? body.visitDate : "";
  const parsedVisitDate = new Date(`${visitDate}T00:00:00.000Z`);
  if (
    !allowedUsers.has(username) ||
    !/^\d{4}-\d{2}-\d{2}$/.test(visitDate) ||
    !Number.isFinite(parsedVisitDate.getTime()) ||
    parsedVisitDate.toISOString().slice(0, 10) !== visitDate
  ) {
    return jsonResponse({ error: "Invalid visit query scope" }, 400);
  }

  const query = rawSql<{
    visit_id: string;
    visit_date: string;
    slot: string;
    status: string;
    inmate_no: string;
    inmate_name: string;
    visitor_name: string;
    block_name: string;
  }>(
    `SELECT v.visit_id, v.visit_date::text AS visit_date, v.slot, v.status,
            i.inmate_no, i.full_name AS inmate_name, vr.full_name AS visitor_name,
            b.block_name
       FROM visits v
       JOIN inmates i USING (inmate_id)
       JOIN visitors vr USING (visitor_id)
       JOIN blocks b USING (block_id)
       JOIN staff_access s
         ON s.db_username = $1
        AND (s.facility_id IS NULL OR s.facility_id = b.facility_id)
      WHERE v.visit_date = $2::date
      ORDER BY v.slot, v.visit_id
      LIMIT 100`,
    [username, visitDate],
  );

  try {
    const sealedQuery = await realtime.seal({ query });
    return jsonResponse({ query: sealedQuery });
  } catch {
    console.error("Could not seal the authorized Neon Realtime query");
    return jsonResponse({ error: "Could not prepare live visit updates" }, 503);
  }
}
