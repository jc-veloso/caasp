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

## 6. Conversão dos Jobs FATZZ* pra multithread/paralelo

Proposta de arquitetura completa em `arquitetura_loop_startjob.md`
(diagramas: `diagrama_startjob_paralelo.svg`,
`diagrama_orquestrador_pendencias.svg`). Volume atual (~5.000 notas/dia)
não exige isso hoje — é ganho de latência, não de capacidade — mas fica
registrado pra quando o volume crescer. Três propostas, não excludentes:

- **Proposta 1 (baixo risco, recomendada primeiro)**: loop interno no
  próprio fonte do Job — reconsulta a fila e processa até zerar, em vez
  de sair e esperar o próximo disparo do Schedule. Elimina overhead de
  reabertura de ambiente repetido. Continua single-thread, sem risco de
  concorrência novo. Falta só definir a válvula de escape (limite de
  tempo/quantidade por execução, pra não rodar indefinidamente).
- **Proposta 2 (risco moderado)**: distribuição em até 5 threads
  paralelas via `StartJob()`, lotes fixos pré-divididos (evita disputa de
  `SELECT` entre threads). Precisa de status novo `'F'` + timestamp de
  início de processamento, e uma decisão em aberto sobre limitar o total
  de threads simultâneas globalmente (não só por rodada) — risco real de
  contenção no Oracle se não limitar.
- **Proposta 3**: Job orquestrador dedicado só pra pendências
  (`ZZF`/`ZZG`), dispara `StartJob` direcionado pra nota específica assim
  que ela fica livre, em vez de esperar o próximo ciclo normal do Job de
  destino. Mais seguro que a Proposta 2 (sem disputa de `SELECT`), ganho
  depende do intervalo real do Schedule.

Riscos transversais a resolver antes de qualquer paralelização de
verdade: claim atômico de linha por thread (mecanismo ainda não
confirmado via `TCSqlExec`) e duplicidade de cadastro cliente/fornecedor
se duas threads precisarem do mesmo CNPJ novo ao mesmo tempo (`CheckLeg`
atual não protege contra corrida).

---

*Adicionar novos itens conforme forem identificados. Cada item deve ter
contexto suficiente pra ser retomado sem depender de memória da conversa
onde foi levantado.*
