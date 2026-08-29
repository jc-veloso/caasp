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

    Private __cBatch := "1"
    Private lJob      := GetRemoteType() == -1
    Private aFila      := {}
    Private nOk        := 0
    Private nErr       := 0

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
        aAdd(aFila, {AllTrim((cAliZZG)->ZZG_COD), AllTrim((cAliZZG)->ZZG_CHVREF), AllTrim((cAliZZG)->ZZG_TIPOPE), AllTrim((cAliZZG)->ZZG_TIPONF), (cAliZZG)->RECNO})
        (cAliZZG)->(DbSkip())
    EndDo
    (cAliZZG)->(DbCloseArea())

    If lJob
        ZZG_ProcessaFila()
    Else
        Processa({|| ZZG_ProcessaFila()}, "FATZZG01", "Cadastrando Cliente/Fornecedor Pendente...")
    EndIf

    ConOut("[FATZZG01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    If lJob
        RpcClearEnv()
    EndIf
Return

// Percorre aFila (Private) cadastrando cada cliente/fornecedor pendente; nOk/nErr (Private) acumulam o resultado
Static Function ZZG_ProcessaFila()
    Local cCod     := ""
    Local cJson    := ""
    Local cChvRef  := ""
    Local cTipoPen := ""
    Local cTipoNF  := ""
    Local cErrMsg  := ""
    Local nRecno   := 0
    Local lOk      := .F.
    Local jJson    := Nil
    Local aRet     := {}
    Local cTabPai  := ""
    Local nTIni    := 0
    Local nJ       := 0

    If !lJob
        ProcRegua(Len(aFila))
    EndIf

    For nJ := 1 To Len(aFila)
        cCod    := aFila[nJ][1]
        cChvRef := aFila[nJ][2]
        cTipoPen:= aFila[nJ][3]
        cTipoNF := aFila[nJ][4]
        nRecno  := aFila[nJ][5]
        cErrMsg := ""
        lOk     := .F.

        If !lJob
            IncProc("Ref " + cChvRef + " (" + cValToChar(nJ) + "/" + cValToChar(Len(aFila)) + ")")
        EndIf

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
    Next nJ
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
