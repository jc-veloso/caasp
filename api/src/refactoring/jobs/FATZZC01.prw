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
    Local cMsgSuc  := ""
    Local nRecno   := 0
    Local lOk      := .F.
    Local nOk      := 0
    Local nErr     := 0
    Local jJson    := Nil
    Local aRet     := {}
    Local aFila    := {}
    Local nJ       := 0

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

    // [FIX-ALIAS-EVICTION] Jose Carlos - Artiq - 08/2026
    // Mesmo bug ja corrigido em FATZZD01.prw/FATZZA01.prw/FATZZB01.prw:
    // cAliZZC (cursor TOPCONN) ficava aberto durante o loop inteiro,
    // inclusive durante a chamada a ZZC_MotorEntrada -> U_PI_GERAPC_X
    // (MATA120) + U_PI_GERANF_X (MATA103) - motores nativos mexem pesado
    // em work areas e podem evictar/reciclar o slot do cursor mais antigo
    // ainda aberto. Corrigido materializando a fila inteira numa array
    // ANTES de processar qualquer nota.
    While (cAliZZC)->(!Eof())
        aAdd(aFila, {AllTrim((cAliZZC)->ZZC_COD), AllTrim((cAliZZC)->ZZC_CHVNFE), (cAliZZC)->RECNO})
        (cAliZZC)->(DbSkip())
    EndDo
    (cAliZZC)->(DbCloseArea())

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
            cErrMsg := "JSON invalido na fila ZZC. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZC", cCod, "S", "")
            U_ZZCALLBK("ZZC", cChvNFe, cSub, .T., cFilCb, cDocCb, "", cMsgSuc)
            nOk++
            ConOut("[FATZZC01] OK: " + cCod)
        Else
            U_UPDSTAT("ZZC", cCod, "E", cErrMsg)
            U_ZZCALLBK("ZZC", cChvNFe, cSub, .F., "", "", cErrMsg)
            nErr++
            ConOut("[FATZZC01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf
    Next nJ

    ConOut("[FATZZC01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

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

    Private lMsErroAuto := .F. ; Private lAutoErrNoFile := .T.

    If ValType(aInv) != "A" .Or. Len(aInv) == 0 ; Return {.F., "Array notas ausente (ZZC/NFE)", ""} ; EndIf
    oHead := aInv[1] ; aPrd := oHead['itens']
    cSub  := cValToChar(U_PI_VAL_X(oHead, 'cod_Subseccao'))

    aEmp := U_PI_FILIAL_X(U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ')))
    If Len(aEmp) < 2 ; Return {.F., "Filial nao encontrada (ZZC/NFE)", cSub} ; EndIf
    If aEmp[1] != cEmpAnt .Or. aEmp[2] != cFilAnt ; RpcClearEnv() ; RpcSetEnv(aEmp[1], aEmp[2], Nil, Nil, "FAT") ; EndIf

    // [MOVIDO-ZZ901] Jose Carlos - Artiq - 08/2026
    // Numeracao migrou do classificador pra ca - ANTES do U_PI_GERAPC_X
    // (MATA120), nao so antes do U_PI_GERANF_X (MATA103). O doc original
    // (instrucao_mover_numeracao_para_jobs.md) deixava em aberto qual dos
    // dois pontos era o certo, ja que o cLeg passado pro GERAPC e so
    // referencia informativa (C7_OBS/C7_LEGADO - confirmado no corpo de
    // U_PI_GERAPC_X, nao afeta numeracao fiscal). Mas se a numeracao (e a
    // checagem de duplicidade dentro dela) so rodasse depois do GERAPC, uma
    // nota duplicada em retry criaria um pedido de compra (SC7) novo antes
    // de ser barrada - regressao em relacao ao comportamento original, onde
    // a duplicidade era checada em ZZ901_Classifica antes de QUALQUER
    // chamada de motor. Numerando aqui, cLeg tambem fica igual ao numero
    // real (mesmo comportamento de antes). Entrada usa SF1/F1_DOC; preserva
    // o desvio de numero pre-informado (a nota do fornecedor normalmente ja
    // vem com numero real na compra).
    nValNF := U_PI_VAL_X(oHead, 'num_NF', 'num_NotaFiscal')
    If nValNF == 0 ; nValNF := U_PI_VAL_X(oHead, 'cod_ReciboVenda') ; EndIf
    cNumInf := IIF(nValNF == 0, "", cValToChar(nValNF))

    aNum := U_PI_NUMERA_X("SF1", "F1_DOC", AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNumInf)
    If !aNum[1] ; Return {.F., "NUMERACAO: " + cValToChar(aNum[2]), cSub} ; EndIf
    If aNum[3] ; Return {.T., "Ja processada anteriormente: " + cValToChar(aNum[2]), cSub, xFilial("SF1"), cValToChar(aNum[2])} ; EndIf
    cNF := cValToChar(aNum[2])

    U_PI_SETFCA(AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), AllTrim(U_PI_STR_X(oHead,'_COND')), oHead)

    aRet := U_PI_GERAPC_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNF, aEmp, AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_FIL')), "", AllTrim(U_PI_STR_X(oHead,'_COND')))

    If !aRet[1] ; Return {.F., "MATA120: " + cValToChar(aRet[2]), cSub} ; EndIf

    cPCNew := aRet[3]
    aRet   := U_PI_GERANF_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), cPCNew, AllTrim(U_PI_STR_X(oHead,'_TAB')), AllTrim(U_PI_STR_X(oHead,'_FIL')), 0, AllTrim(U_PI_STR_X(oHead,'_COND')))

    If aRet[1]
        // [REV2-FIX] JSON_COMPRA/PI_GER_E2 agora sao User Function (FATPI01E.prw)
        U_JSON_COMPRA(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')))
        U_PI_GER_E2(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_TAB')), SE2->(RECNO()))
        Return {.T., "NFE: " + xFilial("SF1") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF1"), cValToChar(aRet[2])}
    EndIf
Return {.F., "MATA103: " + cValToChar(aRet[2]), cSub}
