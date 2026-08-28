# Instrução pra Claude Code — campo ID iPaaS em todas as filas

## Contexto

Decisão combinada com José Carlos/Maurício: o payload do iPaaS traz um
identificador próprio na tag `id_Ipaas` (exemplo real:
`6f620917-9f03-11f1-a7ab-dbe0f49fcb94` — formato GUID, 36 caracteres).
Esse ID não é específico de NFe Entrada — é um identificador do
envelope do payload em geral, então entra nas **6 filas Muro Z**
(`ZZA`, `ZZB`, `ZZC`, `ZZD`, `ZZE`, `ZZF`), capturado no respectivo
**endpoint de ingestão** de cada uma, no mesmo momento em que os outros
campos sintéticos (`_COD`, `_CHVNFE`/`_CODRCB`, etc.) são montados e a
linha é gravada na fila.

**Importante — não tenho os fontes atuais dos endpoints nesta rodada.**
O `FATPI01.prw` que está salvo no projeto é a versão antiga/síncrona
(prefixo `FZ_`, grava direto em SF1/SC7/SE2), não a `FATPI01_V2` atual
(fila assíncrona, prefixo `PI_`) que o restante da documentação do
projeto descreve. Os fontes `FATPI01_V2`, `FATPI09` e `FATPI08_V2`
precisam ser conferidos direto no repositório por quem for implementar
— a instrução abaixo descreve o padrão a seguir, não uma edição
linha-a-linha.

## Campos novos (SX3 — cadastrar antes de rodar)

Um campo por tabela, mesmo nome relativo, `Character(36)`:

| Tabela | Campo |
|---|---|
| ZZA | `ZZA_IDIPS` |
| ZZB | `ZZB_IDIPS` |
| ZZC | `ZZC_IDIPS` |
| ZZD | `ZZD_IDIPS` |
| ZZE | `ZZE_IDIPS` |
| ZZF | `ZZF_IDIPS` |

(9 caracteres cada, dentro do limite de 10 do AdvPL. Checar duplicidade
antes de cravar, mesma regra de sempre.)

## Onde capturar

Em cada um dos 4 endpoints, no ponto em que o payload já foi
desserializado (`oHead` ou equivalente, a partir de `jJson['notas']`
ou `jJson['items']`) e a linha está sendo montada/gravada na fila
correspondente:

- **`FATPI01_V2`** — grava `ZZA`, `ZZB` ou `ZZC` conforme o roteamento
  (saída, devolução, entrada). Capturar o ID uma vez, no início do
  processamento do payload (mesmo ponto onde hoje se extrai
  `cod_Subseccao`/`num_SubseccaoCNPJ`), e passar pro `INSERT` da fila
  que for usada nesse fluxo.
- **`FATPI09`** — grava `ZZD` (NFCe). Mesmo padrão.
- **`FATPI08_V2`** — grava `ZZE` (Recibo de Venda). Mesmo padrão.
- **`FATPI10`** — grava `ZZF` (Produtos Pendentes). Mesmo padrão.

Padrão de extração (seguindo o helper já usado pra outros campos do
envelope, ex. `U_PI_STR_X` — conferir o nome exato do helper vigente em
cada endpoint, pode ter variado entre `FZ_STR_X` e `PI_STR_X`
dependendo de qual arquivo já passou pela renomeação):

```
cIdIpaas := AllTrim(U_PI_STR_X(oHead, 'id_Ipaas'))
```

E no `INSERT`/gravação da linha na fila, incluir `<PREFIXO>_IDIPS :=
cIdIpaas` junto aos demais campos sintéticos.

## Pontos de atenção

- Se o payload não trouxer `id_Ipaas` (campo ausente/vazio), gravar
  vazio — não bloquear o processamento por causa disso. Confirmar com
  Arthur se `id_Ipaas` é realmente obrigatório em todo payload do
  iPaaS ou só em alguns fluxos.
- Esse campo é só armazenamento/rastreio por enquanto — **não está
  sendo usado como chave de deduplicação** nessa rodada (a checagem de
  duplicidade continua pela chave que cada fila já usa hoje: `CHVNFE`,
  `CODRCB`, etc.). Se no futuro vocês quiserem usar `id_Ipaas` como
  chave de idempotência, isso é uma decisão separada (índice único,
  revisão da lógica de duplicidade em cada endpoint).
- Não depende e não bloqueia a entrega do `StartJob`/`ZZC` (ver
  `instrucao_startjob_zzc.md`) — são mudanças paralelas, podem ir na
  mesma branch ou em branch separada, como José Carlos preferir.
- Antes de implementar, confirmar no repositório os nomes reais dos
  arquivos `_V2` e do helper de extração de campo (`_STR_X`) vigente
  em cada um, já que a cópia que tenho aqui do `FATPI01.prw` está
  desatualizada.

## Checklist de teste

1. Cadastrar os 6 campos novos no SX3.
2. Mandar um payload de teste com `id_Ipaas` preenchido pra cada um dos
   4 endpoints e conferir que o valor chegou certo na respectiva fila.
3. Mandar um payload sem `id_Ipaas` e confirmar que não quebra (grava
   vazio, segue o fluxo normal).
