#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

Static CEMPPAD := "01"
Static CFILPAD := "01001"

// Job agendado - fila ZZE: processa Recibo de Venda via U_FATPI08NF (Hub de Vendas SIGALOJA)

// Le a fila ZZE e processa cada recibo de venda
User Function FATZZE01()
    Local cAliZZE  := GetNextAlias()
    Local cQry     := ""
    Local cCod     := ""
    Local cJson    := ""
    Local cCodRcb  := ""
    Local cErrMsg  := ""
    Local cSub     := ""
    Local nRecno   := 0
    Local lOk      := .F.
    Local nOk      := 0
    Local nErr     := 0
    Local jJson    := Nil
    Local aRet     := {}
    Local cEmpOri  := cEmpAnt
    Local cFilOri  := cFilAnt

    Private __cBatch := "1" ; Private __cXEvento := "LOJ"
    Private lJob      := GetRemoteType() == -1

    ConOut("[FATZZE01] Iniciando Recibo de Venda - " + DToS(Date()) + " " + Time())

    If lJob
        RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "LOJ")
    EndIf

    cQry := "SELECT ZZE_COD, ZZE_CODRCB, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZE") + " "
    cQry += "WHERE ZZE_STATUS IN ('P','A') AND ZZE_PRDPEN = 'N' "
    cQry += "AND ZZE_FILIAL = '" + xFilial("ZZE") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZE_DTINCL, ZZE_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZE, .T., .T.)

    While (cAliZZE)->(!Eof())
        cCod    := AllTrim((cAliZZE)->ZZE_COD)
        cCodRcb := AllTrim((cAliZZE)->ZZE_CODRCB)
        nRecno  := (cAliZZE)->RECNO
        cErrMsg := ""
        lOk     := .F.

        DbSelectArea("ZZE")
        ZZE->(DbGoto(nRecno))
        cJson := ZZE->ZZE_JSON

        U_UPDSTAT("ZZE", cCod, "A", "")
        ConOut("[FATZZE01] Processando: " + cCod + " | Recibo: " + cCodRcb)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            aRet := ZZE_MotorRecibo(jJson)
            lOk  := aRet[1]
            cSub := IIF(Len(aRet) >= 3, cValToChar(aRet[3]), "")
            If !lOk ; cErrMsg := cValToChar(aRet[2]) ; EndIf
        Else
            cErrMsg := "JSON invalido na fila ZZE. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZE", cCod, "S", "")
            U_ZZCALLBK("ZZE", cCodRcb, cSub, .T., "", "", "", cValToChar(aRet[2]))
            nOk++
            ConOut("[FATZZE01] OK: " + cCod)
        Else
            U_UPDSTAT("ZZE", cCod, "E", cErrMsg)
            U_ZZCALLBK("ZZE", cCodRcb, cSub, .F., "", "", cErrMsg)
            nErr++
            ConOut("[FATZZE01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf

        (cAliZZE)->(DbSkip())
    EndDo
    (cAliZZE)->(DbCloseArea())

    ConOut("[FATZZE01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    If lJob
        RpcClearEnv()
    ElseIf cEmpAnt != cEmpOri .Or. cFilAnt != cFilOri
        // Restaura a filial original da sessao interativa, caso algum recibo tenha trocado de filial
        RpcClearEnv()
        RpcSetEnv(cEmpOri, cFilOri, Nil, Nil, "LOJ")
    EndIf
Return

// Resolve filial e dispara U_FATPI08NF (motor de recibo de venda, sem recalculo fiscal)
Static Function ZZE_MotorRecibo(jJson)
    Local oData  := Nil
    Local aEmp   := {}
    Local jRes   := Nil
    Local aRet   := {.F., ""}
    Local cSub   := ""

    If ValType(jJson['notas']) == "A" .And. Len(jJson['notas']) > 0
        oData := jJson['notas'][1]
    Else
        oData := jJson
    EndIf

    cSub := cValToChar(U_PI_VAL_X(oData, 'cod_Subseccao'))

    aEmp := U_PI_FILIAL_X(U_PI_LIMPA_X(U_PI_STR_X(oData, "num_SubseccaoCNPJ")))
    If Len(aEmp) < 2 ; Return {.F., "Filial nao encontrada (ZZE/RCV)", cSub} ; EndIf
    If aEmp[1] != cEmpAnt .Or. aEmp[2] != cFilAnt ; RpcClearEnv() ; RpcSetEnv(aEmp[1], aEmp[2], Nil, Nil, "LOJ") ; EndIf

    jRes := U_FATPI08NF(oData, aEmp[2])

    If jRes:HasProperty('resultado') .And. AllTrim(jRes['resultado']) == "Sucesso"
        aRet := {.T., AllTrim(jRes['mensagem']), cSub}
    Else
        aRet := {.F., IIF(jRes:HasProperty('mensagem'), AllTrim(jRes['mensagem']), "Erro FATPI08NF"), cSub}
    EndIf
    FreeObj(jRes)
Return aRet
