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
| Descritivo: FATZZA01 - Job Schedule - Fila ZZA (NFe Saida)                |
|             Processa: cOper = S (Saida)                                    |
|             Motor: PI_SAIDA_X (MaNfs2Nfs)                                   |
| [REV2] Jose Carlos - Artiq - 07/2026                                       |
|   Devolucao (cOper=D) foi extraida para o Job FATZZB01 (fila ZZB), que     |
|   antes era processada aqui junto com a Saida. Este Job agora so trata    |
|   NFS (Saida). O branch NFD e a funcao ZZA_MotorDevolucao foram removidos.|
+----------------------------------------------------------------------------+
*/

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

    Private __cBatch := "1"

    ConOut("[FATZZA01] Iniciando NFe Saida - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    // [FIX-MEMO] Nao seleciona ZZA_JSON aqui � le via R_E_C_N_O_ + DbGoto
    // na area nativa, mais abaixo (mesmo fix aplicado no FATZZF01).
    cQry := "SELECT ZZA_COD, ZZA_CHVNFE, ZZA_PROC, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZA") + " "
    cQry += "WHERE ZZA_STATUS IN ('P','A') AND ZZA_PRDPEN = 'N' "
    cQry += "AND ZZA_FILIAL = '" + xFilial("ZZA") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZA_DTINCL, ZZA_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZA, .T., .T.)

    While (cAliZZA)->(!Eof())
        cCod    := AllTrim((cAliZZA)->ZZA_COD)
        cChvNFe := AllTrim((cAliZZA)->ZZA_CHVNFE)
        cProc   := AllTrim((cAliZZA)->ZZA_PROC)
        nRecno  := (cAliZZA)->RECNO
        cErrMsg := ""
        cSub    := ""
        cFilCb  := ""
        cDocCb  := ""
        cMsgSuc := ""
        lOk     := .F.

        // Reposiciona na area nativa ZZA so pra ler o memo certo
        DbSelectArea("ZZA")
        ZZA->(DbGoto(nRecno))
        cJson := ZZA->ZZA_JSON

        U_UPDSTAT("ZZA", cCod, "A", "")
        ConOut("[FATZZA01] Processando: " + cCod + " | Proc: " + cProc + " | Chave: " + cChvNFe)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            If cProc == "NFS"
                aRet := ZZA_MotorSaida(jJson)
            Else
                aRet := {.F., "Tipo de processo inesperado na ZZA (apenas NFS e aceito): " + cProc, ""}
            EndIf
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

        (cAliZZA)->(DbSkip())
    EndDo
    (cAliZZA)->(DbCloseArea())

    ConOut("[FATZZA01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

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

    // [MOVIDO-ZZ901] Jose Carlos - Artiq - 08/2026
    // Numeracao migrou do classificador (FATZZ901.prw) pra ca - so aqui o
    // ambiente ja esta trocado pra filial real da nota (ver
    // instrucao_mover_numeracao_para_jobs.md). Preserva o desvio original:
    // se a nota ja veio com numero (num_NF/num_NotaFiscal/cod_ReciboVenda),
    // usa ele em vez de gerar (GetSxeNum) - mesmo comportamento de antes.
    nValNF := U_PI_VAL_X(oHead, 'num_NF', 'num_NotaFiscal')
    If nValNF == 0 ; nValNF := U_PI_VAL_X(oHead, 'cod_ReciboVenda') ; EndIf
    cNumInf := IIF(nValNF == 0, "", cValToChar(nValNF))

    aNum := U_PI_NUMERA_X("SF2", "F2_DOC", AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNumInf)
    If !aNum[1] ; Return {.F., "NUMERACAO: " + cValToChar(aNum[2]), cSub} ; EndIf
    If aNum[3] ; Return {.T., "Ja processada anteriormente: " + cValToChar(aNum[2]), cSub, xFilial("SF2"), cValToChar(aNum[2])} ; EndIf
    cNF := cValToChar(aNum[2])

    U_PI_SETFCA(AllTrim(U_PI_STR_X(oHead, '_TAB')), AllTrim(U_PI_STR_X(oHead, '_COD')), AllTrim(U_PI_STR_X(oHead, '_LOJA')), AllTrim(U_PI_STR_X(oHead, '_COND')), oHead)

    // [MOVIDO-ZZ901] cLeg/cLegT (5o/12o parametros) - confirmado via grep
    // que U_PI_SAIDA_X nunca le esses parametros no corpo da funcao (mortos
    // ha tempos). Passa cNF mesmo assim, so pra preservar o valor que
    // sempre foi (cLeg == cNF, ver ZZ901_Classifica antigo).
    aRet := U_PI_SAIDA_X(aPrd, oHead, AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')), cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_FIL')), AllTrim(U_PI_STR_X(oHead,'_TAB')), U_PI_STR_X(oHead,'_TRANSF')=="S", cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), cNF, AllTrim(U_PI_STR_X(oHead,'_COND')))

    If aRet[1]
        // [MIGRADO-DO-ENDPOINT] Jose Carlos - Artiq - 08/2026
        // CONVENIOS - transferencia entre filiais com rollback automatico.
        // Antes rodava no FATPI01_V2 logo apos o motor.
        lIsTransf := U_PI_STR_X(oHead,'_TRANSF') == "S"
        cCnpjEmit := AllTrim(U_PI_STR_X(oHead,'_CNPJEMIT'))
        cCnpjDest := AllTrim(U_PI_STR_X(oHead,'_CNPJDEST'))

        If lIsTransf .And. cCnpjEmit != cCnpjDest
            aEmpDest := U_PI_FILIAL_X(cCnpjDest)
            If Len(aEmpDest) >= 2
                aRetTransf := U_FATPI01NF(aPrd, oHead, cCnpjEmit, cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), aEmpDest)
                If !aRetTransf[1]
                    U_PI_ROLLBACK_NF(cNF, AllTrim(U_PI_STR_X(oHead,'_SER')), AllTrim(U_PI_STR_X(oHead,'_COD')), AllTrim(U_PI_STR_X(oHead,'_LOJA')))
                    // [FIX-CALLBACK-ERRO] Jose Carlos - Artiq - 08/2026
                    // cSub adicionado - faltava aqui (unico Return {.F.,...}
                    // desta funcao sem o 3o elemento), fazia o callback de
                    // erro sair com cod_Subseccao=0 mesmo com o valor ja
                    // disponivel na variavel local.
                    Return {.F., "ROLLBACK_CONVENIOS: " + cValToChar(aRetTransf[2]) + " | Saida (SF2) na origem foi ESTORNADA.", cSub}
                EndIf
            EndIf
        EndIf

        Return {.T., "NFS: " + xFilial("SF2") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF2"), cValToChar(aRet[2])}
    EndIf
Return {.F., IIF(aRet[3],"NFORIGEM","MANFS2NFS") + ": " + cValToChar(aRet[2]), cSub}
