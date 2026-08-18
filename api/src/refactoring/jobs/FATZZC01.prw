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
| Descritivo: FATZZC01 - Job Schedule - Fila ZZC (NFe Entrada)              |
|             Processa: cOper = E (Entrada / Compras)                       |
|             Motor: PI_GERAPC_X (MATA120) + PI_GERANF_X (MATA103)             |
| [REV2] Jose Carlos - Artiq - 07/2026                                       |
|   Era FATZZB01 (fila ZZB). Deslizou uma letra porque NFe Devolucao ganhou |
|   fila propria (ZZB). Sem mudanca de logica, so de tabela/nome.           |
|   Chamadas de JSON_COMPRA/PI_GER_E2 corrigidas para U_ (promovidas para   |
|   User Function em FATPI01E.prw).                                         |
+----------------------------------------------------------------------------+
*/

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
    Local nRecno   := 0
    Local lOk      := .F.
    Local nOk      := 0
    Local nErr     := 0
    Local jJson    := Nil
    Local aRet     := {}

    Private __cBatch := "1"

    ConOut("[FATZZC01] Iniciando NFe Entrada - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    // [FIX-MEMO] Nao seleciona ZZC_JSON aqui � le via R_E_C_N_O_ + DbGoto
    // na area nativa, mais abaixo (mesmo fix aplicado no FATZZF01).
    cQry := "SELECT ZZC_COD, ZZC_CHVNFE, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZC") + " "
    cQry += "WHERE ZZC_STATUS IN ('P','A') AND ZZC_PRDPEN = 'N' "
    cQry += "AND ZZC_FILIAL = '" + xFilial("ZZC") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZC_DTINCL, ZZC_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZC, .T., .T.)

    While (cAliZZC)->(!Eof())
        cCod    := AllTrim((cAliZZC)->ZZC_COD)
        cChvNFe := AllTrim((cAliZZC)->ZZC_CHVNFE)
        nRecno  := (cAliZZC)->RECNO
        cErrMsg := ""
        cSub    := ""
        cFilCb  := ""
        cDocCb  := ""
        lOk     := .F.

        // Reposiciona na area nativa ZZC so pra ler o memo certo
        DbSelectArea("ZZC")
        ZZC->(DbGoto(nRecno))
        cJson := ZZC->ZZC_JSON

        U_UPDSTAT("ZZC", cCod, "A", "")
        ConOut("[FATZZC01] Processando: " + cCod + " | Chave: " + cChvNFe)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            aRet := ZZC_MotorEntrada(jJson)
            lOk  := aRet[1]
            cSub := IIF(Len(aRet) >= 3, cValToChar(aRet[3]), "")
            If lOk
                cFilCb := IIF(Len(aRet) >= 5, cValToChar(aRet[4]), "")
                cDocCb := IIF(Len(aRet) >= 5, cValToChar(aRet[5]), "")
            Else
                cErrMsg := cValToChar(aRet[2])
            EndIf
        Else
            cErrMsg := "JSON invalido na fila ZZC. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZC", cCod, "S", "")
            U_ZZCALLBK("ZZC", cChvNFe, cSub, .T., cFilCb, cDocCb, "")
            nOk++
            ConOut("[FATZZC01] OK: " + cCod)
        Else
            U_UPDSTAT("ZZC", cCod, "E", cErrMsg)
            U_ZZCALLBK("ZZC", cChvNFe, cSub, .F., "", "", cErrMsg)
            nErr++
            ConOut("[FATZZC01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf

        (cAliZZC)->(DbSkip())
    EndDo
    (cAliZZC)->(DbCloseArea())

    ConOut("[FATZZC01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

Static Function ZZC_MotorEntrada(jJson)
    Local aInv   := jJson['notas']
    Local oHead  := Nil
    Local aPrd   := {}
    Local aEmp   := {}
    Local aRet   := {.F., ""}
    Local cPCNew := ""
    Local cSub   := ""

    Private lMsErroAuto := .F. ; Private lAutoErrNoFile := .T.

    If ValType(aInv) != "A" .Or. Len(aInv) == 0 ; Return {.F., "Array notas ausente (ZZC/NFE)", ""} ; EndIf
    oHead := aInv[1] ; aPrd := oHead['itens']
    cSub  := cValToChar(U_PI_VAL_X(oHead, 'cod_Subseccao'))

    aEmp := U_PI_FILIAL_X(U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ')))
    If Len(aEmp) < 2 ; Return {.F., "Filial nao encontrada (ZZC/NFE)", cSub} ; EndIf
    If aEmp[1] != cEmpAnt .Or. aEmp[2] != cFilAnt ; RpcClearEnv() ; RpcSetEnv(aEmp[1], aEmp[2], Nil, Nil, "FAT") ; EndIf

    U_PI_SETFCA(AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), AllTrim(U_PI_STR_X(oHead,'_COND')), oHead)

    aRet := U_PI_GERAPC_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), AllTrim(U_PI_STR_X(oHead,'_LEG')), aEmp, AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_FIL')), "", AllTrim(U_PI_STR_X(oHead,'_COND')))

    If !aRet[1] ; Return {.F., "MATA120: " + cValToChar(aRet[2]), cSub} ; EndIf

    cPCNew := aRet[3]
    aRet   := U_PI_GERANF_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), AllTrim(U_PI_STR_X(oHead,'_NF')), AllTrim(U_PI_STR_X(oHead,'_SER')), cPCNew, AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_FIL')), 0, AllTrim(U_PI_STR_X(oHead,'_COND')))

    If aRet[1]
        // [REV2-FIX] JSON_COMPRA/PI_GER_E2 agora sao User Function (FATPI01E.prw)
        U_JSON_COMPRA(AllTrim(U_PI_STR_X(oHead,'_NF')), AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')))
        U_PI_GER_E2(AllTrim(U_PI_STR_X(oHead,'_NF')), AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')), SE2->(RECNO()))
        Return {.T., "NFE: " + xFilial("SF1") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF1"), cValToChar(aRet[2])}
    EndIf
Return {.F., "MATA103: " + cValToChar(aRet[2]), cSub}
