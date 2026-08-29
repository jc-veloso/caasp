#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

STATIC CEMPPAD := "01"
STATIC CFILPAD := "01001"

// Job agendado - fila ZZF: cadastra produtos pendentes (SB1) e libera a nota pai; tambem
// concentra funcoes utilitarias compartilhadas por todos os Jobs FATZZ* (deve compilar primeiro).

// Le a fila ZZF e cadastra cada produto pendente, liberando a nota pai quando concluido
User Function FATZZF01()
    Local cAliZZF  := GetNextAlias()
    Local cQry     := ""
    Local cCod     := ""
    Local cChvRef  := ""
    Local cTipoNF  := ""
    Local cCodLeg  := ""
    Local cErrMsg  := ""
    Local lOk      := .F.
    Local nOk      := 0
    Local nErr     := 0
    Local aRet     := {}
    Local cTabPai  := ""
    Local nTIni    := 0

    Private __cBatch := "1"
    Private lJob      := GetRemoteType() == -1

    ConOut("[FATZZF01] Iniciando Produtos Pendentes - " + DToS(Date()) + " " + Time())

    If lJob
        RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")
    EndIf

    cQry := "SELECT ZZF_COD, ZZF_CHVREF, ZZF_TIPONF, ZZF_CODLEG FROM " + RetSqlName("ZZF") + " "
    cQry += "WHERE ZZF_STATUS IN ('P','A') "
    cQry += "AND ZZF_FILIAL = '" + xFilial("ZZF") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZF_DTINCL, ZZF_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZF, .T., .T.)

    While (cAliZZF)->(!Eof())
        cCod    := AllTrim((cAliZZF)->ZZF_COD)
        cChvRef := AllTrim((cAliZZF)->ZZF_CHVREF)
        cTipoNF := AllTrim((cAliZZF)->ZZF_TIPONF)
        cCodLeg := AllTrim((cAliZZF)->ZZF_CODLEG)
        cErrMsg := ""
        lOk     := .F.

        U_UPDSTAT("ZZF", cCod, "A", "")
        ConOut("[FATZZF01] Cadastrando produto: " + cCodLeg + " | Ref: " + cChvRef + " | Tipo: " + cTipoNF)

        nTIni := Seconds()
        aRet  := ZZF_CADPRD(cCodLeg)
        ConOut("[TIMING][FATZZF01] ZZF_CADPRD: " + cValToChar(Seconds() - nTIni) + "s | " + cCodLeg)
        lOk  := aRet[1]
        If !lOk ; cErrMsg := cValToChar(aRet[2]) ; EndIf

        If lOk
            U_UPDSTAT("ZZF", cCod, "S", "")
            nOk++
            ConOut("[FATZZF01] Produto OK: " + cCodLeg)

            If U_ZZPENDOK(cChvRef, cCod, "ZZF")
                Do Case
                    Case cTipoNF == "ZZ9" ; cTabPai := "ZZ9"
                    Case cTipoNF == "NFS" ; cTabPai := "ZZA"
                    Case cTipoNF == "NFD" ; cTabPai := "ZZB"
                    Case cTipoNF == "NFE" ; cTabPai := "ZZC"
                    Case cTipoNF == "NFC" ; cTabPai := "ZZD"
                    Case cTipoNF == "RCV" ; cTabPai := "ZZE"
                    Otherwise              ; cTabPai := "ZZA"
                EndCase
                U_ZZ_LIBNF(cTabPai, cChvRef)
                ConOut("[FATZZF01] Nota liberada na " + cTabPai + " | Chave: " + cChvRef)

                nTIni := Seconds()
                ConOut("[TIMING][FATZZF01] Callback iPaaS: " + cValToChar(Seconds() - nTIni) + "s | " + cChvRef)
            EndIf
        Else
            U_UPDSTAT("ZZF", cCod, "E", cErrMsg)
            nErr++
            ConOut("[FATZZF01] ERRO produto: " + cCodLeg + " | " + Left(cErrMsg, 100))

            Do Case
                Case cTipoNF == "ZZ9" ; cTabPai := "ZZ9"
                Case cTipoNF == "NFS" ; cTabPai := "ZZA"
                Case cTipoNF == "NFD" ; cTabPai := "ZZB"
                Case cTipoNF == "NFE" ; cTabPai := "ZZC"
                Case cTipoNF == "NFC" ; cTabPai := "ZZD"
                Case cTipoNF == "RCV" ; cTabPai := "ZZE"
                Otherwise              ; cTabPai := "ZZA"
            EndCase

            nTIni := Seconds()
            ConOut("[TIMING][FATZZF01] Callback iPaaS (erro): " + cValToChar(Seconds() - nTIni) + "s | " + cChvRef)
        EndIf

        (cAliZZF)->(DbSkip())
    EndDo
    (cAliZZF)->(DbCloseArea())

    ConOut("[FATZZF01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    If lJob
        RpcClearEnv()
    EndIf
Return

// Busca o cadastro definitivo do produto na API da CAASP e chama U_PI_PROD_X para gravar (SB1)
Static Function ZZF_CADPRD(cCodLeg)
    Local aRet      := {.F., ""}
    Local aRes      := {}
    Local aHeader   := {}
    Local cUrl      := "https://api.caasp.org.br/integracoes/totvs/produtos/listar"
    Local cToken    := AllTrim(SuperGetMv("MV_XCPTOK", .F., "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1bmlxdWVfbmFtZSI6IlRPVFZTIiwianRpIjoiOTQ5ZjU1ZDY5YjQ0NDU5YWFmODBjMTAzOWQ1ODVlM2IiLCJuYmYiOjE3NjU4MTk5NDQsImV4cCI6MTc2NTgyMzU0NCwiaWF0IjoxNzY1ODE5OTQ0LCJpc3MiOiJodHRwczovL2FwaS5jYWFzcC5vcmcuYnIiLCJhdWQiOiJodHRwczovL2FwaS5jYWFzcC5vcmcuYnIifQ.22h-Y1zND9xcZFrWocakbDiItreh367rRYiTPqOIhNA"))
    Local cBody     := ""
    Local cHeadRet  := ""
    Local jResp     := Nil
    Local jProd     := Nil
    Local nRetries  := SuperGetMv("MV_XCPRET", .F., 5)
    Local nWaitSecs := SuperGetMv("MV_XCPWAIT", .F., 2)
    Local nTimeOut  := 30
    Local nTent     := 0
    Local lHttpOk   := .F.
    Local cErroHttp := ""
    Local nTIni     := 0

    If Empty(cToken)
        Return {.F., "Parametro MV_XCPTOK (token da API CAASP) nao configurado."}
    EndIf

    For nTent := 0 To nRetries
        If nTent > 0
            ConOut("[ZZF_CADPRD] Retry " + cValToChar(nTent) + "/" + cValToChar(nRetries) + " para produto: " + cCodLeg)
            Sleep(nWaitSecs * 1000)
        EndIf

        aHeader := {}
        aAdd(aHeader, "Authorization: Bearer " + cToken)
        cHeadRet := ""
        nTIni := Seconds()
        cBody := HttpGet(cUrl + "?int_PaginaAtual=1&int_ItemsPorPagina=1&cod_Produto=" + AllTrim(cCodLeg), "", nTimeOut, aHeader, @cHeadRet)
        ConOut("[TIMING][ZZF_CADPRD] HttpGet CAASP (tentativa " + cValToChar(nTent + 1) + "): " + cValToChar(Seconds() - nTIni) + "s | " + cCodLeg)

        If Empty(cBody) .Or. !("200" $ cHeadRet .Or. "201" $ cHeadRet)
            cErroHttp := "Header resposta: " + cHeadRet
            Loop
        EndIf

        lHttpOk := .T.
        Exit
    Next nTent

    If !lHttpOk
        Return {.F., "Falha HTTP ao consultar produto na API CAASP apos " + cValToChar(nRetries + 1) + " tentativa(s): " + cCodLeg + " | " + cErroHttp}
    EndIf

    jResp := JsonObject():New()
    If !Empty(jResp:FromJson(cBody))
        FreeObj(jResp)
        Return {.F., "Resposta invalida (JSON) da API CAASP para produto: " + cCodLeg}
    EndIf

    If ValType(jResp['items']) != "A" .Or. Len(jResp['items']) == 0
        FreeObj(jResp)
        Return {.F., "Produto nao encontrado na API CAASP: " + cCodLeg}
    EndIf

    jProd := jResp['items'][1]

    If !FindFunction("U_PI_PROD_X")
        FreeObj(jResp)
        Return {.F., "Motor PI_PROD_X (FATPI02) nao disponivel. Verificar compilacao."}
    EndIf

    nTIni := Seconds()
    aRes  := U_PI_PROD_X(jProd)
    ConOut("[TIMING][ZZF_CADPRD] U_PI_PROD_X: " + cValToChar(Seconds() - nTIni) + "s | " + cCodLeg)
    If aRes[1]
        aRet := {.T., "Produto cadastrado: " + aRes[3]}
    Else
        aRet := {.F., aRes[2]}
    EndIf
    FreeObj(jResp)
Return aRet

// Verifica se uma nota (cChvRef) esta livre de pendencias em ambas as filas (ZZF/produto e ZZG/cliente-fornecedor)
User Function ZZPENDOK(cChvRef, cCodAtual, cTabAtual)
    Local cAli   := ""
    Local lRet   := .F.
    Local nQtdF  := 0
    Local nQtdG  := 0
    Local cQry   := ""

    cQry := "SELECT COUNT(*) AS QTD FROM " + RetSqlName("ZZF") + " "
    cQry += "WHERE ZZF_CHVREF = '" + cChvRef + "' AND ZZF_STATUS IN ('P','A','E') "
    If cTabAtual == "ZZF"
        cQry += "AND ZZF_COD != '" + cCodAtual + "' "
    EndIf
    cQry += "AND D_E_L_E_T_ = ' '"
    cAli := GetNextAlias()
    MpSysOpenQuery(cQry, cAli)
    If (cAli)->(!Eof())
        nQtdF := (cAli)->QTD
    EndIf
    (cAli)->(DbCloseArea())

    cQry := "SELECT COUNT(*) AS QTD FROM " + RetSqlName("ZZG") + " "
    cQry += "WHERE ZZG_CHVREF = '" + cChvRef + "' AND ZZG_STATUS IN ('P','A','E') "
    If cTabAtual == "ZZG"
        cQry += "AND ZZG_COD != '" + cCodAtual + "' "
    EndIf
    cQry += "AND D_E_L_E_T_ = ' '"
    cAli := GetNextAlias()
    MpSysOpenQuery(cQry, cAli)
    If (cAli)->(!Eof())
        nQtdG := (cAli)->QTD
    EndIf
    (cAli)->(DbCloseArea())

    lRet := (nQtdF == 0 .And. nQtdG == 0)
    ConOut("[ZZPENDOK] Chave: " + cChvRef + " | ZZF pendentes: " + cValToChar(nQtdF) + " | ZZG pendentes: " + cValToChar(nQtdG) + " | " + IIF(lRet, "LIBERA", "AGUARDA OUTRAS PENDENCIAS"))
Return lRet

// Libera a nota pai (zera PRDPEN/CLIPEN/FORPEN) na tabela Muro informada
User Function ZZ_LIBNF(cTabPai, cChvRef)
    Local cCampChv := cTabPai + "_CHVNFE"
    Local cSql     := ""
    If cTabPai == "ZZE" ; cCampChv := "ZZE_CODRCB" ; EndIf

    cSql := "UPDATE " + RetSqlName(cTabPai) + " SET " + cTabPai + "_PRDPEN = 'N'"
    If (cTabPai)->(FieldPos(cTabPai + "_CLIPEN")) > 0
        cSql += ", " + cTabPai + "_CLIPEN = 'N'"
    EndIf
    If (cTabPai)->(FieldPos(cTabPai + "_FORPEN")) > 0
        cSql += ", " + cTabPai + "_FORPEN = 'N'"
    EndIf
    cSql += " WHERE " + cCampChv + " = '" + cChvRef + "' AND D_E_L_E_T_ = ' '"
    TCSqlExec(cSql)
Return


User Function PI_ERRO_RT(oErro)
    Local cMsg := ""

    If ValType(oErro) == "O"
        cMsg := "Excecao nao tratada"
        If !Empty(oErro:Description)
            cMsg += ": " + AllTrim(cValToChar(oErro:Description))
        EndIf
        If oErro:GenCode != Nil .And. oErro:GenCode != 0
            cMsg += " (GenCode " + cValToChar(oErro:GenCode) + IIF(oErro:OsCode != Nil .And. oErro:OsCode != 0, "/OsCode " + cValToChar(oErro:OsCode), "") + ")"
        EndIf
        If !Empty(oErro:Operation)
            cMsg += " | Operacao: " + AllTrim(cValToChar(oErro:Operation))
        EndIf
    Else
        cMsg := "Excecao nao tratada: " + cValToChar(oErro)
    EndIf
Return cMsg

// Atualiza status/mensagem de uma linha da tabela Muro (ERRMSG e memo, gravado via area nativa)
User Function UPDSTAT(cTab, cCod, cStatus, cMsg)
    Local cCampCod := cTab + "_COD"
    Local cCampSts := cTab + "_STATUS"
    Local cCampMsg := cTab + "_ERRMSG"
    Local cCampDtP := cTab + "_DTPROC"
    Local cCampHrP := cTab + "_HRPROC"
    Local cQry     := ""
    Local nRet     := 0
    Local cQryAux  := ""
    Local cAliAux  := ""
    Local nRecno   := 0

    cQry := "UPDATE " + RetSqlName(cTab) + " SET " + cCampSts + " = '" + cStatus + "'"
    If cStatus == "S" .And. cTab != "ZZF"
        cQry += ", " + cCampDtP + " = '" + DToS(Date()) + "'"
        cQry += ", " + cCampHrP + " = '" + Time() + "'"
    EndIf
    cQry += " WHERE " + cCampCod + " = '" + cCod + "' AND D_E_L_E_T_ = ' '"

    nRet := TCSqlExec(cQry)
    ConOut("[UPDSTAT] Tab: " + cTab + " | Cod: " + cCod + " | Status: " + cStatus + " | TCSqlExec retorno: " + cValToChar(nRet))

    If !Empty(cMsg)
        cQryAux := "SELECT R_E_C_N_O_ AS REC FROM " + RetSqlName(cTab) + " WHERE " + cCampCod + " = '" + cCod + "' AND D_E_L_E_T_ = ' '"
        cAliAux := GetNextAlias()
        MpSysOpenQuery(cQryAux, cAliAux)
        If (cAliAux)->(!Eof())
            nRecno := (cAliAux)->REC
            (cAliAux)->(DbCloseArea())
            DbSelectArea(cTab)
            (cTab)->(DbGoto(nRecno))
            If RecLock(cTab, .F.)
                (cTab)->(FieldPut(FieldPos(cCampMsg), Left(cMsg, 8000))) // _ERRMSG e Memo, cap so por bom senso
                (cTab)->(MsUnlock())
            EndIf
        Else
            (cAliAux)->(DbCloseArea())
        EndIf
    EndIf
Return

// Grava um produto pendente na fila ZZF
User Function ZZF_GRV(cChvRef, cTipoNF, cCodLeg, cJsonPayload, cIdIpaas)
    Local lOk  := .F.
    Local cCod := ""

    Default cIdIpaas := ""

    cCod := GetSxeNum("ZZF", "ZZF_COD")

    DbSelectArea("ZZF")
    If RecLock("ZZF", .T.)
        ZZF->ZZF_FILIAL := xFilial("ZZF")
        ZZF->ZZF_COD    := PadR(cCod, TamSx3("ZZF_COD")[1])
        ZZF->ZZF_STATUS := "P"
        ZZF->ZZF_CHVREF := PadR(cChvRef, TamSx3("ZZF_CHVREF")[1])
        ZZF->ZZF_TIPONF := PadR(cTipoNF, TamSx3("ZZF_TIPONF")[1])
        ZZF->ZZF_CODLEG := PadR(cCodLeg, TamSx3("ZZF_CODLEG")[1])
        ZZF->ZZF_JSON   := cJsonPayload
        ZZF->ZZF_DTINCL := Date()
        ZZF->ZZF_HRINCL := Time()
        If ZZF->(FieldPos("ZZF_IDIPS")) > 0
            ZZF->(FieldPut(ZZF->(FieldPos("ZZF_IDIPS")), PadR(cIdIpaas, TamSx3("ZZF_IDIPS")[1])))
        EndIf
        ZZF->(MsUnlock())
        ConfirmSx8()
        lOk := .T.
    Else
        RollBackSx8()
    EndIf
Return lOk

// Grava um registro generico numa tabela Muro (ZZ9/ZZA-ZZE)
User Function ZZX_Gravar(cTabMuro, cProc, cCampoChave, cChvRef, cJsonPayload, cCampoExtra, cValorExtra, cPrdPend, cQtProd, cIdIpaas)
    Local lOk  := .F.
    Local cCod := ""

    Default cCampoExtra := ""
    Default cValorExtra := ""
    Default cPrdPend    := "N"
    Default cQtProd     := ""
    Default cIdIpaas    := ""

    cCod := GetSxeNum(cTabMuro, cTabMuro + "_COD")

    DbSelectArea(cTabMuro)
    If RecLock(cTabMuro, .T.)
        (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_FILIAL"), xFilial(cTabMuro)))
        (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_COD"),    PadR(cCod, TamSx3(cTabMuro + "_COD")[1])))
        If FieldPos(cTabMuro + "_PROC") > 0
            (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_PROC"), PadR(cProc, TamSx3(cTabMuro + "_PROC")[1])))
        EndIf
        (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_STATUS"), "P"))
        (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_" + cCampoChave), PadR(cChvRef, TamSx3(cTabMuro + "_" + cCampoChave)[1])))
        (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_JSON"),   cJsonPayload))
        (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_DTINCL"), Date()))
        (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_HRINCL"), Time()))
        (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_PRDPEN"), cPrdPend))
        (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_ERRMSG"), ""))
        If FieldPos(cTabMuro + "_CLIPEN") > 0
            (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_CLIPEN"), "N"))
        EndIf
        If FieldPos(cTabMuro + "_FORPEN") > 0
            (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_FORPEN"), "N"))
        EndIf
        If FieldPos(cTabMuro + "_QTPROD") > 0
            (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_QTPROD"), Val(cQtProd)))
        EndIf
        If FieldPos(cTabMuro + "_IDIPS") > 0
            (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_IDIPS"), PadR(cIdIpaas, TamSx3(cTabMuro + "_IDIPS")[1])))
        EndIf
        If !Empty(cCampoExtra)
            (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_" + cCampoExtra), cValorExtra))
        EndIf
        (cTabMuro)->(MsUnlock())
        ConfirmSx8()
        lOk := .T.
    Else
        RollBackSx8()
    EndIf
Return lOk

// Valida existencia de CEST (F0G) ou NCM (SYD) no cadastro fiscal
User Function BUSCACAD(cCad, nOpc)
    Local lRet := .F.
    Local nTam := IIF(nOpc = 1, TamSx3("F0G_CEST")[1], TamSx3("YD_TEC")[1])

    cCad := PadR(AllTrim(cCad), nTam, '')

    If nOpc = 1
        DbSelectArea('F0G')
        F0G->(DbSetOrder(1))
        If F0G->(DbSeek(xFilial("F0G") + cCad))
            lRet := .T.
        EndIf
    ElseIf nOpc = 2
        DbSelectArea('SYD')
        SYD->(DbSetOrder(1))
        If SYD->(DbSeek(xFilial("SYD") + cCad))
            lRet := .T.
        EndIf
    EndIf
Return lRet

// Roteia o callback de processamento pro iPaaS conforme o dominio (Nota Fiscal vs Recibo)
User Function ZZCALLBK(cTab, cChave, cSubSeccao, lSucesso, cFilNota, cDocumento, cMsgErro, cMsgCustom)
    Local cUrl        := ""
    Local cCampoChave := ""
    Local cMsgPad     := ""
    Local lProducao   := Upper(AllTrim(GetEnvServer())) == Upper(AllTrim(SuperGetMv("MV_XCPPRD", .F., "CZA3BD_PROD")))

    Do Case
        Case cTab == "ZZE"
            cUrl        := "https://api-ipaas.totvs.app/ipaas/api/v1/integrations/2246e04c-65ec-4b83-b298-f8ec1643420c/api-key/67e28815-d2ff-4501-9f2f-e99271e6a3d7"
            cCampoChave := "num_PedidoReciboVenda"
            cMsgPad     := "Nota Varejo Processada"
        Otherwise
            // callback de producao so pra Notas Fiscais - Recibo (ZZE) segue na URL de homologacao ate ter o proprio endpoint de producao
            If lProducao
                cUrl := "https://api-ipaas.totvs.app/ipaas/api/v1/integrations/1119ae85-a6c6-4739-8eb8-6a60be3c8d15/api-key/77f0f449-8f94-45b8-b484-12e18996b758"
            Else
                cUrl := "https://api-ipaas.totvs.app/ipaas/api/v1/integrations/9aa6e2ae-1ece-4907-ba77-61c33d07bd79/api-key/6df64a64-4fc2-4b31-9c36-0958f06fcf33"
            EndIf
            cCampoChave := "cod_ChaveNFe"
            cMsgPad     := "Nota"
    EndCase

    CBackIpaas(cUrl, cCampoChave, cMsgPad, cTab, cChave, cSubSeccao, lSucesso, cFilNota, cDocumento, cMsgErro, cMsgCustom)
Return()

// Monta o payload e envia o callback HTTP de processamento pro iPaaS
Static Function CBackIpaas(cUrl, cCampoChave, cMsgPad, cTab, cChave, cSubSeccao, lSucesso, cFilNota, cDocumento, cMsgErro, cMsgCustom)
    Local aHeader  := {}
    Local cHeadRet := ""
    Local jPayload := JsonObject():New()

    Default cSubSeccao := ""
    Default lSucesso   := .F.
    Default cFilNota   := ""
    Default cDocumento := ""
    Default cMsgErro   := ""
    Default cMsgCustom := ""

    jPayload[cCampoChave]     := cChave
    jPayload['cod_Subseccao'] := Val(cSubSeccao)

    If !Empty(cMsgCustom)
        jPayload['des_Processamento'] := cMsgCustom
        jPayload['flg_Processamento'] := IIF(lSucesso, "S", "E")
    ElseIf lSucesso
        jPayload['des_Processamento'] := cMsgPad + ": " + AllTrim(cFilNota) + " - " + AllTrim(cDocumento)
        jPayload['flg_Processamento'] := "S"
    Else
        jPayload['des_Processamento'] := cMsgErro
        jPayload['flg_Processamento'] := "E"
    EndIf

    aAdd(aHeader, "Content-Type: application/json")
    HttpPost(cUrl, "", jPayload:toJSON(), 30, aHeader, @cHeadRet)

    If "200" $ cHeadRet .Or. "201" $ cHeadRet .Or. "204" $ cHeadRet
        ConOut("[ZZCALLBK] OK: " + cTab + " | " + cChave + " | " + jPayload['flg_Processamento'])
    Else
        ConOut("[ZZCALLBK] AVISO HTTP - Header resposta: " + cHeadRet + " | " + cChave)
    EndIf

    FreeObj(jPayload)
Return
