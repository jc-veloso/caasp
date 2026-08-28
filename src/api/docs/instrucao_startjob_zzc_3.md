# Instrução pra Claude Code — StartJob assíncrono na ZZC (entrada)

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

**Não fazer a comparação de idade em SQL.** `TO_DATE`/`SYSDATE` são
Oracle (o SQL Server usa `CONVERT`/`GETDATE()`, por exemplo) — não tem
sintaxe única que rode igual nos bancos que o Protheus suporta, e não
vale a pena manter query dupla por dialeto. Calcular a idade em AdvPL
puro funciona igual em qualquer banco por trás.

**Atualização combinada com José Carlos/Maurício**: em vez de reaproveitar
`ZZC_DTPROC`/`ZZC_HRPROC` (campos genéricos, usados por outras partes do
fluxo pra outros fins) pra controle de thread, criar **campos dedicados
só pra isso**:

- `ZZC_THRDT` (Date) — data em que a thread foi disparada pra essa linha
  (o "claim").
- `ZZC_THRHR` (Character 8, `"HH:MM:SS"`) — hora do claim.

Cadastrar os dois no dicionário (SX3) da `ZZC` antes de implementar.

```
cQry := "SELECT ZZC_COD, ZZC_CHVNFE, ZZC_STATUS, ZZC_THRDT, ZZC_THRHR, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZC") + " "
cQry += "WHERE ZZC_STATUS IN ('P','A') AND ZZC_PRDPEN = 'N' "
cQry += "AND ZZC_FILIAL = '" + xFilial("ZZC") + "' "
cQry += "AND D_E_L_E_T_ = ' ' "
cQry += "ORDER BY ZZC_DTINCL, ZZC_HRINCL"
```

E no laço que monta `aFila`, filtra o `'A'` fresco antes de adicionar
(mesma lógica de antes, só trocando o campo de origem):

```
While (cAliZZC)->(!Eof())
    If (cAliZZC)->ZZC_STATUS == "P" .Or. PI_MINATRS((cAliZZC)->ZZC_THRDT, (cAliZZC)->ZZC_THRHR) > nMinStale
        aAdd(aFila, {AllTrim((cAliZZC)->ZZC_COD), AllTrim((cAliZZC)->ZZC_CHVNFE), (cAliZZC)->RECNO})
    EndIf
    (cAliZZC)->(DbSkip())
EndDo
```

Com `nMinStale := SuperGetMv("MV_XCPSTL", .F., 15)` lido uma vez no
início da função, e uma função nova pequena e portável (nenhuma
dependência de banco):

```
Static Function PI_MINATRS(dThrDt, cThrHr)
    Local nSegThr := 0
    If Empty(dThrDt) .Or. Empty(cThrHr)
        Return 999999  // sem claim registrado ainda -> trata como muito antigo, nao bloqueia
    EndIf
    nSegThr := Val(SubStr(cThrHr,1,2))*3600 + Val(SubStr(cThrHr,4,2))*60 + Val(SubStr(cThrHr,7,2))
Return (Date() - dThrDt) * 1440 + (Seconds() - nSegThr) / 60
```

(`Seconds()` é função nativa do AdvPL, retorna segundos decorridos
desde a meia-noite do servidor de aplicação — não precisa de nenhuma
função de banco.)

**Gravar o claim** (`ZZC_THRDT`/`ZZC_THRHR`) tem que acontecer no mesmo
momento que `U_UPDSTAT("ZZC", cCod, "A", "")`, no laço principal — ver
bloco completo do laço mais abaixo, no passo que já mostra isso.

### Throttle (esperar vaga antes de disparar)

Antes de disparar o `StartJob` de cada nota, checar quantas estão
`STATUS='A'` pra essa filial (`SELECT COUNT(*) FROM ZZC WHERE
ZZC_STATUS='A' AND ZZC_FILIAL=...` — sem data nenhuma, `COUNT` puro,
não tem problema de dialeto aqui), e esperar (`Sleep` curto, ex.
1000ms, repetindo o `COUNT` a cada ciclo) enquanto `nAtivas >=
MV_XCPTHR` (novo parâmetro, default **10**, é o número que o André
propôs). Isso reaproveita o próprio `STATUS='A'` como semáforo de
concorrência — não precisa de tabela ou contador novo. (Detalhe sem
risco: esse `COUNT` pode incluir algum órfão travado que ainda não foi
resgatado — só deixa o throttle um pouco mais conservador, não gera
inconsistência.)

### Trecho do laço `For nJ := 1 To Len(aFila)` — é AQUI que entra o `StartJob`

Hoje o corpo do laço chama `ZZC_MotorEntrada(jJson)` direto, trata
`aRet`, atualiza status e callback ali mesmo (linhas 64-104 do fonte
atual). Isso tudo migra pra função nova (ver Mudança 2). O `StartJob`
substitui exatamente o bloco que hoje vai de `jJson :=
JsonObject():New()` até o fim do `If lOk / Else` de status+callback
(linhas 71-104 do fonte original). O laço em `FATZZC01` fica assim:

```
For nJ := 1 To Len(aFila)
    cCod    := aFila[nJ][1]
    cChvNFe := aFila[nJ][2]
    nRecno  := aFila[nJ][3]

    DbSelectArea("ZZC")
    ZZC->(DbGoto(nRecno))
    cJson := ZZC->ZZC_JSON

    U_UPDSTAT("ZZC", cCod, "A", "")

    // grava o claim nos campos dedicados de controle de thread
    cQryClaim := "UPDATE " + RetSqlName("ZZC") + " SET ZZC_THRDT = '" + DToS(Date()) + "', "
    cQryClaim += "ZZC_THRHR = '" + Time() + "' WHERE ZZC_COD = '" + cCod + "' AND D_E_L_E_T_ = ' '"
    If !TCSqlExec(cQryClaim)
        ConOut("[FATZZC01] FALHA ao gravar claim de thread: " + cCod + " | " + TCSqlError())
    EndIf

    ConOut("[FATZZC01] Disparando thread: " + cCod + " | Chave: " + cChvNFe)

    // throttle: espera vaga antes de disparar a proxima thread
    While U_PI_QTDATIVA() >= SuperGetMv("MV_XCPTHR", .F., 10)
        Sleep(1000)
    EndDo

    // dispara e NAO espera retorno - segue pro proximo nJ
    StartJob("U_PI_ENTTH", GetEnvServer(), .F., cCod, cChvNFe, cJson)
Next nJ
```

(`cQryClaim` precisa ser declarada `Local` no topo de `FATZZC01`, junto
com as demais. `TCSqlExec` sempre checando retorno, conforme já é regra
do projeto.)

(`U_PI_QTDATIVA` é uma função pequena auxiliar só com o `SELECT
COUNT(*) FROM ZZC WHERE ZZC_STATUS='A' AND ZZC_FILIAL=...` descrito no
throttle acima — checar 10 caracteres antes de nomear, mesma regra.)

Note que `nOk`/`nErr` (contadores de fim do Job) somem do
`FATZZC01` — como o processamento agora é assíncrono, ele não sabe mais
quantas terminaram OK/erro no fim da própria execução (isso passa a
acontecer dentro de cada `U_PI_ENTTH`, minutos depois). Se José Carlos
quiser continuar tendo esse resumo por rodada, é um ponto a decidir
separado (ex. outra query de fechamento, ou log agregado por
`ZZC_DTINCL` do dia) — não é bloqueante pra essa entrega.

O `Begin Sequence/Recover/End Sequence` + `ErrorBlock` que hoje envolve
a chamada de `ZZC_MotorEntrada` sai do laço principal e vai pra dentro
da função nova — ele não protege nada rodando numa thread separada.

**Verificar no TDN a assinatura exata do `StartJob`** antes de
implementar (nome do parâmetro de servidor — normalmente
`GetEnvServer()` —, se tem `lReset`/flag de log, quantos parâmetros
variádicos aceita). Não tenho certeza absoluta da assinatura de cor;
confirmar contra a documentação oficial evita gastar tempo com erro de
sintaxe, igual aconteceu com o `RpcSetEnv` dentro de `WSRESTFUL`.

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
        // ZZC_ERRMSG passa a guardar tambem a mensagem de sucesso (decisao
        // com Mauricio: reaproveitar o campo existente em vez de criar um
        // novo so pra log de sucesso, por enquanto)
        U_UPDSTAT("ZZC", cCod, "S", cMsgSuc)
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

## Campos novos (SX3 — cadastrar antes de rodar)

- `ZZC_THRDT` (Date) — data do claim de thread (quando o `StartJob` foi
  disparado pra essa linha). Dedicado, não reaproveita `ZZC_DTPROC`.
- `ZZC_THRHR` (Character 8, `"HH:MM:SS"`) — hora do claim. Dedicado, não
  reaproveita `ZZC_HRPROC`.
- `ZZC_ERRMSG` (já existe) — passa a guardar também a mensagem de
  sucesso, não só erro (decisão com Mauricio: não criar campo novo pra
  isso por enquanto).

## Parâmetros novos (SX6 — cadastrar antes de rodar)

- `MV_XCPTHR` — máximo de threads simultâneas na entrada. Default: **10**
  (número do André — José Carlos confirmou manter, ambiente já está
  controlado o suficiente pra estrear nesse valor).
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
- **Variável compartilhada entre threads — motivo de `nOk`/`nErr`
  terem saído do laço principal.** Nenhuma variável de módulo (`Static`
  fora de função) pode ser escrita dentro de `U_PI_ENTTH` ou de
  qualquer função chamada por ela — os únicos `Static` do arquivo
  (`CEMPPAD`/`CFILPAD`) são constantes, nunca reescritas, então leitura
  concorrente é segura. Se em algum ponto da implementação surgir
  necessidade de um contador ou flag agregada entre threads, **não**
  usar variável de módulo direto — usar o próprio campo `STATUS` da
  `ZZC` (como já faz o throttle) ou, se for inevitável, `PutGlbValue`/
  `GetGlbValue` com muito cuidado (não é o caminho recomendado aqui).
- **Depuração multi-thread**: habilitar "Permitir depuração de
  múltiplas threads" no TDS/VSCode antes dos primeiros testes. Mesmo
  assim, depurar várias threads simultâneas é difícil — contar
  principalmente com os `ConOut` (todos já carregam `cCod`, dá pra
  filtrar o log por nota mesmo com processamento paralelo).
- **`FATZZC01` não sabe mais, em tempo real, se uma thread terminou com
  erro** — o processamento é fire-and-forget. A visibilidade de erro
  continua existindo (status `'E'` + `ZZC_ERRMSG` + callback pro
  Arthur, igual hoje), só não é mais síncrona dentro da execução do
  Job. Se precisar de um resumo agregado por rodada (quantas OK/erro),
  é decisão separada — pode entrar depois com `IPCCount`/`IPCWaitEx` ou
  uma query de fechamento, não bloqueia essa entrega.

## Checklist de teste

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
