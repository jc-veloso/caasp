#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

Static CEMPPAD := "01"
Static CFILPAD := "01001"

// Job agendado - fila ZZB: processa NFe Devolucao (cOper=D) via MATA103

// Le a fila ZZB e processa cada nota de devolucao (NFD)
User Function FATZZB01()
    Local cAliZZB  := GetNextAlias()
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

    ConOut("[FATZZB01] Iniciando NFe Devolucao - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    cQry := "SELECT ZZB_COD, ZZB_CHVNFE, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZB") + " "
    cQry += "WHERE ZZB_STATUS IN ('P','A') AND ZZB_PRDPEN = 'N' "
    cQry += "AND ZZB_FILIAL = '" + xFilial("ZZB") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZB_DTINCL, ZZB_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZB, .T., .T.)

    While (cAliZZB)->(!Eof())
        aAdd(aFila, {AllTrim((cAliZZB)->ZZB_COD), AllTrim((cAliZZB)->ZZB_CHVNFE), (cAliZZB)->RECNO})
        (cAliZZB)->(DbSkip())
    EndDo
    (cAliZZB)->(DbCloseArea())

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

        DbSelectArea("ZZB")
        ZZB->(DbGoto(nRecno))
        cJson := ZZB->ZZB_JSON

        U_UPDSTAT("ZZB", cCod, "A", "")
        ConOut("[FATZZB01] Processando: " + cCod + " | Chave: " + cChvNFe)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            bErrOld := ErrorBlock({|oErr| Break(oErr)})
            Begin Sequence
                aRet := ZZB_MotorDevolucao(jJson)
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
            cErrMsg := "JSON invalido na fila ZZB. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZB", cCod, "S", "")
            U_ZZCALLBK("ZZB", cChvNFe, cSub, .T., cFilCb, cDocCb, "", cMsgSuc)
            nOk++
            ConOut("[FATZZB01] OK: " + cCod)
        Else
            U_UPDSTAT("ZZB", cCod, "E", cErrMsg)
            U_ZZCALLBK("ZZB", cChvNFe, cSub, .F., "", "", cErrMsg)
            nErr++
            ConOut("[FATZZB01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf
    Next nJ

    ConOut("[FATZZB01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

// Resolve numeracao e dispara U_PI_DEVOL_X (MATA103 tipo devolucao)
Static Function ZZB_MotorDevolucao(jJson)
    Local aInv  := jJson['notas']
    Local oHead := Nil
    Local aPrd  := {}
    Local aEmp  := {}
    Local aRet  := {.F., ""}
    Local aNum  := {}
    Local cSub  := ""
    Local nValNF  := 0
    Local cNumInf := ""
    Local cNF     := ""

    Private lMsErroAuto := .F. ; Private lAutoErrNoFile := .T.

    If ValType(aInv) != "A" .Or. Len(aInv) == 0 ; Return {.F., "Array notas ausente (ZZB/NFD)", ""} ; EndIf
    oHead := aInv[1] ; aPrd := oHead['itens']
    cSub  := cValToChar(U_PI_VAL_X(oHead, 'cod_Subseccao'))

    aEmp := U_PI_FILIAL_X(U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ')))
    If Len(aEmp) < 2 ; Return {.F., "Filial nao encontrada (ZZB/NFD)", cSub} ; EndIf
    If aEmp[1] != cEmpAnt .Or. aEmp[2] != cFilAnt ; RpcClearEnv() ; RpcSetEnv(aEmp[1], aEmp[2], Nil, Nil, "FAT") ; EndIf

    nValNF := U_PI_VAL_X(oHead, 'num_NF', 'num_NotaFiscal')
    If nValNF == 0 ; nValNF := U_PI_VAL_X(oHead, 'cod_ReciboVenda') ; EndIf
    cNumInf := IIF(nValNF == 0, "", cValToChar(nValNF))

    aNum := U_PI_NUMERA_X("SF1", "F1_DOC", AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNumInf)
    If !aNum[1] ; Return {.F., "NUMERACAO: " + cValToChar(aNum[2]), cSub} ; EndIf
    If aNum[3] ; Return {.T., "Ja processada anteriormente: " + cValToChar(aNum[2]), cSub, xFilial("SF1"), cValToChar(aNum[2])} ; EndIf
    cNF := cValToChar(aNum[2])

    U_PI_SETFCA(AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), AllTrim(U_PI_STR_X(oHead,'_COND')), oHead)

    aRet := U_PI_DEVOL_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_FIL')), 0, AllTrim(U_PI_STR_X(oHead,'_COND')))

    If aRet[1]
        U_JSON_COMPRA(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')))
        Return {.T., "NFD: " + xFilial("SF1") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF1"), cValToChar(aRet[2])}
    EndIf
Return {.F., IIF(aRet[3],"NFORIGEM","MATA103_DEV") + ": " + cValToChar(aRet[2]), cSub}
