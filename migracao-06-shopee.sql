-- BAÚ DE ACHADINHOS — migração 06: consulta à API de afiliados da Shopee
-- Rodar no SQL Editor, depois das migrações 04 e 05 (esta reaproveita a extensão http).
--
-- Esta migração é PROPOSITALMENTE mínima: ela só faz UMA pergunta à Shopee e
-- devolve a resposta crua. Serve para descobrir, com o menor esforço possível,
-- se o monitoramento automático é viável — antes de construir qualquer rotina.

-- ---------- 1. Guardar as credenciais da Shopee ----------
create or replace function public.shopee_guardar_credenciais(p_app_id text, p_secret text)
returns text
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_app_id,'') = '' or coalesce(p_secret,'') = '' then
    return 'ERRO: informe o App ID e o Secret.';
  end if;
  insert into public.integracoes (chave, valor) values
    ('shopee_app_id', trim(p_app_id)),
    ('shopee_secret', trim(p_secret))
  on conflict (chave) do update set valor = excluded.valor;
  return 'ok — credenciais da Shopee guardadas (App ID ' || trim(p_app_id) || ')';
end $$;

-- ---------- 2. Chamada assinada à API ----------
-- A Shopee autentica assim:
--   Authorization: SHA256 Credential={AppId}, Timestamp={ts}, Signature={sig}
--   sig = sha256( AppId + Timestamp + Payload + Secret )   -- sem espaços entre eles
-- O texto assinado tem que ser EXATAMENTE o mesmo texto enviado no corpo,
-- por isso montamos o corpo uma vez só e reaproveitamos.
create or replace function public.shopee_graphql(p_query text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  id text; seg text; ts bigint; corpo text; assin text;
  r extensions.http_response; saida jsonb;
begin
  select valor into id  from public.integracoes where chave = 'shopee_app_id';
  select valor into seg from public.integracoes where chave = 'shopee_secret';
  if id is null or seg is null then
    return jsonb_build_object('status', 0, 'corpo',
      jsonb_build_object('erro', 'rode shopee_guardar_credenciais primeiro'));
  end if;

  ts    := extract(epoch from now())::bigint;          -- segundos, não milissegundos
  -- corpo compacto, sem espaços: to_json escapa aspas e quebras de linha do texto
  corpo := '{"query":' || to_json(p_query)::text || '}';
  assin := encode(sha256(convert_to(id || ts::text || corpo || seg, 'UTF8')), 'hex');

  select * into r from extensions.http((
    'POST',
    'https://open-api.affiliate.shopee.com.br/graphql',
    array[extensions.http_header(
      'Authorization',
      'SHA256 Credential=' || id || ', Timestamp=' || ts::text || ', Signature=' || assin)],
    'application/json',
    corpo
  )::extensions.http_request);

  begin saida := r.content::jsonb;
  exception when others then saida := jsonb_build_object('cru', left(r.content, 600)); end;

  return jsonb_build_object('status', r.status, 'corpo', saida);
end $$;

-- ---------- 3. O teste: consultar um produto pelo código ----------
create or replace function public.shopee_teste(p_item_id bigint)
returns jsonb
language sql security definer set search_path = public as $$
  select public.shopee_graphql(
    '{ productOfferV2(itemId: ' || p_item_id::text || ', page: 1, limit: 5) {'
    || ' nodes { itemId productName priceMin priceMax priceDiscountRate sales'
    || ' commissionRate shopId shopName offerLink }'
    || ' pageInfo { page limit hasNextPage } } }');
$$;

-- ---------- 4. Trancar ----------
do $$
declare f text;
begin
  foreach f in array array[
    'public.shopee_guardar_credenciais(text,text)',
    'public.shopee_graphql(text)',
    'public.shopee_teste(bigint)'
  ] loop
    execute format('revoke all on function %s from public', f);
    begin execute format('revoke all on function %s from anon, authenticated', f);
    exception when undefined_object then null; end;
  end loop;
end $$;

-- ---------- 5. Conferência ----------
select 'funções da Shopee criadas: ' ||
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like 'shopee\_%')::text as resultado;
