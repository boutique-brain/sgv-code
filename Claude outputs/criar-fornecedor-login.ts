// Supabase Edge Function: criar-fornecedor-login
// Cria o login (usuário) de um brechó e já liga ao cadastro do fornecedor.
// Segurança: só funciona se quem chamou for a ADMIN (você). O "poder" de criar
// usuário (service role) fica aqui no servidor, nunca no site.
//
// Deploy: Supabase > Edge Functions > Deploy a new function > nome "criar-fornecedor-login"
// > cole este código > Deploy. Não precisa configurar secret: o Supabase já injeta
// SUPABASE_URL, SUPABASE_ANON_KEY e SUPABASE_SERVICE_ROLE_KEY automaticamente.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";

    // 1) Confirma que quem chamou é a admin (usa o login de quem fez a chamada)
    const asUser = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: ehAdmin, error: e1 } = await asUser.rpc("sou_admin");
    if (e1) return json({ error: "Falha ao validar permissão: " + e1.message }, 500);
    if (!ehAdmin) return json({ error: "Só a administradora pode criar logins." }, 403);

    // 2) Lê os dados
    const body = await req.json().catch(() => ({} as any));
    const email = String(body.email || "").trim().toLowerCase();
    const senha = String(body.senha || "");
    const forn_id = String(body.forn_id || "");
    if (!email || !senha) return json({ error: "Informe e-mail e senha." }, 400);
    if (senha.length < 6) return json({ error: "A senha precisa de ao menos 6 caracteres." }, 400);
    if (!forn_id) return json({ error: "Fornecedor não informado." }, 400);

    // 3) Cria o usuário (com poder de admin) e já confirma o e-mail
    const admin = createClient(url, service);
    const { data: criado, error: e2 } = await admin.auth.admin.createUser({
      email,
      password: senha,
      email_confirm: true,
    });
    if (e2) {
      const msg = /already|exist/i.test(e2.message)
        ? "Já existe uma conta com esse e-mail. Use 'ligar conta existente'."
        : e2.message;
      return json({ error: msg }, 400);
    }

    // 4) Liga o novo usuário ao fornecedor
    const uid = criado.user?.id;
    const { error: e3 } = await admin.from("fornecedores").update({ user_id: uid }).eq("id", forn_id);
    if (e3) return json({ error: "Login criado, mas falhou ao ligar ao brechó: " + e3.message }, 500);

    return json({ ok: true, user_id: uid });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
