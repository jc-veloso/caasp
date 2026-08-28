# Instrução — Claim atômico no `FATZZC01.prw` (StartJob paralelo, ZZC)

## Contexto e urgência

Revisão do `FATZZC01.prw` (implementação do `StartJob` paralelo pra fila
de Entrada) encontrou um problema real: o `UPDATE` de claim (que marca a
nota como `'A'`/em andamento antes de disparar o `StartJob`) **não tem
condição de status no `WHERE`** — escreve por cima sem checar se a nota
já não foi reivindicada por outra execução.

**Por que isso é urgente**: o novo dispatcher despacha rápido e sai (não
espera as threads) — isso aumenta a chance real de duas execuções do
`FATZZC01` se sobreporem (o Schedule disparando de novo antes da anterior
terminar de percorrer a fila). Se isso acontecer, as duas execuções podem
reivindicar a **mesma** nota (o `ZZC_COD` garante que miram a linha
certa — o problema não é ambiguidade de linha, é ausência de exclusão
mútua na escrita) e disparar **dois** `StartJob` pra ela — reproduzindo
de propósito o erro de chave duplicada (`SD2010_UNQ`/Oracle) que já
apareceu antes neste projeto por outro motivo.

**Priorizar esta correção antes/junto da instrução `id_Ipaas` Parte B**
(pendente de outra sessão) — não é a mesma urgência.

---

## O que muda

Não dá pra confiar em "quantas linhas o `UPDATE` afetou" — isso nunca foi
confirmado como obter via `TCSqlExec` em AdvPL neste ambiente (pendência
técnica registrada há tempo, ainda em aberto). A correção usa um **token
de claim único por execução** + **releitura de confirmação** — não
depende dessa resposta.

**Lógica**: cada execução do `FATZZC01` roda numa thread própria
(`ThreadID()` único, garantido diferente entre execuções que se
sobrepõem — dentro de uma mesma execução, todas as notas do laço `For`
compartilham o mesmo `ThreadID()`, sem problema, porque não há corrida
dentro da própria execução, só entre execuções concorrentes). Grava esse
token na linha, relê imediatamente — se o token que voltou é o que a
própria execução escreveu, o claim foi exclusivo; se for outro, alguém
sobrescreveu no meio, e essa execução desiste da nota.

### 1. Campo novo: `ZZC_THRTOK` (Character, ~20 posições)

Confirmar no SIGACFG antes de criar (mesma cautela de sempre com campos
novos no projeto).

### 2. Token único por tentativa de claim

```advpl
Local cClaimTok := cValToChar(ThreadID()) + "_" + Time() + "_" + cValToChar(Seconds())
```
Gerar **uma vez por execução do `FATZZC01`** (fora do `For nJ`, não
recalcular por nota) — já que o objetivo é diferenciar **execuções**
concorrentes, não notas dentro da mesma execução.

### 3. Capturar `ZZC_THRDT`/`ZZC_THRHR` originais no array `aFila`

Hoje `aFila` só guarda `{cCod, cChvNFe, nRecno}`. Precisa guardar também
os valores de `ZZC_THRDT`/`ZZC_THRHR` lidos no `SELECT` inicial (usados
na condição do claim pra identificar "esse é o mesmo órfão que eu decidi
resgatar", não um órfão novo que apareceu depois):
```advpl
aAdd(aFila, {AllTrim((cAliZZC)->ZZC_COD), AllTrim((cAliZZC)->ZZC_CHVNFE), (cAliZZC)->RECNO, (cAliZZC)->ZZC_THRDT, (cAliZZC)->ZZC_THRHR})
```

### 4. `UPDATE` de claim — condicional, um só (substitui os dois atuais)

Troca o `U_UPDSTAT("ZZC", cCod, "A", "")` + o `cQryClaim` de hoje por um
único `UPDATE` com `WHERE` cobrindo os dois casos elegíveis:
```advpl
cQryClaim := "UPDATE " + RetSqlName("ZZC") + " SET ZZC_STATUS = 'A', "
cQryClaim += "ZZC_THRDT = '" + DToS(Date()) + "', ZZC_THRHR = '" + Time() + "', "
cQryClaim += "ZZC_THRTOK = '" + cClaimTok + "' "
cQryClaim += "WHERE ZZC_COD = '" + cCod + "' AND D_E_L_E_T_ = ' ' AND ("
cQryClaim += "ZZC_STATUS = 'P' OR "
cQryClaim += "(ZZC_STATUS = 'A' AND ZZC_THRDT = '" + DToS(aFila[nJ][4]) + "' AND ZZC_THRHR = '" + aFila[nJ][5] + "')"
cQryClaim += ")"
TCSqlExec(cQryClaim)
```

### 5. Releitura de confirmação — só dispara `StartJob` se o claim foi exclusivo

```advpl
Local lClaimOk := .F.
Local cAliCheck := ""
Local cQryCheck := ""

cQryCheck := "SELECT ZZC_THRTOK FROM " + RetSqlName("ZZC") + " WHERE ZZC_COD = '" + cCod + "' AND D_E_L_E_T_ = ' '"
cAliCheck := GetNextAlias()
MpSysOpenQuery(cQryCheck, cAliCheck)
lClaimOk := (cAliCheck)->(!Eof()) .And. AllTrim((cAliCheck)->ZZC_THRTOK) == cClaimTok
(cAliCheck)->(DbCloseArea())

If !lClaimOk
    ConOut("[FATZZC01] Claim perdido (outra execucao ja reivindicou): " + cCod)
    Loop
EndIf
```
Só chega no `StartJob("U_PI_ENTTH", ...)` se `lClaimOk` for `.T.`.

### 6. Remover o `U_UPDSTAT("ZZC", cCod, "A", "")` antigo

Fica substituído pelo `UPDATE` condicional da seção 4 — não gravar
status duas vezes (uma sem condição, outra com).

---

## Nota sobre alternativa mais simples (não aplicar agora, só registrar)

Se em algum momento for confirmado que existe forma confiável de obter
"quantas linhas o `UPDATE` afetou" em AdvPL/`TCSqlExec` neste ambiente,
todo esse mecanismo de token vira desnecessário — um `UPDATE ... WHERE
STATUS='P' ...` simples, checando linhas afetadas, resolveria sozinho.
Não foi possível confirmar isso até agora; a solução acima funciona sem
depender dessa confirmação.

## Checklist

- [ ] Campo `ZZC_THRTOK` confirmado/criado no SIGACFG.
- [ ] `aFila` passa a guardar `ZZC_THRDT`/`ZZC_THRHR` originais junto de
      `cCod`/`cChvNFe`/`nRecno`.
- [ ] `cClaimTok` gerado uma vez por execução (fora do `For nJ`).
- [ ] `UPDATE` de claim único e condicional, substituindo os dois atuais
      (`U_UPDSTAT` + `cQryClaim` sem condição).
- [ ] Releitura de confirmação (`lClaimOk`) implementada, `StartJob` só
      dispara se `lClaimOk = .T.`.
- [ ] Testado com duas execuções forçadas a se sobrepor (ex.: disparar
      `FATZZC01` manualmente duas vezes em sequência rápida) — confirmar
      que a mesma nota nunca dispara dois `StartJob`.
