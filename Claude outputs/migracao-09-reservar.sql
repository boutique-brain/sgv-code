-- BAÚ DE ACHADINHOS — migração 09: reservar peça (usada quando o cliente marca "Já fiz o PIX")
-- Rodar no Supabase > SQL Editor > Run.
-- Só reserva se a peça ainda estiver disponível (não mexe em vendida/reservada).

create or replace function public.reservar_peca(p_codigo text)
returns text
language plpgsql security definer set search_path = public as $$
declare afetadas int;
begin
  update public.pecas
     set status='reservado', atualizado_em=now()
   where codigo=p_codigo and coalesce(status,'disponivel')='disponivel';
  get diagnostics afetadas = row_count;
  return case when afetadas>0 then 'reservado' else 'indisponivel' end;
end $$;

grant execute on function public.reservar_peca(text) to anon, authenticated;

notify pgrst, 'reload schema';
