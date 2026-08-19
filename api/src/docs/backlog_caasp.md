# Backlog — Projeto CAASP

Itens identificados durante o desenvolvimento, fora do escopo imediato do
go-live, pra tratar numa rodada futura.

---

## 1. Normalizar mensagens de callback (endpoint e pós-processamento)

Hoje as mensagens que saem tanto na resposta imediata do endpoint quanto
no callback assíncrono pós-processamento (`U_ZZCALLBK`/`CBackIpaas`) não
seguem um padrão único — variam em formato, nível de detalhe e tom entre
os diferentes pontos de gravação (`FATPI01_V2`, `FATPI09`, `FATZZA01`/
`B01`/`C01`/`D01`, etc.). Definir um formato padrão (estrutura, idioma,
nível de detalhe técnico vs. amigável) e aplicar de forma consistente em
todos os pontos que geram mensagem pro iPaaS.

## 2. Endpoint retorna chave NFe, precisa retornar número da nota

O retorno do endpoint (resposta HTTP imediata do `POST`) hoje traz a
chave de acesso da NFe (`cod_ChaveNFe`, 44 dígitos). Precisa passar a
retornar também (ou no lugar) o **número da nota** (`F2_DOC`/documento
fiscal). Como a numeração real só é gerada depois, de forma assíncrona
(dentro do Job, não no endpoint — ver a migração de numeração pro
`ZZA_MotorSaida`/etc.), esse item pode esbarrar numa limitação de design:
o endpoint não tem o número no momento em que responde. Avaliar se o
requisito é "retornar o número já na resposta síncrona" (exigiria
repensar onde/quando o número é gerado) ou "disponibilizar o número
depois, via callback" (mais simples, já que o callback já carrega
`cDocumento`/`des_Processamento`).

## 3. Limpeza periódica das tabelas Muro

Existe um plano de limpar periodicamente as tabelas Muro (`ZZ9`, `ZZA`-
`ZZG`) — registros já processados (`STATUS='S'`) acumulam indefinidamente
hoje, sem rotina de expurgo. Definir: critério de retenção (quantos dias/
meses manter antes de expurgar), se é exclusão física ou arquivamento
(mover pra tabela histórica antes de excluir), e se roda como mais um Job
agendado ou rotina manual.

## 4. Tratamento de exceção nos Jobs assíncronos

Nenhum dos Jobs (`FATZZ901`, `FATZZA01`...`FATZZF01`) envolve a chamada
ao motor fiscal (`_Motor*`/`Classifica`) em `Begin Sequence`/`Recover
Using`/`End Sequence`. Falhas de *regra de negócio* (motor retorna
`{.F., msg}` limpo — TES não encontrado, cliente não cadastrado, etc.)
já chegam certinho no `U_ZZCALLBK`. Mas uma exceção de runtime de
verdade (erro fatal do AdvPL dentro do motor — mesma classe do bug
"Alias does not exist" já encontrado e corrigido no `FATZZD01.prw`) hoje
não tem rede de segurança nenhuma: aborta a execução antes de chegar no
`Else`/callback, ou até no `U_UPDSTAT`. A linha fica presa em
`STATUS='A'` (reprocessada no próximo run, já que a query principal
filtra `IN ('P','A')`), mas o iPaaS nunca é notificado, e o Job pode
ficar recrashando na mesma linha indefinidamente.

Ao implementar: envolver a chamada ao motor/classificador em cada Job
com `Begin Sequence`/`Recover Using bErrorBlock`/`End Sequence`,
traduzindo o erro capturado pra `{.F., "<contexto>: " + <descrição do
erro>}` — deve fluir pelo `If lOk ... Else ... U_ZZCALLBK(...)` que já
existe em todos os 7 Jobs, sem precisar de mais nenhum encanamento novo.

## 5. Token da API CAASP hardcoded (`MV_XCPTOK`)

`FATZZF01.prw`, dentro de `ZZF_CADPRD`, tem um JWT Bearer da API CAASP
hardcoded como fallback default de `SuperGetMv("MV_XCPTOK", .F., "<jwt>")`
(comentário `[FIX-TOKEN-TAMANHO]` no código) — decisão temporária e
consciente, não descuido: o campo de parâmetro do Protheus (`X6_CONTEUD`,
SX6) não comporta o tamanho da string do JWT. Precisa de uma solução
definitiva de armazenamento (provavelmente uma tabela dedicada em vez de
SX6) — alinhar com o time de arquitetura antes de implementar. Enquanto
isso não sai, manter o fallback hardcoded como está (não é pra "corrigir"
isso como violação de segredo hardcoded sem essa solução definitiva
pronta).

---

*Adicionar novos itens conforme forem identificados. Cada item deve ter
contexto suficiente pra ser retomado sem depender de memória da conversa
onde foi levantado.*
