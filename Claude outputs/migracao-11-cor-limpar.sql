-- BAÚ DE ACHADINHOS — migração 11: limpar cor gravada em categorias que NÃO usam o campo
-- (ex.: o livro "20 Regras de Ouro..." pegou "Dourado" do título).
-- Rodar no Supabase > SQL Editor > New query > Run.

update public.pecas
   set cor = null
 where categoria not in ('moda','uniforme','sapatos','acessorios','objetos');

notify pgrst, 'reload schema';

-- Conferir (opcional):
-- select categoria, cor, count(*) from public.pecas group by 1,2 order by 1,2;
