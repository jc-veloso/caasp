#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

Static CEMPPAD := "01"
Static CFILPAD := "01001"

// Job agendado - fila ZZA: processa NFe Saida (cOper=S) via MaNfs2Nfs

// Le a fila ZZA e processa cada nota de saida (NFS)
User Function FATZZA01()
    Local cAliZZA  := GetNextAlias()
    Local cQry     := ""
    Local cCod     := ""
    Local cJson    := ""
    Local cChvNFe  := ""
    Local cProc    := ""
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
    Private lJob      := GetRemoteType() == -1

    ConOut("[FATZZA01] Iniciando NFe Saida - " + DToS(Date()) + " " + Time())

    If lJob
        RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")
    EndIf

    cQry := "SELECT ZZA_COD, ZZA_CHVNFE, ZZA_PROC, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZA") + " "
    cQry += "WHERE ZZA_STATUS IN ('P','A') AND ZZA_PRDPEN = 'N' "
    cQry += "AND ZZA_FILIAL = '" + xFilial("ZZA") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZA_DTINCL, ZZA_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZA, .T., .T.)

    While (cAliZZA)->(!Eof())
        aAdd(aFila, {AllTrim((cAliZZA)->ZZA_COD), AllTrim((cAliZZA)->ZZA_CHVNFE), AllTrim((cAliZZA)->ZZA_PROC), (cAliZZA)->RECNO})
        (cAliZZA)->(DbSkip())
    EndDo
    (cAliZZA)->(DbCloseArea())

    For nJ := 1 To Len(aFila)
        cCod    := aFila[nJ][1]
        cChvNFe := aFila[nJ][2]
        cProc   := aFila[nJ][3]
        nRecno  := aFila[nJ][4]
        cErrMsg := ""
        cSub    := ""
        cFilCb  := ""
        cDocCb  := ""
        cMsgSuc := ""
        lOk     := .F.

        DbSelectArea("ZZA")
        ZZA->(DbGoto(nRecno))
        cJson := ZZA->ZZA_JSON

        U_UPDSTAT("ZZA", cCod, "A", "")
        ConOut("[FATZZA01] Processando: " + cCod + " | Proc: " + cProc + " | Chave: " + cChvNFe)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            If cProc == "NFS"
                bErrOld := ErrorBlock({|oErr| Break(oErr)})
                Begin Sequence
                    aRet := ZZA_MotorSaida(jJson)
                Recover Using oErrRT
                    aRet := {.F., "EXCEPTION: " + U_PI_ERRO_RT(oErrRT), ""}
                End Sequence
                ErrorBlock(bErrOld)
            Else
                aRet := {.F., "Tipo de processo inesperado na ZZA (apenas NFS e aceito): " + cProc, ""}
            EndIf
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
            cErrMsg := "JSON invalido na fila ZZA. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZA", cCod, "S", "")
            U_ZZCALLBK("ZZA", cChvNFe, cSub, .T., cFilCb, cDocCb, "", cMsgSuc)
            nOk++
            ConOut("[FATZZA01] OK: " + cCod)
        Else
            U_UPDSTAT("ZZA", cCod, "E", cErrMsg)
            U_ZZCALLBK("ZZA", cChvNFe, cSub, .F., "", "", cErrMsg)
            nErr++
            ConOut("[FATZZA01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf
    Next nJ

    ConOut("[FATZZA01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    If lJob
        RpcClearEnv()
    EndIf
Return

// Resolve numeracao/CFOP, dispara U_PI_SAIDA_X e trata transferencia entre filiais (CONVENIOS)
Static Function ZZA_MotorSaida(jJson)
    Local aInv       := jJson['notas']
    Local oHead      := Nil
    Local aPrd       := {}
    Local aEmp       := {}
    Local aRet       := {.F., ""}
    Local aNum       := {}
    Local cSub       := ""
    Local lIsTransf  := .F.
    Local cCnpjEmit  := ""
    Local cCnpjDest  := ""
    Local aEmpDest   := {}
    Local aRetTransf := {}
    Local nValNF     := 0
    Local cNumInf    := ""
    Local cNF        := ""

    Private lMsErroAuto := .F. ; Private lAutoErrNoFile := .T.

    If ValType(aInv) != "A" .Or. Len(aInv) == 0 ; Return {.F., "Array notas ausente (ZZA/NFS)", ""} ; EndIf
    oHead := aInv[1] ; aPrd := oHead['itens']
    cSub  := cValToChar(U_PI_VAL_X(oHead, 'cod_Subseccao'))

    aEmp := U_PI_FILIAL_X(U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ')))
    If Len(aEmp) < 2 ; Return {.F., "Filial nao encontrada (ZZA/NFS)", cSub} ; EndIf
    If aEmp[1] != cEmpAnt .Or. aEmp[2] != cFilAnt ; RpcClearEnv() ; RpcSetEnv(aEmp[1], aEmp[2], Nil, Nil, "FAT") ; EndIf

    nValNF := U_PI_VAL_X(oHead, 'num_NF', 'num_NotaFiscal')
    If nValNF == 0 ; nValNF := U_PI_VAL_X(oHead, 'cod_ReciboVenda') ; EndIf
    cNumInf := IIF(nValNF == 0, "", cValToChar(nValNF))

    aNum := U_PI_NUMERA_X("SF2", "F2_DOC", AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNumInf)
    If !aNum[1] ; Return {.F., "NUMERACAO: " + cValToChar(aNum[2]), cSub} ; EndIf
    If aNum[3] ; Return {.T., "Ja processada anteriormente: " + cValToChar(aNum[2]), cSub, xFilial("SF2"), cValToChar(aNum[2])} ; EndIf
    cNF := cValToChar(aNum[2])

    U_PI_SETFCA(AllTrim(U_PI_STR_X(oHead, '_TAB')), AllTrim(U_PI_STR_X(oHead, '_COD')), AllTrim(U_PI_STR_X(oHead, '_LOJA')), AllTrim(U_PI_STR_X(oHead, '_COND')), oHead)

    aRet := U_PI_SAIDA_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_FIL')), AllTrim(U_PI_STR_X(oHead,'_TAB')), U_PI_STR_X(oHead,'_TRANSF')=="S", cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), cNF, AllTrim(U_PI_STR_X(oHead,'_COND')))

    If aRet[1]
        lIsTransf := U_PI_STR_X(oHead,'_TRANSF') == "S"
        cCnpjEmit := AllTrim(U_PI_STR_X(oHead,'_CNPJEMIT'))
        cCnpjDest := AllTrim(U_PI_STR_X(oHead,'_CNPJDEST'))

        If lIsTransf .And. cCnpjEmit != cCnpjDest
            aEmpDest := U_PI_FILIAL_X(cCnpjDest)
            If Len(aEmpDest) >= 2
                aRetTransf := U_FATPI01NF(aPrd, oHead, cCnpjEmit, cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), aEmpDest, lIsTransf)
                If !aRetTransf[1]
                    U_PI_ROLLBACK_NF(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')))
                    Return {.F., "ROLLBACK_CONVENIOS: " + cValToChar(aRetTransf[2]) + " | Saida (SF2) na origem foi ESTORNADA.", cSub}
                EndIf
            EndIf
        EndIf

        Return {.T., "NFS: " + xFilial("SF2") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF2"), cValToChar(aRet[2])}
    EndIf
Return {.F., IIF(aRet[3],"NFORIGEM","MANFS2NFS") + ": " + cValToChar(aRet[2]), cSub}
