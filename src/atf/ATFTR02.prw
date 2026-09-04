//Bibliotecas
#Include "totvs.ch"
#Include "FWMVCDef.ch"

#Define OP_BAIXA  "1"
#Define OP_TRANSF "2"

// Variaveis Estaticas do Fonte
Static cTitle
Static cKeyFields
Static cTableAlias
Static oGerenciador

/*/{Protheus.doc} ATFTR02
Entry Point - Carregamento do Browse MVC principal 100% AdvPL
@author Antonio Nunes O Jr
@since 27/08/2026
@version 1.0
@description Cofre Validacao26-08-26 - Ponto de entrada para gestao de lotes de ativos.
/*/
User Function ATFTR02()
    Local oBrowse
    Local aArea
    
    aArea       := FWGetArea()
    cTitle      := "Gestao de Lotes de Ativos"
    cKeyFields  := "Z6_NUMLOT;Z6_DATAINC;Z6_TIPOOP;"
    cTableAlias := "SZ6"

    DbSelectArea("SN1")
    DbSelectArea("SN3")
    DbSelectArea("SZ6")
    SZ6->(DbSetOrder(1)) 

    // Instanciando o browse
    oBrowse := FWMBrowse():New()
    oBrowse:SetAlias(cTableAlias)
    oBrowse:SetDescription(cTitle)
    oBrowse:SetMenuDef("ATFTR02")
    
    // Legendas
    oBrowse:AddLegend("Z6_STATUS == 'PROC'", "GREEN",   "Processado (Baixa)")
    oBrowse:AddLegend("Z6_STATUS == 'TRAN'", "BLUE",    "Transferido (Origem)")
    oBrowse:AddLegend("Z6_STATUS == 'DEST'", "BR_PINK", "Destino Transferencia")
    oBrowse:AddLegend("Z6_STATUS == 'PEND'", "RED",     "Pendente com Erro")
    oBrowse:AddLegend("Empty(Z6_STATUS)",    "YELLOW",  "Nao Processado")

    oBrowse:DisableDetails()
    oBrowse:DisableReport()

    // Ativa a Browse
    oBrowse:Activate()

    FWRestArea(aArea)
Return Nil

/*/{Protheus.doc} MenuDef
Opcoes do Menu
@type Static Function
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
Static Function MenuDef()
    Local aRotina 
    
    aRotina := {}

    ADD OPTION aRotina TITLE "Visualizar"     ACTION "VIEWDEF.ATFTR02" OPERATION 2 ACCESS 0
    ADD OPTION aRotina TITLE "Incluir"        ACTION "VIEWDEF.ATFTR02" OPERATION 3 ACCESS 0
    ADD OPTION aRotina TITLE "Alterar"        ACTION "VIEWDEF.ATFTR02" OPERATION 4 ACCESS 0
    ADD OPTION aRotina TITLE "Excluir"        ACTION "VIEWDEF.ATFTR02" OPERATION 5 ACCESS 0
    ADD OPTION aRotina TITLE "Processar Lote" ACTION "U_ATFT0212"      OPERATION 6 ACCESS 0

Return aRotina

/*/{Protheus.doc} ModelDef
Estrutura MVC
@type Static Function
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
Static Function ModelDef()
    Local oStructEnchoice 
    Local oStructGrid     
    Local aRelation       
    Local oModel          
    Local bPos            
    Local bCancel         
    Local bLinePos
    Local bVldAct
    Local cIdx1
    Local aArea

    aRelation := {}
    aArea     := FWGetArea()
    cTitle    := "Gestao de Lotes de Ativos"
    cKeyFields:= "Z6_NUMLOT;Z6_DATAINC;Z6_TIPOOP;"
    
    oStructEnchoice := FWFormStruct(1, "SZ6", {|cField| AllTrim(cField) $ cKeyFields}) 
    
    // Injetando campo virtual oculto (Dummy) para forcar a edicao da estrutura principal
    oStructEnchoice:AddField("Dummy", "Dummy", "Z6_DUMMY", "C", 1, 0, Nil, Nil, {}, .F., {|| ""}, .F., .F., .T.)
    
    oStructGrid     := FWFormStruct(1, "SZ6", {|cField| !(AllTrim(cField) $ cKeyFields .Or. AllTrim(cField) == "Z6_STATUS")}) 

    // Mapeamento das rotinas em CodeBlocks para o Modelo MVC
    bVldAct     := {|oMdl| U_ATFT0221(oMdl)}
    bPos        := {|oMdl| U_ATFT0202(oMdl)}
    bCancel     := {|oMdl| .T.}
    bLinePos    := {|oGrid| U_ATFT0210(oGrid)}

    oModel := MPFormModel():New("ATFTR02M", Nil, bPos, /*bCommit*/ Nil, bCancel)
    
    // Setando a validacao de abertura
    oModel:SetVldActivate(bVldAct)

    oModel:AddFields("SZ6MASTER", /*cOwner*/, oStructEnchoice)
    oModel:AddGrid("SZ6DETAIL", "SZ6MASTER", oStructGrid, /*bLinePre*/ Nil, bLinePos)
    
    oModel:SetDescription("Modelo de dados - " + cTitle)
    oModel:GetModel("SZ6MASTER"):SetDescription("Dados de - " + cTitle)
    oModel:GetModel("SZ6DETAIL"):SetDescription("Grid de - " + cTitle)
    
    // Array vazio para evitar bloqueio agressivo de chave primaria nativo do MVC
    oModel:SetPrimaryKey({})

    aAdd(aRelation, {"Z6_FILIAL", "xFilial('SZ6')"} )
    aAdd(aRelation, {"Z6_NUMLOT", "Z6_NUMLOT"})
    
    DbSelectArea("SZ6")
    SZ6->(DbSetOrder(1))
    cIdx1 := SZ6->(IndexKey(1))
    FWRestArea(aArea)
    
    oModel:SetRelation("SZ6DETAIL", aRelation, cIdx1)
    
    // Plaqueta dita a regra de unicidade da linha
    oModel:GetModel("SZ6DETAIL"):SetUniqueLine({"Z6_CHAPA"})
    
    // Regras de Tela (Master) - TODAS AS EXPRESSOES SAO STRINGS (C)
    If oStructEnchoice:HasField("Z6_NUMLOT")
        oStructEnchoice:SetProperty("Z6_NUMLOT", MODEL_FIELD_INIT, FWBuildFeature(STRUCT_FEATURE_INIPAD, "U_ATFT0205()"))
        oStructEnchoice:SetProperty("Z6_NUMLOT", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0204()"))
    EndIf
    If oStructEnchoice:HasField("Z6_DATAINC")
        oStructEnchoice:SetProperty("Z6_DATAINC", MODEL_FIELD_INIT, FWBuildFeature(STRUCT_FEATURE_INIPAD, "dDataBase"))
        oStructEnchoice:SetProperty("Z6_DATAINC", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0204()"))
        oStructEnchoice:SetProperty("Z6_DATAINC", MODEL_FIELD_VALID, FWBuildFeature(STRUCT_FEATURE_VALID, "U_ATFT0217()"))
    EndIf
    If oStructEnchoice:HasField("Z6_TIPOOP")
        oStructEnchoice:SetProperty("Z6_TIPOOP", MODEL_FIELD_INIT, FWBuildFeature(STRUCT_FEATURE_INIPAD, "'1'"))
        oStructEnchoice:SetProperty("Z6_TIPOOP", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0204()"))
    EndIf

    // ==========================================================
    // REGRAS DE TELA (GRID) COM TRAVAS EM STRING (C)
    // ==========================================================
    
    // Gatilho Principal (Plaqueta)
    If oStructGrid:HasField("Z6_CHAPA")
        oStructGrid:SetProperty("Z6_CHAPA", MODEL_FIELD_VALID, FWBuildFeature(STRUCT_FEATURE_VALID, "U_ATFT0211()"))
        oStructGrid:SetProperty("Z6_CHAPA", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0208()"))
    EndIf
    
    // Campos Descritivos - Sempre Bloqueados
    If oStructGrid:HasField("Z6_CBASE")
        oStructGrid:SetProperty("Z6_CBASE", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, ".F."))
    EndIf
    If oStructGrid:HasField("Z6_ITEM")
        oStructGrid:SetProperty("Z6_ITEM", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, ".F."))
    EndIf
    If oStructGrid:HasField("Z6_DESCRI")
        oStructGrid:SetProperty("Z6_DESCRI", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, ".F."))
    EndIf
    
    // Regras de Baixa (Liberados apenas na operacao 1)
    If oStructGrid:HasField("Z6_PERBAI")
        oStructGrid:SetProperty("Z6_PERBAI", MODEL_FIELD_INIT, FWBuildFeature(STRUCT_FEATURE_INIPAD, "100"))
        oStructGrid:SetProperty("Z6_PERBAI", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0206()"))
    EndIf
    If oStructGrid:HasField("Z6_BAIXA")
        oStructGrid:SetProperty("Z6_BAIXA", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0206()"))
    EndIf
    If oStructGrid:HasField("Z6_MOTIVO")
        oStructGrid:SetProperty("Z6_MOTIVO", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0206()"))
    EndIf
    If oStructGrid:HasField("Z6_DEPREC")
        oStructGrid:SetProperty("Z6_DEPREC", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0206()"))
    EndIf

    // Regras de Origem e Custos
    If oStructGrid:HasField("Z6_FILORI")
        oStructGrid:SetProperty("Z6_FILORI", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, ".F.")) 
    EndIf
    If oStructGrid:HasField("Z6_CCORIG")
        oStructGrid:SetProperty("Z6_CCORIG", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, ".F."))
    EndIf
    If oStructGrid:HasField("Z6_CUSTBEM")
        oStructGrid:SetProperty("Z6_CUSTBEM", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, ".F."))
    EndIf
    If oStructGrid:HasField("Z6_DTPROC")
        oStructGrid:SetProperty("Z6_DTPROC", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, ".F."))
    EndIf
    
    // Regras de Transferencia (Destino - Liberados apenas na operacao 2)
    If oStructGrid:HasField("Z6_FILDES") 
        oStructGrid:SetProperty("Z6_FILDES", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0207()"))
    EndIf
    If oStructGrid:HasField("Z6_CCDEST") 
        oStructGrid:SetProperty("Z6_CCDEST", MODEL_FIELD_WHEN, FWBuildFeature(STRUCT_FEATURE_WHEN, "U_ATFT0207()"))
    EndIf

Return oModel

/*/{Protheus.doc} ViewDef
Visualizacao de dados
@type Static Function
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
Static Function ViewDef()
    Local oModel          
    Local oStructEnchoice 
    Local oStructGrid     
    Local oView           

    cKeyFields      := "Z6_NUMLOT;Z6_DATAINC;Z6_TIPOOP;"
    oModel          := FWLoadModel("ATFTR02") 
    oStructEnchoice := FWFormStruct(2, "SZ6", {|cField| AllTrim(cField) $ cKeyFields}) 
    oStructGrid     := FWFormStruct(2, "SZ6", {|cField| !(AllTrim(cField) $ cKeyFields .Or. AllTrim(cField) == "Z6_STATUS")}) 

    oView := FWFormView():New()
    oView:SetModel(oModel)
    oView:AddField("VIEW_SZ6", oStructEnchoice, "SZ6MASTER")
    oView:AddGrid("GRID_SZ6",  oStructGrid,  "SZ6DETAIL")

    oView:CreateHorizontalBox("CABEC", 30)
    oView:CreateHorizontalBox("GRID", 70)
    oView:SetOwnerView("VIEW_SZ6", "CABEC")
    oView:SetOwnerView("GRID_SZ6", "GRID")

    oView:EnableTitleView("VIEW_SZ6", "Cabecalho - Lote SZ6")
    oView:EnableTitleView("GRID_SZ6", "Itens do Lote")

    If oStructGrid:HasField("Z6_CHAPA")
        oView:AddIncrementField("GRID_SZ6", "Z6_CHAPA")
    EndIf

Return oView


// ============================================================================
// ================= FUNCOES DE VALIDACAO DA REGRA DE NEGOCIO =================
// ============================================================================

/*/{Protheus.doc} ATF_MESANO
Converte uma data em um valor comparavel de mes/ano (Ano*12+Mes)
@type Static Function
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
Static Function ATF_MESANO(dData)
Return (Year(dData) * 12) + Month(dData)

/*/{Protheus.doc} ATF_DESCSTATUS
Descricao do N1_STATUS (SN1)
@type Static Function
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
Static Function ATF_DESCSTATUS(cStatus)
    Local cDesc

    Do Case
        Case cStatus == "0"
            cDesc := "Pendente de Classificacao"
        Case cStatus == "1"
            cDesc := "Em Uso"
        Case cStatus == "2"
            cDesc := "Bloqueado por Usuario"
        Case cStatus == "3"
            cDesc := "Bloqueado por Local"
        Case cStatus == "4"
            cDesc := "Transferencia entre Filiais"
        OtherWise
            cDesc := "Nao classificado"
    EndCase

Return cDesc

/*/{Protheus.doc} ATFT0202
Pos-validacao do modelo (Usado para forcar alteracao no cabecalho na Inclusao)
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0202(oMdl)
    Local nOpc
    Local oCab
    
    nOpc := oMdl:GetOperation()
    
    // Modifica o campo Dummy para que o MVC saiba que o cabecalho foi editado e aprove a gravacao
    If nOpc == 3 .Or. nOpc == 4
        oCab := oMdl:GetModel("SZ6MASTER")
        If ValType(oCab) == "O"
            oCab:SetValue("Z6_DUMMY", "1")
        EndIf
    EndIf
    
Return .T.

/*/{Protheus.doc} ATFT0204
Libera a chave primaria apenas na Inclusao
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0204()
    Local lRet
    Local oMdlAct
    
    lRet := .T.
    oMdlAct := FWModelActive()
    
    If ValType(oMdlAct) == "O"
        lRet := (oMdlAct:GetOperation() == 3)
    EndIf
Return lRet

/*/{Protheus.doc} ATFT0205
Geracao automatica de numero de lote
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0205()
    Local cRetorno
    cRetorno := DToS(Date()) + SubStr(StrTran(Time(), ":", ""), 1, 4)
Return cRetorno

/*/{Protheus.doc} ATFT0206
When para campos de baixa
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0206()
    Local lRet
    Local oModelAct
    Local oCab
    Local cTipo
    
    lRet      := .F.
    oModelAct := FWModelActive()
    
    If ValType(oModelAct) == "O"
        oCab := oModelAct:GetModel("SZ6MASTER")
        If ValType(oCab) == "O"
            cTipo := oCab:GetValue("Z6_TIPOOP")
            If ValType(cTipo) == "C" .And. cTipo == OP_BAIXA
                lRet := .T.
            EndIf
        EndIf
    EndIf
Return lRet

/*/{Protheus.doc} ATFT0207
When para campos de transferencia
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0207()
    Local lRet
    Local oModelAct
    Local oCab
    Local cTipo
    
    lRet      := .F.
    oModelAct := FWModelActive()
    
    If ValType(oModelAct) == "O"
        oCab := oModelAct:GetModel("SZ6MASTER")
        If ValType(oCab) == "O"
            cTipo := oCab:GetValue("Z6_TIPOOP")
            If ValType(cTipo) == "C" .And. cTipo == OP_TRANSF
                lRet := .T.
            EndIf
        EndIf
    EndIf
Return lRet

/*/{Protheus.doc} ATFT0208
When para campo CHAPA
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0208()
    Local lRet
    lRet := .T.
Return lRet

/*/{Protheus.doc} ATFT0209
Validacao do Indice 3 - Anti-duplicidade
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0209()
    Local lRet
    Local cLote
    Local cTipo
    Local dData
    Local cFilAux
    Local nOpc
    Local aArea
    Local oModelAct
    Local oCab
    Local cChave3

    lRet      := .T.
    cFilAux   := xFilial("SZ6")
    aArea     := FWGetArea() 
    oModelAct := FWModelActive()
    
    If ValType(oModelAct) == "O"
        nOpc := oModelAct:GetOperation()
        
        If nOpc == 3 
            oCab := oModelAct:GetModel("SZ6MASTER")
            If ValType(oCab) == "O"
                cLote := oCab:GetValue("Z6_NUMLOT")
                cTipo := oCab:GetValue("Z6_TIPOOP")
                dData := oCab:GetValue("Z6_DATAINC")
                
                If ValType(cLote) == "C" .And. !Empty(cLote) .And. ValType(cTipo) == "C" .And. !Empty(cTipo) .And. ValType(dData) == "D" .And. !Empty(dData)
                    DbSelectArea("SZ6")
                    SZ6->(DbSetOrder(3)) 
                    
                    cChave3 := cFilAux + PadR(AllTrim(cLote), FWTamSX3("Z6_NUMLOT")[1]) + DToS(dData) + PadR(AllTrim(cTipo), FWTamSX3("Z6_TIPOOP")[1])
                    
                    If SZ6->(DbSeek(cChave3))
                        MsgAlert("Atencao: A combinacao de Lote (" + AllTrim(cLote) + "), Data (" + DToC(dData) + ") e Operacao (" + AllTrim(cTipo) + ") ja existe! Digite outra para seguir.", "Aviso")
                        lRet := .F.
                    EndIf
                EndIf
            EndIf
        EndIf
    EndIf
    
    FWRestArea(aArea)
Return lRet

/*/{Protheus.doc} ATFT0217
Valida a data de inclusao contra o MV_ULTDEPR:
- Mes/ano igual ou anterior ao MV_ULTDEPR: bloqueia sempre
- Mes seguinte ao MV_ULTDEPR: libera direto
- Mes posterior ao seguinte: alerta e aborta se o usuario responder Nao
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0217()
    Local lRet
    Local oModelAct
    Local oCab
    Local dDataInc
    Local dUltDepr
    Local nCompInc
    Local nCompUlt
    Local cMsg

    lRet      := .T.
    oModelAct := FWModelActive()

    If ValType(oModelAct) == "O"
        oCab := oModelAct:GetModel("SZ6MASTER")
        If ValType(oCab) == "O"
            dDataInc := oCab:GetValue("Z6_DATAINC")

            If ValType(dDataInc) == "D" .And. !Empty(dDataInc)
                dUltDepr := GetMV("MV_ULTDEPR", .F., CTOD(""))

                If ValType(dUltDepr) == "D" .And. !Empty(dUltDepr)
                    nCompInc := ATF_MESANO(dDataInc)
                    nCompUlt := ATF_MESANO(dUltDepr)

                    If nCompInc <= nCompUlt
                        cMsg := "A data de inclusao (" + DToC(dDataInc) + ") nao pode ser do mesmo mes ou anterior ao ultimo mes de depreciacao processado (MV_ULTDEPR: " + DToC(dUltDepr) + ")."
                        MsgAlert(cMsg, "Data Invalida")
                        lRet := .F.
                    ElseIf nCompInc > (nCompUlt + 1)
                        cMsg := "A data de inclusao (" + DToC(dDataInc) + ") nao esta no mes imediatamente seguinte ao ultimo mes de depreciacao processado (MV_ULTDEPR: " + DToC(dUltDepr) + ")." + CRLF + "Deseja confirmar mesmo assim?"
                        lRet := MsgYesNo(cMsg, "Atencao - Data de Inclusao")
                    EndIf
                EndIf
            EndIf
        EndIf
    EndIf

Return lRet

/*/{Protheus.doc} ATFT0210
Pos-validacao de linha - valida CHAPA e repassa dados
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0210(oGrid)
    Local lRet
    Local oStruct
    Local oModelAct
    Local oCab
    Local cTipo
    Local cData
    Local cChapa
    Local dBaixa
    
    lRet := .T.
    
    If oGrid:GetLine() <= 0
        Return .T.
    EndIf
    
    oStruct   := oGrid:GetStruct()
    oModelAct := FWModelActive()
    
    If ValType(oModelAct) == "O"
        oCab := oModelAct:GetModel("SZ6MASTER")
        If ValType(oCab) == "O"
            cTipo := oCab:GetValue("Z6_TIPOOP")
            cData := oCab:GetValue("Z6_DATAINC")
        EndIf
    EndIf
    
    cChapa := AllTrim(oGrid:GetValue("Z6_CHAPA"))
    
    If Empty(cChapa)
        Help("", 1, "VALID", "", "Numero da Plaqueta (CHAPA) e obrigatorio em todas as linhas.", 1, 0)
        Return .F.
    EndIf
    
    If ValType(cTipo) == "C" .And. oStruct:HasField("Z6_TIPOOP")
        oGrid:LoadValue("Z6_TIPOOP", cTipo)
    EndIf
    If ValType(cData) == "D" .And. oStruct:HasField("Z6_DATAINC")
        oGrid:LoadValue("Z6_DATAINC", cData)
    EndIf
    
    If ValType(cTipo) == "C" .And. cTipo == OP_BAIXA
        If oStruct:HasField("Z6_MOTIVO") .And. Empty(AllTrim(oGrid:GetValue("Z6_MOTIVO")))
            Help("", 1, "VALID", "", "Motivo obrigatorio para Baixa.", 1, 0)
            lRet := .F.
        EndIf
        
        If oStruct:HasField("Z6_BAIXA")
            dBaixa := oGrid:GetValue("Z6_BAIXA")
            If Empty(dBaixa)
                Help("", 1, "VALID", "", "Data de Baixa obrigatoria.", 1, 0)
                lRet := .F.
            EndIf
        EndIf
    EndIf
    
    If ValType(cTipo) == "C" .And. cTipo == OP_TRANSF
        If oStruct:HasField("Z6_FILDES") .And. Empty(AllTrim(oGrid:GetValue("Z6_FILDES")))
            Help("", 1, "VALID", "", "Filial de Destino obrigatoria na Transferencia.", 1, 0)
            lRet := .F.
        EndIf

        If oStruct:HasField("Z6_CCDEST") .And. Empty(AllTrim(oGrid:GetValue("Z6_CCDEST")))
            Help("", 1, "VALID", "", "Centro de Custo de Destino obrigatorio na Transferencia.", 1, 0)
            lRet := .F.
        EndIf

        // Filial de Destino e Centro de Custo de Destino podem repetir a origem, mas ao menos um dos dois precisa ser diferente.
        If lRet .And. oStruct:HasField("Z6_FILORI") .And. oStruct:HasField("Z6_FILDES") .And. ;
           oStruct:HasField("Z6_CCORIG") .And. oStruct:HasField("Z6_CCDEST")
            If oGrid:GetValue("Z6_FILORI") == oGrid:GetValue("Z6_FILDES") .And. ;
               AllTrim(oGrid:GetValue("Z6_CCORIG")) == AllTrim(oGrid:GetValue("Z6_CCDEST"))
                Help("", 1, "VALID", "", "A Filial de Destino ou o Centro de Custo de Destino deve ser diferente da origem.", 1, 0)
                lRet := .F.
            EndIf
        EndIf
    EndIf

Return lRet

/*/{Protheus.doc} ATFT0211
Validacao de CHAPA e carga de dados do bem
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0211()
    Local lRet
    Local oModel
    Local oGrid
    // Local oCab      // Nao utilizada - checagem agora usa N1_BAIXA, nao depende mais do tipo de operacao.
    Local cChapa
    Local cCBase
    Local aDados
    // Local cTipoAtual // Nao utilizada - checagem agora usa N1_BAIXA, nao depende mais do tipo de operacao.
    Local aAreaSN1
    Local cStatusBem
    Local cItemBem

    lRet       := .T.
    // cTipoAtual := ""
    oModel     := FWModelActive()
    oGrid      := oModel:GetModel("SZ6DETAIL")
    
    If ValType(oGerenciador) != "O"
        oGerenciador := ATFGER02():New()
    EndIf
    
    If !oGrid:GetStruct():HasField("Z6_CHAPA")
        Return .T.
    EndIf
    
    cChapa := AllTrim(oGrid:GetValue("Z6_CHAPA"))
    
    If !Empty(cChapa)
        
        aAreaSN1 := SN1->(GetArea())
        DbSelectArea("SN1")
        SN1->(DbSetOrder(2)) 
        
        If SN1->(DbSeek(xFilial("SN1") + PadR(cChapa, TamSX3("N1_CHAPA")[1])))
            cCBase     := SN1->N1_CBASE
            cItemBem   := SN1->N1_ITEM
            cStatusBem := AllTrim(SN1->N1_STATUS)
        Else
            cCBase     := ""
            cItemBem   := ""
            cStatusBem := ""
        EndIf
        RestArea(aAreaSN1)

        If Empty(cCBase)
            MsgAlert("Plaqueta '" + cChapa + "' invalida ou nao encontrada.", "Validacao")
            lRet := .F.

            If oGrid:GetStruct():HasField("Z6_CBASE")  ; oGrid:LoadValue("Z6_CBASE", "")   ; EndIf
            If oGrid:GetStruct():HasField("Z6_ITEM")   ; oGrid:LoadValue("Z6_ITEM", "")    ; EndIf
            If oGrid:GetStruct():HasField("Z6_DESCRI") ; oGrid:LoadValue("Z6_DESCRI", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_FILORI") ; oGrid:LoadValue("Z6_FILORI", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_CCORIG") ; oGrid:LoadValue("Z6_CCORIG", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_FILDES") ; oGrid:LoadValue("Z6_FILDES", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_CCDEST") ; oGrid:LoadValue("Z6_CCDEST", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_CUSTBEM"); oGrid:LoadValue("Z6_CUSTBEM", 0)  ; EndIf
            Return lRet
        EndIf

        // Baseado no que o usuario efetivamente digitou (Chapa -> registro SN1 encontrado acima), nao mais re-derivado via SN3.
        If cStatusBem != "1"
            MsgAlert("Bem indisponivel para baixa/transferencia. Status: " + cStatusBem + " - " + ATF_DESCSTATUS(cStatusBem), "Atencao")
            Return .F.
        EndIf

        aDados := oGerenciador:ObtBem(cCBase)
        
        If Len(aDados) == 0
            MsgAlert("Bem da Plaqueta '" + cChapa + "' invalido, pode ter sido transferido ou ja baixado totalmente na filial corrente.", "Validacao")
            lRet := .F.
            
            If oGrid:GetStruct():HasField("Z6_CBASE")  ; oGrid:LoadValue("Z6_CBASE", "")   ; EndIf
            If oGrid:GetStruct():HasField("Z6_ITEM")   ; oGrid:LoadValue("Z6_ITEM", "")    ; EndIf
            If oGrid:GetStruct():HasField("Z6_DESCRI") ; oGrid:LoadValue("Z6_DESCRI", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_FILORI") ; oGrid:LoadValue("Z6_FILORI", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_CCORIG") ; oGrid:LoadValue("Z6_CCORIG", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_FILDES") ; oGrid:LoadValue("Z6_FILDES", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_CCDEST") ; oGrid:LoadValue("Z6_CCDEST", "")  ; EndIf
            If oGrid:GetStruct():HasField("Z6_CUSTBEM"); oGrid:LoadValue("Z6_CUSTBEM", 0)  ; EndIf
        Else
            // oCab := oModel:GetModel("SZ6MASTER") // Nao utilizada - checagem agora usa N1_BAIXA, nao depende mais do tipo de operacao.
            // If ValType(oCab) == "O"
            //     cTipoAtual := oCab:GetValue("Z6_TIPOOP")
            // EndIf

            // Checagem de N1_BAIXA movida para cima, direto no registro encontrado pela Chapa digitada -
            // aDados[4] (item vindo da SN3) nao e confiavel para re-buscar a SN1, ver conversa sobre o assunto.
            // DbSelectArea("SN1")
            // SN1->(DbSetOrder(1))
            // If SN1->(DbSeek(xFilial("SN1") + aDados[1] + aDados[4]))
            //     If !Empty(SN1->N1_BAIXA)
            //         MsgAlert("Bem ja baixado ou transferido, nao pode ser usado.", "Atencao")
            //         Return .F.
            //     EndIf
            // EndIf

            If oGrid:GetStruct():HasField("Z6_CBASE")
                oGrid:LoadValue("Z6_CBASE", aDados[1])
            EndIf
            If oGrid:GetStruct():HasField("Z6_ITEM")
                oGrid:LoadValue("Z6_ITEM", cItemBem)
            EndIf
            If oGrid:GetStruct():HasField("Z6_DESCRI")
                oGrid:LoadValue("Z6_DESCRI", aDados[3])
            EndIf
            If oGrid:GetStruct():HasField("Z6_FILORI")
                oGrid:LoadValue("Z6_FILORI", aDados[9])
            EndIf
            If oGrid:GetStruct():HasField("Z6_CCORIG")
                oGrid:LoadValue("Z6_CCORIG", aDados[7])
            EndIf

            // Filial/CC de Destino vem pre-preenchido igual a origem (usuario pode manter ou trocar - ver regra em ATFT0210).
            If oGrid:GetStruct():HasField("Z6_FILDES")
                oGrid:LoadValue("Z6_FILDES", aDados[9])
            EndIf
            If oGrid:GetStruct():HasField("Z6_CCDEST")
                oGrid:LoadValue("Z6_CCDEST", aDados[7])
            EndIf
            
            If oGrid:GetStruct():HasField("Z6_CUSTBEM")
                oGrid:LoadValue("Z6_CUSTBEM", aDados[8])
            EndIf
        EndIf
    EndIf
    
Return lRet

/*/{Protheus.doc} ATFT0221
Bloqueia a ABERTURA DA TELA para alteracao/exclusao se o lote ja tiver sido processado
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0221(oMdl)
    Local nOpc
    Local lRet
    Local cLote
    Local dData
    Local cTipo
    Local cFilAux
    Local nTamLote
    Local nTamTipo
    Local aAreaSZ6
    
    nOpc      := oMdl:GetOperation()
    lRet      := .T.

    If nOpc == 4 .Or. nOpc == 5
        cLote     := SZ6->Z6_NUMLOT
        dData     := SZ6->Z6_DATAINC
        cTipo     := SZ6->Z6_TIPOOP
        cFilAux   := xFilial("SZ6")
        nTamLote  := FWTamSX3("Z6_NUMLOT")[1]
        nTamTipo  := FWTamSX3("Z6_TIPOOP")[1]
        aAreaSZ6  := FWGetArea()

        DbSelectArea("SZ6")
        SZ6->(DbSetOrder(3)) 

        If SZ6->(MsSeek(cFilAux + PadR(cLote, nTamLote) + DToS(dData) + PadR(cTipo, nTamTipo)))
            While !SZ6->(Eof()) .And. SZ6->Z6_FILIAL == cFilAux .And. ;
                  AllTrim(SZ6->Z6_NUMLOT) == AllTrim(cLote) .And. ;
                  SZ6->Z6_DATAINC == dData .And. ;
                  AllTrim(SZ6->Z6_TIPOOP) == AllTrim(cTipo)

                If AllTrim(SZ6->Z6_STATUS) $ "PROC|TRAN|DEST"
                    MsgAlert("Este lote ja foi processado/transferido e nao pode ser alterado ou excluido.", "Operacao Bloqueada")
                    lRet := .F.
                    Exit
                EndIf
                
                SZ6->(DbSkip())
            EndDo
        EndIf
        
        FWRestArea(aAreaSZ6)
    EndIf
Return lRet

/*/{Protheus.doc} ATFT0212
Processamento de lote - Entry Point do botao
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0212()
    Local cNroLote
    Local cTipoOp
    Local dDataInc
    Local dDataProc
    Local dUltDepr
    Local lUsarSistema
    Local aLog
    Local aArea
    Local cMsg

    aArea := FWGetArea()

    cNroLote := AllTrim(SZ6->Z6_NUMLOT)
    cTipoOp  := SZ6->Z6_TIPOOP
    dDataInc := SZ6->Z6_DATAINC
    aLog     := {}
    lUsarSistema := .F.

    If ValType(oGerenciador) != "O"
        oGerenciador := ATFGER02():New()
    EndIf

    If Empty(cNroLote)
        MsgAlert("Selecione um item do lote no Browse para processar.", "Atencao")
        FWRestArea(aArea)
        Return Nil
    EndIf

    // 1) Bloqueia se o lote (todas as linhas Lote+Data+TipoOp) ja estiver totalmente processado
    If !oGerenciador:TemPendente(cNroLote, cTipoOp, dDataInc)
        MsgAlert("Este lote ja foi totalmente processado.", "Operacao Invalida")
        FWRestArea(aArea)
        Return Nil
    EndIf

    dUltDepr := GetMV("MV_ULTDEPR", .F., CTOD(""))

    If ValType(dUltDepr) == "D" .And. !Empty(dUltDepr)

        // 2) Alerta (nao bloqueia) se a data do sistema nao estiver no mes imediatamente posterior ao MV_ULTDEPR
        If ATF_MESANO(dDataBase) != (ATF_MESANO(dUltDepr) + 1)
            MsgAlert("Atencao: a data do sistema (" + DToC(dDataBase) + ") nao esta no mes imediatamente posterior ao ultimo mes de depreciacao processado (MV_ULTDEPR: " + DToC(dUltDepr) + ").", "Atencao - Data do Sistema")
        EndIf

        // 3) Se a data do lote nao estiver no mes imediatamente posterior ao MV_ULTDEPR, avisa que sera usada a data do sistema
        If ATF_MESANO(dDataInc) != (ATF_MESANO(dUltDepr) + 1)
            cMsg := "A data deste lote (" + DToC(dDataInc) + ") nao esta no mes imediatamente posterior ao ultimo mes de depreciacao processado (MV_ULTDEPR: " + DToC(dUltDepr) + ")." + CRLF + ;
                    "O processamento sera realizado na data do sistema (" + DToC(dDataBase) + ")." + CRLF + "Deseja continuar?"

            If !MsgYesNo(cMsg, "Atencao - Data do Lote")
                FWRestArea(aArea)
                Return Nil
            EndIf

            lUsarSistema := .T.
        EndIf
    EndIf

    dDataProc := If(lUsarSistema, dDataBase, dDataInc)

    If lUsarSistema
        Processa({|| U_ATFT0213(cNroLote, cTipoOp, dDataInc, dDataProc, @aLog)}, "Aguarde", "Processando Lote...")
        U_ATFT0214(aLog)
    ElseIf MsgYesNo("Deseja processar os ativos pendentes deste Lote/Data?", "Aviso")
        Processa({|| U_ATFT0213(cNroLote, cTipoOp, dDataInc, dDataProc, @aLog)}, "Aguarde", "Processando Lote...")
        U_ATFT0214(aLog)
    EndIf

    FWRestArea(aArea)
Return Nil

/*/{Protheus.doc} ATFT0213
Processamento de lote - chamada interna
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0213(cNroLote, cTipoOp, dDataInc, dDataProc, aLog)
    oGerenciador:ProcLote(cNroLote, cTipoOp, dDataInc, dDataProc, @aLog)
Return Nil

/*/{Protheus.doc} ATFT0214
Exibicao do log de processamento
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0214(aLog)
    Local oDlg
    Local oLbx
    Local aBrowse
    Local nX
    Local cLinha
    
    aBrowse  := {}
    
    If ValType(aLog) != "A"
        aLog := {}
    EndIf
    
    If Len(aLog) == 0
        AAdd(aBrowse, "Nenhum processamento foi realizado.")
    Else
        For nX := 1 To Len(aLog)
            If ValType(aLog[nX]) == "A" .And. Len(aLog[nX]) >= 5
                cLinha := PadR("Bem: " + AllTrim(aLog[nX][1]), 15) + " | " + ;
                          PadR("Item: " + AllTrim(aLog[nX][2]), 12) + " | " + ;
                          PadR("Plaqueta: " + AllTrim(aLog[nX][3]), 15) + " | " + ;
                          aLog[nX][4]
                AAdd(aBrowse, cLinha)
            Else
                AAdd(aBrowse, "Item de log em formato invalido.")
            EndIf
        Next nX
        
        If Len(aBrowse) == 0
            AAdd(aBrowse, "Nenhum item valido encontrado no log.")
        EndIf
    EndIf
    
    ConOut(">>> Total de linhas no Log: " + Str(Len(aBrowse)))
    
    DEFINE MSDIALOG oDlg TITLE "Log de Resultados" FROM 000, 000 TO 300, 750 PIXEL
    
    @ 10, 10 LISTBOX oLbx ITEMS aBrowse SIZE 355, 120 OF oDlg PIXEL
    
    @ 135, 160 BUTTON "Fechar" SIZE 40, 12 OF oDlg PIXEL ACTION oDlg:End()
    
    ACTIVATE MSDIALOG oDlg CENTERED
    
Return Nil

/*/{Protheus.doc} ATFGER02
Classe gerenciadora de ativos
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
Class ATFGER02
    Public Method New()
    Public Method ValBem(cCBase)
    Public Method ObtBem(cCBase)
    Public Method TemPendente(cNroLote, cTipoOp, dDataInc)
    Public Method ProcLote(cNroLote, cTipoOp, dDataInc, dDataProc, aLog)
EndClass

Method New() Class ATFGER02
Return Self

Method ValBem(cCBase) Class ATFGER02
    Local lRet
    Local aArea
    Local lAchou
    
    lRet   := .F.
    aArea  := FWGetArea()
    lAchou := .F.
    
    DbSelectArea("SN3")
    SN3->(DbSetOrder(1)) 
    
    If SN3->(DbSeek(xFilial("SN3") + PadR(cCBase, TamSX3("N3_CBASE")[1])))
        While !SN3->(Eof()) .And. SN3->N3_FILIAL == xFilial("SN3") .And. AllTrim(SN3->N3_CBASE) == AllTrim(cCBase)
            If SN3->N3_BAIXA != "1" 
                lAchou := .T.
                Exit
            EndIf
            SN3->(DbSkip())
        EndDo
    EndIf
    
    lRet := lAchou
    FWRestArea(aArea)
Return lRet

Method ObtBem(cCBase) Class ATFGER02
    Local aDados
    Local cChapa
    Local cDescri
    Local cCCOrig
    Local cCusBem
    Local cFilBem
    Local cItem
    Local aArea
    
    aDados  := {}
    aArea   := FWGetArea()
    cChapa  := ""
    cDescri := ""
    cCCOrig := ""
    cCusBem := 0
    cFilBem := ""
    cItem   := ""
    
    If Self:ValBem(cCBase)
        DbSelectArea("SN3")
        SN3->(DbSetOrder(1))
        
        If SN3->(DbSeek(xFilial("SN3") + PadR(cCBase, TamSX3("N3_CBASE")[1])))
            While !SN3->(Eof()) .And. SN3->N3_FILIAL == xFilial("SN3") .And. AllTrim(SN3->N3_CBASE) == AllTrim(cCBase)
                If SN3->N3_BAIXA != "1"
                    cCCOrig := SN3->N3_CCUSTO 
                    cCusBem := SN3->N3_CUSTBEM
                    cFilBem := SN3->N3_FILIAL
                    cItem   := SN3->N3_ITEM
                    
                    DbSelectArea("SN1")
                    SN1->(DbSetOrder(1)) 
                    If SN1->(DbSeek(xFilial("SN1") + SN3->N3_CBASE + SN3->N3_ITEM))
                        cChapa  := SN1->N1_CHAPA
                        cDescri := SN1->N1_DESCRIC
                    EndIf
                    
                    aDados := {SN3->N3_CBASE, cChapa, cDescri, cItem, SN3->N3_TIPO, SN3->N3_TPSALDO, cCCOrig, cCusBem, cFilBem}
                    Exit
                EndIf
                SN3->(DbSkip())
            EndDo
        EndIf
    EndIf
    
    FWRestArea(aArea)
Return aDados

Method TemPendente(cNroLote, cTipoOp, dDataInc) Class ATFGER02
    Local cFilAux
    Local cChave3
    Local nTamLote
    Local nTamTipo
    Local aArea
    Local lPendente

    lPendente := .F.
    aArea     := FWGetArea()
    cFilAux   := xFilial("SZ6")

    DbSelectArea("SZ6")
    nTamLote := FWTamSX3("Z6_NUMLOT")[1]
    nTamTipo := FWTamSX3("Z6_TIPOOP")[1]

    SZ6->(DbSetOrder(3))

    cChave3 := cFilAux + PadR(AllTrim(cNroLote), nTamLote) + DToS(dDataInc) + PadR(AllTrim(cTipoOp), nTamTipo)

    If SZ6->(DbSeek(cChave3))
        While !SZ6->(Eof()) .And. SZ6->Z6_FILIAL == cFilAux .And. ;
              AllTrim(SZ6->Z6_NUMLOT) == AllTrim(cNroLote) .And. ;
              SZ6->Z6_DATAINC == dDataInc .And. ;
              AllTrim(SZ6->Z6_TIPOOP) == AllTrim(cTipoOp)

            If !AllTrim(SZ6->Z6_STATUS) $ "PROC|TRAN|DEST"
                lPendente := .T.
                Exit
            EndIf

            SZ6->(DbSkip())
        EndDo
    EndIf

    FWRestArea(aArea)
Return lPendente

Method ProcLote(cNroLote, cTipoOp, dDataInc, dDataProc, aLog) Class ATFGER02
    Local cFilAux
    Local nReg
    Local nRecBase
    Local cChave3
    Local nTamLote
    Local nTamTipo
    Local aArea
    
    nReg     := 0
    nTamLote := 0
    nTamTipo := 0
    
    aArea    := FWGetArea()
    cFilAux  := xFilial("SZ6")
    
    DbSelectArea("SZ6")
    nTamLote := FWTamSX3("Z6_NUMLOT")[1]
    nTamTipo := FWTamSX3("Z6_TIPOOP")[1]
    
    If nTamLote <= 0
        nTamLote := 20
    EndIf
    If nTamTipo <= 0
        nTamTipo := 1
    EndIf
    
    SZ6->(DbSetOrder(3)) 
    
    cChave3 := cFilAux + PadR(AllTrim(cNroLote), nTamLote) + DToS(dDataInc) + PadR(AllTrim(cTipoOp), nTamTipo)
    
    If SZ6->(DbSeek(cChave3))
        While !SZ6->(Eof()) .AND. SZ6->Z6_FILIAL == cFilAux .AND. ;
              AllTrim(SZ6->Z6_NUMLOT) == AllTrim(cNroLote) .AND. ;
              SZ6->Z6_DATAINC == dDataInc .AND. ;
              AllTrim(SZ6->Z6_TIPOOP) == AllTrim(cTipoOp)
            
            If !Empty(SZ6->Z6_CBASE) .And. AllTrim(SZ6->Z6_STATUS) != "PROC" .And. AllTrim(SZ6->Z6_STATUS) != "TRAN" .And. AllTrim(SZ6->Z6_STATUS) != "DEST"
                nRecBase := SZ6->(RecNo())
                
                If SZ6->Z6_TIPOOP == OP_BAIXA
                    U_ATFT0215(nRecBase, dDataProc, @aLog)
                Else
                    U_ATFT0216(nRecBase, dDataProc, @aLog)
                EndIf
                nReg++
                
                DbSelectArea("SZ6")
                SZ6->(DbSetOrder(3))
                SZ6->(DbGoto(nRecBase))
            Else
                AAdd(aLog, {AllTrim(SZ6->Z6_CBASE), If(SZ6->(FieldPos("Z6_ITEM")) > 0, AllTrim(SZ6->Z6_ITEM), ""), AllTrim(SZ6->Z6_CHAPA), "Item ja estava processado/transferido, foi ignorado.", "I"})
            EndIf

            SZ6->(DbSkip())
        EndDo
    Else
        AAdd(aLog, {" ", "", "", "Lote nao encontrado. Chave: " + cChave3, "E"})
    EndIf
    
    FWRestArea(aArea)
    FWLogMsg("Lote " + cNroLote + " processado. Ativos executados: " + AllTrim(Str(nReg)))
Return .T.

/*/{Protheus.doc} ATFT0215
Processamento de baixa via ExecAuto ATFA036
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0215(nRec, dDataProc, aLog)
    Local lRet
    Local aCab
    Local aItem
    Local cCBase
    Local cChapa
    Local cMotivo
    Local dBaixa
    Local nPerbai
    Local cDeprec
    Local cFilAux
    Local aArea
    Local aErroLog
    Local nI
    Local oErr
    Local lFound
    Local cItemBem
    Local nQtdBx
    Local cTipoBem
    Local cTpSaldo
    Local cSeqBem
    Local cSeqReav
    Local cOldFilt
    Local cFullErro
    Local cLinhaErro
    Local nPos
    
    Private lMsHelpAuto    := .F.
    Private lAutoErrNoFile := .T.
    Private lMsErroAuto    := .F.
    
    oErr       := Nil
    lFound     := .F.
    lRet       := .F.
    aCab       := {}
    aItem      := {} 
    cDeprec    := ""
    cItemBem   := ""
    cTipoBem   := ""
    cTpSaldo   := ""
    cSeqBem    := ""
    cSeqReav   := ""
    cOldFilt   := ""
    nQtdBx     := 0
    aArea      := FWGetArea()
    
    DbSelectArea("SZ6")
    SZ6->(DbGoto(nRec))
    
    cCBase  := PadR(AllTrim(SZ6->Z6_CBASE), TamSX3("N1_CBASE")[1])
    cChapa  := AllTrim(SZ6->Z6_CHAPA)
    cMotivo := PadR(AllTrim(SZ6->Z6_MOTIVO), TamSX3("FN6_MOTIVO")[1])
    dBaixa  := SZ6->Z6_BAIXA
    nPerbai := SZ6->Z6_PERBAI
    cFilAux := SZ6->Z6_FILIAL

    If ValType(dDataProc) != "D" .Or. Empty(dDataProc)
        dDataProc := SZ6->Z6_DATAINC
    EndIf

    If SZ6->(FieldPos("Z6_DEPREC")) > 0
        cDeprec := SZ6->Z6_DEPREC
    EndIf
    
    If Empty(cDeprec)
        cDeprec := GetMV("MV_ATFDPBX", .F., "1")
    EndIf
    
    DbSelectArea("SN1")
    SN1->(DbSetOrder(1))

    If SZ6->(FieldPos("Z6_ITEM")) > 0
        cItemBem := PadR(AllTrim(SZ6->Z6_ITEM), TamSX3("N1_ITEM")[1])
        If !Empty(cItemBem)
            If !SN1->(DbSeek(cFilAux + cCBase + cItemBem)) .Or. !Empty(SN1->N1_BAIXA)
                cItemBem := ""
            EndIf
        EndIf
    EndIf

    If Empty(cItemBem)
        // Fallback - Z6_ITEM vazio (linha anterior a criacao do campo) ou item ja baixado - varre a SN1 procurando linha pendente.
        If SN1->(DbSeek(cFilAux + cCBase))
            While !SN1->(Eof()) .And. SN1->N1_FILIAL == cFilAux .And. SN1->N1_CBASE == cCBase
                If Empty(SN1->N1_BAIXA)
                    cItemBem := SN1->N1_ITEM
                    Exit
                EndIf
                SN1->(DbSkip())
            EndDo
        EndIf
    EndIf

    If Empty(cItemBem)
        AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Bem nao encontrado ou ja esta totalmente baixado", "E"})
        FWRestArea(aArea)
        Return lRet
    EndIf
    
    DbSelectArea("SN3")
    SN3->(DbSetOrder(1))
    If SN3->(DbSeek(cFilAux + cCBase + cItemBem))
        While !SN3->(Eof()) .And. SN3->N3_FILIAL == cFilAux .And. ;
              SN3->N3_CBASE == cCBase .And. SN3->N3_ITEM == cItemBem
            
            If SN3->N3_BAIXA != "1"
                lFound   := .T.
                cTipoBem := SN3->N3_TIPO
                cTpSaldo := SN3->N3_TPSALDO
                cSeqBem  := SN3->N3_SEQ
                cSeqReav := SN3->N3_SEQREAV
                
                AAdd(aItem, {"N3_FILIAL" , cFilAux  , NIL})
                AAdd(aItem, {"N3_CBASE"  , cCBase   , NIL})
                AAdd(aItem, {"N3_ITEM"   , cItemBem , NIL})
                AAdd(aItem, {"N3_TIPO"   , cTipoBem , NIL})
                AAdd(aItem, {"N3_BAIXA"  , "0"      , NIL}) 
                AAdd(aItem, {"N3_TPSALDO", cTpSaldo , NIL})
                AAdd(aItem, {"N3_SEQ"    , cSeqBem  , NIL})
                AAdd(aItem, {"N3_SEQREAV", cSeqReav , NIL})
                Exit
            EndIf
            SN3->(DbSkip())
        EndDo
    EndIf
    
    If !lFound .Or. Len(aItem) == 0
        AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Bem sem saldo disponivel para Baixa", "E"})
        FWRestArea(aArea)
        Return lRet
    EndIf
    
    If SN1->N1_QUANTD > 0
        nQtdBx := SN1->N1_QUANTD * (nPerbai / 100)
    Else
        nQtdBx := 1
    EndIf
    
    AAdd(aCab, {"FN6_FILIAL", xFilial("FN6") , NIL})
    AAdd(aCab, {"FN6_CBASE" , cCBase         , NIL})
    AAdd(aCab, {"FN6_CITEM" , cItemBem       , NIL})
    AAdd(aCab, {"FN6_MOTIVO", cMotivo        , NIL})
    AAdd(aCab, {"FN6_DTBAIX", dBaixa         , NIL})
    AAdd(aCab, {"FN6_BAIXA" , nPerbai        , NIL})
    AAdd(aCab, {"FN6_PERCBX", nPerbai        , NIL})
    AAdd(aCab, {"FN6_QTDBX" , nQtdBx         , NIL})
    AAdd(aCab, {"FN6_DEPREC", cDeprec        , NIL})
    AAdd(aCab, {"FN6_GERANF", "2"            , NIL})
    
    Begin Sequence
        
        DbSelectArea("SN3")
        cOldFilt := DBFilter()
        Set Filter To N3_BAIXA != '1'
        
        MSExecAuto({|x, y, z| ATFA036(x, y, z)}, aCab, aItem, 3)
        
        DbSelectArea("SN3")
        If Empty(cOldFilt)
            DbClearFilter()
        Else
            Set Filter To &cOldFilt
        EndIf
        
        If lMsErroAuto
            aErroLog := GetAutoGRLog()
            
            If ValType(aErroLog) == "C"
                aErroLog := {aErroLog}
            EndIf
            
            If ValType(aErroLog) == "A"
                For nI := 1 To Len(aErroLog)
                    If ValType(aErroLog[nI]) == "C"
                        cFullErro := aErroLog[nI]
                        cFullErro := StrTran(cFullErro, "<br>", Chr(10))
                        cFullErro := StrTran(cFullErro, CRLF, Chr(10))
                        cFullErro := StrTran(cFullErro, Chr(13), Chr(10))
                        
                        While !Empty(cFullErro)
                            nPos := At(Chr(10), cFullErro)
                            If nPos > 0
                                cLinhaErro := SubStr(cFullErro, 1, nPos - 1)
                                cFullErro  := SubStr(cFullErro, nPos + 1)
                            Else
                                cLinhaErro := cFullErro
                                cFullErro  := ""
                            EndIf
                            
                            cLinhaErro := AllTrim(cLinhaErro)
                            If !Empty(cLinhaErro) .And. !("---" $ cLinhaErro)
                                AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Falha na Baixa - " + cLinhaErro, "E"})
                            EndIf
                        EndDo
                    EndIf
                Next nI
            EndIf
            
            If Len(aLog) == 0 .Or. aLog[Len(aLog)][3] != "E"
                AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Falha na Baixa (Erro n�o detalhado pelo ExecAuto)", "E"})
            EndIf
            
            DbSelectArea("SZ6")
            SZ6->(RecLock("SZ6", .F.))
            SZ6->Z6_STATUS := "PEND" 
            SZ6->(MsUnLock())
        Else
            lRet := .T.
            AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Baixa registrada com sucesso", "C"})
            
            DbSelectArea("SZ6")
            SZ6->(RecLock("SZ6", .F.))
            SZ6->Z6_STATUS := "PROC"
            If SZ6->(FieldPos("Z6_DTPROC")) > 0
                SZ6->Z6_DTPROC := dDataProc
            EndIf
            SZ6->(MsUnLock())
            
            DbSelectArea("SN1")
            If SN1->(DbSeek(cFilAux + cCBase + cItemBem))
                RecLock("SN1", .F.)
                SN1->N1_BAIXA := dBaixa 
                SN1->(MsUnLock())
            EndIf
        EndIf
        
    Recover Using oErr
        DbSelectArea("SN3")
        If Empty(cOldFilt)
            DbClearFilter()
        Else
            Set Filter To &cOldFilt
        EndIf
        
        If ValType(oErr) == "O"
            AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: EXCECAO Baixa - " + oErr:Description, "E"})
        Else
            AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: EXCECAO desconhecida na Baixa", "E"})
        EndIf
    End Sequence
    
    FWRestArea(aArea)
Return lRet

/*/{Protheus.doc} ATFT0216
Processamento de transferencia via ExecAuto ATFA060
@author Antonio Nunes O Jr
@since 27/08/2026
/*/
User Function ATFT0216(nRec, dDataProc, aLog)
    Local lRet
    Local aDadosAuto
    Local cCBase
    Local cFilAux
    Local cCCOri
    Local cCCDes
    Local cFilDes
    Local cItemBem
    Local dDataInc
    Local cChapa
    Local aArea
    Local aErroLog
    Local nI
    Local oErr
    Local lFound
    Local cFilBkp
    Local aParamAuto
    Local dDataBkp
    Local cFullErro
    Local cLinhaErro
    Local nPos
    
    lRet       := .F.
    aDadosAuto := {}
    aParamAuto := {}
    oErr       := Nil
    lFound     := .F.
    cFilBkp    := cFilAnt

    Private lMsHelpAuto    := .F.
    Private lAutoErrNoFile := .T.
    Private lMsErroAuto    := .F.
    
    aArea := FWGetArea()
    
    DbSelectArea("SZ6")
    SZ6->(DbGoto(nRec))
    
    cCBase   := AllTrim(SZ6->Z6_CBASE)
    cFilAux  := SZ6->Z6_FILIAL
    cCCOri   := AllTrim(SZ6->Z6_CCORIG)
    cCCDes   := AllTrim(SZ6->Z6_CCDEST)
    cFilDes  := AllTrim(SZ6->Z6_FILDES)

    dDataInc := SZ6->Z6_DATAINC
    cChapa   := AllTrim(SZ6->Z6_CHAPA)

    // Sem data de processamento valida informada, mantem o comportamento original (usa a data do lote)
    If ValType(dDataProc) != "D" .Or. Empty(dDataProc)
        dDataProc := dDataInc
    EndIf

    cItemBem := ""
    If SZ6->(FieldPos("Z6_ITEM")) > 0
        cItemBem := AllTrim(SZ6->Z6_ITEM)
    EndIf

    If Empty(cCBase) .Or. Empty(cCCOri) .Or. Empty(cCCDes)
        AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Dados obrigatorios (CBASE/CC origem/CC destino) vazios", "E"})
        FWRestArea(aArea)
        Return lRet
    EndIf

    DbSelectArea("SN3")
    SN3->(DbSetOrder(1))

    If !Empty(cItemBem)
        If SN3->(DbSeek(cFilAux + PadR(cCBase, TamSX3("N3_CBASE")[1]) + PadR(cItemBem, TamSX3("N3_ITEM")[1])))
            While !SN3->(Eof()) .And. SN3->N3_FILIAL == cFilAux .And. AllTrim(SN3->N3_CBASE) == cCBase .And. AllTrim(SN3->N3_ITEM) == cItemBem
                If SN3->N3_BAIXA == "0"
                    lFound := .T.
                    Exit
                EndIf
                SN3->(DbSkip())
            EndDo
        EndIf
    EndIf

    If !lFound
        // Fallback - Z6_ITEM vazio (linha anterior a criacao do campo) ou nao localizado - pega a primeira balanca ativa do CBASE.
        DbSelectArea("SN3")
        SN3->(DbSetOrder(1))
        If SN3->(DbSeek(cFilAux + PadR(cCBase, TamSX3("N3_CBASE")[1])))
            While !SN3->(Eof()) .And. SN3->N3_FILIAL == cFilAux .And. AllTrim(SN3->N3_CBASE) == cCBase
                If SN3->N3_BAIXA == "0"
                    lFound := .T.
                    Exit
                EndIf
                SN3->(DbSkip())
            EndDo
        EndIf
    EndIf

    If !lFound
        AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Bem ativo nao encontrado.", "E"})
        FWRestArea(aArea)
        Return lRet
    EndIf
    
    DbSelectArea("SN1")
    SN1->(DbSetOrder(1))
    If !SN1->(DbSeek(cFilAux + SN3->N3_CBASE + SN3->N3_ITEM))
        AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Bem nao encontrado", "E"})
        FWRestArea(aArea)
        Return lRet
    EndIf
    
    AAdd(aDadosAuto, {"N3_CBASE"  , SN3->N3_CBASE  , Nil})
    AAdd(aDadosAuto, {"N3_ITEM"   , SN3->N3_ITEM   , Nil})
    AAdd(aDadosAuto, {"N3_TIPO"   , SN3->N3_TIPO   , Nil})
    AAdd(aDadosAuto, {"N1_FILIAL" , PadR(cFilDes, TamSX3("N1_FILIAL")[1]) , Nil})
    AAdd(aDadosAuto, {"N4_DATA"   , dDataProc      , Nil})
    AAdd(aDadosAuto, {"N3_CCONTAB", SN3->N3_CCONTAB, Nil})
    AAdd(aDadosAuto, {"N3_CCORREC", SN3->N3_CCORREC, Nil})
    AAdd(aDadosAuto, {"N3_CDEPREC", SN3->N3_CDEPREC, Nil})
    AAdd(aDadosAuto, {"N3_CCDEPR" , SN3->N3_CCDEPR , Nil})
    AAdd(aDadosAuto, {"N3_CDESP"  , SN3->N3_CDESP  , Nil})
    AAdd(aDadosAuto, {"N3_CCUSTO" , PadR(cCCDes, TamSX3("N3_CCUSTO")[1]), Nil})
    AAdd(aDadosAuto, {"N3_CUSTBEM", PadR(cCCDes, TamSX3("N3_CCUSTO")[1]), Nil})
    AAdd(aDadosAuto, {"N3_CCDESP" , PadR(cCCDes, TamSX3("N3_CCUSTO")[1]), Nil})
    AAdd(aDadosAuto, {"N3_CCCDEP" , PadR(cCCDes, TamSX3("N3_CCUSTO")[1]), Nil})
    AAdd(aDadosAuto, {"N3_CCCDES" , PadR(cCCDes, TamSX3("N3_CCUSTO")[1]), Nil})
    AAdd(aDadosAuto, {"N3_CCCORR" , PadR(cCCDes, TamSX3("N3_CCUSTO")[1]), Nil})

    AAdd(aParamAuto, {"MV_PAR01", 1}) 
    AAdd(aParamAuto, {"MV_PAR02", 2}) 
    AAdd(aParamAuto, {"MV_PAR03", 2}) 
    AAdd(aParamAuto, {"MV_PAR04", 1}) // 1=Sim: Autoriza divergencia de datas no calculo de depreciacao entre filiais
    AAdd(aParamAuto, {"MV_PAR05", 1}) 
    
    dDataBkp  := dDataBase
    dDataBase := dDataProc
    
    Begin Sequence
        lMsErroAuto := .F.
        MSExecAuto({|x, y, w, z| ATFA060(x, y, w, z)}, aDadosAuto, 4, aParamAuto, .F.)
        
        If lMsErroAuto
            aErroLog := GetAutoGRLog()
            
            If ValType(aErroLog) == "C"
                aErroLog := {aErroLog}
            EndIf
            
            If ValType(aErroLog) == "A"
                For nI := 1 To Len(aErroLog)
                    If ValType(aErroLog[nI]) == "C"
                        cFullErro := aErroLog[nI]
                        
                        // Normalizando as quebras de linha
                        cFullErro := StrTran(cFullErro, "<br>", Chr(10))
                        cFullErro := StrTran(cFullErro, CRLF, Chr(10))
                        cFullErro := StrTran(cFullErro, Chr(13), Chr(10))
                        
                        While !Empty(cFullErro)
                            nPos := At(Chr(10), cFullErro)
                            If nPos > 0
                                cLinhaErro := SubStr(cFullErro, 1, nPos - 1)
                                cFullErro  := SubStr(cFullErro, nPos + 1)
                            Else
                                cLinhaErro := cFullErro
                                cFullErro  := ""
                            EndIf
                            
                            cLinhaErro := AllTrim(cLinhaErro)
                            If !Empty(cLinhaErro) .And. !("---" $ cLinhaErro)
                                AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Falha na Transferencia - " + cLinhaErro, "E"})
                            EndIf
                        EndDo
                    EndIf
                Next nI
            EndIf
            
            If Len(aLog) == 0 .Or. aLog[Len(aLog)][3] != "E"
                AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Falha na Transferencia (Inconsistencia estrutural da rotina)", "E"})
            EndIf
            
            DbSelectArea("SZ6")
            SZ6->(DbGoto(nRec))
            SZ6->(RecLock("SZ6", .F.))
            SZ6->Z6_STATUS := "PEND"  
            SZ6->(MsUnLock())
            
        Else
            lRet := .T.
            AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: Transferencia realizada com sucesso", "C"})
            
            DbSelectArea("SZ6")
            SZ6->(DbGoto(nRec))
            SZ6->(RecLock("SZ6", .F.))
            SZ6->Z6_STATUS := "TRAN"
            SZ6->Z6_DTPROC := dDataProc
            SZ6->(MsUnLock())

        EndIf
        
    Recover Using oErr
        If ValType(oErr) == "O"
            AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: EXCECAO Transf - " + oErr:Description, "E"})
        Else
            AAdd(aLog, {cCBase, cItemBem, cChapa, "Status: EXCECAO desconhecida na Transf", "E"})
        EndIf
    End Sequence
    
    dDataBase := dDataBkp
    cFilAnt   := cFilBkp
    
    FWRestArea(aArea)
Return lRet
