# Contexto — Integração CAASP/Protheus (Artiq)

José Carlos (Artiq) desenvolve integração assíncrona entre CAASP (Caixa
de Assistência dos Advogados de SP), TOTVS iPaaS (contato: Arthur
Ferreira) e Protheus ERP. Processa NFe (mod. 55), NFCe (mod. 65) e
Recibo de Venda. Fluxo de trabalho: planejar/decidir aqui no chat →
gerar instrução clara pro Claude Code → ele executa no VSCode → José
Carlos manda os fontes de volta → reviso contra o combinado → sincroniza
como nova matriz → próxima rodada.

## Arquitetura — 6 tabelas Muro Z (filas assíncronas)

| Tabela | Domínio | Endpoint | Job | Chave |
|---|---|---|---|---|
| ZZA | NFe Saída | FATPI01_V2 | FATZZA01 | ZZA_CHVNFE + ZZA_TRANSF |
| ZZB | NFe Devolução | FATPI01_V2 | FATZZB01 | ZZB_CHVNFE |
| ZZC | NFe Entrada | FATPI01_V2 | FATZZC01 | ZZC_CHVNFE |
| ZZD | NFCe (mod. 65) | FATPI09 | FATZZD01 | ZZD_CHVNFE |
| ZZE | Recibo de Venda | FATPI08_V2 | FATZZE01 | ZZE_CODRCB |
| ZZF | Produtos Pendentes | FATPI10 | FATZZF01 | ZZF_CHVREF + ZZF_TIPONF |

Campos padrão nas 5 primeiras: `_FILIAL, _COD, _STATUS(P/A/S/E), _PROC,
_CHVNFE(ou _CODRCB), _JSON(memo), _DTINCL/_HRINCL, _DTPROC/_HRPROC,
_PRDPEN(S/N), _ERRMSG(memo)`. **Atenção**: é `_PRDPEN`, não `_PRDPEND`
(11 chars estoura limite de campo do SIGACFG).

Outro endpoint: **FATPI02_V2** (upsert de produto, chamado internamente
via `U_PI_PROD_X`, não mais como REST puro).

## Aprendizados críticos (já custaram tempo real hoje)

- **Limite de 10 caracteres do AdvPL**: `User Function` é resolvida com
  prefixo `U_`, e só os primeiros 10 caracteres do nome completo (`U_` +
  nome) contam pra checar duplicidade/link — não precisa ter exatamente
  10, só os 10 primeiros precisam ser únicos entre TODAS as funções do
  projeto. Verificar sempre antes de nomear algo novo.
- **`RpcSetEnv`/`RpcClearEnv` NÃO se usa dentro de `WSRESTFUL`** (TDN
  oficial, doc "Abertura de ambiente em Web Service", a partir da
  12.1.27) — ambiente já vem pronto via `PREPAREIN` do `appserver.ini`.
  Só os 6 **Jobs** (Schedule, começam sem ambiente) continuam
  precisando — bootstrap fixo via `#Define CEMPPAD`/`CFILPAD` no topo do
  arquivo (não dá pra usar `SuperGetMv` nesse ponto, `SX6` ainda não
  existe).
- **Leitura de campo memo via TOPCONN não é confiável** — sempre buscar
  `R_E_C_N_O_ AS RECNO` na query e reposicionar na área nativa
  (`DbGoto`) só pra ler o memo, nunca ler direto do resultset SQL.
- **`STATUS IN ('P','A')`** nas queries dos Jobs (não só `'P'`) — senão
  registro que trava em "Em Andamento" (Job interrompido) fica órfão pra
  sempre.
- **Nomes de variável podem colidir com macros reservadas dos includes**
  — já pegamos `cFilial` (virava "assign to function call") e `CALLBACK`
  sozinho. Se der erro de sintaxe estranho numa declaração aparentemente
  correta, suspeitar disso primeiro.
- **`TCSqlExec` sempre checar o retorno** — update silencioso que falha
  (ex: coluna que não existe pra aquela tabela específica) não avisa
  nada se ninguém conferir.
- **Prefixo de função `PI_`** (não mais `FZ_`) — o `FZ_` original
  colidia com fontes antigos do legado do cliente. 27 funções já
  renomeadas (tabela de/para com nomes descritivos, ex: `FZ_STR_X` →
  `PI_STR_X`, `FZ_GETEST` → `PI_UF_X`). Qualquer função nova, usar `PI_`.
- **Encoding**: Claude Code já corrompeu travessão (—) e acento
  (ã/á/ã) pra `�` em várias rodadas — sempre conferir arquivo por
  arquivo depois de qualquer edição, incluindo strings ativas (já achou
  bug real assim: `"CARTÃO"` virou `"CART�O"` numa comparação de forma
  de pagamento, quebrando silenciosamente).
- **`FATCFOP01`** (motor de classificação CFOP) é passa-reto hoje — 18
  blocos de regra vazios, só devolve o mesmo CFOP que recebeu. Migração
  futura pros perfis do configurador de tributos (`MV_PERVDA`/
  `MV_PERDVV`/`MV_PERDVC`) ainda não implementada.

## Status atual (validado com teste real)

- **NFCe**: ponta a ponta funcionando — endpoint, fila `ZZD`/`ZZF`,
  cadastro de produto via API real da CAASP (`GET .../produtos/listar`,
  token `MV_XCPTOK`, retry via `MV_XCPRET`/`MV_XCPWAIT`), liberação de
  nota, callback oficial pro Arthur.
- **NFe**: bug crítico achado e corrigido ontem à noite — motor fiscal
  rodava 2x (síncrono no endpoint + de novo no Job, com parâmetros
  **vazios** no Job, porque o enriquecimento de JSON nunca existia).
  Corrigido: `FATPI01_V2` agora só enfileira (com JSON enriquecido:
  `_COD/_LOJA/_NF/_SER/_LEG/_FIL/_TAB/_TRANSF/_COND/_CNPJEMIT/
  _CNPJDEST`); motor + financeiro (`JSON_COMPRA`/`PI_GER_E2`) +
  `CONVENIOS`+rollback migraram pros Jobs (`FATZZA01`/`B01`/`C01`).
  **Ainda não testado ponta a ponta com nota real.**
- **Callback pro Arthur**: endpoint oficial de Notas Fiscais
  implementado (`CBackNotaF`), formato `{cod_ChaveNFe, cod_Subseccao,
  des_Processamento, flg_Processamento}`. Dispara tanto na liberação de
  produto pendente quanto no processamento final da nota (mesmo
  endpoint, mensagens diferentes). Recibo (`CBackRecib`) ainda no
  mecanismo antigo/genérico — endpoint oficial de Recibo não
  implementado (falta `num_PedidoReciboVenda`, que o motor ainda não
  gera).

## PRÓXIMA TAREFA — Migração para tabela intermediária ZZ9 (NFe)

Decisão já fechada: o iPaaS vai mandar um endpoint novo de aviso de
produto pendente **sem CFOP** — então não dá mais pra classificar
`ZZA`/`ZZB`/`ZZC` na hora do recebimento como hoje. Solução: tabela
intermediária **só pra NFe** (NFCe/`ZZD` e Recibo/`ZZE` não precisam,
já cumprem esse papel sozinhas).

**Nome**: `ZZ9` (não `ZZG` — José Carlos escolheu pra ordenar antes de
`ZZA`). **Estrutura já definida e documentada** (ver `CLAUDE.md` do
projeto — já tem a tabela de campos/índices formalizada, só falta
implementar o código).

**Plano de migração** (Opção B, mesma lógica já usada pro NFCe):
- `FATPI01_V2` vira endpoint fino — só recebe, valida, verifica
  duplicidade (contra `ZZ9` agora) e grava JSON bruto na `ZZ9`
  (`PRDPEN` vindo do payload). **Remove toda a classificação** (SA1/SA2,
  `cOper`, numeração, CFOP/TES) — isso tudo migra pro Job novo.
- **Job novo** (nome ainda não definido, candidato `FATZZ901.prw`) — lê
  `ZZ9` (`STATUS IN ('P','A') AND PRDPEN='N'`), herda a lógica de
  classificação que saiu do endpoint (roteamento fiscal, `cOper`,
  numeração, CFOP/TES), enriquece o JSON com os campos sintéticos
  (mesmo padrão `_COD/_LOJA/_NF/...`) e grava via `ZZX_Gravar` na tabela
  final (`ZZA`/`ZZB`/`ZZC`) — **sem chamar motor**, isso já é trabalho
  dos outros 3 Jobs. Marca `ZZ9_STATUS='S'` + `ZZ9_DESTMU`.
- `FATZZF01` — quando `cTipoNF` é `NFS`/`NFD`/`NFE`, a liberação de
  produto pendente (`ZZF_LIBNF`) precisa apontar pra `ZZ9` em vez de
  `ZZA`/`ZZB`/`ZZC` direto (a nota ainda não foi classificada nesse
  ponto). `NFC`/`RCV` sem mudança.

**Isso ainda não foi implementado** — é o próximo passo real de código.

## Outros pendentes (não bloqueiam a ZZ9)

- Callback oficial de Recibo (aguardando Arthur confirmar formato +
  origem do `num_PedidoReciboVenda`)
- `FATCFOP01` real (perfis de tributo) — combinado que fica pra depois
- `FZ_ROLLBACK_NF` já foi renomeado pra `PI_ROLLBACK_NF` (promovida de
  Static pra User Function no processo de mover CONVENIOS pro Job)
