-- BAÚ DE ACHADINHOS — migração 10: campo COR nas peças + preenchimento automático
-- Rodar no Supabase > SQL Editor > New query > Run.
-- 1) Cria a coluna "cor". 2) Preenche automaticamente a cor de TODAS as peças já
--    cadastradas, detectando a 1ª cor citada no título/descrição (só onde ainda está vazia).

alter table public.pecas add column if not exists cor text;

update public.pecas p set cor = sub.cor_detect
from (
  select codigo,
    case
      when t ~* 'rosa choque|pink'            then 'Pink'
      when t ~* 'rosa|salmao|salm'            then 'Rosa'
      when t ~* 'azul marinho|marinho'        then 'Azul-marinho'
      when t ~* 'azul beb|azul claro'         then 'Azul-claro'
      when t ~* 'azul|jeans'                  then 'Azul'
      when t ~* 'verde'                       then 'Verde'
      when t ~* 'vermelh'                     then 'Vermelho'
      when t ~* 'amarel'                      then 'Amarelo'
      when t ~* 'laranja'                     then 'Laranja'
      when t ~* 'roxo'                        then 'Roxo'
      when t ~* 'lil'                         then 'Lilás'
      when t ~* 'vinho|bord'                  then 'Vinho'
      when t ~* 'marrom|caramelo|caf'         then 'Marrom'
      when t ~* 'bege|nude|creme'             then 'Bege'
      when t ~* 'cinza|chumbo|grafite'        then 'Cinza'
      when t ~* 'pret'                        then 'Preto'
      when t ~* 'branc|off.?white'            then 'Branco'
      when t ~* 'dourad|ouro'                 then 'Dourado'
      when t ~* 'prata|pratead'               then 'Prata'
      when t ~* 'estampad|floral|xadrez|listrad|poa|bolinha' then 'Estampado'
      else null
    end as cor_detect
  from (
    select codigo, lower(coalesce(titulo,'') || ' ' || coalesce(descricao,'')) as t
    from public.pecas
  ) x
) sub
where p.codigo = sub.codigo
  and coalesce(p.cor,'') = ''
  and sub.cor_detect is not null
  and p.categoria in ('moda','uniforme','sapatos','acessorios','objetos');

notify pgrst, 'reload schema';

-- Conferir o resultado (opcional):
-- select categoria, cor, count(*) from public.pecas group by 1,2 order by 1,2;
