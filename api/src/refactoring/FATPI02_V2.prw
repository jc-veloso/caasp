#Include "protheus.ch"
#Include "RESTFul.ch"
#Include "TopConn.ch"

/*/{Protheus.doc} WSRESTFUL FATPI02_V2
Fonte: Antonio NUNES_2026-03-08_FATPI02_CAMPOS_SEP
Descricao: Importador PRODUTO - 16 campos separados por blocos, Upsert e Validacao NCM/CEST.
@author Antonio NUNES
@since 08/03/2026
@version 48.0

[FIX-EXTRACAO] Jose Carlos - Artiq - 08/2026
A logica de upsert/validacao/MATA010 que vivia inteira dentro do WSMETHOD foi
extraida para User Function PI_PROD_X — o FATZZF01 (Job de produtos pendentes)
precisa cadastrar produto sem passar por HTTP, e esperava uma funcao
U_FATPI02_PROC que nunca existiu (suposicao incorreta, nunca conferida
contra este fonte). PI_PROD_X tem 10 caracteres (U_FATPI02_PROC tinha 14,
estourava o limite classico do AdvPL em fonte .prw). O WSMETHOD abaixo ficou
fino — so parseia o request, chama PI_PROD_X e monta a resposta HTTP.
Nenhuma regra de negocio mudou; e transcricao 1:1 do que ja existia.
/*/

WSRESTFUL FATPI02_V2 DESCRIPTION 'Importador PRODUTO CAASP'
    WSDATA id         AS STRING
    WSDATA updated_at AS STRING

    WSMETHOD POST DESCRIPTION 'Upsert de Produtos' WSSYNTAX "/fatpi02/v2" PATH '/fatpi02/v2' PRODUCES APPLICATION_JSON
END WSRESTFUL

/*/{Protheus.doc} WSMETHOD POST
/*/
WSMETHOD POST WSSERVICE FATPI02_V2
    Local cJson      := Self:GetContent()
    Local jJson       := JsonObject():New()
    Local jResponse   := JsonObject():New()
    Local aRes        := {}

    Self:SetContentType('application/json')
    jJson:FromJson(cJson)

    aRes := U_PI_PROD_X(jJson)

    Self:setStatus(201)
    If aRes[1]
        jResponse['resultado'] := "Sucesso"
        jResponse['mensagem']  := aRes[2]
        jResponse['cod_erp']   := aRes[3]
    Else
        jResponse['resultado'] := "Falha"
        jResponse['mensagem']  := aRes[2]
    EndIf
    Self:SetResponse(EncodeUTF8(jResponse:toJSON()))

    // Limpeza de memoria
    If ValType(jJson) == "O" ; jJson:Clear() ; FreeObj(jJson) ; EndIf

Return .T.

// ==========================================================================
// PI_PROD_X - Upsert de produto (SB1) via MATA010. Extraida do WSMETHOD POST
// NEW deste mesmo fonte para ser reaproveitavel pelo FATZZF01 (Job), que
// precisa cadastrar produto internamente, sem HTTP.
//
// Transcricao 1:1 da logica original — mesmos 5 passos (validacao de
// legado, upsert preventivo, validacao CEST, validacao NCM, montagem de
// campos + MsExecAuto/MATA010), so trocado o padrao de "seta lOk e segue"
// por early-return, equivalente em comportamento.
//
// Parametro: jJson (JsonObject com os dados do produto)
// Retorno:   {lOk, cMensagem, cCodProtheus}
//   lOk == .T.  -> cMensagem = mensagem de sucesso, cCodProtheus = B1_COD
//   lOk == .F.  -> cMensagem = motivo da falha, cCodProtheus = ""
// ==========================================================================
User Function PI_PROD_X(jJson)
    Local aDados         := {}
    Local cCodLegado     := ''
    Local cCodProtheus   := ''
    Local aErros         := {}
    Local nI             := 0
    Local cMensagem      := ""
    Local cGrupo         := ""
    Local cCentroCusto   := ""
    Local cContaContab   := ""
    Local cContaDef      := "11100901"
    Local nTamLegado     := 0
    Local cCest          := ""
    Local cNcm           := ""
    Local nOpcao         := 3
    Local aRet           := {.F., "", ""}

    Private lMsErroAuto    := .F.
    Private lMsHelpAuto    := .T.
    Private lAutoErrNoFile := .T.

    nTamLegado := TamSX3("B1_LEGADO")[1]

    // 1. EXTRACAO E VALIDACAO DA CHAVE LEGADO
    cCodLegado := If(jJson:HasProperty('cod'), AllTrim(cValToChar(jJson:GetJsonObject('cod'))), "")

    If Empty(cCodLegado)
        Return {.F., "Campo 'cod' (legado) obrigatorio nao enviado", ""}
    EndIf

    // 2. BUSCA PREVENTIVA (UPSERT)
    DbSelectArea("SB1")
    SB1->(DbOrderNickname("LEGADO"))
    If SB1->(DbSeek(xFilial("SB1") + PadR(cCodLegado, nTamLegado)))
        cCodProtheus := SB1->B1_COD
        nOpcao := 4
    Else
        nOpcao := 3
    EndIf

    // 3. VALIDACAO FISCAL: CEST (F0G)
    cCest := If(jJson:HasProperty('des_ProdutoCEST'), AllTrim(cValToChar(jJson:GetJsonObject('des_ProdutoCEST'))), "")
    If !Empty(cCest) .And. Lower(cCest) != "null"
        DbSelectArea("F0G")
        F0G->(DbSetOrder(1))
        If ! F0G->(DbSeek(xFilial("F0G") + cCest))
            Return {.F., "Validacao Fiscal: CEST [" + cCest + "] inexistente.", ""}
        EndIf
    EndIf

    // 4. VALIDACAO FISCAL: NCM (SYD)
    cNcm := If(jJson:HasProperty('pos_IPI_NCM'), AllTrim(cValToChar(jJson:GetJsonObject('pos_IPI_NCM'))), "")
    If !Empty(cNcm) .And. Lower(cNcm) != "null"
        DbSelectArea("SYD")
        SYD->(DbSetOrder(1))
        If ! SYD->(DbSeek(xFilial("SYD") + cNcm))
            Return {.F., "Validacao Fiscal: NCM [" + cNcm + "] inexistente.", ""}
        EndIf
    EndIf

    // 5. MONTAGEM DOS CAMPOS E EXECUCAO
    cGrupo := If(jJson:HasProperty('grupo'), AllTrim(cValToChar(jJson:GetJsonObject('grupo'))), "0002")
    cContaContab := If(jJson:HasProperty('cod_ContaContabil'), AllTrim(cValToChar(jJson:GetJsonObject('cod_ContaContabil'))), cContaDef)
    cCentroCusto := If(FindFunction("U_PI_CCUSTO_X"), U_PI_CCUSTO_X(cCodLegado), "03801")

    Begin Transaction
        If nOpcao == 3
            cCodProtheus := GetSXENum("SB1", "B1_COD")
            cMensagem    := "Produto cadastrado com sucesso"
        Else
            cMensagem    := "Produto atualizado com sucesso"
        EndIf

        aDados := {}

        // --- BLOCO 1: IDENTIFICACAO (3) ---
        aAdd(aDados, {'B1_FILIAL', xFilial("SB1"), Nil})
        aAdd(aDados, {'B1_COD',    cCodProtheus,   Nil})
        aAdd(aDados, {'B1_LEGADO', Left(cCodLegado, nTamLegado), Nil})

        // --- BLOCO 2: CARACTERISTICAS (5) ---
        // [FIX-TAMANHO] Jose Carlos - Artiq - 08/2026
        // Left(...,100) era chute — B1_DESC real tem 50 (MsExecAuto nao
        // trunca, so rejeita se nao couber). Troquei todos os campos de
        // texto livre pra usar TamSx3 de verdade, em vez de numero fixo
        // ou sem protecao nenhuma.
        aAdd(aDados, {'B1_DESC',   Upper(Left(AllTrim(cValToChar(If(jJson:HasProperty('descricao'), jJson:GetJsonObject('descricao'), ""))), TamSx3("B1_DESC")[1])), Nil})
        aAdd(aDados, {'B1_TIPO',   Left(AllTrim(cValToChar(If(jJson:HasProperty('tipo_Produto'), jJson:GetJsonObject('tipo_Produto'), "PA"))), TamSx3("B1_TIPO")[1]), Nil})
        aAdd(aDados, {'B1_UM',     Left(AllTrim(cValToChar(If(jJson:HasProperty('unidade'), jJson:GetJsonObject('unidade'), "UN"))), TamSx3("B1_UM")[1]), Nil})
        aAdd(aDados, {'B1_LOCPAD', Left(AllTrim(cValToChar(If(jJson:HasProperty('armazem'), jJson:GetJsonObject('armazem'), "01"))), TamSx3("B1_LOCPAD")[1]), Nil})
        aAdd(aDados, {'B1_GRUPO',  Left(cGrupo, TamSx3("B1_GRUPO")[1]), Nil})

        // --- BLOCO 3: DADOS FISCAIS / EAN (4) ---
        aAdd(aDados, {'B1_CEST',   Left(cCest, TamSx3("B1_CEST")[1]), Nil})
        aAdd(aDados, {'B1_CODBAR', Left(AllTrim(cValToChar(If(jJson:HasProperty('cod_ProdutoEAN'), jJson:GetJsonObject('cod_ProdutoEAN'), ""))), TamSx3("B1_CODBAR")[1]), Nil})
        aAdd(aDados, {'B1_POSIPI', Left(cNcm, TamSx3("B1_POSIPI")[1]), Nil})
        aAdd(aDados, {'B1_ORIGEM', Left(AllTrim(cValToChar(If(jJson:HasProperty('origem'), jJson:GetJsonObject('origem'), "0"))), TamSx3("B1_ORIGEM")[1]), Nil})

        // --- BLOCO 4: VALORES / CONTABEIS (4) ---
        aAdd(aDados, {'B1_PRV1',   Val(cValToChar(If(jJson:HasProperty('preco_Venda'), jJson:GetJsonObject('preco_Venda'), 0))), Nil})
        aAdd(aDados, {'B1_PESO',   Val(cValToChar(If(jJson:HasProperty('peso'), jJson:GetJsonObject('peso'), 0))), Nil})
        aAdd(aDados, {'B1_CONTA',  cContaContab, Nil})
        //aAdd(aDados, {'B1_CC',     cCentroCusto, Nil})

        ConOut("[PI_PROD_X] Chamando MsExecAuto MATA010 | Opcao: " + cValToChar(nOpcao) + " | Legado: " + cCodLegado + " | Cod: " + cCodProtheus + " | Desc: " + Left(cValToChar(If(jJson:HasProperty('descricao'), jJson:GetJsonObject('descricao'), "")), 60))

        MsExecAuto({|x, y, z| MATA010(x, y, z)}, aDados, nOpcao)

        If lMsErroAuto
            DisarmTransaction()
            RollBackSx8()
            aErros := GetAutoGRLog()
            cMensagem := ""
            ConOut("[PI_PROD_X] ERRO no MsExecAuto MATA010 — Legado: " + cCodLegado + " | Qtd linhas de log: " + cValToChar(Len(aErros)))
            For nI := 1 To Len(aErros)
                ConOut("[PI_PROD_X]   -> " + AllTrim(aErros[nI]))
                cMensagem += AllTrim(aErros[nI]) + " "
            Next nI
            If Len(aErros) == 0
                ConOut("[PI_PROD_X]   -> lMsErroAuto = .T. mas GetAutoGRLog() veio vazio (sem detalhe do MATA010)")
                cMensagem := "Erro no ExecAuto MATA010 sem detalhe no log (GetAutoGRLog vazio)"
            EndIf
            aRet := {.F., "Erro Protheus: " + AllTrim(cMensagem), ""}
        Else
            ConfirmSX8()
            ConOut("[PI_PROD_X] MATA010 OK | Legado: " + cCodLegado + " | Cod Protheus: " + AllTrim(cCodProtheus))
            aRet := {.T., cMensagem, AllTrim(cCodProtheus)}
        EndIf
    End Transaction

Return aRet
