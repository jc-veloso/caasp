# Callback de "produtos cadastrados" no endpoint oficial (pedido do Arthur)

## Contexto

Arthur pediu: o mesmo endpoint oficial de Notas Fiscais (o que já usamos
quando a nota termina de processar) deve ser chamado também no momento em
que o `FATZZF01` termina de cadastrar os produtos pendentes e libera a
nota — não só no fim do processamento real.

Problema: `CBackNotaF` hoje só sabe montar a mensagem de sucesso no
formato `"Nota: [filial] - [documento]"` — mas nesse momento (produto
cadastrado, nota só liberada, ainda não processada) não existe
`documento` ainda, quem gera isso é o Job que processa a nota de
verdade (`FATZZD01`/`FATZZA01`/etc.), mais adiante.

**Decisão fechada com o José Carlos**: nesse evento intermediário, manda
`flg_Processamento: "S"` com `des_Processamento: "Produtos cadastrados.
Nota em processamento."` (sem o formato "Nota: filial - documento").

**Recibo (`RCV`/`ZZE`) fica de fora** — continua chamando o mecanismo
antigo (`ZZX_IPURL`/`CBackRecib`), sem mudança. O callback oficial de
Recibo ainda não foi implementado (pendente separado).

## Arquivo único: `FATZZF01.prw`

### 1. Estender `CBackNotaF` pra aceitar mensagem customizada

Adicionar um 8º elemento opcional ao array `aDados` — se vier preenchido,
sobrescreve a montagem automática de `des_Processamento` (tanto pro
formato "Nota: filial - documento" quanto pro erro):

```advpl
Static Function CBackNotaF(aDados)
    Local oHttp       := Nil
    Local jPayload    := JsonObject():New()
    Local cTab        := aDados[1]
    Local cChave      := aDados[2]
    Local cSubSeccao  := aDados[3]
    Local lSucesso    := aDados[4]
    Local cFilNota    := aDados[5]
    Local cDocumento  := aDados[6]
    Local cMsgErro    := aDados[7]
    Local cMsgCustom  := IIF(Len(aDados) >= 8, aDados[8], "")
    Local cUrl        := "https://api-ipaas.totvs.app/ipaas/api/v1/integrations/9aa6e2ae-1ece-4907-ba77-61c33d07bd79/api-key/6df64a64-4fc2-4b31-9c36-0958f06fcf33"

    If cSubSeccao == Nil ; cSubSeccao := "" ; EndIf
    If lSucesso   == Nil ; lSucesso   := .F. ; EndIf
    If cFilNota   == Nil ; cFilNota   := "" ; EndIf
    If cDocumento == Nil ; cDocumento := "" ; EndIf
    If cMsgErro   == Nil ; cMsgErro   := "" ; EndIf

    jPayload['cod_ChaveNFe']  := cChave
    jPayload['cod_Subseccao'] := Val(cSubSeccao)

    If !Empty(cMsgCustom)
        jPayload['des_Processamento'] := cMsgCustom
        jPayload['flg_Processamento'] := IIF(lSucesso, "S", "E")
    ElseIf lSucesso
        jPayload['des_Processamento'] := "Nota: " + AllTrim(cFilNota) + " - " + AllTrim(cDocumento)
        jPayload['flg_Processamento'] := "S"
    Else
        jPayload['des_Processamento'] := cMsgErro
        jPayload['flg_Processamento'] := "E"
    EndIf

    // resto da funcao (montagem do oHttp, envio, log) sem mudanca
```

(Manter todo o resto do corpo da função igual — só a montagem do
`des_Processamento`/`flg_Processamento` muda, virando um `If/ElseIf/Else`
em vez do `If/Else` atual.)

### 2. Atualizar o roteador `ZZCALLBK` pra repassar o 8º parâmetro

```advpl
User Function ZZCALLBK(cTab, cChave, p3, p4, p5, p6, p7, p8)
    If cTab == "ZZE" .Or. cTab == "ZZF"
        CBackRecib(cTab, cChave, p3, p4)
    Else
        CBackNotaF({cTab, cChave, p3, p4, p5, p6, p7, p8})
    EndIf
Return()
```

### 3. Trocar o disparo no laço principal (`FATZZF01()`)

Localizar o bloco onde a nota é liberada (`ZZF_LIBNF` + `ConOut("[FATZZF01]
Nota liberada...")`) e trocar a chamada de callback logo depois:

```advpl
If ZZF_ALL_OK(cChvRef, cCod)
    Do Case
        Case cTipoNF == "NFS" ; cTabPai := "ZZA"
        Case cTipoNF == "NFD" ; cTabPai := "ZZB"
        Case cTipoNF == "NFE" ; cTabPai := "ZZC"
        Case cTipoNF == "NFC" ; cTabPai := "ZZD"
        Case cTipoNF == "RCV" ; cTabPai := "ZZE"
        Otherwise              ; cTabPai := "ZZA"
    EndCase
    ZZF_LIBNF(cTabPai, cChvRef)
    ConOut("[FATZZF01] Nota liberada na " + cTabPai + " | Chave: " + cChvRef)

    // [FIX-CALLBACK-PRODUTO] Jose Carlos - Artiq - 08/2026
    // Pedido do Arthur: mesmo endpoint oficial de Notas Fiscais na
    // liberacao de produto, nao so no processamento final. Recibo (ZZE)
    // fica no mecanismo antigo — callback oficial de Recibo ainda nao
    // existe.
    If cTabPai == "ZZE"
        U_ZZCALLBK("ZZF", cChvRef, "ProdutosCadastrados", "Todos os produtos cadastrados. Nota liberada para processamento.")
    Else
        U_ZZCALLBK(cTabPai, cChvRef, "", .T., "", "", "", "Produtos cadastrados. Nota em processamento.")
    EndIf
EndIf
```

**Atenção**: a chamada pra `RCV` continua passando `"ZZF"` literal como
primeiro argumento (formato antigo, 4 argumentos) — não mudar isso, é o
que já funciona hoje pro Recibo.

## Validação depois de aplicar

1. Confirmar que a chamada de `NFS`/`NFD`/`NFE`/`NFC` (liberação de
   produto) chega no endpoint oficial com `flg_Processamento: "S"` e
   `des_Processamento: "Produtos cadastrados. Nota em processamento."`
2. Confirmar que `RCV` continua exatamente como estava (sem regressão)
3. Balanceamento `If`/`EndIf`/`Do Case`/`EndCase` no arquivo
4. Testar os dois cenários (nota com produto pendente completo, e nota
   sem pendência nenhuma) pra garantir que o segundo caminho (callback no
   fim do processamento real, no `FATZZD01`/`FATZZA01`) continua intacto
   e não foi afetado por essa mudança
