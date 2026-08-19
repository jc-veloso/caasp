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
| Descritivo: FATZZB01 - Job Schedule - Fila ZZB (NFe Devolucao)            |
|             Processa: cOper = D (Devolucao de Venda)                       |
|             Motor: PI_DEVOL_X (MATA103 tipo D)                             |
| [REV2] Jose Carlos - Artiq - 07/2026                                       |
|   Job novo. Extraido do FATZZA01 (antes Saida e Devolucao processavam      |
|   juntos na fila ZZA). Devolucao agora tem fila propria (ZZB).            |
+----------------------------------------------------------------------------+
*/

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

    Private __cBatch := "1"

    ConOut("[FATZZB01] Iniciando NFe Devolucao - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    // [FIX-MEMO] Nao seleciona ZZB_JSON aqui � le via R_E_C_N_O_ + DbGoto
    // na area nativa, mais abaixo (mesmo fix aplicado no FATZZF01).
    cQry := "SELECT ZZB_COD, ZZB_CHVNFE, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZB") + " "
    cQry += "WHERE ZZB_STATUS IN ('P','A') AND ZZB_PRDPEN = 'N' "
    cQry += "AND ZZB_FILIAL = '" + xFilial("ZZB") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZB_DTINCL, ZZB_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZB, .T., .T.)

    While (cAliZZB)->(!Eof())
        cCod    := AllTrim((cAliZZB)->ZZB_COD)
        cChvNFe := AllTrim((cAliZZB)->ZZB_CHVNFE)
        nRecno  := (cAliZZB)->RECNO
        cErrMsg := ""
        cSub    := ""
        cFilCb  := ""
        cDocCb  := ""
        cMsgSuc := ""
        lOk     := .F.

        // Reposiciona na area nativa ZZB so pra ler o memo certo
        DbSelectArea("ZZB")
        ZZB->(DbGoto(nRecno))
        cJson := ZZB->ZZB_JSON

        U_UPDSTAT("ZZB", cCod, "A", "")
        ConOut("[FATZZB01] Processando: " + cCod + " | Chave: " + cChvNFe)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            aRet := ZZB_MotorDevolucao(jJson)
            lOk  := aRet[1]
            cSub := IIF(Len(aRet) >= 3, cValToChar(aRet[3]), "")
            If lOk
                cFilCb := IIF(Len(aRet) >= 5, cValToChar(aRet[4]), "")
                cDocCb := IIF(Len(aRet) >= 5, cValToChar(aRet[5]), "")
                // [FIX-MSG-DUPLICIDADE] Jose Carlos - Artiq - 08/2026
                // aRet[2] (mensagem descritiva do motor - inclui "Ja
                // processada anteriormente: ..." no caso de duplicidade,
                // pedido do Arthur) antes se perdia aqui, nunca chegava no
                // callback. Repassado como cMsgCustom (8o parametro).
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

        (cAliZZB)->(DbSkip())
    EndDo
    (cAliZZB)->(DbCloseArea())

    ConOut("[FATZZB01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

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

    // [MOVIDO-ZZ901] Jose Carlos - Artiq - 08/2026
    // Numeracao migrou do classificador pra ca - ver
    // instrucao_mover_numeracao_para_jobs.md. Devolucao usa SF1/F1_DOC.
    // Preserva o desvio de numero pre-informado (num_NF/num_NotaFiscal/
    // cod_ReciboVenda), mesmo comportamento de antes.
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
        // [REV2-FIX] JSON_COMPRA agora e User Function (promovida em FATPI01E.prw),
        // por isso pode ser chamada aqui sem redeclaracao local.
        U_JSON_COMPRA(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')))
        Return {.T., "NFD: " + xFilial("SF1") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF1"), cValToChar(aRet[2])}
    EndIf
Return {.F., IIF(aRet[3],"NFORIGEM","MATA103_DEV") + ": " + cValToChar(aRet[2]), cSub}
