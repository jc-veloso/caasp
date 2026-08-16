#Include "Totvs.ch"
#Include "RESTFul.ch"
#Include "TopConn.ch"

/*/{Protheus.doc} WSRESTFUL FATPI02
Fonte: Antonio NUNES_2026-03-08_FATPI02_CAMPOS_SEP
Descrição: Importador PRODUTO - 16 campos separados por blocos, Upsert e Validação NCM/CEST.
@author Antonio NUNES
@since 08/03/2026
@version 48.0
/*/

WSRESTFUL FATPI02 DESCRIPTION 'Importador PRODUTO CAASP'
    WSDATA id         AS STRING
    WSDATA updated_at AS STRING
 
    WSMETHOD POST NEW DESCRIPTION 'Upsert de Produtos' PATH 'new' PRODUCES APPLICATION_JSON
END WSRESTFUL

/*/{Protheus.doc} WSMETHOD POST NEW
/*/
WSMETHOD POST NEW WSSERVICE FATPI02
    // Variáveis locais sempre no início
    Local lRet           := .T.
    Local aDados         := {}
    Local jJson          := Nil
    Local cJson          := Self:GetContent()
    Local jResponse      := JsonObject():New()
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
    Local lOk            := .T. 
    
    // Variáveis Privadas para ExecAuto
    Private lMsErroAuto    := .F.
    Private lMsHelpAuto    := .T.
    Private lAutoErrNoFile := .T.

    Self:SetContentType('application/json')
    jJson := JsonObject():New()
    jJson:FromJson(cJson)
    
    nTamLegado := TamSX3("B1_LEGADO")[1]
 
    // 1. EXTRAÇÃO E VALIDAÇÃO DA CHAVE LEGADO
    cCodLegado := If(jJson:HasProperty('cod'), AllTrim(cValToChar(jJson:GetJsonObject('cod'))), "")
    
    If Empty(cCodLegado)
        Self:setStatus(201)
        jResponse['resultado'] := "Falha"
        jResponse['mensagem']  := "Campo 'cod' (legado) obrigatorio nao enviado"
        Self:SetResponse(EncodeUTF8(jResponse:toJSON()))
        lOk := .F.
    EndIf

    // 2. BUSCA PREVENTIVA (UPSERT)
    If lOk
        DbSelectArea("SB1")
        SB1->(DbOrderNickname("LEGADO"))
        If SB1->(DbSeek(xFilial("SB1") + PadR(cCodLegado, nTamLegado))) 
            cCodProtheus := SB1->B1_COD
            nOpcao := 4 
        Else
            nOpcao := 3 
        EndIf
    EndIf

    // 3. VALIDAÇÃO FISCAL: CEST (F0G)
    If lOk
        cCest := If(jJson:HasProperty('des_ProdutoCEST'), AllTrim(cValToChar(jJson:GetJsonObject('des_ProdutoCEST'))), "")
        If !Empty(cCest) .And. Lower(cCest) != "null"
            DbSelectArea("F0G")
            F0G->(DbSetOrder(1)) 
            If ! F0G->(DbSeek(xFilial("F0G") + cCest))
                Self:setStatus(201)
                jResponse['resultado'] := "Falha"
                jResponse['erro']      := "CEST"
                jResponse['mensagem']  := "Validacao Fiscal: CEST [" + cCest + "] inexistente."
                Self:SetResponse(EncodeUTF8(jResponse:toJSON()))
                lOk := .F.
            EndIf
        EndIf
    EndIf

    // 4. VALIDAÇÃO FISCAL: NCM (SYD)
    If lOk
        cNcm := If(jJson:HasProperty('pos_IPI_NCM'), AllTrim(cValToChar(jJson:GetJsonObject('pos_IPI_NCM'))), "")
        If !Empty(cNcm) .And. Lower(cNcm) != "null"
            DbSelectArea("SYD")
            SYD->(DbSetOrder(1)) 
            If ! SYD->(DbSeek(xFilial("SYD") + cNcm))
                Self:setStatus(201)
                jResponse['resultado'] := "Falha"
                jResponse['erro']      := "NCM"
                jResponse['mensagem']  := "Validacao Fiscal: NCM [" + cNcm + "] inexistente."
                Self:SetResponse(EncodeUTF8(jResponse:toJSON()))
                lOk := .F.
            EndIf
        EndIf
    EndIf

    // 5. MONTAGEM DOS CAMPOS E EXECUÇÃO
    If lOk
        cGrupo := If(jJson:HasProperty('grupo'), AllTrim(cValToChar(jJson:GetJsonObject('grupo'))), "0002")
        cContaContab := If(jJson:HasProperty('cod_ContaContabil'), AllTrim(cValToChar(jJson:GetJsonObject('cod_ContaContabil'))), cContaDef)
        cCentroCusto := If(FindFunction("U_FZ_CC_X"), u_FZ_CC_X(cCodLegado), "03801")

        Begin Transaction
            If nOpcao == 3
                cCodProtheus := GetSXENum("SB1", "B1_COD")
                cMensagem    := "Produto cadastrado com sucesso"
            Else
                cMensagem    := "Produto atualizado com sucesso"
            EndIf

            aDados := {}

            // --- BLOCO 1: IDENTIFICAÇÃO (3) ---
            aAdd(aDados, {'B1_FILIAL', xFilial("SB1"), Nil}) 
            aAdd(aDados, {'B1_COD',    cCodProtheus,   Nil}) 
            aAdd(aDados, {'B1_LEGADO', cCodLegado,     Nil}) 

            // --- BLOCO 2: CARACTERÍSTICAS (5) ---
            aAdd(aDados, {'B1_DESC',   Upper(Left(AllTrim(cValToChar(If(jJson:HasProperty('descricao'), jJson:GetJsonObject('descricao'), ""))), 100)), Nil})
            aAdd(aDados, {'B1_TIPO',   AllTrim(cValToChar(If(jJson:HasProperty('tipo_Produto'), jJson:GetJsonObject('tipo_Produto'), "PA"))), Nil})
            aAdd(aDados, {'B1_UM',     AllTrim(cValToChar(If(jJson:HasProperty('unidade'), jJson:GetJsonObject('unidade'), "UN"))), Nil})
            aAdd(aDados, {'B1_LOCPAD', AllTrim(cValToChar(If(jJson:HasProperty('armazem'), jJson:GetJsonObject('armazem'), "01"))), Nil}) 
            aAdd(aDados, {'B1_GRUPO',  cGrupo, Nil}) 

            // --- BLOCO 3: DADOS FISCAIS / EAN (4) ---
            aAdd(aDados, {'B1_CEST',   cCest, Nil}) 
            aAdd(aDados, {'B1_CODBAR', AllTrim(cValToChar(If(jJson:HasProperty('cod_ProdutoEAN'), jJson:GetJsonObject('cod_ProdutoEAN'), ""))), Nil})
            aAdd(aDados, {'B1_POSIPI', cNcm, Nil}) 
            aAdd(aDados, {'B1_ORIGEM', AllTrim(cValToChar(If(jJson:HasProperty('origem'), jJson:GetJsonObject('origem'), "0"))), Nil})

            // --- BLOCO 4: VALORES / CONTÁBEIS (4) ---
            aAdd(aDados, {'B1_PRV1',   Val(cValToChar(If(jJson:HasProperty('preco_Venda'), jJson:GetJsonObject('preco_Venda'), 0))), Nil})
            aAdd(aDados, {'B1_PESO',   Val(cValToChar(If(jJson:HasProperty('peso'), jJson:GetJsonObject('peso'), 0))), Nil})
            aAdd(aDados, {'B1_CONTA',  cContaContab, Nil}) 
            //aAdd(aDados, {'B1_CC',     cCentroCusto, Nil}) 

            MsExecAuto({|x, y, z| MATA010(x, y, z)}, aDados, nOpcao)

            If lMsErroAuto
                DisarmTransaction()
                RollBackSx8()
                aErros := GetAutoGRLog()
                cMensagem := ""
                For nI := 1 To Len(aErros); cMensagem += AllTrim(aErros[nI]) + " "; Next nI
                Self:setStatus(201)
                jResponse['resultado'] := "Falha"
                jResponse['mensagem']  := "Erro Protheus: " + AllTrim(cMensagem)
            Else
                ConfirmSX8()
                Self:setStatus(201)
                jResponse['resultado'] := "Sucesso"
                jResponse['mensagem']  := cMensagem
                jResponse['cod_erp']   := AllTrim(cCodProtheus)
            EndIf
        End Transaction
        Self:SetResponse(EncodeUTF8(jResponse:toJSON()))
    EndIf

    // Limpeza de memória
    aDados := {} 
    If ValType(jJson) == "O" ; jJson:Clear() ; FreeObj(jJson) ; EndIf
    
Return lRet
