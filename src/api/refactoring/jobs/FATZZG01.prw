#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

Static CEMPPAD := "01"
Static CFILPAD := "01001"

// Job agendado - fila ZZG: cadastra cliente/fornecedor pendente e libera a nota pai

// Le a fila ZZG e cadastra cada cliente/fornecedor pendente, liberando a nota pai quando concluido
User Function FATZZG01()
    Local cAliZZG  := GetNextAlias()
    Local cQry     := ""
    Local cCod     := ""
    Local cJson    := ""
    Local cChvRef  := ""
    Local cTipoPen := ""
    Local cTipoNF  := ""
    Local cErrMsg  := ""
    Local nRecno   := 0
    Local lOk      := .F.
    Local nOk      := 0
    Local nErr     := 0
    Local jJson    := Nil
    Local aRet     := {}
    Local cTabPai  := ""
    Local nTIni    := 0

    Private __cBatch := "1"
    Private lJob      := GetRemoteType() == -1

    ConOut("[FATZZG01] Iniciando Cliente/Fornecedor Pendente - " + DToS(Date()) + " " + Time())

    If lJob
        RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")
    EndIf

    cQry := "SELECT ZZG_COD, ZZG_CHVREF, ZZG_TIPOPE, ZZG_TIPONF, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZG") + " "
    cQry += "WHERE ZZG_STATUS IN ('P','A') "
    cQry += "AND ZZG_FILIAL = '" + xFilial("ZZG") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZG_DTINCL, ZZG_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZG, .T., .T.)

    While (cAliZZG)->(!Eof())
        cCod    := AllTrim((cAliZZG)->ZZG_COD)
        cChvRef := AllTrim((cAliZZG)->ZZG_CHVREF)
        cTipoPen:= AllTrim((cAliZZG)->ZZG_TIPOPE)
        cTipoNF := AllTrim((cAliZZG)->ZZG_TIPONF)
        nRecno  := (cAliZZG)->RECNO
        cErrMsg := ""
        lOk     := .F.

        DbSelectArea("ZZG")
        ZZG->(DbGoto(nRecno))
        cJson := ZZG->ZZG_JSON

        U_UPDSTAT("ZZG", cCod, "A", "")
        ConOut("[FATZZG01] Processando: " + cCod + " | Tipo: " + cTipoPen + " | Chave: " + cChvRef)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            nTIni := Seconds()
            If cTipoPen == "CLI"
                aRet := U_PI_CLI_X(jJson)
            ElseIf cTipoPen == "FOR"
                aRet := U_PI_FORN_X(jJson)
            Else
                aRet := {.F., "ZZG_TIPOPE inesperado (apenas CLI/FOR e aceito): " + cTipoPen}
            EndIf
            ConOut("[TIMING][FATZZG01] " + cTipoPen + ": " + cValToChar(Seconds() - nTIni) + "s | " + cCod)
            lOk := aRet[1]
            If !lOk ; cErrMsg := cValToChar(aRet[2]) ; EndIf
        Else
            cErrMsg := "JSON invalido na fila ZZG. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZG", cCod, "S", "")
            nOk++
            ConOut("[FATZZG01] OK: " + cCod)

            If U_ZZPENDOK(cChvRef, cCod, "ZZG")
                cTabPai := IIF(cTipoNF == "ZZ9", "ZZ9", "ZZD")
                U_ZZ_LIBNF(cTabPai, cChvRef)
                ConOut("[FATZZG01] Nota liberada na " + cTabPai + " | Chave: " + cChvRef)

                nTIni := Seconds()
                ConOut("[TIMING][FATZZG01] Callback iPaaS: " + cValToChar(Seconds() - nTIni) + "s | " + cChvRef)
            EndIf
        Else
            U_UPDSTAT("ZZG", cCod, "E", cErrMsg)
            nErr++
            ConOut("[FATZZG01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))

            cTabPai := IIF(cTipoNF == "ZZ9", "ZZ9", "ZZD")
        EndIf

        (cAliZZG)->(DbSkip())
    EndDo
    (cAliZZG)->(DbCloseArea())

    ConOut("[FATZZG01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    If lJob
        RpcClearEnv()
    EndIf
Return

// Grava um cliente/fornecedor pendente na fila ZZG
User Function ZZG_GRV(cChvRef, cTipoPen, cTipoNF, cJsonPayload, cIdIpaas)
    Local lOk  := .F.
    Local cCod := ""

    Default cIdIpaas := ""

    cCod := GetSxeNum("ZZG", "ZZG_COD")

    DbSelectArea("ZZG")
    If RecLock("ZZG", .T.)
        ZZG->ZZG_FILIAL  := xFilial("ZZG")
        ZZG->ZZG_COD     := PadR(cCod, TamSx3("ZZG_COD")[1])
        ZZG->ZZG_STATUS  := "P"
        ZZG->ZZG_CHVREF  := PadR(cChvRef, TamSx3("ZZG_CHVREF")[1])
        ZZG->ZZG_TIPOPE := PadR(cTipoPen, TamSx3("ZZG_TIPOPE")[1])
        ZZG->ZZG_TIPONF  := PadR(cTipoNF, TamSx3("ZZG_TIPONF")[1])
        ZZG->ZZG_JSON    := cJsonPayload
        ZZG->ZZG_DTINCL  := Date()
        ZZG->ZZG_HRINCL  := Time()
        If ZZG->(FieldPos("ZZG_IDIPS")) > 0
            ZZG->(FieldPut(ZZG->(FieldPos("ZZG_IDIPS")), PadR(cIdIpaas, TamSx3("ZZG_IDIPS")[1])))
        EndIf
        ZZG->(MsUnlock())
        ConfirmSx8()
        lOk := .T.
    Else
        RollBackSx8()
    EndIf
Return lOk
