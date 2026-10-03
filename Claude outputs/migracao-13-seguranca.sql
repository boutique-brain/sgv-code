-- BAÚ DE ACHADINHOS — migração 13: SEGURANÇA POR BRECHÓ (Fase 0, tijolo 3)
-- Rodar no Supabase > SQL Editor > New query > Run.
--
-- O que faz:
--   • A VITRINE (público/anon) continua lendo as peças visíveis — nada muda pro cliente.
--   • No backoffice, cada brechó passa a ver/editar SÓ as peças dele.
--   • Você (admin) continua vendo e gerenciando TUDO.
--   • Pedidos e clientes ficam visíveis só pra você (admin) por enquanto
--     (a fatia de cada brechó nos pedidos entra na Fase 1).
--   • Cria a função pra LIGAR o login de um brechó (usada no botão do backoffice).
--
-- Seguro pra você: como admin, seu acesso não muda.

-- ---------- PEÇAS ----------
alter table public.pecas enable row level security;

-- Remove todas as policies atuais de pecas (recriamos abaixo, do jeito certo)
do $$ declare r record; begin
  for r in select policyname from pg_policies where schemaname='public' and tablename='pecas' loop
    execute format('drop policy %I on public.pecas', r.policyname);
  end loop;
end $$;

-- Vitrine (visitante): só as peças marcadas como visíveis
create policy pecas_sel_anon on public.pecas
  for select to anon using (disponivel = true);

-- Backoffice (logado): admin vê tudo; brechó vê só as dele
create policy pecas_sel_auth on public.pecas
  for select to authenticated
  using (public.sou_admin() or fornecedor_id = public.meu_fornecedor_id());

create policy pecas_ins_auth on public.pecas
  for insert to authenticated
  with check (public.sou_admin() or fornecedor_id = public.meu_fornecedor_id());

create policy pecas_upd_auth on public.pecas
  for update to authenticated
  using (public.sou_admin() or fornecedor_id = public.meu_fornecedor_id())
  with check (public.sou_admin() or fornecedor_id = public.meu_fornecedor_id());

create policy pecas_del_auth on public.pecas
  for delete to authenticated
  using (public.sou_admin() or fornecedor_id = public.meu_fornecedor_id());

grant select on public.pecas to anon;
grant select, insert, update, delete on public.pecas to authenticated;

-- ---------- PEDIDOS (só admin por enquanto) ----------
drop policy if exists pedidos_select_auth on public.pedidos;
create policy pedidos_select_auth on public.pedidos
  for select to authenticated using (public.sou_admin());
drop policy if exists pedidos_update_auth on public.pedidos;
create policy pedidos_update_auth on public.pedidos
  for update to authenticated using (public.sou_admin()) with check (public.sou_admin());
drop policy if exists pedidos_delete_auth on public.pedidos;
create policy pedidos_delete_auth on public.pedidos
  for delete to authenticated using (public.sou_admin());
-- (o insert pelo carrinho/visitante continua como estava)

-- ---------- CLIENTES (só admin acessa direto) ----------
drop policy if exists clientes_sel_auth on public.clientes;
create policy clientes_sel_auth on public.clientes
  for select to authenticated using (public.sou_admin());
drop policy if exists clientes_all_auth on public.clientes;
create policy clientes_all_auth on public.clientes
  for all to authenticated using (public.sou_admin()) with check (public.sou_admin());
-- (o site segue lendo/salvando cliente pelas funções seguras buscar_cliente/salvar_cliente)

-- ---------- Ligar o login de um brechó (admin) ----------
-- Fluxo: você cria o usuário do brechó em Authentication > Users (e-mail + senha),
-- depois no backoffice clica "Ligar login" e informa esse e-mail.
create or replace function public.ligar_fornecedor(p_forn uuid, p_email text)
returns text language plpgsql security definer set search_path=public as $$
declare v_uid uuid;
begin
  if not public.sou_admin() then return 'nao_autorizado'; end if;
  select id into v_uid from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if v_uid is null then return 'email_sem_conta'; end if;
  update public.fornecedores set user_id = v_uid where id = p_forn;
  return 'ligado';
end $$;
grant execute on function public.ligar_fornecedor(uuid,text) to authenticated;

notify pgrst, 'reload schema';

-- Conferência rápida (opcional): deve listar as 5 policies de pecas
-- select policyname, cmd, roles from pg_policies where tablename='pecas' order by policyname;
