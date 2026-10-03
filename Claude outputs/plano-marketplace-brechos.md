# Baú de Achadinhos → Marketplace de Brechós
### Plano de arquitetura (rascunho para discutirmos amanhã)

A ideia em uma frase: o Baú deixa de ser uma loja de um dono só e vira uma **vitrine única e curada** onde vários brechós (fornecedores) colocam suas peças. O cliente compra sem saber de qual brechó veio cada peça; cada brechó enxerga e gerencia **só as suas** peças e recebe o aviso quando uma peça sua é reservada/vendida; e você (admin) enxerga **tudo** — todos os brechós e o pedido completo de cada cliente.

---

## 1. Os três papéis

- **Admin (você)** — vê e gerencia tudo: todas as peças, todos os brechós, os pedidos completos, configurações e repasses.
- **Fornecedor (brechó)** — faz login no mesmo backoffice, mas só vê/edita **as peças dele** e só a **parte dele** de cada pedido.
- **Cliente final** — não faz login, compra na vitrine normalmente (não muda nada pra ele, a não ser o "formar looks").

Tecnicamente cada brechó é uma conta de login (Supabase Auth). Uma tabela `fornecedores` liga cada login ao perfil do brechó, e a sua conta fica marcada como admin.

---

## 2. O que muda no banco de dados

- **Nova tabela `fornecedores`**: nome do brechó, apelido, telefone, chave PIX (para repasse), ativo/inativo, e o vínculo com a conta de login.
- **Tabela `pecas`**: ganha uma coluna `fornecedor_id` (de quem é a peça). Todo o resto continua igual.
- **Tabela `pedidos`** (já existe): continua sendo o **pedido completo do carrinho** — a sua visão, com cliente, total, pagamento.
- **Nova tabela `pedido_itens`**: cada peça do carrinho vira uma linha, carregando o `fornecedor_id` e o status dela (reservado/vendido/etc.). **É essa tabela que "fatia" o pedido por brechó** — é o que faz cada fornecedor ver só a parte dele e você ver o todo.
- **(Fase posterior) tabela `looks`**: para os looks prontos montados por você.

---

## 3. A segurança é o coração disso (RLS)

É o ponto mais delicado: tem que ser **impossível** um brechó ver ou mexer na peça do outro. No Supabase isso se faz com regras de acesso (RLS) por linha:

- A vitrine (público) continua lendo as peças disponíveis, **sem nunca expor de qual brechó é** — vou usar uma "visão" pública que só mostra as colunas seguras.
- O fornecedor logado só enxerga peças com o `fornecedor_id` dele.
- Você (admin) enxerga todas.
- Mesma lógica para os pedidos: o fornecedor vê só os itens dele; você vê o pedido inteiro com os dados do cliente.

Isso tudo é testável peça por peça antes de abrir pra qualquer brechó real.

---

## 4. Como fica o fluxo de um pedido com peças de vários brechós

1. Cliente monta o carrinho com peças de brechós diferentes (anônimo, sem identificação).
2. Opcionalmente **forma um look** (ver seção 5).
3. No checkout, escolhe entrega e paga (PIX para o Baú — um pagamento só).
4. O sistema cria **1 pedido** + **N itens** (um por peça, cada um sabendo de qual brechó é).
5. Cada peça vira *reservada* (quando ele marca "já fiz o PIX") e depois *vendida* (quando você confirma).
6. **No backoffice de cada brechó** aparece o aviso: "sua peça X foi reservada/vendida".
7. **No seu backoffice** aparece o pedido completo: todas as peças, de todos os brechós, com os dados do cliente e o total.

---

## 5. "Formar looks" — como eu imagino construir

Começando simples e evoluindo:

- **MVP (mais simples e já encantador):** um botão "Montar meu look" na vitrine. O cliente vai escolhendo peças (uma de cima, uma de baixo, um calçado, um acessório…) numa bandeja de look e adiciona o conjunto todo ao carrinho de uma vez. As peças podem ser de brechós diferentes e se combinam de forma transparente — o cliente nem percebe a origem.
- **Fase 2:** **looks prontos** montados por você ("Looks do Baú") como inspiração, cada um com um botão "quero esse look".
- **Fase 3:** sugestões inteligentes (por tamanho, cor, estilo).

Um detalhe importante do brechó: cada peça é **única**. Então um "look pronto" precisa checar se todas as peças ainda estão disponíveis — se uma vende, o look se desfaz. O look montado pelo cliente na hora não tem esse problema.

---

## 6. O backoffice vira "inteligente" por papel

O mesmo painel que já existe, que se adapta a quem entrou:

- **Brechó logado:** vê só as peças dele, adiciona peças (já entram como dele automaticamente) e vê só as vendas dele.
- **Você (admin):** tudo isso + uma aba **Fornecedores** (cadastrar brechós, criar o login deles, ativar/desativar) + os **pedidos completos** + os **repasses**.

---

## 7. Como colocar no ar sem quebrar o que já está funcionando

Faria em fases, cada uma testável e reversível:

- **Fase A — Fundação (cliente não vê diferença):** criar a tabela de fornecedores, adicionar `fornecedor_id` nas peças, criar o brechó "Baú (Amanda)" e atribuir **todas as 95 peças atuais** a ele. Nada muda na vitrine.
- **Fase B — Segurança + backoffice por papel:** as regras de acesso e o painel adaptado. Testar com **um brechó piloto**.
- **Fase C — Pedidos multi-brechó:** a tabela de itens e o aviso por fornecedor.
- **Fase D — Formar looks (MVP).**
- **Fase E — Repasse/comissão + looks prontos.**

---

## 8. Decisões que preciso de você (pra gente destravar amanhã)

Estas aqui mudam bastante o desenho, então vale você já ir pensando:

1. **Entrega:** o Baú centraliza o envio (os brechós te entregam as peças e você despacha) **ou** cada brechó envia a peça dele direto pro cliente? → muda o que o fornecedor precisa ver do endereço e como o frete é calculado quando o carrinho tem peças de vários brechós.
2. **Comissão:** o Baú fica com uma % de cada venda? Quanto? → é o que define o repasse pra cada brechó.
3. **Privacidade:** o brechó vê os dados do cliente (contato/endereço) ou só "sua peça foi vendida/reservada", e você cuida do contato?
4. **Código da peça:** mantém neutro como hoje (ex.: MOI000016) ou inclui uma sigla do brechó? (recomendo manter neutro pra não vazar a origem)
5. **Formar looks:** começamos pelo look montado pelo cliente (mais simples) ou pelos looks prontos montados por você?
6. **Frete com vários brechós** (se o envio for descentralizado): soma os fretes de cada um ou frete único do Baú?

---

Minha recomendação de ordem: **Fase A + B primeiro** (fundação e segurança, com um brechó piloto), porque é o alicerce de tudo e dá pra testar sem risco. Com isso de pé, "formar looks" e o repasse vêm naturalmente por cima.

---

# Adendo — ideias de divulgação + organização física (noite de hoje)

Com o material de divulgação que você trouxe, ficou claro que o Baú não é só uma loja: é um **produto pra vender pra outras donas de brechó**. Isso acrescenta duas frentes ao plano.

## 9. A virada de estratégia: são DOIS produtos num só

- **Produto 1 — o App/SaaS:** organiza o brechó da dona (catálogo virtual, estoque, SKU, localização física). É o que resolve a "dor do caos" do vídeo.
- **Produto 2 — o Marketplace:** faz as peças venderem em rede com os looks combinados entre brechós. É o "você nunca mais vende sozinha".

Isso abre um **modelo de receita em camadas** (ver seção 11) e reforça que devemos desenhar tudo multi-brechó desde a fundação — exatamente o que já planejamos.

## 10. Módulo Organização Física (SKU + etiqueta + "achar em 5 segundos")

A mágica do "vendeu → acho em segundos" tem uma **escada de tecnologia**. A base entrega quase tudo sem custo; o topo é o diferencial premium.

**Degrau 1 — já construímos cedo, custo zero, sem hardware:**
- **SKU inteligente automático:** já temos categoria e cor, então gerar `TH-VEST-FLOR-001` é só software. Sai junto com o cadastro.
- **Etiqueta imprimível** com QR Code + código de barras + SKU: imprime em papel comum ou impressorinha térmica barata. O QR leva o cliente pra peça/look no marketplace.
- **Localização física:** campo "onde guardei" (ex.: Arara D-12 · Vestidos/Floral). Quando a peça vende, o app mostra na hora onde ela está. **É o recurso que mais economiza tempo da dona — e é só dado, não precisa de RFID.**
- **Busca/scan pelo celular:** escaneia o código de barras/QR e acha a peça. Resolve o "20 minutos procurando" com a câmera do telefone.

**Degrau 2 — "Baú PRO" / futuro / pitch de investidor:**
- **RFID + portais anti-furto + inventário automático.** É real e impressionante, mas caro: cada etiqueta RFID custa, o leitor de mão custa alguns milhares de reais e os portais de porta, bem mais. Inviável pro brechó pequeno no começo.
- **Como usar isso a nosso favor:** desenhar o banco já com campo pra código RFID (barato fazer agora) e vender o RFID como **plano PRO** e como **argumento de investidor** ("a arquitetura já está pronta pra RFID/inventário automático"), enquanto o dia a dia roda no Degrau 1. Under-promise no produto, over-deliver — e o pitch continua forte.

## 11. Planos e receita (rascunho)

- **Grátis / Básico:** catálogo virtual + estoque + SKU + QR. Isca pra atrair brechós.
- **PRO (pago, mensal):** localização física avançada, etiquetas RFID, relatórios de vendas, destaque na vitrine.
- **Comissão do marketplace:** uma % sobre o que vende em rede (liga direto com o repasse da seção 8).

## 12. Material de divulgação (guardado aqui pra não perder)

Você já tem, e está ótimo:
- Narração curta (30s) "do caos ao sucesso".
- 3 legendas com CTA "comenta EU QUERO" (a emocional é a que mais converte).
- **Roteiro estendido de 90s ("essa era eu há 3 meses") — o mais forte, porque vende a transformação, não a função.**
- Narração com RFID/SKU pro vídeo longo.
- Pitch de investidor ("primeiro marketplace que une o virtual ao físico").

**Nota honesta:** o depoimento em 1ª pessoa ("minhas vendas triplicaram") funciona lindo — só vale, no ar, ser de uma usuária real (nem que seja a primeira piloto) ou enquadrado como "veja como funciona", pra ficar 100% verdadeiro e te proteger.

## Decisões novas que entram na lista

7. **Modelo de negócio:** vamos de SaaS (planos pagos) + comissão, só comissão, ou começamos tudo grátis pra crescer base e cobrar depois?
8. **Organização física no MVP:** entramos já com SKU + etiqueta QR + localização (Degrau 1)? (recomendo que sim — é barato e é o que mais encanta no vídeo)
9. **RFID:** deixamos só o "gancho" no banco agora (campo de código) e tratamos como PRO/futuro? (recomendo que sim)

---

## Como eu encaixaria tudo (visão de ordem)

1. **Fase A + B** — fundação multi-brechó + segurança + backoffice por papel (piloto com 1 brechó).
2. **Fase C** — pedidos multi-brechó (o aviso que "cai" pra cada fornecedor).
3. **Degrau 1 da organização física** (SKU + etiqueta QR + localização) — entra cedo porque é barato e é o coração do vídeo de divulgação.
4. **Fase D** — formar looks (MVP montado pelo cliente).
5. **Fase E** — repasse/comissão + looks prontos + planos pagos.
6. **Baú PRO** — RFID e inventário automático, quando houver brechó disposto a pagar e/ou investidor.

Assim a gente tem, desde cedo, uma versão que **já dá pra filmar o vídeo de verdade** (catálogo lindo + "achar em 5 segundos") e **já funciona em rede** (looks entre brechós), deixando o RFID como o brilho premium que sustenta o pitch.
