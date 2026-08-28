# Instrução pra Claude Code — StartJob assíncrono na ZZC (entrada)

**Status: implementado** na branch `feature/threads-startjob`
(`api/src/refactoring/jobs/FATZZC01.prw`). Ainda não commitado — falta
validar contra o checklist de teste no fim deste doc.

## Objetivo

`FATZZC01` continua fazendo o SELECT na fila `ZZC` como hoje, mas em vez
de chamar `ZZC_MotorEntrada(jJson)` direto e esperar o retorno (MATA120
+ MATA103 síncronos), dispara um `StartJob` pra cada nota, processando
em paralelo. O laço principal só marca o status e segue pra próxima
nota, sem bloquear.

## Por que não é só "trocar a chamada por StartJob"

Duas coisas do desenho atual dependiam do processamento ser síncrono e
quebram se a gente só trocar a chamada por `StartJob` sem mais nada:

1. **A query inclui `ZZC_STATUS IN ('P','A')`.** Hoje isso existe pra
   recuperar registro órfão de um Job que foi interrompido no meio
   (trava em "Em Andamento" pra sempre, senão). Com processamento
   síncrono isso é seguro, porque enquanto uma nota está com
   `STATUS='A'` o próprio Job está travado nela — não tem como o mesmo
   Job (ou outra execução agendada dele) reler essa linha em paralelo.
   **Com `StartJob`, isso deixa de ser verdade**: o Job dispara a
   thread e segue. Se a próxima execução agendada do `FATZZC01` rodar
   enquanto a thread anterior ainda está processando, ela vai
   reselecionar a mesma linha (`STATUS='A'`, ainda não virou `S`/`E`) e
   processar a nota **duas vezes** — PC duplicado, nota duplicada.
   Precisa de um corte por idade: só resgatar `STATUS='A'` se já estiver
   "andamento" há mais tempo que um limiar razoável (nota realmente
   travada), não qualquer `'A'` recente (que é só uma thread em voo).

2. **Throttle de concorrência.** A decisão foi ~10 threads simultâneas,
   não uma por nota da fila inteira de uma vez (pode ter dezenas
   acumuladas). Sem limite, `FATZZC01` dispararia um `StartJob` pra cada
   linha da fila de uma vez só.

A boa notícia: dá pra resolver os dois com o que já existe no schema,
sem tabela nova. `STATUS='A'` já é marcado logo antes de disparar o
processamento — ele já funciona como "claim" da linha. Basta:

- Trocar o filtro pra só recuperar `'A'` órfão (mais velho que um
  limiar), não `'A'` fresco.
- Usar `COUNT(*) WHERE STATUS='A' AND` (fresco, dentro do limiar) como
  contador de threads em voo, e esperar liberar uma vaga antes de
  disparar a próxima.

## Mudança 1 — `FATZZC01` (Job principal, `FATZZC01.prw`)

### Query (trocar o filtro)

Hoje:

```
cQry := "SELECT ZZC_COD, ZZC_CHVNFE, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZC") + " "
cQry += "WHERE ZZC_STATUS IN ('P','A') AND ZZC_PRDPEN = 'N' "
cQry += "AND ZZC_FILIAL = '" + xFilial("ZZC") + "' "
cQry += "AND D_E_L_E_T_ = ' ' "
cQry += "ORDER BY ZZC_DTINCL, ZZC_HRINCL"
```

**Implementado**: não faz a comparação de idade em SQL — `TO_DATE`/
`SYSDATE` são Oracle-específicos, sem sintaxe única entre os bancos que
o Protheus suporta. A query continua trazendo `STATUS IN ('P','A')`
(igual hoje), só que agora com `ZZC_STATUS`, `ZZC_DTPROC`, `ZZC_HRPROC`
como colunas normais do resultset (não são memo, dá pra ler direto,
sem `DbGoto`); o filtro "pega `P` sempre, pega `A` só se velho" roda no
laço AdvPL que monta `aFila`, via `Static Function PI_MINATRS(dDtProc,
cHrProc)` (minutos decorridos desde o timestamp até agora, usando só
`Date()`/`Seconds()` — nenhuma dependência de banco). Data/hora vazia
(linha nunca carimbada) conta como bem antiga, elegível a resgate
imediato.

### Throttle (esperar vaga antes de disparar)

Antes de disparar o `StartJob` de cada nota, checar quantas estão
`STATUS='A'` pra essa filial (`SELECT COUNT(*) FROM ZZC WHERE
ZZC_STATUS='A' AND ZZC_FILIAL=...` — sem data nenhuma, `COUNT` puro,
sem problema de dialeto), e esperar (`Sleep(1000)`, repetindo o `COUNT`
a cada ciclo) enquanto `nAtivas >= MV_XCPTHR` (novo parâmetro, default
**10**). Reaproveita o próprio `STATUS='A'` como semáforo — não precisa
de tabela ou contador novo. Esse `COUNT` pode incluir algum órfão
travado ainda não resgatado — só deixa o throttle um pouco mais
conservador, não gera inconsistência. Implementado como `User Function
PI_QTDATIVA()` (10 caracteres verificados sem colisão).

**Claim precisa gravar o timestamp**: `U_UPDSTAT` (compartilhado,
`FATZZF01.prw`) só grava `DTPROC`/`HRPROC` quando o status vira `'S'`,
nunca em `'A'` — sem isso `PI_MINATRS` não teria nada pra comparar.
Resolvido com um `TCSqlExec` extra logo após o `U_UPDSTAT("ZZC", cCod,
"A", "")` do claim, gravando `ZZC_DTPROC`/`ZZC_HRPROC` = agora — local,
só neste arquivo, não mexe no `U_UPDSTAT` compartilhado (nem afeta os
outros 6 Jobs).

### Trecho do laço `For nJ := 1 To Len(aFila)`

Hoje o corpo do laço chama `ZZC_MotorEntrada(jJson)` direto, trata
`aRet`, atualiza status e callback ali mesmo. Isso tudo migra pra
função nova (ver Mudança 2). O laço em `FATZZC01` fica responsável só
por:

1. Ler `cJson` (posicionar por `RECNO`, igual já faz hoje).
2. `U_UPDSTAT("ZZC", cCod, "A", "")` — continua aqui, é o claim.
3. Esperar vaga de thread (throttle acima).
4. Disparar `StartJob("U_PI_ENTTH", <cEnvServer>, .F., cCod, cChvNFe, cJson)`
   e seguir pro próximo `nJ` **sem esperar retorno**.

O `Begin Sequence/Recover/End Sequence` + `ErrorBlock` que hoje envolve
a chamada de `ZZC_MotorEntrada` sai do laço principal e vai pra dentro
da função nova — ele não protege nada rodando numa thread separada.

**Assinatura do `StartJob` confirmada** contra o stub do TDS neste
checkout (`.vscode/.advpl/_binary_functions.prw`, não é suposição):
`StartJob(<cName>, <cEnv>, <lWait>, [parm1..parm25])`. Implementado com
`cEnv := GetEnvServer()`, `lWait := .F.` (não espera). Parâmetros vão
como string crua (`cCod`/`cChvNFe`/`cJson`) — o stub documenta que
Code-Block/Object chegam como `NIL` do outro lado, então o JSON é
re-parseado dentro da thread, não passado como objeto já montado.

## Mudança 2 — função nova `U_PI_ENTTH` (thread worker)

Nome proposto: `U_PI_ENTTH` (10 caracteres exatos, prefixo `PI_`
conforme convenção do projeto). **Antes de criar, grep no projeto
inteiro pelos primeiros 10 caracteres de `U_PI_ENTTH` pra garantir que
não colide com nenhuma função existente** (regra dos 10 caracteres do
AdvPL, já documentada).

Essa função roda dentro da thread nova disparada pelo `StartJob`, então
**não herda nada do ambiente do Job pai** — precisa montar o próprio
contexto do zero, igual todo Job de Schedule faz hoje:

```
User Function PI_ENTTH(cCod, cChvNFe, cJson)
    Local jJson   := Nil
    Local aRet    := {}
    Local lOk     := .F.
    Local cSub    := ""
    Local cFilCb  := ""
    Local cDocCb  := ""
    Local cMsgSuc := ""
    Local cErrMsg := ""
    Local bErrOld := Nil
    Local oErrRT  := Nil

    Private __cBatch := "1"

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    jJson := JsonObject():New()
    If Empty(jJson:FromJson(cJson))
        bErrOld := ErrorBlock({|oErr| Break(oErr)})
        Begin Sequence
            aRet := ZZC_MotorEntrada(jJson)
        Recover Using oErrRT
            aRet := {.F., "EXCEPTION: " + U_PI_ERRO_RT(oErrRT), ""}
        End Sequence
        ErrorBlock(bErrOld)
        lOk  := aRet[1]
        cSub := IIF(Len(aRet) >= 3, cValToChar(aRet[3]), "")
        If lOk
            cFilCb  := IIF(Len(aRet) >= 5, cValToChar(aRet[4]), "")
            cDocCb  := IIF(Len(aRet) >= 5, cValToChar(aRet[5]), "")
            cMsgSuc := IIF(Len(aRet) >= 2, cValToChar(aRet[2]), "")
        Else
            cErrMsg := cValToChar(aRet[2])
        EndIf
    Else
        cErrMsg := "JSON invalido na fila ZZC. COD: " + cCod
    EndIf
    FreeObj(jJson)

    If lOk
        U_UPDSTAT("ZZC", cCod, "S", "")
        U_ZZCALLBK("ZZC", cChvNFe, cSub, .T., cFilCb, cDocCb, "", cMsgSuc)
        ConOut("[PI_ENTTH] OK: " + cCod)
    Else
        U_UPDSTAT("ZZC", cCod, "E", cErrMsg)
        U_ZZCALLBK("ZZC", cChvNFe, cSub, .F., "", "", cErrMsg)
        ConOut("[PI_ENTTH] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
    EndIf

    RpcClearEnv()
Return
```

`CEMPPAD`/`CFILPAD` continuam vindo dos `Static` já declarados no topo
de `FATZZC01.prw` (mesma constante hoje usada no Job). `ZZC_MotorEntrada`
não precisa mudar — continua `Static Function` no mesmo fonte, chamada
de dentro da nova `U_PI_ENTTH` (ambas no mesmo `.prw`).

## Parâmetros novos (SX6 — cadastrar antes de rodar)

- `MV_XCPTHR` — máximo de threads simultâneas na entrada. Default: **10**
  (confirmado — ambiente já está controlado o suficiente pra estrear
  nesse valor).
- `MV_XCPSTL` — minutos pra considerar `STATUS='A'` órfão (Job/thread
  travado de verdade, seguro resgatar). Default proposto: **15**.

## Pontos de atenção (aprendizados já documentados do projeto)

- Conferir encoding depois da edição (travessão/acento já corromperam
  em rodadas anteriores).
- `TCSqlExec`/`U_UPDSTAT` sempre checando retorno.
- Leitura de memo (`ZZC_JSON`) continua via `DbGoto(nRecno)` na área
  nativa, nunca direto do resultset — isso já está certo no código
  atual e não muda.
- Risco de cadastro duplicado de cliente/fornecedor se duas threads
  pegarem notas com o mesmo CNPJ novo ao mesmo tempo — **não resolvido
  nessa rodada**, é risco conhecido a observar no teste real. Se
  aparecer, próximo passo é lock por CNPJ antes do cadastro dentro de
  `U_PI_ENTTH` (ou dentro da rotina de cadastro que ela chama).
- **Variável compartilhada entre threads — motivo de `nOk`/`nErr` terem
  saído do laço principal.** Nenhuma variável de módulo (`Static` fora
  de função) pode ser escrita dentro de `U_PI_ENTTH` ou de qualquer
  função chamada por ela. Confirmado seguro: os únicos `Static` do
  arquivo (`CEMPPAD`/`CFILPAD`) são constantes, nunca reescritas —
  leitura concorrente é segura. Se surgir necessidade de um contador ou
  flag agregada entre threads no futuro, **não** usar variável de
  módulo direto — usar o próprio campo `STATUS` da `ZZC` (como já faz o
  throttle) ou, se for inevitável, `PutGlbValue`/`GetGlbValue` com
  muito cuidado (não é o caminho recomendado aqui).
- **Depuração multi-thread**: habilitar "Permitir depuração de
  múltiplas threads" no TDS/VSCode antes dos primeiros testes. Mesmo
  assim, depurar várias threads simultâneas é difícil — contar
  principalmente com os `ConOut` (todos já carregam `cCod`, dá pra
  filtrar o log por nota mesmo com processamento paralelo).
- **`FATZZC01` não sabe mais, em tempo real, se uma thread terminou com
  erro** — o processamento é fire-and-forget. A visibilidade de erro
  continua existindo (status `'E'` + `ZZC_ERRMSG` + callback pro
  iPaaS, igual hoje), só não é mais síncrona dentro da execução do
  Job. Se precisar de um resumo agregado por rodada (quantas OK/erro),
  é decisão separada — pode entrar depois com `IPCCount`/`IPCWaitEx` ou
  uma query de fechamento, não bloqueia essa entrega.

## Checklist de teste

0. Habilitar "Permitir depuração de múltiplas threads" no TDS/VSCode.
1. Cadastrar `MV_XCPTHR` e `MV_XCPSTL` no SX6.
2. Rodar com poucas notas na fila (2-3) e confirmar que processam em
   paralelo (log com timestamps sobrepostos) e que cada uma gera PC +
   NF corretos, sem duplicar.
3. Forçar um cenário de "órfão de verdade" (derrubar o appserver com
   uma linha em `'A'`) e confirmar que só é resgatada depois do
   `MV_XCPSTL`, não antes.
4. Rodar com fila maior que `MV_XCPTHR` e confirmar que o throttle
   segura o disparo (nunca mais que N notas `'A'` fresco ao mesmo
   tempo).
5. Medir tempo efetivo por nota contra a baseline de 15-25s sequencial
   — sem assumir ganho linear, é pra registrar o número real.
