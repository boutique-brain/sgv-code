-- BAÚ DE ACHADINHOS — migração 05: conexão com a API do Mercado Livre
-- Rodar uma vez no SQL Editor, DEPOIS da migração 04. Pode rodar de novo sem problema.
--
-- Esta migração só instala o encanamento. Ela NÃO contém nenhuma senha.
-- As credenciais entram no passo seguinte, num comando separado que só você roda.

-- ---------- 1. Extensão que permite o banco fazer chamadas HTTP ----------
create extension if not exists http with schema extensions;

-- ---------- 2. Utilitário: codificar texto para uso em formulário web ----------
-- O Mercado Livre espera os parâmetros no formato de formulário. Sem codificar,
-- a barra e os dois-pontos da URL de retorno quebrariam a requisição.
create or replace function public.url_encode(p_txt text)
returns text language plpgsql immutable as $$
declare saida text := ''; c text; b bytea; i int;
begin
  if p_txt is null then return ''; end if;
  for c in select regexp_split_to_table(p_txt, '') loop
    if c ~ '^[A-Za-z0-9_.~-]$' then
      saida := saida || c;
    else
      b := convert_to(c, 'UTF8');
      for i in 0 .. octet_length(b) - 1 loop
        saida := saida || '%' || upper(lpad(to_hex(get_byte(b, i)), 2, '0'));
      end loop;
    end if;
  end loop;
  return saida;
end $$;

-- ---------- 3. Guardar as credenciais ----------
create or replace function public.ml_guardar_credenciais(p_app_id text, p_secret text)
returns text
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_app_id,'') = '' or coalesce(p_secret,'') = '' then
    return 'ERRO: informe o App ID e o Client Secret.';
  end if;
  insert into public.integracoes (chave, valor) values
    ('ml_app_id', trim(p_app_id)),
    ('ml_client_secret', trim(p_secret))
  on conflict (chave) do update set valor = excluded.valor;
  return 'ok — credenciais guardadas (App ID ' || trim(p_app_id) || ')';
end $$;

-- ---------- 4. Chamada crua ao endpoint de token ----------
create or replace function public.ml_post_token(p_corpo text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r extensions.http_response; corpo jsonb;
begin
  select * into r from extensions.http((
    'POST',
    'https://api.mercadolibre.com/oauth/token',
    array[extensions.http_header('Accept','application/json')],
    'application/x-www-form-urlencoded',
    p_corpo
  )::extensions.http_request);

  begin corpo := r.content::jsonb; exception when others then corpo := jsonb_build_object('cru', r.content); end;
  return jsonb_build_object('status', r.status, 'corpo', corpo);
end $$;

-- ---------- 5. Gravar o resultado de um token ----------
create or replace function public.ml_gravar_token(p_resp jsonb)
returns text
language plpgsql security definer set search_path = public as $$
declare c jsonb := p_resp->'corpo'; st int := (p_resp->>'status')::int; seg int;
begin
  if st <> 200 or c->>'access_token' is null then
    return 'ERRO ' || st || ': ' || coalesce(c->>'message', c->>'error', c::text);
  end if;

  seg := coalesce((c->>'expires_in')::int, 21600);

  insert into public.integracoes (chave, valor, expira_em) values
    ('ml_access_token', c->>'access_token', now() + make_interval(secs => seg))
  on conflict (chave) do update set valor = excluded.valor, expira_em = excluded.expira_em;

  -- o refresh token só vem quando existe; num token de aplicação não vem, e tudo bem
  if c->>'refresh_token' is not null then
    insert into public.integracoes (chave, valor) values ('ml_refresh_token', c->>'refresh_token')
    on conflict (chave) do update set valor = excluded.valor;
  end if;

  return 'ok — token válido por ' || round(seg/3600.0, 1) || ' h'
         || case when c->>'refresh_token' is not null then ', com renovação automática' else ', sem renovação' end;
end $$;

-- ---------- 6. Os três jeitos de obter token ----------

-- 6a. Token de aplicação (não precisa de autorização no navegador)
create or replace function public.ml_token_aplicacao()
returns text
language plpgsql security definer set search_path = public as $$
declare id text; seg text;
begin
  select valor into id  from public.integracoes where chave = 'ml_app_id';
  select valor into seg from public.integracoes where chave = 'ml_client_secret';
  if id is null or seg is null then return 'ERRO: rode ml_guardar_credenciais primeiro.'; end if;

  return public.ml_gravar_token(public.ml_post_token(
    'grant_type=client_credentials'
    || '&client_id='     || public.url_encode(id)
    || '&client_secret=' || public.url_encode(seg)));
end $$;

-- 6b. Trocar o código da autorização (o que aparece na página mloauth.html)
create or replace function public.ml_trocar_codigo(p_code text)
returns text
language plpgsql security definer set search_path = public as $$
declare id text; seg text; volta text := 'https://baudeachadinhos.com.br/mloauth.html';
begin
  select valor into id  from public.integracoes where chave = 'ml_app_id';
  select valor into seg from public.integracoes where chave = 'ml_client_secret';
  if id is null or seg is null then return 'ERRO: rode ml_guardar_credenciais primeiro.'; end if;
  if coalesce(p_code,'') = '' then return 'ERRO: cole o código da autorização.'; end if;

  return public.ml_gravar_token(public.ml_post_token(
    'grant_type=authorization_code'
    || '&client_id='     || public.url_encode(id)
    || '&client_secret=' || public.url_encode(seg)
    || '&code='          || public.url_encode(trim(p_code))
    || '&redirect_uri='  || public.url_encode(volta)));
end $$;

-- 6c. Renovar usando o refresh token
create or replace function public.ml_renovar()
returns text
language plpgsql security definer set search_path = public as $$
declare id text; seg text; ref text;
begin
  select valor into id  from public.integracoes where chave = 'ml_app_id';
  select valor into seg from public.integracoes where chave = 'ml_client_secret';
  select valor into ref from public.integracoes where chave = 'ml_refresh_token';
  if ref is null then return 'ERRO: não há refresh token guardado.'; end if;

  return public.ml_gravar_token(public.ml_post_token(
    'grant_type=refresh_token'
    || '&client_id='     || public.url_encode(id)
    || '&client_secret=' || public.url_encode(seg)
    || '&refresh_token=' || public.url_encode(ref)));
end $$;

-- ---------- 7. Token válido, renovando sozinho quando precisa ----------
create or replace function public.ml_token()
returns text
language plpgsql security definer set search_path = public as $$
declare tok text; venc timestamptz; r text;
begin
  select valor, expira_em into tok, venc
    from public.integracoes where chave = 'ml_access_token';

  -- margem de 5 minutos, para não usar um token que vence no meio da checagem
  if tok is not null and venc is not null and venc > now() + interval '5 minutes' then
    return tok;
  end if;

  -- vencido: tenta renovar; se não der, tenta token de aplicação
  if exists (select 1 from public.integracoes where chave = 'ml_refresh_token') then
    r := public.ml_renovar();
  else
    r := public.ml_token_aplicacao();
  end if;

  if r like 'ERRO%' then
    raise exception 'Não consegui um token do Mercado Livre. %', r;
  end if;

  select valor into tok from public.integracoes where chave = 'ml_access_token';
  return tok;
end $$;

-- ---------- 8. Consultar um anúncio ----------
create or replace function public.ml_item(p_id text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r extensions.http_response; corpo jsonb;
begin
  select * into r from extensions.http((
    'GET',
    'https://api.mercadolibre.com/items/' || upper(trim(p_id)),
    array[extensions.http_header('Authorization', 'Bearer ' || public.ml_token())],
    null, null
  )::extensions.http_request);

  begin corpo := r.content::jsonb; exception when others then corpo := jsonb_build_object('cru', left(r.content, 400)); end;
  return jsonb_build_object('status', r.status, 'corpo', corpo);
end $$;

-- ---------- 9. Leitura amigável de um anúncio ----------
-- É esta que vamos usar no teste e, depois, na checagem diária.
create or replace function public.ml_anuncio(p_id text)
returns table (
  situacao      text,
  titulo        text,
  preco         numeric,
  estoque       int,
  disponivel    boolean,
  nota          text
)
language plpgsql security definer set search_path = public as $$
declare resp jsonb; c jsonb; st int; sub text;
begin
  resp := public.ml_item(p_id);
  st := (resp->>'status')::int;
  c  := resp->'corpo';

  if st = 404 then
    return query select 'nao encontrado'::text, null::text, null::numeric, null::int, false,
                        'O anúncio não existe mais no Mercado Livre.'::text;
    return;
  elsif st <> 200 then
    return query select ('erro ' || st)::text, null::text, null::numeric, null::int, null::boolean,
                        coalesce(c->>'message', c->>'error', left(c::text, 200))::text;
    return;
  end if;

  sub := c->>'status';   -- active, paused, closed, under_review
  return query select
    sub,
    c->>'title',
    (c->>'price')::numeric,
    (c->>'available_quantity')::int,
    (sub = 'active' and coalesce((c->>'available_quantity')::int, 0) > 0),
    case
      when sub = 'closed'                                     then 'Anúncio encerrado pelo vendedor.'
      when sub = 'paused'                                     then 'Anúncio pausado pelo vendedor.'
      when sub = 'under_review'                               then 'Anúncio em revisão no Mercado Livre.'
      when coalesce((c->>'available_quantity')::int, 0) = 0   then 'Sem estoque.'
      else 'Ativo e com estoque.'
    end::text;
end $$;

-- ---------- 10. Trancar as funções ----------
-- Nada disto pode ser chamado pela API pública nem pelo painel: só pelo SQL Editor
-- e pela tarefa agendada, que rodam como dono do banco.
do $$
declare f text;
begin
  foreach f in array array[
    'public.url_encode(text)',
    'public.ml_guardar_credenciais(text,text)',
    'public.ml_post_token(text)',
    'public.ml_gravar_token(jsonb)',
    'public.ml_token_aplicacao()',
    'public.ml_trocar_codigo(text)',
    'public.ml_renovar()',
    'public.ml_token()',
    'public.ml_item(text)',
    'public.ml_anuncio(text)'
  ] loop
    execute format('revoke all on function %s from public', f);
    begin execute format('revoke all on function %s from anon, authenticated', f);
    exception when undefined_object then null; end;
  end loop;
end $$;

-- ---------- 11. Conferência ----------
select 'extensão http instalada: ' ||
       coalesce((select extversion from pg_extension where extname = 'http'), 'NÃO') as passo_1,
       'funções criadas: ' ||
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like 'ml\_%')::text as passo_2;
