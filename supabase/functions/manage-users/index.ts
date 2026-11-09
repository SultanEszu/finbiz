import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return respond({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  const accessToken = authorization?.replace(/^Bearer\s+/i, "");
  const projectUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!accessToken) return respond({ error: "Authentication required" }, 401);
  if (!projectUrl || !publishableKey || !serviceRoleKey) {
    return respond({ error: "Server configuration is incomplete" }, 500);
  }

  const callerClient = createClient(projectUrl, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
  const adminClient = createClient(projectUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: userResult, error: authError } = await callerClient.auth.getUser(accessToken);
  if (authError || !userResult.user) return respond({ error: "Invalid session" }, 401);

  const { data: actor, error: actorError } = await adminClient
    .from("profiles")
    .select("id, role")
    .eq("id", userResult.user.id)
    .single();
  if (actorError || !actor || !["admin", "creator"].includes(actor.role)) {
    return respond({ error: "Insufficient permission" }, 403);
  }

  let input: Record<string, unknown>;
  try {
    input = await request.json();
  } catch {
    return respond({ error: "Invalid request body" }, 400);
  }

  if (input.action === "list") {
    const { data, error } = await adminClient
      .from("profiles")
      .select("id, full_name, email, role, avatar_url, must_change_password")
      .order("full_name");
    if (error) return respond({ error: "Unable to load users" }, 500);
    return respond({ users: data });
  }

  if (input.action === "create") {
    const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
    const password = typeof input.password === "string" ? input.password : "";
    const fullName = typeof input.full_name === "string" ? input.full_name.trim() : "";
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || password.length < 8 || !fullName) {
      return respond({ error: "Invalid account details" }, 400);
    }

    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: false,
      user_metadata: { full_name: fullName },
    });
    if (createError || !created.user) {
      return respond({ error: "Unable to create user" }, 400);
    }

    const { error: profileError } = await adminClient
      .from("profiles")
      .update({ must_change_password: true })
      .eq("id", created.user.id);
    if (profileError) {
      await adminClient.auth.admin.deleteUser(created.user.id);
      return respond({ error: "Unable to initialize user profile" }, 500);
    }
    const { error: auditError } = await adminClient.from("audit_logs").insert({
      actor_id: actor.id,
      action: "create_user",
      target_user_id: created.user.id,
      details: { email },
    });
    if (auditError) {
      await adminClient.auth.admin.deleteUser(created.user.id);
      return respond({ error: "Unable to record account operation" }, 500);
    }
    return respond({ id: created.user.id }, 201);
  }

  if (input.action === "delete") {
    const targetId = typeof input.user_id === "string" ? input.user_id : "";
    if (!targetId || targetId === actor.id) {
      return respond({ error: "Invalid account target" }, 400);
    }
    const { data: target, error: targetError } = await adminClient
      .from("profiles")
      .select("id, email, role")
      .eq("id", targetId)
      .maybeSingle();
    if (targetError || !target) return respond({ error: "User not found" }, 404);
    if (actor.role === "admin" && target.role !== "user") {
      return respond({ error: "Admins may only remove regular users" }, 403);
    }
    if (target.role === "creator") {
      const { count, error: countError } = await adminClient
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("role", "creator");
      if (countError || (count ?? 0) <= 1) {
        return respond({ error: "The last Creator account cannot be removed" }, 409);
      }
    }

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(targetId);
    if (deleteError) return respond({ error: "Unable to delete user" }, 500);
    const { error: auditError } = await adminClient.from("audit_logs").insert({
      actor_id: actor.id,
      action: "delete_user",
      details: { target_user_id: targetId, email: target.email },
    });
    if (auditError) return respond({ error: "User deleted but audit logging failed" }, 500);
    return respond({ success: true });
  }

  return respond({ error: "Unsupported action" }, 400);
});
