#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

Static CEMPPAD := "01"
Static CFILPAD := "01001"

// Job agendado - fila ZZC: processa NFe Entrada (cOper=E) via MATA120+MATA103

// Le a fila ZZC e processa cada nota de entrada (NFE/compra)
User Function FATZZC01()
    Local cAliZZC  := GetNextAlias()
    Local cQry     := ""
    Local cCod     := ""
    Local cJson    := ""
    Local cChvNFe  := ""
    Local cErrMsg  := ""
    Local cSub     := ""
    Local cFilCb   := ""
    Local cDocCb   := ""
    Local cMsgSuc  := ""
    Local nRecno   := 0
    Local lOk      := .F.
    Local nOk      := 0
    Local nErr     := 0
    Local jJson    := Nil
    Local aRet     := {}
    Local aFila    := {}
    Local nJ       := 0
    Local bErrOld  := Nil
    Local oErrRT   := Nil

    Private __cBatch := "1"

    ConOut("[FATZZC01] Iniciando NFe Entrada - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    cQry := "SELECT ZZC_COD, ZZC_CHVNFE, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZC") + " "
    cQry += "WHERE ZZC_STATUS IN ('P','A') AND ZZC_PRDPEN = 'N' "
    cQry += "AND ZZC_FILIAL = '" + xFilial("ZZC") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZC_DTINCL, ZZC_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZC, .T., .T.)

    While (cAliZZC)->(!Eof())
        aAdd(aFila, {AllTrim((cAliZZC)->ZZC_COD), AllTrim((cAliZZC)->ZZC_CHVNFE), (cAliZZC)->RECNO})
        (cAliZZC)->(DbSkip())
    EndDo
    (cAliZZC)->(DbCloseArea())

    For nJ := 1 To Len(aFila)
        cCod    := aFila[nJ][1]
        cChvNFe := aFila[nJ][2]
        nRecno  := aFila[nJ][3]
        cErrMsg := ""
        cSub    := ""
        cFilCb  := ""
        cDocCb  := ""
        cMsgSuc := ""
        lOk     := .F.

        DbSelectArea("ZZC")
        ZZC->(DbGoto(nRecno))
        cJson := ZZC->ZZC_JSON

        U_UPDSTAT("ZZC", cCod, "A", "")
        ConOut("[FATZZC01] Processando: " + cCod + " | Chave: " + cChvNFe)

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
                cFilCb := IIF(Len(aRet) >= 5, cValToChar(aRet[4]), "")
                cDocCb := IIF(Len(aRet) >= 5, cValToChar(aRet[5]), "")
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
            nOk++
            ConOut("[FATZZC01] OK: " + cCod)
        Else
            U_UPDSTAT("ZZC", cCod, "E", cErrMsg)
            U_ZZCALLBK("ZZC", cChvNFe, cSub, .F., "", "", cErrMsg)
            nErr++
            ConOut("[FATZZC01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf
    Next nJ

    ConOut("[FATZZC01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

// Resolve numeracao, gera pedido de compra (U_PI_GERAPC_X) e nota de entrada (U_PI_GERANF_X)
Static Function ZZC_MotorEntrada(jJson)
    Local aInv   := jJson['notas']
    Local oHead  := Nil
    Local aPrd   := {}
    Local aEmp   := {}
    Local aRet   := {.F., ""}
    Local aNum   := {}
    Local cPCNew := ""
    Local cSub   := ""
    Local nValNF  := 0
    Local cNumInf := ""
    Local cNF     := ""

    Private lMsErroAuto := .F. ; Private lAutoErrNoFile := .T.

    If ValType(aInv) != "A" .Or. Len(aInv) == 0 ; Return {.F., "Array notas ausente (ZZC/NFE)", ""} ; EndIf
    oHead := aInv[1] ; aPrd := oHead['itens']
    cSub  := cValToChar(U_PI_VAL_X(oHead, 'cod_Subseccao'))

    aEmp := U_PI_FILIAL_X(U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ')))
    If Len(aEmp) < 2 ; Return {.F., "Filial nao encontrada (ZZC/NFE)", cSub} ; EndIf
    If aEmp[1] != cEmpAnt .Or. aEmp[2] != cFilAnt ; RpcClearEnv() ; RpcSetEnv(aEmp[1], aEmp[2], Nil, Nil, "FAT") ; EndIf

    nValNF := U_PI_VAL_X(oHead, 'num_NF', 'num_NotaFiscal')
    If nValNF == 0 ; nValNF := U_PI_VAL_X(oHead, 'cod_ReciboVenda') ; EndIf
    cNumInf := IIF(nValNF == 0, "", cValToChar(nValNF))

    aNum := U_PI_NUMERA_X("SF1", "F1_DOC", AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNumInf)
    If !aNum[1] ; Return {.F., "NUMERACAO: " + cValToChar(aNum[2]), cSub} ; EndIf
    If aNum[3] ; Return {.T., "Ja processada anteriormente: " + cValToChar(aNum[2]), cSub, xFilial("SF1"), cValToChar(aNum[2])} ; EndIf
    cNF := cValToChar(aNum[2])

    U_PI_SETFCA(AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), AllTrim(U_PI_STR_X(oHead,'_COND')), oHead)

    aRet := U_PI_GERAPC_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNF, aEmp, AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_FIL')), "", AllTrim(U_PI_STR_X(oHead,'_COND')))

    If !aRet[1] ; Return {.F., "MATA120: " + cValToChar(aRet[2]), cSub} ; EndIf

    cPCNew := aRet[3]
    aRet   := U_PI_GERANF_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), cPCNew, AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_FIL')), 0, AllTrim(U_PI_STR_X(oHead,'_COND')))

    If aRet[1]
        U_JSON_COMPRA(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')))
        U_PI_GER_E2(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')), SE2->(RECNO()))
        Return {.T., "NFE: " + xFilial("SF1") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF1"), cValToChar(aRet[2])}
    EndIf
Return {.F., "MATA103: " + cValToChar(aRet[2]), cSub}
