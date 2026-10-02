-- BAÚ DE ACHADINHOS — migração 08: cadastro de CLIENTES (LGPD-friendly)
-- Rodar no Supabase > SQL Editor > New query > Run.
-- A tabela NÃO fica aberta ao público: o site só acessa por 2 funções seguras
-- (buscar por CPF+CEP, e salvar). Só a Amanda (logada) consegue listar os clientes.

create table if not exists public.clientes (
  cpf          text primary key,            -- só dígitos
  nome         text,
  telefone     text,
  cep          text,
  logradouro   text,
  numero       text,
  complemento  text,
  bairro       text,
  cidade       text,
  uf           text,
  email        text,
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table public.clientes enable row level security;

-- Ninguém acessa a tabela direto, exceto a dona (logada), que pode ver/gerenciar.
drop policy if exists clientes_sel_auth on public.clientes;
create policy clientes_sel_auth on public.clientes for select to authenticated using (true);
drop policy if exists clientes_all_auth on public.clientes;
create policy clientes_all_auth on public.clientes for all to authenticated using (true) with check (true);
grant select, insert, update, delete on public.clientes to authenticated;

-- ---------- Buscar cliente (por CPF + CEP) ----------
-- Só retorna o cadastro se CPF E CEP baterem (barreira de privacidade).
create or replace function public.buscar_cliente(p_cpf text, p_cep text)
returns public.clientes
language sql security definer set search_path = public as $$
  select * from public.clientes
   where cpf = regexp_replace(coalesce(p_cpf,''),'\D','','g')
     and cep = regexp_replace(coalesce(p_cep,''),'\D','','g')
   limit 1;
$$;
grant execute on function public.buscar_cliente(text,text) to anon, authenticated;

-- ---------- Salvar / atualizar cliente ----------
create or replace function public.salvar_cliente(
  p_cpf text, p_nome text, p_telefone text, p_cep text, p_logradouro text,
  p_numero text, p_complemento text, p_bairro text, p_cidade text, p_uf text, p_email text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(regexp_replace(coalesce(p_cpf,''),'\D','','g'),'') = '' then return; end if;
  insert into public.clientes(cpf,nome,telefone,cep,logradouro,numero,complemento,bairro,cidade,uf,email,atualizado_em)
  values (regexp_replace(p_cpf,'\D','','g'), p_nome, p_telefone, regexp_replace(coalesce(p_cep,''),'\D','','g'),
          p_logradouro, p_numero, p_complemento, p_bairro, p_cidade, p_uf, p_email, now())
  on conflict (cpf) do update set
    nome=excluded.nome, telefone=excluded.telefone, cep=excluded.cep, logradouro=excluded.logradouro,
    numero=excluded.numero, complemento=excluded.complemento, bairro=excluded.bairro,
    cidade=excluded.cidade, uf=excluded.uf,
    email=coalesce(excluded.email, public.clientes.email), atualizado_em=now();
end $$;
grant execute on function public.salvar_cliente(text,text,text,text,text,text,text,text,text,text,text) to anon, authenticated;

notify pgrst, 'reload schema';
