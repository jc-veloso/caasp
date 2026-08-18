#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

// [BOOTSTRAP] Empresa/filial padrao para o RpcSetEnv inicial do Job.
// Nao da pra usar SuperGetMv aqui � SX6/cEmpAnt ainda nao existem antes
// do primeiro RpcSetEnv (erro 'variable does not exist CFILANT'). Hardcode
// e o padrao correto nesse bootstrap; isolado em #Define para ficar facil
// de achar/trocar se o ambiente mudar.
Static CEMPPAD := "01"
Static CFILPAD := "01001"

/*
+----------------------------------------------------------------------------+
| Autor: Jose Carlos - Artiq                                                 |
| Data: 07/2026                                                              |
| Descritivo: FATZZE01 - Job Schedule - Fila ZZE (Recibo de Venda)         |
|             Motor: FATPI08NF do FATPI08 (SEM FISCAL)                      |
| [REV2] Jose Carlos - Artiq - 07/2026                                       |
|   Era FATZZD01 (fila ZZD). Deslizou uma letra: Devolucao->ZZB, Entrada->  |
|   ZZC, NFCe->ZZD, Recibo->ZZE. Campo-chave continua ZZE_CODRCB (ja usava  |
|   CODRCB antes, so trocou o prefixo de ZZD_ para ZZE_).                   |
+----------------------------------------------------------------------------+
*/

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

    Private __cBatch := "1" ; Private __cXEvento := "LOJ"

    ConOut("[FATZZE01] Iniciando Recibo de Venda - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "LOJ")

    // [FIX-MEMO] Nao seleciona ZZE_JSON aqui � le via R_E_C_N_O_ + DbGoto
    // na area nativa, mais abaixo (mesmo fix aplicado no FATZZF01).
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

        // Reposiciona na area nativa ZZE so pra ler o memo certo
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

        // [REV-ZZCALLBK-UNIFICADO] Jose Carlos - Artiq - 08/2026
        // U_ZZCALLBK agora usa a mesma assinatura das Notas Fiscais (ver
        // FATZZF01.prw). U_FATPI08NF (via ZZE_MotorRecibo) ja devolve a
        // mensagem de sucesso pronta no formato "Nota Varejo Processada:
        // [filial] - [documento]" - passada como cMsgCustom (8o param) em
        // vez de cFilNota/cDocumento separados.
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
    RpcClearEnv()
Return

Static Function ZZE_MotorRecibo(jJson)
    Local oData  := Nil
    Local aEmp   := {}
    Local jRes   := Nil
    Local aRet   := {.F., ""}
    // [REV-ZZCALLBK-UNIFICADO] Jose Carlos - Artiq - 08/2026
    // cod_Subseccao extraido aqui (igual ZZA_MotorSaida/ZZD_MotorNFCe ja
    // fazem) pra alimentar o callback unificado (ver U_ZZCALLBK) - antes
    // nao era usado, o mecanismo antigo do Recibo nao mandava esse campo.
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
