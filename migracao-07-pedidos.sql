-- BAÚ DE ACHADINHOS — migração 07: tabela de PEDIDOS (histórico de vendas)
-- Rodar no Supabase > SQL Editor > New query > Run.
-- Cria a tabela onde cada finalização do carrinho vira um registro de venda.

create table if not exists public.pedidos (
  id         bigint generated always as identity primary key,
  criado_em  timestamptz not null default now(),
  cliente    text,
  telefone   text,
  itens      jsonb   not null default '[]'::jsonb,   -- [{codigo,titulo,preco}]
  qtd        int     not null default 0,
  total      numeric not null default 0,
  agua       numeric default 0,
  co2        numeric default 0,
  economia   numeric default 0,
  status     text    not null default 'novo',        -- novo | pago | entregue | cancelado
  canal      text    default 'whatsapp',
  obs        text
);

create index if not exists pedidos_criado_idx on public.pedidos (criado_em desc);

-- Segurança (RLS): visitante pode CRIAR pedido; só quem está logada vê/edita.
alter table public.pedidos enable row level security;

drop policy if exists pedidos_insert_todos on public.pedidos;
create policy pedidos_insert_todos on public.pedidos
  for insert to anon, authenticated with check (true);

drop policy if exists pedidos_select_auth on public.pedidos;
create policy pedidos_select_auth on public.pedidos
  for select to authenticated using (true);

drop policy if exists pedidos_update_auth on public.pedidos;
create policy pedidos_update_auth on public.pedidos
  for update to authenticated using (true) with check (true);

drop policy if exists pedidos_delete_auth on public.pedidos;
create policy pedidos_delete_auth on public.pedidos
  for delete to authenticated using (true);

-- Privilégios de tabela (o RLS acima é quem realmente controla o acesso)
grant insert on public.pedidos to anon;
grant select, insert, update, delete on public.pedidos to authenticated;

notify pgrst, 'reload schema';
