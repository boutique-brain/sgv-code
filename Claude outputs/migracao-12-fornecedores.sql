-- BAÚ DE ACHADINHOS — migração 12: FUNDAÇÃO MULTI-BRECHÓ (Fase 0, tijolos 1 e 2)
-- Rodar no Supabase > SQL Editor > New query > Run.
--
-- O que faz (tudo SEGURO e invisível pro cliente):
--   1) cria a tabela de fornecedores (brechós);
--   2) adiciona o "dono" (fornecedor_id) em cada peça;
--   3) cria o brechó "Baú — Amanda", liga à sua conta de login e marca como admin;
--   4) atribui TODAS as peças atuais a você.
-- NÃO altera as regras de acesso das peças — seu backoffice continua funcionando igual.

create extension if not exists pgcrypto;

-- 1) Tabela de fornecedores (brechós)
create table if not exists public.fornecedores (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid unique references auth.users(id) on delete set null,
  nome         text not null,
  apelido      text,
  telefone     text,
  pix_chave    text,
  comissao_pct numeric not null default 0,     -- % do Baú sobre a venda (define depois)
  is_admin     boolean not null default false, -- você = true (vê tudo)
  ativo        boolean not null default true,
  criado_em    timestamptz not null default now()
);

-- 2) "Dono" da peça
alter table public.pecas add column if not exists fornecedor_id uuid references public.fornecedores(id);

-- 3) e 4) Cria o brechó "Baú — Amanda", liga à sua conta e atribui as peças
do $$
declare v_uid uuid; v_forn uuid;
begin
  -- sua conta de login do backoffice:
  select id into v_uid from auth.users where lower(email)=lower('amandaschmidts@gmail.com') limit 1;

  select id into v_forn from public.fornecedores where nome='Baú — Amanda' limit 1;
  if v_forn is null then
    insert into public.fornecedores(user_id,nome,apelido,is_admin,comissao_pct)
    values (v_uid,'Baú — Amanda','bau',true,0)
    returning id into v_forn;
  else
    update public.fornecedores set user_id=coalesce(v_uid,user_id), is_admin=true where id=v_forn;
  end if;

  -- toda peça ainda sem dono passa a ser do Baú
  update public.pecas set fornecedor_id=v_forn where fornecedor_id is null;
end $$;

-- Funções-ajudantes (serão usadas pela segurança na migração 13)
create or replace function public.meu_fornecedor_id()
returns uuid language sql stable security definer set search_path=public as $$
  select id from public.fornecedores where user_id=auth.uid() limit 1;
$$;

create or replace function public.sou_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select is_admin from public.fornecedores where user_id=auth.uid() limit 1),false);
$$;

-- Segurança só da tabela de fornecedores (não toca nas peças ainda):
alter table public.fornecedores enable row level security;
drop policy if exists forn_rw on public.fornecedores;
create policy forn_rw on public.fornecedores for all to authenticated
  using (public.sou_admin() or user_id = auth.uid())   -- admin vê todos; brechó vê só o próprio
  with check (public.sou_admin());                      -- só admin cria/edita brechós
grant select,insert,update,delete on public.fornecedores to authenticated;
grant execute on function public.meu_fornecedor_id() to anon,authenticated;
grant execute on function public.sou_admin() to anon,authenticated;

notify pgrst,'reload schema';

-- Conferência (opcional — rode e me diga o resultado):
-- select nome, is_admin, (user_id is not null) as ligada_a_conta from public.fornecedores;
-- select count(*) filter (where fornecedor_id is not null) as com_dono, count(*) as total from public.pecas;
