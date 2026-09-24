-- BAÚ DE ACHADINHOS — migração 04: base do monitoramento do Mercado Livre
-- Rodar uma vez no SQL Editor. Pode rodar de novo sem problema.
-- Esta migração só cria a estrutura. As credenciais entram depois, num comando separado.

-- ---------- 1. Cofre das credenciais ----------
-- Guarda App ID, Client Secret e os tokens do Mercado Livre.
create table if not exists public.integracoes (
  chave         text primary key,
  valor         text,
  expira_em     timestamptz,
  atualizado_em timestamptz not null default now()
);

-- RLS ligado e NENHUMA policy: de propósito.
-- Sem policy, a API do Supabase não lê nem escreve nesta tabela — nem para o
-- visitante da vitrine, nem para você logada no painel. O único acesso é por
-- aqui (SQL Editor) e pelas funções de manutenção, que rodam como dono do banco.
alter table public.integracoes enable row level security;

create or replace function public.integracoes_touch()
returns trigger language plpgsql as $$
begin new.atualizado_em := now(); return new; end $$;

drop trigger if exists integracoes_touch on public.integracoes;
create trigger integracoes_touch before insert or update on public.integracoes
for each row execute function public.integracoes_touch();

-- ---------- 2. Campos de monitoramento na peça ----------
-- ml_item      : código do anúncio no Mercado Livre (MLB123456789)
-- disponivel   : false quando o anúncio caiu, pausou ou esgotou
-- checado_em   : quando foi a última verificação
-- checagem_nota: o que a última verificação encontrou, em português
alter table public.pecas add column if not exists ml_item        text;
alter table public.pecas add column if not exists disponivel     boolean not null default true;
alter table public.pecas add column if not exists checado_em     timestamptz;
alter table public.pecas add column if not exists checagem_nota  text;

create index if not exists pecas_ml_item_idx on public.pecas (ml_item)
  where ml_item is not null;

-- o monitoramento não deve mexer na data de atualização da peça:
-- senão toda checagem diária faria a peça parecer "recém-mexida" na vitrine
create or replace function public.pecas_touch()
returns trigger language plpgsql as $$
declare so_monitor boolean;
begin
  if tg_op = 'UPDATE' then
    so_monitor := (to_jsonb(new) - 'cliques' - 'disponivel' - 'checado_em' - 'checagem_nota')
                = (to_jsonb(old) - 'cliques' - 'disponivel' - 'checado_em' - 'checagem_nota');
    if so_monitor then
      return new;   -- só mudou clique/monitoramento: não carimba atualizado_em
    end if;
  end if;

  new.atualizado_em := now();
  if new.status = 'vendido' and (tg_op = 'INSERT' or old.status is distinct from 'vendido') then
    new.vendido_em := coalesce(new.vendido_em, now());
  elsif new.status <> 'vendido' then
    new.vendido_em := null;
  end if;
  return new;
end $$;

drop trigger if exists pecas_touch on public.pecas;
create trigger pecas_touch before insert or update on public.pecas
for each row execute function public.pecas_touch();

-- ---------- 3. Conferência ----------
-- Deve listar as 4 colunas novas.
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'pecas'
   and column_name in ('ml_item','disponivel','checado_em','checagem_nota')
 order by column_name;
