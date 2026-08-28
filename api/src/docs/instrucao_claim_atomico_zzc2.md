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
**Atenção**: `ZZC_THRDT` vem do `TCGenQry` já como string (não como tipo
Data nativo) — não aplicar `DToS()` em cima na hora de montar o `WHERE`
do claim (seção 4), usar o valor direto, do mesmo jeito que `ZZC_THRHR`
já é usado sem conversão. Confirmar que o formato bate com o que o `SET`
grava (`DToS(Date())`, ou seja `"YYYYMMDD"`) antes de aplicar.

### 4. `UPDATE` de claim — condicional, um só (substitui os dois atuais)

Troca o `U_UPDSTAT("ZZC", cCod, "A", "")` + o `cQryClaim` de hoje por um
único `UPDATE` com `WHERE` cobrindo os dois casos elegíveis:
```advpl
cQryClaim := "UPDATE " + RetSqlName("ZZC") + " SET ZZC_STATUS = 'A', "
cQryClaim += "ZZC_THRDT = '" + DToS(Date()) + "', ZZC_THRHR = '" + Time() + "', "
cQryClaim += "ZZC_THRTOK = '" + cClaimTok + "' "
cQryClaim += "WHERE ZZC_COD = '" + cCod + "' AND D_E_L_E_T_ = ' ' AND ("
cQryClaim += "ZZC_STATUS = 'P' OR "
cQryClaim += "(ZZC_STATUS = 'A' AND ZZC_THRDT = '" + aFila[nJ][4] + "' AND ZZC_THRHR = '" + aFila[nJ][5] + "')"
cQryClaim += ")"
If TCSqlExec(cQryClaim) != 0
    ConOut("[FATZZC01] FALHA ao executar UPDATE de claim: " + cCod + " | " + TCSqlError())
    Loop
EndIf
```
`TCSqlExec` devolve código numérico (`0` = sem erro de execução,
diferente de `0` = erro — não é booleano). **Atenção**: isso só confirma
que o `UPDATE` rodou sem erro de SQL — **não diz quantas linhas foram
afetadas**. Um `UPDATE` cujo `WHERE` não bate com nenhuma linha (porque
outra execução já reivindicou primeiro) também retorna `0` — por isso a
checagem de erro acima **não substitui** a releitura de confirmação da
seção 5, só evita seguir adiante em caso de falha real de execução
(conexão, sintaxe, etc.), que é um problema diferente.

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

## Confirmado: `TCSqlExec` não expõe contagem de linhas afetadas

Fecha uma dúvida que estava em aberto há dias neste projeto. `TCSqlExec`
devolve um código **numérico de erro de execução** (`0` = sem erro,
diferente de `0` = erro, capturável via `TCSqlError()`) — não expõe
quantas linhas o comando alterou. Ou seja, **não existe** a alternativa
mais simples que a instrução original cogitava ("se confirmar que dá pra
saber linhas afetadas, o mecanismo de token vira desnecessário") — o
mecanismo de token + releitura da seção 5 é necessário mesmo, não é uma
solução provisória à espera de algo mais simples.

## 🔴 Novo bug encontrado em debug — `U_PI_QTDATIVA()` conta `'A'` órfão como ativo

Durante teste em produção, o `While U_PI_QTDATIVA() >= nMaxThr` travou permanentemente antes mesmo do primeiro `StartJob` da execução disparar. Diagnóstico confirmado: existiam linhas `ZZC_STATUS='A'` órfãs de execuções/testes anteriores (10+), e `U_PI_QTDATIVA()` conta **qualquer** `'A'`, sem checar idade — diferente do `SELECT` que monta `aFila`, que já filtra órfão fresco vs. velho via `PI_MINATRS`/`MV_XCPSTL`. Com o semáforo "cheio" de lixo acumulado que nunca termina de processar, o throttle nunca libera vaga.

### Correção — `U_PI_QTDATIVA()` passa a considerar só `'A'` fresco (não órfão)

Trocar o `COUNT(*)` puro em SQL por leitura das linhas + contagem em AdvPL
usando `PI_MINATRS` (mesmo motivo de sempre: evitar `TO_DATE`/`SYSDATE`
específico de banco em SQL):
```advpl
User Function PI_QTDATIVA()
    Local cQryThr := "SELECT ZZC_THRDT, ZZC_THRHR FROM " + RetSqlName("ZZC") + " "
    Local cAliThr := GetNextAlias()
    Local nQtd    := 0
    Local nStaleMin := SuperGetMv("MV_XCPSTL", .F., 15)

    cQryThr += "WHERE ZZC_STATUS = 'A' AND ZZC_FILIAL = '" + xFilial("ZZC") + "' AND D_E_L_E_T_ = ' '"
    MpSysOpenQuery(cQryThr, cAliThr)
    While (cAliThr)->(!Eof())
        If PI_MINATRS((cAliThr)->ZZC_THRDT, (cAliThr)->ZZC_THRHR) <= nStaleMin
            nQtd++
        EndIf
        (cAliThr)->(DbSkip())
    EndDo
    (cAliThr)->(DbCloseArea())
Return nQtd
```
**Atenção**: `PI_MINATRS` hoje é `Static Function` (só visível dentro de
`FATZZC01.prw`) — como `U_PI_QTDATIVA` já está no mesmo arquivo, não
precisa promover pra `User Function`, só confirmar que a chamada direta
(`PI_MINATRS(...)`, sem `U_`) funciona normalmente dentro do próprio
arquivo.

### Limpeza imediata, antes de testar de novo

As linhas `'A'` órfãs que já existem na base (as que causaram o travamento
agora) não vão se resolver sozinhas com o fix acima — o fix só evita
**contar** órfão como ativo daqui pra frente, não limpa quem já está
preso. Rodar um `UPDATE` manual pra devolver essas linhas pro estado
`'P'` (voltam a ser elegíveis pro claim atômico normal) antes do próximo
teste:
```sql
UPDATE ZZC010 SET ZZC_STATUS = 'P' WHERE ZZC_STATUS = 'A' AND D_E_L_E_T_ = ' '
```
(confirmar que não há nenhuma thread de verdade rodando antes de fazer
esse `UPDATE` manual, senão corre o risco de "resetar" uma nota que está
sendo processada de verdade nesse exato momento)

## Checklist

- [ ] Campo `ZZC_THRTOK` confirmado/criado no SIGACFG.
- [ ] `aFila` passa a guardar `ZZC_THRDT`/`ZZC_THRHR` originais junto de
      `cCod`/`cChvNFe`/`nRecno`.
- [ ] `cClaimTok` gerado uma vez por execução (fora do `For nJ`).
- [ ] `UPDATE` de claim único e condicional, substituindo os dois atuais
      (`U_UPDSTAT` + `cQryClaim` sem condição).
- [ ] Releitura de confirmação (`lClaimOk`) implementada, `StartJob` só
      dispara se `lClaimOk = .T.`.
- [ ] `U_PI_QTDATIVA()` corrigida pra considerar só `'A'` fresco (via
      `PI_MINATRS`), não qualquer `'A'`.
- [ ] Linhas `'A'` órfãs já existentes limpas manualmente (`UPDATE ...
      SET STATUS='P'`) antes do próximo teste.
- [ ] Testado com duas execuções forçadas a se sobrepor (ex.: disparar
      `FATZZC01` manualmente duas vezes em sequência rápida) — confirmar
      que a mesma nota nunca dispara dois `StartJob`.
