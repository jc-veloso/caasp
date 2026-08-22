#Include "protheus.ch"
#Include "RESTFul.ch"
#Include "TopConn.ch"

// POST /fatpi02/v2 - endpoint de upsert de produto (SB1), tambem chamavel diretamente via U_PI_PROD_X

WSRESTFUL FATPI02_V2 DESCRIPTION 'Importador PRODUTO CAASP'
    WSDATA id         AS STRING
    WSDATA updated_at AS STRING

    WSMETHOD POST DESCRIPTION 'Upsert de Produtos' WSSYNTAX "/fatpi02/v2" PATH '/fatpi02/v2' PRODUCES APPLICATION_JSON
END WSRESTFUL

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

    If ValType(jJson) == "O" ; jJson:Clear() ; FreeObj(jJson) ; EndIf

Return .T.

// Upsert de produto (SB1) via MATA010, validando CEST/NCM antes de gravar
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

    cCodLegado := If(jJson:HasProperty('cod'), AllTrim(cValToChar(jJson:GetJsonObject('cod'))), "")

    If Empty(cCodLegado)
        Return {.F., "Campo 'cod' (legado) obrigatorio nao enviado", ""}
    EndIf

    DbSelectArea("SB1")
    SB1->(DbOrderNickname("LEGADO"))
    If SB1->(DbSeek(xFilial("SB1") + PadR(cCodLegado, nTamLegado)))
        cCodProtheus := SB1->B1_COD
        nOpcao := 4
    Else
        nOpcao := 3
    EndIf

    cCest := If(jJson:HasProperty('des_ProdutoCEST'), AllTrim(cValToChar(jJson:GetJsonObject('des_ProdutoCEST'))), "")
    If !Empty(cCest) .And. Lower(cCest) != "null"
        DbSelectArea("F0G")
        F0G->(DbSetOrder(1))
        If ! F0G->(DbSeek(xFilial("F0G") + cCest))
            Return {.F., "Validacao Fiscal: CEST [" + cCest + "] inexistente.", ""}
        EndIf
    EndIf

    cNcm := If(jJson:HasProperty('pos_IPI_NCM'), AllTrim(cValToChar(jJson:GetJsonObject('pos_IPI_NCM'))), "")
    If !Empty(cNcm) .And. Lower(cNcm) != "null"
        DbSelectArea("SYD")
        SYD->(DbSetOrder(1))
        If ! SYD->(DbSeek(xFilial("SYD") + cNcm))
            Return {.F., "Validacao Fiscal: NCM [" + cNcm + "] inexistente.", ""}
        EndIf
    EndIf

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

        aAdd(aDados, {'B1_FILIAL', xFilial("SB1"), Nil})
        aAdd(aDados, {'B1_COD',    cCodProtheus,   Nil})
        aAdd(aDados, {'B1_LEGADO', Left(cCodLegado, nTamLegado), Nil})

        aAdd(aDados, {'B1_DESC',   Upper(Left(AllTrim(cValToChar(If(jJson:HasProperty('descricao'), jJson:GetJsonObject('descricao'), ""))), TamSx3("B1_DESC")[1])), Nil})
        aAdd(aDados, {'B1_TIPO',   Left(AllTrim(cValToChar(If(jJson:HasProperty('tipo_Produto'), jJson:GetJsonObject('tipo_Produto'), "PA"))), TamSx3("B1_TIPO")[1]), Nil})
        aAdd(aDados, {'B1_UM',     Left(AllTrim(cValToChar(If(jJson:HasProperty('unidade'), jJson:GetJsonObject('unidade'), "UN"))), TamSx3("B1_UM")[1]), Nil})
        aAdd(aDados, {'B1_LOCPAD', Left(AllTrim(cValToChar(If(jJson:HasProperty('armazem'), jJson:GetJsonObject('armazem'), "01"))), TamSx3("B1_LOCPAD")[1]), Nil})
        aAdd(aDados, {'B1_GRUPO',  Left(cGrupo, TamSx3("B1_GRUPO")[1]), Nil})

        aAdd(aDados, {'B1_CEST',   Left(cCest, TamSx3("B1_CEST")[1]), Nil})
        aAdd(aDados, {'B1_CODBAR', Left(AllTrim(cValToChar(If(jJson:HasProperty('cod_ProdutoEAN'), jJson:GetJsonObject('cod_ProdutoEAN'), ""))), TamSx3("B1_CODBAR")[1]), Nil})
        aAdd(aDados, {'B1_POSIPI', Left(cNcm, TamSx3("B1_POSIPI")[1]), Nil})
        aAdd(aDados, {'B1_ORIGEM', Left(AllTrim(cValToChar(If(jJson:HasProperty('origem'), jJson:GetJsonObject('origem'), "0"))), TamSx3("B1_ORIGEM")[1]), Nil})

        aAdd(aDados, {'B1_PRV1',   Val(cValToChar(If(jJson:HasProperty('preco_Venda'), jJson:GetJsonObject('preco_Venda'), 0))), Nil})
        aAdd(aDados, {'B1_PESO',   Val(cValToChar(If(jJson:HasProperty('peso'), jJson:GetJsonObject('peso'), 0))), Nil})
        aAdd(aDados, {'B1_CONTA',  cContaContab, Nil})

        ConOut("[PI_PROD_X] Chamando MsExecAuto MATA010 | Opcao: " + cValToChar(nOpcao) + " | Legado: " + cCodLegado + " | Cod: " + cCodProtheus + " | Desc: " + Left(cValToChar(If(jJson:HasProperty('descricao'), jJson:GetJsonObject('descricao'), "")), 60))

        MsExecAuto({|x, y, z| MATA010(x, y, z)}, aDados, nOpcao)

        If lMsErroAuto
            DisarmTransaction()
            RollBackSx8()
            aErros := GetAutoGRLog()
            cMensagem := ""
            ConOut("[PI_PROD_X] ERRO no MsExecAuto MATA010 � Legado: " + cCodLegado + " | Qtd linhas de log: " + cValToChar(Len(aErros)))
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
