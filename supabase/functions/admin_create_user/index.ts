import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.toLowerCase().startsWith('bearer ')) {
      return new Response('Unauthorized: missing or invalid Authorization header', { status: 401 });
    }

    const projectUrl = Deno.env.get('SUPABASE_URL') ?? Deno.env.get('EDGE_SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('EDGE_SUPABASE_ANON_KEY');
    if (!anonKey) {
      return new Response('Missing SUPABASE_ANON_KEY', { status: 500 });
    }
    if (!projectUrl) {
      return new Response('Missing SUPABASE_URL', { status: 500 });
    }

    // Validate the JWT manually using the anon key (no verify_jwt)
    const authClient = createClient(projectUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await authClient.auth.getUser();
    if (userErr || !userData?.user) {
      console.error('getUser error:', userErr);
      return new Response(`Unauthorized: ${userErr?.message ?? 'invalid JWT'}`, { status: 401 });
    }

    let isAdminCaller = false;
    try {
      const { data: prof } = await authClient
        .from('profiles')
        .select('is_admin')
        .eq('id', userData.user.id)
        .maybeSingle();
      isAdminCaller = (prof as any)?.is_admin === true;
    } catch (_) {
      isAdminCaller = (userData.user.user_metadata as any)?.is_admin === true;
    }

    if (!isAdminCaller) {
      return new Response('Forbidden', { status: 403 });
    }

    const { email, password, name, is_admin, course, department, created_by } = await req.json();
    if (!email || !password || !name) {
      return new Response('email, password, name required', { status: 400 });
    }

    const serviceRoleKey = Deno.env.get('SERVICE_ROLE_KEY') ?? Deno.env.get('EDGE_SERVICE_ROLE_KEY');
    if (!serviceRoleKey) {
      return new Response('Missing SERVICE_ROLE_KEY', { status: 500 });
    }

    const supabase = createClient(projectUrl, serviceRoleKey);

    // 1) Create auth user
    const { data: userRes, error: authErr } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { name, is_admin: !!is_admin, course, department, created_by },
    });
    if (authErr || !userRes?.user) {
      return new Response(JSON.stringify(authErr ?? { error: 'createUser failed' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    // 2) Insert profile row
    const profilePayload: Record<string, unknown> = {
      id: userRes.user.id,
      name,
      email,
      course,
      department,
      is_admin: !!is_admin,
      created_by: created_by ?? 'admin',
      active: true,
      created_at: new Date().toISOString(),
    };

    const missingCol = (message: string): string | null => {
      const m = /Could not find the '([^']+)' column/.exec(message);
      return m?.[1] ?? null;
    };

    let attempt = { ...profilePayload };
    for (let i = 0; i < 8; i++) {
      const { error: profErr } = await supabase.from('profiles').insert(attempt);
      if (!profErr) break;

      const msg = (profErr as any)?.message?.toString?.() ?? JSON.stringify(profErr);
      const code = (profErr as any)?.code?.toString?.();
      const col = missingCol(msg);
      if (code === 'PGRST204' && col && Object.prototype.hasOwnProperty.call(attempt, col)) {
        delete (attempt as any)[col];
        continue;
      }
      return new Response(JSON.stringify(profErr), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
