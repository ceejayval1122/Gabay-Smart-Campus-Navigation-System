import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.toLowerCase().startsWith('bearer ')) {
      return new Response('Unauthorized', { status: 401 });
    }

    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!anonKey) {
      return new Response('Missing SUPABASE_ANON_KEY', { status: 500 });
    }

    const authClient = createClient(Deno.env.get('SUPABASE_URL')!, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await authClient.auth.getUser();
    if (userErr || !userData?.user) {
      return new Response('Unauthorized', { status: 401 });
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

    const { user_id } = await req.json();
    if (!user_id) return new Response('user_id required', { status: 400 });

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SERVICE_ROLE_KEY')! // Service Role ONLY in server env
    );

    const { error } = await supabase.auth.admin.deleteUser(user_id);
    if (error) {
      return new Response(JSON.stringify({ error }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
