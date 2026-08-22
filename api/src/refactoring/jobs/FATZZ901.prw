#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

#DEFINE CEMPPAD "01"
#DEFINE CFILPAD "01001"

// Job agendado - fila ZZ9: classifica notas NFe pendentes e enfileira em ZZA/ZZB/ZZC

// Le a fila ZZ9, classifica cada nota e grava o resultado na fila de destino (ZZA/ZZB/ZZC)
User Function FATZZ901()
    Local cAliZZ9    := GetNextAlias()
    Local cQry       := ""
    Local cCod       := ""
    Local cJson      := ""
    Local cChvNFe    := ""
    Local cFilOri    := ""
    Local nRecno     := 0
    Local cErrMsg    := ""
    Local cSub       := ""
    Local cTabPai    := ""
    Local cTipoPen   := ""
    Local cProdPend  := ""
    Local lOk        := .F.
    Local lDup       := .F.
    Local nOk        := 0
    Local nErr       := 0
    Local nPark      := 0
    Local jJson      := Nil
    Local aRet       := {}
    Local dDataBaseSis := CToD("")
    Local bErrOld    := Nil
    Local oErrRT     := Nil

    Private __cBatch := "1"

    ConOut("[FATZZ901] Iniciando Classificacao NFe (ZZ9) - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    dDataBaseSis := dDataBase

    cQry := "SELECT ZZ9_COD, ZZ9_CHVNFE, ZZ9_FILIAL, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZ9") + " "
    cQry += "WHERE ZZ9_STATUS IN ('P','A') AND ZZ9_PRDPEN = 'N' AND ZZ9_CLIPEN = 'N' AND ZZ9_FORPEN = 'N' "
    cQry += "AND ZZ9_FILIAL = '" + xFilial("ZZ9") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZ9_DTINCL, ZZ9_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZ9, .T., .T.)

    While (cAliZZ9)->(!Eof())
        cCod    := AllTrim((cAliZZ9)->ZZ9_COD)
        cChvNFe := AllTrim((cAliZZ9)->ZZ9_CHVNFE)
        cFilOri := AllTrim((cAliZZ9)->ZZ9_FILIAL)
        nRecno  := (cAliZZ9)->RECNO
        cErrMsg := ""
        cSub    := ""
        cTabPai := ""
        cTipoPen:= ""
        cProdPend := ""
        lOk     := .F.
        lDup    := .F.

        dDataBase := dDataBaseSis

        DbSelectArea("ZZ9")
        ZZ9->(DbGoto(nRecno))
        cJson := ZZ9->ZZ9_JSON

        U_UPDSTAT("ZZ9", cCod, "A", "")
        ConOut("[FATZZ901] Classificando: " + cCod + " | Chave: " + cChvNFe)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            bErrOld := ErrorBlock({|oErr| Break(oErr)})
            Begin Sequence
                aRet := ZZ901_Classifica(jJson)
            Recover Using oErrRT
                aRet := {.F., "EXCEPTION: " + U_PI_ERRO_RT(oErrRT)}
            End Sequence
            ErrorBlock(bErrOld)
            lOk  := aRet[1]
            If lOk
                cTabPai := IIF(Len(aRet) >= 3, aRet[3], "")
                lDup    := IIF(Len(aRet) >= 4, aRet[4], .F.)
            Else
                cErrMsg  := IIF(Len(aRet) >= 2, cValToChar(aRet[2]), "Erro desconhecido na classificacao")
                cSub     := IIF(Len(aRet) >= 3, cValToChar(aRet[3]), "")
                cTipoPen  := IIF(Len(aRet) >= 4 .And. (aRet[4] == "CLI" .Or. aRet[4] == "FOR" .Or. aRet[4] == "PRD"), aRet[4], "")
                cProdPend := IIF(cTipoPen == "PRD" .And. Len(aRet) >= 5, cValToChar(aRet[5]), "")
            EndIf
        Else
            cErrMsg := "JSON invalido na fila ZZ9. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZ9", cCod, "S", "")
            If !Empty(cTabPai)
                TCSqlExec("UPDATE " + RetSqlName("ZZ9") + " SET ZZ9_DESTMU = '" + cTabPai + "' WHERE ZZ9_COD = '" + cCod + "' AND ZZ9_FILIAL = '" + cFilOri + "' AND D_E_L_E_T_ = ' '")
            EndIf
            nOk++
            ConOut("[FATZZ901] OK: " + cCod + " | Destino: " + cTabPai + IIF(lDup, " (nota ja existia, nao duplicou)", ""))
        ElseIf cTipoPen == "PRD"
            U_UPDSTAT("ZZ9", cCod, "P", "")
            U_ZZF_GRV(cChvNFe, "ZZ9", cProdPend, "")
            TCSqlExec("UPDATE " + RetSqlName("ZZ9") + " SET ZZ9_PRDPEN = 'S' WHERE ZZ9_COD = '" + cCod + "' AND ZZ9_FILIAL = '" + cFilOri + "' AND D_E_L_E_T_ = ' '")
            nPark++
            ConOut("[FATZZ901] ESTACIONADA (produto pendente): " + cCod + " | Produto: " + cProdPend)
        ElseIf !Empty(cTipoPen)
            U_UPDSTAT("ZZ9", cCod, "P", "")
            TCSqlExec("UPDATE " + RetSqlName("ZZ9") + " SET ZZ9_" + IIF(cTipoPen == "CLI", "CLIPEN", "FORPEN") + " = 'S' WHERE ZZ9_COD = '" + cCod + "' AND ZZ9_FILIAL = '" + cFilOri + "' AND D_E_L_E_T_ = ' '")
            nPark++
            ConOut("[FATZZ901] ESTACIONADA (" + cTipoPen + " pendente): " + cCod + " | " + Left(cErrMsg, 100))
        Else
            U_UPDSTAT("ZZ9", cCod, "E", cErrMsg)
            U_ZZCALLBK("ZZ9", cChvNFe, cSub, .F., "", "", cErrMsg)
            nErr++
            ConOut("[FATZZ901] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf

        (cAliZZ9)->(DbSkip())
    EndDo
    (cAliZZ9)->(DbCloseArea())

    ConOut("[FATZZ901] Fim. OK: " + cValToChar(nOk) + " | Estacionadas: " + cValToChar(nPark) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

// Classifica uma nota NFe (roteamento SA1/SA2, cOper, produtos/CFOP/TES) e grava em ZZA/ZZB/ZZC
Static Function ZZ901_Classifica(jJson)
    Local aInv         := jJson['notas']
    Local oHead        := Nil
    Local aPrd         := {}
    Local aEmp         := {}
    Local cSub         := ""
    Local cCnpj        := ""
    Local cSer         := ""
    Local cOper        := ""
    Local cTab         := ""
    Local cCod         := ""
    Local cLoja        := ""
    Local cFil         := ""
    Local cCliD        := "000001"
    Local dVencto      := CToD("//")
    Local cCondSafe    := ""
    Local nI           := 0
    Local cQryAux      := ""
    Local cAliAux      := ""
    Local cAuxC        := ""
    Local cProdLeg     := ""
    Local cProdInt     := ""
    Local cCheckCFOP   := ""
    Local cKeyDest     := ""
    Local lIsTransf    := .F.
    Local oMotorRegras := Nil
    Local aRetCfop     := {}
    Local cNatOp       := ""
    Local cCnpjEmit    := ""
    Local cCnpjDest    := ""
    Local cUsuario     := ""
    Local lCest
    Local lNcm
    Local cModDoc      := ""
    Local cTabPai      := ""

    If ValType(aInv) != "A" .Or. Len(aInv) == 0
        Return {.F., "Array notas ausente (ZZ9)"}
    EndIf
    oHead   := aInv[1]
    cModDoc := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')
    aPrd    := oHead['itens']
    cNatOp  := Upper(AllTrim(U_PI_STR_X(oHead, 'des_NatOp')))
    cSub    := cValToChar(U_PI_VAL_X(oHead, 'cod_Subseccao'))

    If ValType(aPrd) == "A" .And. Len(aPrd) > 0
        cCheckCFOP := Upper(U_PI_STR_X(aPrd[1], 'cod_ProdutoCFOP', 'cfop'))

        If ("REM P/ VENDA FORA" $ cNatOp .Or. "REMESSA P/ VENDA FORA" $ cNatOp) .AND. SUBSTR(cCheckCFOP,1,1) $ '5/6'
            cCheckCFOP := "5904"
        EndIf

        If "5557" $ cCheckCFOP .Or. "TRANSF" $ cCheckCFOP .Or. "TRANSF" $ cNatOp .Or. "5152" $ cCheckCFOP
            lIsTransf := .T.
        EndIf
    EndIf

    cCnpj := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ', 'num_SubseccaoCNPJ'))
    aEmp := U_PI_FILIAL_X(cCnpj)

    If Len(aEmp) < 2
        Return {.F., "Filial nao encontrada para CNPJ: " + AllTrim(cCnpj), cSub}
    EndIf


    dVencto := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Emissao', 'dta_Vencimento'))
    If !Empty(dVencto)
        dDataBase := dVencto
    EndIf

    cCondSafe := PadR(U_PI_COND_X("004"), 3)
    oMotorRegras := U_FATCFOP01()
    cAuxC := cCheckCFOP

    cCnpjEmit := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'des_EmitDocumento', 'cnpJ_FORNECEDOR'))
    cCnpjDest := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'des_DestDocumento', 'cpf'))

    If U_PI_STR_X(oHead, 'des_Finalidade') == "4" .And. "DEVOLUCAO DE VENDA" $ cNatOp
        If ValType(aPrd) == "A" .And. Len(aPrd) > 0
            cUsuario := AllTrim(U_PI_STR_X(oHead, 'cod_Exportacao'))
        EndIf
    EndIf

    If !Empty(cUsuario)
        cQryAux := "SELECT A1_COD, A1_LOJA FROM " + RetSqlName("SA1") + " WHERE TRIM(A1_LEGADO) = '" + cUsuario + "' AND D_E_L_E_T_ = ' '"
        cAliAux := GetNextAlias()
        MpSysOpenQuery(cQryAux, cAliAux)
        If (cAliAux)->(!Eof())
            cCod  := (cAliAux)->A1_COD
            cLoja := (cAliAux)->A1_LOJA
            cFil  := xFilial("SA1")
        EndIf
        (cAliAux)->(DbCloseArea())

        cTab  := "SA1"
        cKeyDest := cUsuario
        cOper := "D"
    Else
        If cCnpj == cCnpjEmit
            cKeyDest := cCnpjDest
        Else
            cKeyDest := cCnpjEmit
        EndIf

        If lIsTransf .Or. cAuxC $ "5557/1557/5152/5409/1152/1409"
            If cCnpj == cCnpjDest .And. cCnpj != cCnpjEmit
                cOper := "E"
                cTab  := "SA2"
            ElseIf cCnpj == cCnpjEmit .And. cCnpj != cCnpjDest
                cOper := "S"
                cTab  := "SA1"
            Else
                If Left(cAuxC, 1) $ "1/2"
                    cOper := "E"
                Else
                    cOper := "S"
                EndIf
                cTab  := "SA2"
            EndIf

        ElseIf cAuxC $ "1202/1411/2202"
            cOper := "D"
            cTab  := "SA1"
        ElseIf cAuxC $ "5202/5411/6202"
            cOper := "S"
            cTab  := "SA2"
        ElseIf Left(cAuxC, 1) $ "1/2/3"
            cOper := "E"
            cTab  := "SA2"
        ElseIf Left(cAuxC, 1) $ "5/6/7"
            cOper := "S"
            cTab  := "SA1"
        Else
            cOper := "E"
            cTab  := "SA2"
        EndIf

        U_PI_BUSCA_X(cTab, cKeyDest, aEmp[2], @cCod, @cLoja, @cFil)

        If Empty(cCod) .And. cTab == "SA1" .And. cOper == "S"
            cCod := cCliD
            cLoja := "01"
            U_PI_BUSCA_X(cTab, cCod, aEmp[2], @cCod, @cLoja, @cFil)
        EndIf
    EndIf

    IF cOper == 'D' .AND. cTab == 'SA2'
        SA2->(DbSetOrder(3))
        If SA2->(DbSeek(xFilial("SA2") + cCnpjEmit))
            cCod := SA2->A2_COD
            cLoja := SA2->A2_LOJA
        Endif
    ENDIF

    If Empty(cCod)
        Return {.F., "Destinatario nao localizado. Doc: " + cKeyDest, cSub, IIF(cTab == "SA1", "CLI", "FOR")}
    Endif

    SA2->(DbSetOrder(3))
    If !SA2->(DbSeek(xFilial("SA2") + cCnpjEmit))
        SA2->(DbSetOrder(1))
        Return {.F., "Emitente nao esta cadastrado como fornecedor na filial destino. CNPJ: " + cCnpjEmit, cSub, "FOR"}
    EndIf
    SA2->(DbSetOrder(1))

    Do Case
        Case cOper == "D" ; cTabPai := "ZZB"
        Case cOper == "S" ; cTabPai := "ZZA"
        Otherwise          ; cTabPai := "ZZC"
    EndCase

    cSer := AllTrim(U_PI_STR_X(oHead, 'cod_Serie', 'num_Serie'))
    If Empty(cSer)
        cSer := "1"
    EndIf
    cSer := PadR(cSer, TamSx3("F2_SERIE")[1], " ")

    For nI := 1 To Len(aPrd)
        cProdLeg := AllTrim(U_PI_STR_X(aPrd[nI], 'cod_Produto'))
        cProdInt := ""

        lCest := .T.
        lNcm  := .T.

        DbSelectArea("SB1")
        SB1->(DbOrderNickName("LEGADO"))
        If SB1->(DbSeek(xFilial("SB1") + PadR(cProdLeg, TamSx3("B1_LEGADO")[1])))
            cProdInt := AllTrim(SB1->B1_COD)
            aPrd[nI]['cod_Produto'] := cProdInt

            if !Empty(aPrd[nI]['des_ProdutoCEST'])
                lCest := U_BUSCACAD(aPrd[nI]['des_ProdutoCEST'],1)
            Endif

            if !Empty(aPrd[nI]['des_ProdutoNCM'])
                lNcm  := U_BUSCACAD(aPrd[nI]['des_ProdutoNCM'],2)
            Endif

            if lCest .and. lNcm
                If RecLock("SB1", .F.)
                    SB1->B1_POSIPI := aPrd[nI]['des_ProdutoNCM']
                    SB1->B1_CEST   := aPrd[nI]['des_ProdutoCEST']
                    SB1->(MsUnlock())
                Endif
            else
                Return {.F., "NCM e/ou CEST nao cadastrado. " + IIF(!Empty(aPrd[nI]['des_ProdutoNCM']),aPrd[nI]['des_ProdutoNCM'],'Nil') + '/' + IIF(!Empty(aPrd[nI]['des_ProdutoCEST']),aPrd[nI]['des_ProdutoCEST'],'Nil'), cSub}
            EndIf
        EndIf

        If Empty(cProdInt)
            Return {.F., "Produto nao cadastrado (Item " + cValToChar(nI) + ") Legado: " + cProdLeg, cSub, "PRD", cProdLeg}
        EndIf

        U_PI_FIXPROD(cProdInt, aPrd[nI])

        cAuxC := U_PI_LIMPA_X(U_PI_STR_X(aPrd[nI], 'cod_ProdutoCFOP', 'cfop'))

        If "REM P/ VENDA FORA" $ cNatOp .Or. "REMESSA P/ VENDA FORA" $ cNatOp
            cAuxC := "5904"
        EndIf

        cAuxC := U_PI_INVCFOP(cAuxC, cOper)

        aRetCfop := oMotorRegras:ProcessaRegras(aPrd[nI], cAuxC, "")

        If Len(AllTrim(aRetCfop[1])) == 3 .And. Len(AllTrim(aRetCfop[2])) >= 4
            aPrd[nI]['cod_ProdutoCFOP'] := PadR(aRetCfop[2], 5)
            aPrd[nI]['_TES_CACHE']      := PadR(aRetCfop[1], 3)
        Else
            aPrd[nI]['cod_ProdutoCFOP'] := PadR(aRetCfop[1], 5)
            aPrd[nI]['_TES_CACHE']      := PadR(aRetCfop[2], 3)
        EndIf

        If Empty(aPrd[nI]['cod_ProdutoCFOP'])
            aPrd[nI]['cod_ProdutoCFOP'] := cAuxC
        EndIf

        DbSelectArea("SF4")
        SF4->(DbSetOrder(1))

        If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .OR. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
            cQryAux := "SELECT F4_CODIGO FROM " + RetSqlName("SF4") + " WHERE F4_CF='" + PadR(AllTrim(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("F4_CF")[1]) + "' AND F4_MSBLQL <> '1' AND D_E_L_E_T_=' ' ORDER BY F4_ESTOQUE DESC"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(!Eof())
                aPrd[nI]['_TES_CACHE'] := (cAliAux)->F4_CODIGO
            EndIf
            (cAliAux)->(DbCloseArea())
        EndIf

        If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .OR. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
            Return {.F., "TES nao localizado no cadastro (SF4) da filial atual para o CFOP " + AllTrim(aPrd[nI]['cod_ProdutoCFOP']) + ". Verifique as configuracoes fiscais.", cSub}
        EndIf

        If cOper == "D"
            cQryAux := "SELECT D2_DOC, D2_SERIE, D2_ITEM FROM " + RetSqlName("SD2") + " WHERE D2_FILIAL = '" + xFilial("SD2") + "' AND D2_CLIENTE = '" + cCod + "' AND D2_LOJA = '" + cLoja + "' AND D2_COD = '" + aPrd[nI]['cod_Produto'] + "' AND D_E_L_E_T_ = ' ' ORDER BY D2_EMISSAO DESC"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(!Eof())
                aPrd[nI]['_NFORI']   := (cAliAux)->D2_DOC
                aPrd[nI]['_SERIORI'] := (cAliAux)->D2_SERIE
                aPrd[nI]['_ITEMORI'] := (cAliAux)->D2_ITEM
            EndIf
            (cAliAux)->(DbCloseArea())
        EndIf
    Next nI

    oHead['_COD']      := cCod
    oHead['_LOJA']     := cLoja
    oHead['_SER']      := cSer
    oHead['_FIL']      := cFil
    oHead['_TAB']      := cTab
    oHead['_TRANSF']   := IIF(lIsTransf, "S", "N")
    oHead['_COND']     := cCondSafe
    oHead['_CNPJEMIT'] := cCnpjEmit
    oHead['_CNPJDEST'] := cCnpjDest

    Do Case
        Case cOper == "D"
            If !U_ZZX_Gravar("ZZB", "NFD", "CHVNFE", AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe')), jJson:toJSON(), "", "", "N", AllTrim(U_PI_STR_X(oHead, 'qt_Produto')))
                Return {.F., "Falha ao gravar na fila ZZB.", cSub}
            EndIf

        Case cOper == "S"
            cQryAux := "SELECT X5_CHAVE FROM " + RetSqlName("SX5") + " WHERE X5_FILIAL = '" + xFilial("SX5") + "' AND X5_TABELA = '01' AND X5_CHAVE = '" + cSer + "' AND D_E_L_E_T_ = ' '"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(Eof())
                (cAliAux)->(DbCloseArea())
                Return {.F., "Serie '" + AllTrim(cSer) + "' nao cadastrada na Tabela 01 (SX5) da filial " + xFilial("SX5") + ".", cSub}
            EndIf
            (cAliAux)->(DbCloseArea())

            If !U_ZZX_Gravar("ZZA", "NFS", "CHVNFE", AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe')), jJson:toJSON(), "TRANSF", IIF(lIsTransf, "S", "N"), "N", AllTrim(U_PI_STR_X(oHead, 'qt_Produto')))
                Return {.F., "Falha ao gravar na fila ZZA.", cSub}
            EndIf

        Otherwise
            If !U_ZZX_Gravar("ZZC", "NFE", "CHVNFE", AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe')), jJson:toJSON(), "", "", "N", AllTrim(U_PI_STR_X(oHead, 'qt_Produto')))
                Return {.F., "Falha ao gravar na fila ZZC.", cSub}
            EndIf
    EndCase

Return {.T., "", cTabPai, .F.}
