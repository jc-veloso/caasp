# Instrução — Cliente/Fornecedor pendente vira assíncrono (fila ZZG)

## Contexto e decisão

O Arthur identificou que o gargalo de 12h no envio de notas pro Muro é
causado pela cadeia síncrona que o iPaaS executa quando cliente/fornecedor
não existe no Protheus: GET na API da CAASP → tratamento → `POST` em
`/FATPI03` (fornecedor) ou `/FATPI06` (cliente) → **espera a resposta** →
só então manda a nota. Cada etapa dessa cadeia paga overhead de round-trip
(mesma faixa que já medimos no rastreio do iPaaS, ~0,6-1,8s por chamada) —
multiplicado por um volume alto de CPF/CNPJ novo (comum em NFCe, ponto de
venda), isso vira o gargalo dominante.

**Decisão**: mesmo padrão já validado pra produto pendente (`ZZF`/
`FATPI10`/`FATZZF01`) — o Arthur para de bloquear o envio da nota
esperando o cadastro, manda a nota pro Muro mesmo com cliente/fornecedor
pendente, e o Protheus resolve isso de forma assíncrona via fila + Job.

**Diferença importante em relação ao fluxo de produto**: aqui o Protheus
**não** precisa consultar a API da CAASP — o Arthur já vai mandar o JSON
de cliente/fornecedor **tratado**, pronto pra virar cadastro. Isso deixa
o Job mais simples que o `ZZF_CADPRD` (sem a etapa de `HttpGet`/retry).

**Confirmado com o Zé Carlos, e validado na conversa com o Arthur (16/08)**:
NFCe é sempre venda (`fornecedor_Pendente` nunca se aplica em payload de
NFCe, sempre `"N"`) — fornecedor pendente só existe em NFe Entrada/
Devolução, fora do escopo NFCe. Cliente e fornecedor pendente são **dois
campos independentes** no payload (não um único campo mutuamente
exclusivo como cheguei a propor inicialmente) — existe cenário real de
nota de transferência/CONVENIOS onde os dois podem ser relevantes ao
mesmo tempo (uma filial é fornecedor na origem, outra é cliente no
destino). Cliente/fornecedor pendente **é** independente de produto
pendente — uma nota pode ter os dois ao mesmo tempo.

**Prefixo `ZZG` confirmado livre no SIGACFG** pelo Zé Carlos.

---

## Contrato a fechar com o Arthur (pré-requisito, não é código)

Payload da nota ganha dois campos independentes (não mutuamente
exclusivos — nota de transferência pode ter os dois ao mesmo tempo):
```json
{
    "cliente_Pendente": "N",
    "fornecedor_Pendente": "N",
    "notas": [ {dados...} ]
}
```
Continua junto de `prod_Pendente`, que é independente dos outros dois:
```json
{
    "cliente_Pendente": "N",
    "fornecedor_Pendente": "N",
    "prod_Pendente": "N",
    "notas": [ {dados...} ]
}
```
Para NFCe especificamente, `fornecedor_Pendente` sempre vem `"N"`
(confirmado com o Arthur: NFCe é sempre venda) — só `cliente_Pendente`
é relevante nesse fluxo. `fornecedor_Pendente` só importa pra NFe
Entrada/Devolução, fora do escopo NFCe atual.

Quando algum dos dois vier `"S"`, o Arthur manda o cadastro tratado
**separado**, direto pra fila (confirmado por ele: "vou enviar pra vc
direto pra tabela muro já tratados") — mesmo mecanismo de notificação
separada que já existe pra produto (`FATPI10`), não embutido no payload
da nota.

---

## Parte 1 — Extrair lógica de `FATPI06.prw`/`FATPI03.prw` pra funções compartilhadas

### 1.1 — `U_PI_CLI_X` (a partir de `FATPI06.prw`, função `DoPost`)

Extrair o corpo da `Static Function DoPost` (linhas 44-163) pra uma
`User Function PI_CLI_X(oJson)` em `FATPI01U.prw` (mesmo arquivo das
outras utilidades compartilhadas — `PI_STR_X`, `PI_FILIAL_X`, etc.),
retornando `{lOk, cMensagem, cCodProtheus}` — mesmo formato de retorno
que `U_PI_PROD_X` já usa, pra manter consistência entre os "cadastradores"
assíncronos.

Manter a validação de duplicidade (`CheckLeg`) e a lógica de model
(`CRMA980`) intactas — só trocar a fonte do JSON (de `oSelf:GetContent()`
direto do HTTP pra um parâmetro `oJson` já parseado) e a saída (de
`oSelf:SetResponse` pro retorno array).

Atualizar `FATPI06.prw` (`WSMETHOD POST NewClient`) pra só fazer o parse
do JSON recebido e chamar `U_PI_CLI_X(oJson)` — o endpoint síncrono
continua funcionando exatamente como hoje pra quem ainda chamar direto,
só que sem duplicar a lógica de cadastro.

### 1.2 — `U_PI_FORN_X` (a partir de `FATPI03.prw`, `WSMETHOD POST NEW`)

Mesmo padrão: extrair o corpo do loop `For nX := 1 To Len(jItems)`
(linhas 90-167) pra `User Function PI_FORN_X(jItem)` em `FATPI01U.prw`,
processando **um** fornecedor por chamada (não o array inteiro) —
retornando `{lOk, cMensagem, cCodProtheus}`. Manter a lógica do model
`MATA020` (incluindo o bloco de dados bancários) intacta.

Se o payload do Arthur mandar mais de um fornecedor por notificação, quem
itera é o Job (`FATZZG01`), chamando `U_PI_FORN_X` uma vez por item — não
a função extraída.

Atualizar `FATPI03.prw` (`WSMETHOD POST NEW`) pra iterar `jItems` e chamar
`U_PI_FORN_X(jItem)` pra cada um, mantendo o comportamento atual do
endpoint síncrono.

---

## Parte 2 — Tabela `ZZG` (fila de cliente/fornecedor pendente)

Estrutura (conferir contra `CLAUDE.md`/SIGACFG antes de criar campos,
mesma regra de sempre — não inventar):
- `ZZG_FILIAL`, `ZZG_COD` — padrão.
- `ZZG_TIPOPE` — `"CLI"` ou `"FOR"` (discrimina qual função chamar,
  mesmo espírito do `ZZF_TIPONF`).
- `ZZG_CHVREF` — chave da nota que está esperando esse cadastro (mesmo
  papel do `ZZF_CHVREF`).
- `ZZG_TIPONF` — tipo da nota de origem, pra saber pra qual tabela
  (`ZZ9`/`ZZA`-`ZZE`) liberar depois (mesmo valor que `ZZF_TIPONF` já usa).
- `ZZG_JSON` — cadastro tratado, vindo do `FATPI11`.
- `ZZG_STATUS`, `ZZG_ERRMSG`, `ZZG_DTINCL`, `ZZG_HRINCL`, `ZZG_DTPROC`,
  `ZZG_HRPROC` — padrão igual às outras filas.

## Parte 3 — `FATPI11.prw` (endpoint novo, recebe o cadastro tratado)

Mesmo esqueleto do `FATPI10.prw`: endpoint fino, só valida e grava bruto
na `ZZG` via `U_ZZX_Gravar("ZZG", "", "CHVREF", cChave, oJson:toJSON(), "TIPOPEN", cTipo, "N")`
(reaproveitando a função já promovida em `FATZZF01.prw` — os nomes de
campo de `ZZG` seguem o padrão genérico que `ZZX_Gravar` já espera).

## Parte 4 — `FATZZG01.prw` (Job novo)

Mesmo esqueleto do `FATZZF01.prw`, mais simples (sem GET externo):
1. Query: `ZZG_STATUS IN ('P','A')`.
2. Por registro: lê `ZZG_JSON`, chama `U_PI_CLI_X`/`U_PI_FORN_X` conforme
   `ZZG_TIPOPE`.
3. Sucesso: `U_UPDSTAT("ZZG", cCod, "S", "")`.
4. Depois, igual ao `ZZF_ALL_OK`/`ZZF_LIBNF`: checar se a nota
   referenciada (`ZZG_CHVREF`) não tem mais nenhuma pendência (nem
   produto, nem cliente/fornecedor) e liberar.

**Não esquecer**: `Static CEMPPAD := "01"` / `Static CFILPAD := "01001"`
(sintaxe já padronizada nos outros seis Jobs) e compilar depois de
`FATZZF01.prw` (mesma ordem de sempre, por causa das funções
compartilhadas).

## Parte 5 — Condição de liberação da nota fica composta

**Escopo restrito** (corrigido após revisão): a pendência de cliente/
fornecedor só precisa do campo nas tabelas onde a classificação
**acontece de fato** — não em toda tabela de nota.

- **`ZZ9`**: sim — é onde `ZZ901_Classifica` resolve cliente/fornecedor
  pra NFe (Saída/Devolução/Entrada). Uma nota só sai da `ZZ9` pra
  `ZZA`/`ZZB`/`ZZC` depois de cliente/fornecedor já resolvidos.
- **`ZZD`**: sim — é onde `ZZD_MotorNFCe` resolve cliente pra NFCe (não
  tem uma etapa de pré-classificação separada como a `ZZ9`, a
  classificação acontece na própria `ZZD`).
- **`ZZA`/`ZZB`/`ZZC`**: **não precisam** — uma nota só chega nelas depois
  que `ZZ901_Classifica` já resolveu cliente/fornecedor com sucesso;
  criar o campo aqui seria redundante, nunca chegaria a valer `"S"`.
- **`ZZE`** (Recibo): **fora de escopo por agora** — menor volume, tratar
  numa rodada separada depois de confirmar se `FATPI08_V2`/`ZZE` tem uma
  etapa de pré-classificação (como a `ZZ9`) ou classifica direto na
  própria `ZZE` (como a `ZZD`) — isso decide se precisa do campo ou não,
  mesmo raciocínio acima, só que não verificado ainda.

Nas duas tabelas que precisam (`ZZ9`, `ZZD`), ganham dois campos novos,
`<TAB>_CLIPEN` e `<TAB>_FORPEN` (mesmo padrão de `PRDPEN`, mas dois
independentes — não mutuamente exclusivos, ver nota de transferência),
setados como `"N"` no insert quando a nota não tem essa pendência, ou
`"S"` quando tem (`ZZG` foi gerada pra ela). Para `ZZD` (NFCe),
`ZZD_FORPEN` sempre será `"N"` na prática (nunca é gerado, mas o campo
existe pra manter a estrutura igual entre `ZZ9`/`ZZD`).

Atualizar `ZZ901_Classifica` e `ZZD_MotorNFCe` (que hoje já detectam
"Destinatario nao localizado"/"Fornecedor nao cadastrado" e falham
direto) pra, em vez de falhar, gravar a nota com `CLIPEN='S'` ou
`FORPEN='S'` (conforme o que faltou) e enfileirar em `ZZG` — e só
liberar de verdade (seguir classificação/gravação final) quando
`PRDPEN='N' AND CLIPEN='N' AND FORPEN='N'` juntos.

`ZZF_LIBNF`/`ZZF_ALL_OK` (liberação vinda da `ZZF`, produto pendente)
também precisam checar esses campos antes de liberar — uma nota pode ter
produto pendente resolvido mas cliente/fornecedor ainda não, e vice-versa.

---

## Pendências antes de codar

- [x] Contrato com o Arthur fechado: dois campos (`cliente_Pendente`/
      `fornecedor_Pendente`), NFCe sempre `fornecedor_Pendente="N"`,
      cadastro tratado vem separado (mesmo padrão do `FATPI10`).
- [ ] Conferir estrutura de campos da `ZZG` contra `CLAUDE.md`/SIGACFG.
- [ ] Decidir o número do endpoint novo (`FATPI11` é sugestão, conferir
      se já não tem algo reservado) e o formato exato de
      `{tipo, chave, dados}` com o Arthur.
- [x] `ZZE`/Recibo fica fora de escopo — **decisão consciente do Maurício**,
      confirmada pelo Arthur: "seguimos com o recibo no modelo antigo,
      tem pouca quantidade e funciona". Não é pendência a retomar, é
      escopo fechado — só revisitar se o volume de Recibo crescer o
      suficiente pra justificar.
