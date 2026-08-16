# Retry na API da CAASP + notificação de falha definitiva — FATZZF01.prw

## Contexto

Dois pontos ficaram pendentes da última rodada (o Code implementou a
integração com a API da CAASP em `ZZF_CADPRD`, mas sem retry nem
notificação de falha):

1. **Retry** — a API da CAASP é instável (confirmado com o Arthur).
   Precisa reentar em caso de falha de rede/HTTP.
2. **Notificação de falha definitiva** — se esgotar o retry sem sucesso,
   avisar o Arthur via callback já existente (`ZZCALLBK`), não deixar a
   nota represada silenciosamente.

## 1. Retry em `ZZF_CADPRD` (dentro de `FATZZF01.prw`)

### 1.1 — Dois parâmetros novos (SX6/MV_)
- `MV_XCPRET` — número de retries (tentativas **adicionais**, além da
  primeira). Default `5` se não configurado. `0` desativa o retry (só a
  tentativa original).
- `MV_XCPWAIT` — segundos de espera entre tentativas. Default `2`.

### 1.2 — Envolver só a chamada HTTP num laço de retry
**Importante: só reentar em falha de rede/HTTP** (`oHttp:GetLastError()`
não vazio, ou corpo vazio). **NÃO reentar** quando a resposta é válida mas
`items` vem vazio (produto não encontrado na CAASP) — isso é resultado
definitivo, não instabilidade, retry não ajuda.

Estrutura esperada (adaptar ao estilo do arquivo, mas a lógica é esta):
```advpl
Local nRetries  := SuperGetMv("MV_XCPRET", .F., 5)
Local nWaitSecs := SuperGetMv("MV_XCPWAIT", .F., 2)
Local nTent     := 0
Local lHttpOk   := .F.
Local cErroHttp := ""

For nTent := 0 To nRetries
    If nTent > 0
        ConOut("[ZZF_CADPRD] Retry " + cValToChar(nTent) + "/" + cValToChar(nRetries) + " para produto: " + cCodLeg)
        Sleep(nWaitSecs * 1000)
    EndIf

    oHttp := FWHTTPClient():New()
    oHttp:AddHeader("Authorization", "Bearer " + cToken)
    cBody := oHttp:Get(cUrl + "?int_PaginaAtual=1&int_ItemsPorPagina=1&cod_Produto=" + AllTrim(cCodLeg))

    If oHttp:GetLastError() != "" .Or. Empty(cBody)
        cErroHttp := oHttp:GetLastError()
        FreeObj(oHttp)
        Loop  // tenta de novo, ou sai do For se essa era a ultima
    EndIf
    FreeObj(oHttp)

    lHttpOk := .T.
    Exit  // sucesso HTTP, nao precisa mais tentar
Next nTent

If !lHttpOk
    Return {.F., "Falha HTTP ao consultar produto na API CAASP apos " + cValToChar(nRetries + 1) + " tentativa(s): " + cCodLeg + " | " + cErroHttp}
EndIf
```
O resto de `ZZF_CADPRD` (parse do JSON, checagem de `items`, chamada de
`U_PI_PROD_X`) continua **fora** do laço de retry, sem mudança.

## 2. Notificação de falha definitiva — no laço principal de `FATZZF01()`

No branch `Else` (onde hoje só marca `STATUS='E'` e segue pro próximo),
adicionar notificação via `U_ZZCALLBK` — **usando a assinatura certa por
domínio**, já que `CBackNotaF` (Nota Fiscal/NFCe) e `CBackRecib` (Recibo)
esperam parâmetros diferentes:

```advpl
Else
    U_UPDSTAT("ZZF", cCod, "E", cErrMsg)
    nErr++
    ConOut("[FATZZF01] ERRO produto: " + cCodLeg + " | " + Left(cErrMsg, 100))

    // [NOTIFICA-FALHA] Produto nao pode ser cadastrado apos esgotar o
    // retry — nota nunca vai liberar sozinha, avisa o Arthur em vez de
    // deixar represada silenciosamente. cod_Subseccao vai vazio (decisao
    // consciente — o payload de aviso de produto pendente nao traz esse
    // dado, e nao vale reabrir a nota pai so pra buscar).
    Do Case
        Case cTipoNF == "NFS" ; cTabPai := "ZZA"
        Case cTipoNF == "NFD" ; cTabPai := "ZZB"
        Case cTipoNF == "NFE" ; cTabPai := "ZZC"
        Case cTipoNF == "NFC" ; cTabPai := "ZZD"
        Case cTipoNF == "RCV" ; cTabPai := "ZZE"
        Otherwise              ; cTabPai := "ZZA"
    EndCase

    If cTabPai == "ZZE"
        U_ZZCALLBK("ZZE", cChvRef, "Falha", "Produto pendente nao cadastrado: " + cErrMsg)
    Else
        U_ZZCALLBK(cTabPai, cChvRef, "", .F., "", "", "Produto pendente nao cadastrado: " + cErrMsg)
    EndIf
EndIf
```

Note que o `Do Case` acima é o **mesmo** que já existe no branch de
sucesso (linha ~96-103 do arquivo atual, usado antes de `ZZF_LIBNF`) —
não duplicar lógica nova, só replicar a mesma classificação já validada.

## Validação depois de aplicar

1. Confirmar que `MV_XCPRET=0` realmente desativa o retry (só 1 tentativa,
   sem `Sleep` nenhum)
2. Confirmar que "produto não encontrado" (items vazio) **não** aciona
   retry — só 1 chamada HTTP nesse caso
3. Confirmar que a notificação de falha usa a assinatura certa: `ZZE` vai
   por `CBackRecib` (4 args), as outras 4 tabelas vão por `CBackNotaF`
   (7 args, com `lSucesso=.F.`)
4. Balanceamento `If`/`EndIf`/`For`/`Next` deve mudar (adicionou blocos
   novos) — conferir contagem antes/depois só pra garantir que nada ficou
   desbalanceado na edição
