#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

Static CEMPPAD := "01"
Static CFILPAD := "01001"

// Job agendado - fila ZZC: processa NFe Entrada via MATA120+MATA103, paralelo via StartJob (uma thread por nota), claim atomico por token - ver instrucao_claim_atomico_zzc*.md

// Le a fila ZZC e dispara uma StartJob por nota, respeitando o teto de threads
User Function FATZZC01()
    Local cAliZZC   := GetNextAlias()
    Local cQry      := ""
    Local cCod      := ""
    Local cJson     := ""
    Local cChvNFe   := ""
    Local nRecno    := 0
    Local aFila     := {}
    Local nJ        := 0
    Local nDisparadas := 0
    Local nMaxThr   := 0
    Local nStaleMin := 0
    Local cQryClaim := ""
    Local cClaimTok := ""
    Local lClaimOk  := .F.
    Local cAliCheck := ""
    Local cQryCheck := ""
    Local cThrDtOri := ""

    Private __cBatch := "1"

    ConOut("[FATZZC01] Iniciando NFe Entrada - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    nMaxThr   := SuperGetMv("MV_XCPTHR", .F., 10)
    nStaleMin := SuperGetMv("MV_XCPSTL", .F., 15)

    cClaimTok := cValToChar(ThreadID()) + "_" + Time() // token unico por execucao, nao por nota

    cQry := "SELECT ZZC_COD, ZZC_CHVNFE, ZZC_STATUS, ZZC_THRDT, ZZC_THRHR, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZC") + " "
    cQry += "WHERE ZZC_STATUS IN ('P','A') AND ZZC_PRDPEN = 'N' "
    cQry += "AND ZZC_FILIAL = '" + xFilial("ZZC") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZC_DTINCL, ZZC_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZC, .T., .T.)

    // So entra na fila se 'P' ou 'A' orfao de verdade (mais velho que MV_XCPSTL)
    While (cAliZZC)->(!Eof())
        If (cAliZZC)->ZZC_STATUS == "P" .Or. PI_MINATRS((cAliZZC)->ZZC_THRDT, (cAliZZC)->ZZC_THRHR) > nStaleMin
            aAdd(aFila, {AllTrim((cAliZZC)->ZZC_COD), AllTrim((cAliZZC)->ZZC_CHVNFE), (cAliZZC)->RECNO, (cAliZZC)->ZZC_THRDT, (cAliZZC)->ZZC_THRHR})
        EndIf
        (cAliZZC)->(DbSkip())
    EndDo
    (cAliZZC)->(DbCloseArea())

    For nJ := 1 To Len(aFila)
        cCod    := aFila[nJ][1]
        cChvNFe := aFila[nJ][2]
        nRecno  := aFila[nJ][3]

        // Reposiciona na area nativa ZZC so pra ler o memo certo
        DbSelectArea("ZZC")
        ZZC->(DbGoto(nRecno))
        cJson := ZZC->ZZC_JSON

        // ZZC_THRDT pode vir Character ou Data do TcGenQry - normaliza antes do WHERE
        cThrDtOri := IIF(ValType(aFila[nJ][4]) == "D", DToS(aFila[nJ][4]), aFila[nJ][4])

        cQryClaim := "UPDATE " + RetSqlName("ZZC") + " SET ZZC_STATUS = 'A', "
        cQryClaim += "ZZC_THRDT = '" + DToS(Date()) + "', ZZC_THRHR = '" + Time() + "', "
        cQryClaim += "ZZC_THRTOK = '" + cClaimTok + "' "
        cQryClaim += "WHERE ZZC_COD = '" + cCod + "' AND D_E_L_E_T_ = ' ' AND ("
        cQryClaim += "ZZC_STATUS = 'P' OR "
        cQryClaim += "(ZZC_STATUS = 'A' AND ZZC_THRDT = '" + cThrDtOri + "' AND ZZC_THRHR = '" + aFila[nJ][5] + "')"
        cQryClaim += ")"
        If TCSqlExec(cQryClaim) != 0
            ConOut("[FATZZC01] FALHA ao executar UPDATE de claim: " + cCod + " | " + TCSqlError())
            Loop
        EndIf

        // Releitura de confirmacao: so segue se o token gravado for o desta execucao
        cQryCheck := "SELECT ZZC_THRTOK FROM " + RetSqlName("ZZC") + " WHERE ZZC_COD = '" + cCod + "' AND D_E_L_E_T_ = ' '"
        cAliCheck := GetNextAlias()
        MpSysOpenQuery(cQryCheck, cAliCheck)
        lClaimOk := (cAliCheck)->(!Eof()) .And. AllTrim((cAliCheck)->ZZC_THRTOK) == cClaimTok
        (cAliCheck)->(DbCloseArea())

        If !lClaimOk
            ConOut("[FATZZC01] Claim perdido (outra execucao ja reivindicou): " + cCod)
            Loop
        EndIf

        While U_PI_QTDATIVA() >= nMaxThr // throttle: espera abrir vaga antes de disparar
            Sleep(1000)
        EndDo

        StartJob("U_PI_ENTTH", GetEnvServer(), .F., cCod, cChvNFe, cJson)
//        U_PI_ENTTH(cCod, cChvNFe, cJson)
        nDisparadas++
        ConOut("[FATZZC01] Disparada: " + cCod + " | Chave: " + cChvNFe)
    Next nJ

    ConOut("[FATZZC01] Fim. " + cValToChar(nDisparadas) + " nota(s) disparada(s) para processamento paralelo.")
    RpcClearEnv()
Return

// Minutos decorridos desde o claim (dThrDt/cThrHr) ate agora, em AdvPL puro. Vazio conta como muito antigo.
Static Function PI_MINATRS(dThrDt, cThrHr)
    Local nSegThr  := 0
    Local dThrDtOK := CToD("")

    If ValType(dThrDt) == "D"
        dThrDtOK := dThrDt
    ElseIf ValType(dThrDt) == "C" .And. !Empty(dThrDt)
        dThrDtOK := STOD(dThrDt)
    EndIf

    If Empty(dThrDtOK) .Or. Empty(cThrHr)
        Return 999999
    EndIf
    nSegThr := Val(SubStr(cThrHr,1,2))*3600 + Val(SubStr(cThrHr,4,2))*60 + Val(SubStr(cThrHr,7,2))
Return (Date() - dThrDtOK) * 1440 + (Seconds() - nSegThr) / 60

// Conta notas 'A' frescas (dentro de MV_XCPSTL) na filial - semaforo do throttle
User Function PI_QTDATIVA()
    Local cQryThr    := "SELECT ZZC_THRDT, ZZC_THRHR FROM " + RetSqlName("ZZC") + " "
    Local cAliThr    := GetNextAlias()
    Local nQtd       := 0
    Local nStaleMin  := SuperGetMv("MV_XCPSTL", .F., 15)

    cQryThr += "WHERE ZZC_STATUS = 'A' AND ZZC_FILIAL = '" + xFilial("ZZC") + "' AND D_E_L_E_T_ = ' '"
    MpSysOpenQuery(cQryThr, cAliThr)
    While (cAliThr)->(!Eof())
        If PI_MINATRS((cAliThr)->ZZC_THRDT, (cAliThr)->ZZC_THRHR) <= nStaleMin
            nQtd++
        EndIf
        (cAliThr)->(DbSkip())
    EndDo
    (cAliThr)->(DbCloseArea())
Return nQtd

// Thread worker (StartJob) - processa uma nota isolada, monta o proprio ambiente
User Function PI_ENTTH(cCod, cChvNFe, cJson)
    Local jJson    := Nil
    Local aRet     := {}
    Local lOk      := .F.
    Local cErrMsg  := ""
    Local cSub     := ""
    Local cFilCb   := ""
    Local cDocCb   := ""
    Local cMsgSuc  := ""
    Local bErrOld  := Nil
    Local oErrRT   := Nil

    Private __cBatch := "1"

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

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
        U_UPDSTAT("ZZC", cCod, "S", cMsgSuc) // ZZC_ERRMSG guarda sucesso tambem, nao so erro
        U_ZZCALLBK("ZZC", cChvNFe, cSub, .T., cFilCb, cDocCb, "", cMsgSuc)
        ConOut("[PI_ENTTH] OK: " + cCod)
    Else
        U_UPDSTAT("ZZC", cCod, "E", cErrMsg)
        U_ZZCALLBK("ZZC", cChvNFe, cSub, .F., "", "", cErrMsg)
        ConOut("[PI_ENTTH] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
    EndIf

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
    Local lTranOk := .F.
    Local cErroFn := ""

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

    // PC (MATA120) e NF (MATA103) numa unica transacao - se o NF falhar depois do PC ja criado, desarma e desfaz os dois, evita PC orfao sem NF
    Begin Transaction
        aRet := U_PI_GERAPC_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNF, aEmp, AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_FIL')), "", AllTrim(U_PI_STR_X(oHead,'_COND')))

        If !aRet[1]
            cErroFn := "MATA120: " + cValToChar(aRet[2])
            DisarmTransaction()
        Else
            cPCNew := aRet[3]
            aRet   := U_PI_GERANF_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), cPCNew, AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_FIL')), 0, AllTrim(U_PI_STR_X(oHead,'_COND')))

            If aRet[1]
                lTranOk := .T.
            Else
                cErroFn := "MATA103: " + cValToChar(aRet[2])
                DisarmTransaction()
            EndIf
        EndIf
    End Transaction

    If !lTranOk ; Return {.F., cErroFn, cSub} ; EndIf

    U_JSON_COMPRA(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')))
    U_PI_GER_E2(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')), SE2->(RECNO()))
Return {.T., "NFE: " + xFilial("SF1") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF1"), cValToChar(aRet[2])}
