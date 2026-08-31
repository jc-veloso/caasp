#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

Static CEMPPAD := "01"
Static CFILPAD := "01001"

// Job agendado - fila ZZD: processa NFCe (modelo 65) via U_PI_SAIDA_X (Faturamento)

// Le a fila ZZD e processa cada nota NFCe
User Function FATZZD01()
    Local cAliZZD  := GetNextAlias()
    Local cQry     := ""
    Local cEmpSess := cEmpAnt
    Local cFilSess := cFilAnt

    Private __cBatch := "1"
    Private lJob      := GetRemoteType() == -1
    Private aFila      := {}
    Private nOk        := 0
    Private nErr       := 0
    Private nPark      := 0

    ConOut("[FATZZD01] Iniciando NFCe - " + DToS(Date()) + " " + Time())

    If lJob
        RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")
    EndIf

    cQry := "SELECT ZZD_COD, ZZD_CHVNFE, ZZD_FILIAL, ZZD_IDIPS, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZD") + " "
    cQry += "WHERE ZZD_STATUS IN ('P','A') AND ZZD_PRDPEN = 'N' AND ZZD_CLIPEN = 'N' AND ZZD_FORPEN = 'N' "
    cQry += "AND ZZD_FILIAL = '" + xFilial("ZZD") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZD_DTINCL, ZZD_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZD, .T., .T.)

    While (cAliZZD)->(!Eof())
        aAdd(aFila, {AllTrim((cAliZZD)->ZZD_COD), AllTrim((cAliZZD)->ZZD_CHVNFE), AllTrim((cAliZZD)->ZZD_FILIAL), (cAliZZD)->RECNO, AllTrim((cAliZZD)->ZZD_IDIPS)})
        (cAliZZD)->(DbSkip())
    EndDo
    (cAliZZD)->(DbCloseArea())

    If lJob
        ZZD_ProcessaFila()
    Else
        Processa({|| ZZD_ProcessaFila()}, "FATZZD01", "Processando NFCe...")
    EndIf

    ConOut("[FATZZD01] Fim. OK: " + cValToChar(nOk) + " | Estacionadas: " + cValToChar(nPark) + " | Erro: " + cValToChar(nErr))
    If lJob
        RpcClearEnv()
    ElseIf cEmpAnt != cEmpSess .Or. cFilAnt != cFilSess
        // Restaura a filial original da sessao interativa, caso alguma nota tenha trocado de filial
        RpcClearEnv()
        RpcSetEnv(cEmpSess, cFilSess, Nil, Nil, "FAT")
    EndIf
Return

// Percorre aFila (Private) processando cada nota; nOk/nErr/nPark (Private) acumulam o resultado
Static Function ZZD_ProcessaFila()
    Local cCod      := ""
    Local cJson     := ""
    Local cChvNFe   := ""
    Local cFilOri   := ""
    Local cIdIpaas  := ""
    Local cErrMsg   := ""
    Local cSub      := ""
    Local cFilCb    := ""
    Local cDocCb    := ""
    Local cMsgSuc   := ""
    Local cTipoPen  := ""
    Local cProdPend := ""
    Local nRecno    := 0
    Local lOk       := .F.
    Local jJson     := Nil
    Local aRet      := {}
    Local nJ        := 0
    Local bErrOld   := Nil
    Local oErrRT    := Nil
    Local nTIni     := 0

    If !lJob
        ProcRegua(Len(aFila))
    EndIf

    For nJ := 1 To Len(aFila)
        cCod    := aFila[nJ][1]
        cChvNFe := aFila[nJ][2]
        cFilOri := aFila[nJ][3]
        nRecno  := aFila[nJ][4]
        cIdIpaas:= aFila[nJ][5]
        cErrMsg := ""
        cSub    := ""
        cFilCb  := ""
        cDocCb  := ""
        cMsgSuc := ""
        cTipoPen := ""
        cProdPend := ""
        lOk     := .F.

        If !lJob
            IncProc("Nota " + cCod + " (" + cValToChar(nJ) + "/" + cValToChar(Len(aFila)) + ")")
        EndIf

        DbSelectArea("ZZD")
        ZZD->(DbGoto(nRecno))
        cJson := ZZD->ZZD_JSON

        U_UPDSTAT("ZZD", cCod, "A", "")
        ConOut("[FATZZD01] Processando: " + cCod + " | Chave: " + cChvNFe)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            nTIni := Seconds()
            bErrOld := ErrorBlock({|oErr| Break(oErr)})
            Begin Sequence
                aRet := ZZD_MotorNFCe(jJson)
            Recover Using oErrRT
                aRet := {.F., "EXCEPTION: " + U_PI_ERRO_RT(oErrRT), ""}
            End Sequence
            ErrorBlock(bErrOld)
            ConOut("[TIMING][FATZZD01] ZZD_MotorNFCe: " + cValToChar(Seconds() - nTIni) + "s | " + cCod)
            lOk  := aRet[1]
            cSub := IIF(Len(aRet) >= 3, cValToChar(aRet[3]), "")
            If lOk
                cFilCb := IIF(Len(aRet) >= 5, cValToChar(aRet[4]), "")
                cDocCb := IIF(Len(aRet) >= 5, cValToChar(aRet[5]), "")
                cMsgSuc := IIF(Len(aRet) >= 2, cValToChar(aRet[2]), "")
            Else
                cErrMsg := U_PI_CTX_X(cValToChar(aRet[2]), {{"Chave", cChvNFe}})
                cTipoPen  := IIF(Len(aRet) >= 4 .And. aRet[4] == "PRD", "PRD", "")
                cProdPend := IIF(cTipoPen == "PRD" .And. Len(aRet) >= 5, cValToChar(aRet[5]), "")
            EndIf
        Else
            cErrMsg := "JSON invalido na fila ZZD. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZD", cCod, "S", "")
            nTIni := Seconds()
            U_ZZCALLBK("ZZD", cChvNFe, cSub, .T., cFilCb, cDocCb, "", cMsgSuc)
            ConOut("[TIMING][FATZZD01] Callback iPaaS: " + cValToChar(Seconds() - nTIni) + "s | " + cCod)
            nOk++
            ConOut("[FATZZD01] OK: " + cCod)
        ElseIf cTipoPen == "PRD"
            U_UPDSTAT("ZZD", cCod, "P", "")
            U_ZZF_GRV(cChvNFe, "NFC", cProdPend, "", cIdIpaas)
            TCSqlExec("UPDATE " + RetSqlName("ZZD") + " SET ZZD_PRDPEN = 'S' WHERE ZZD_COD = '" + cCod + "' AND ZZD_FILIAL = '" + cFilOri + "' AND D_E_L_E_T_ = ' '")
            nPark++
            ConOut("[FATZZD01] ESTACIONADA (produto pendente): " + cCod + " | Produto: " + cProdPend)
        Else
            U_UPDSTAT("ZZD", cCod, "E", cErrMsg)
            nTIni := Seconds()
            U_ZZCALLBK("ZZD", cChvNFe, cSub, .F., "", "", cErrMsg)
            ConOut("[TIMING][FATZZD01] Callback iPaaS: " + cValToChar(Seconds() - nTIni) + "s | " + cCod)
            nErr++
            ConOut("[FATZZD01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf
    Next nJ
Return

// Resolve cliente/numeracao/CFOP e dispara U_PI_SAIDA_X (grava SF2/SD2, marcados como NFCE)
Static Function ZZD_MotorNFCe(jJson)
    Local oData        := Nil
    Local aEmp         := {}
    Local aRet         := {.F., ""}
    Local aPrd         := {}
    Local cSub         := ""

    Local cCod         := ""
    Local cLoja        := ""
    Local cFil         := ""
    Local cCliD        := "000001"
    Local cTab         := "SA1"
    Local dVencto      := CToD("//")
    Local cCondSafe    := ""
    Local oMotorRegras := Nil
    Local cAuxC        := ""
    Local cCnpjEmit    := ""
    Local cUsuario     := ""
    Local cQryAux      := ""
    Local cAliAux      := ""
    Local nValNF       := 0
    Local cNF          := ""
    Local cSer         := ""
    Local aNum         := {}
    Local nI           := 0
    Local cProdLeg     := ""
    Local cProdInt     := ""
    Local lCest        := .T.
    Local lNcm         := .T.
    Local aRetCfop     := {}
    Local nTIni        := 0

    If ValType(jJson['notas']) == "A" .And. Len(jJson['notas']) > 0
        oData := jJson['notas'][1]
    Else
        oData := jJson
    EndIf
    aPrd := oData['itens']
    cSub := cValToChar(U_PI_VAL_X(oData, 'cod_Subseccao'))

    aEmp := U_PI_FILIAL_X(U_PI_LIMPA_X(U_PI_STR_X(oData, "num_SubseccaoCNPJ")))
    If Len(aEmp) < 2 ; Return {.F., "Filial nao encontrada (ZZD/NFCe)", cSub} ; EndIf
    If aEmp[1] != cEmpAnt .Or. aEmp[2] != cFilAnt ; RpcClearEnv() ; RpcSetEnv(aEmp[1], aEmp[2], Nil, Nil, "FAT") ; EndIf

    dVencto := U_PI_DATA_X(U_PI_STR_X(oData, 'dta_Emissao', 'dta_Vencimento'))
    If !Empty(dVencto)
        dDataBase := dVencto
    EndIf

    cCondSafe    := PadR(U_PI_COND_X("004"), 3)
    oMotorRegras := U_FATCFOP01()
    cCnpjEmit    := U_PI_LIMPA_X(U_PI_STR_X(oData, 'des_EmitDocumento', 'cnpJ_FORNECEDOR'))
    cUsuario     := AllTrim(U_PI_STR_X(oData, 'cod_Exportacao'))

    If !Empty(cUsuario)
        cQryAux := "SELECT A1_COD, A1_LOJA FROM " + RetSqlName("SA1") + " WHERE TRIM(A1_LEGADO) = '" + cUsuario + "' AND D_E_L_E_T_ = ' '"
        cAliAux := GetNextAlias()
        MpSysOpenQuery(cQryAux, cAliAux)
        If (cAliAux)->(!Eof())
            cCod  := (cAliAux)->A1_COD
            cLoja := (cAliAux)->A1_LOJA
        EndIf
        (cAliAux)->(DbCloseArea())
    EndIf

    If Empty(cCod)
        cCod  := cCliD
        cLoja := "01"
    EndIf

    U_PI_BUSCA_X(cTab, cCod, aEmp[2], @cCod, @cLoja, @cFil)

    cSer := AllTrim(U_PI_STR_X(oData, 'cod_Serie', 'num_Serie'))
    If Empty(cSer)
        cSer := "1"
    EndIf
    cSer := PadR(cSer, TamSx3("F2_SERIE")[1], " ")

    nValNF := U_PI_VAL_X(oData, 'num_NF', 'num_NotaFiscal')
    aNum := U_PI_NUMERA_X("SF2", "F2_DOC", cSer, cCod, cLoja, IIF(nValNF == 0, "", cValToChar(nValNF)))
    If !aNum[1] ; Return {.F., "NUMERACAO: " + cValToChar(aNum[2]), cSub} ; EndIf
    If aNum[3] ; Return {.T., "Ja processada anteriormente: " + cValToChar(aNum[2]), cSub, xFilial("SF2"), cValToChar(aNum[2])} ; EndIf
    cNF := cValToChar(aNum[2])

    cQryAux := "SELECT X5_CHAVE FROM " + RetSqlName("SX5") + " WHERE X5_FILIAL = '" + xFilial("SX5") + "' AND X5_TABELA = '01' AND X5_CHAVE = '" + cSer + "' AND D_E_L_E_T_ = ' '"
    cAliAux := GetNextAlias()
    MpSysOpenQuery(cQryAux, cAliAux)
    If (cAliAux)->(Eof())
        (cAliAux)->(DbCloseArea())
        Return {.F., "Serie '" + AllTrim(cSer) + "' nao cadastrada na Tabela 01 (SX5) da filial " + xFilial("SX5") + ".", cSub}
    EndIf
    (cAliAux)->(DbCloseArea())

    For nI := 1 To Len(aPrd)
        cProdLeg := AllTrim(U_PI_STR_X(aPrd[nI], 'cod_Produto'))
        cProdInt := ""
        lCest    := .T.
        lNcm     := .T.

        DbSelectArea("SB1")
        SB1->(DbOrderNickName("LEGADO"))
        If SB1->(DbSeek(xFilial("SB1") + PadR(cProdLeg, TamSx3("B1_LEGADO")[1])))
            cProdInt := AllTrim(SB1->B1_COD)
            aPrd[nI]['cod_Produto'] := cProdInt

            If !Empty(aPrd[nI]['des_ProdutoCEST'])
                lCest := U_BUSCACAD(aPrd[nI]['des_ProdutoCEST'], 1)
            EndIf
            If !Empty(aPrd[nI]['des_ProdutoNCM'])
                lNcm := U_BUSCACAD(aPrd[nI]['des_ProdutoNCM'], 2)
            EndIf

            If lCest .And. lNcm
                If RecLock("SB1", .F.)
                    SB1->B1_POSIPI := aPrd[nI]['des_ProdutoNCM']
                    SB1->B1_CEST   := aPrd[nI]['des_ProdutoCEST']
                    SB1->(MsUnlock())
                EndIf
            Else
                Return {.F., "NCM/CEST nao cadastrado. Item " + cValToChar(nI) + ": " + IIF(!Empty(aPrd[nI]['des_ProdutoNCM']), aPrd[nI]['des_ProdutoNCM'], 'Nil') + '/' + IIF(!Empty(aPrd[nI]['des_ProdutoCEST']), aPrd[nI]['des_ProdutoCEST'], 'Nil'), cSub}
            EndIf
        EndIf

        If Empty(cProdInt)
            Return {.F., "Produto nao cadastrado (Item " + cValToChar(nI) + ") Legado: " + cProdLeg, cSub, "PRD", cProdLeg}
        EndIf

        U_PI_FIXPROD(cProdInt, aPrd[nI])

        cAuxC := U_PI_LIMPA_X(U_PI_STR_X(aPrd[nI], 'cod_ProdutoCFOP', 'cfop'))
        cAuxC := U_PI_INVCFOP(cAuxC, "S")

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

        If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .Or. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
            cQryAux := "SELECT F4_CODIGO FROM " + RetSqlName("SF4") + " WHERE F4_CF='" + PadR(AllTrim(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("F4_CF")[1]) + "' AND F4_MSBLQL <> '1' AND D_E_L_E_T_=' ' ORDER BY F4_ESTOQUE DESC"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(!Eof())
                aPrd[nI]['_TES_CACHE'] := (cAliAux)->F4_CODIGO
            EndIf
            (cAliAux)->(DbCloseArea())
        EndIf

        If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .Or. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
            Return {.F., "TES nao localizado no cadastro (SF4) para o CFOP " + AllTrim(aPrd[nI]['cod_ProdutoCFOP']) + ". Verifique as configuracoes fiscais.", cSub}
        EndIf
    Next nI

    U_PI_SETFCA(cTab, cCod, cLoja, cCondSafe, oData)

    nTIni := Seconds()
    aRet  := U_PI_SAIDA_X(aPrd, oData, cCod, cLoja, "", cSer, "", cTab, .F., cNF, "", "", cCondSafe)
    ConOut("[TIMING][ZZD_MotorNFCe] U_PI_SAIDA_X (MaNfs2Nfs): " + cValToChar(Seconds() - nTIni) + "s")

    If !aRet[1]
        Return {.F., "MANFS2NFS: " + cValToChar(aRet[2]), cSub}
    EndIf

    TCSqlExec("UPDATE " + RetSqlName("SF2") + " SET F2_ESPECIE = '" + PadR("NFCE", TamSx3("F2_ESPECIE")[1]) + "' WHERE F2_DOC = '" + PadL(AllTrim(cValToChar(aRet[2])), TamSx3("F2_DOC")[1], "0") + "' AND F2_SERIE = '" + cSer + "' AND F2_CLIENTE = '" + cCod + "' AND F2_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '")
    TCSqlExec("UPDATE " + RetSqlName("SF3") + " SET F3_ESPECIE = '" + PadR("NFCE", TamSx3("F3_ESPECIE")[1]) + "' WHERE F3_NFISCAL = '" + PadL(AllTrim(cValToChar(aRet[2])), TamSx3("F2_DOC")[1], "0") + "' AND F3_SERIE = '" + cSer + "' AND F3_CLIEFOR = '" + cCod + "' AND F3_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '")

Return {.T., "NFCe: " + xFilial("SF2") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF2"), cValToChar(aRet[2])}
