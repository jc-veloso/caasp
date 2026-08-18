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
| Descritivo: FATZZD01 - Job Schedule - Fila ZZD (NFCe modelo 65)          |
|             Motor: U_PI_SAIDA_X (Faturamento/MaNfs2Nfs � grava SF2/SD2,  |
|             mesmo motor que FATZZA01 ja usa pra NFe Saida comum,         |
|             definida em FATPI01S.prw. FATZZD01 depende do FATPI01S       |
|             estar compilado/disponivel no RPO.)                          |
| [REV2] Jose Carlos - Artiq - 07/2026                                       |
|   Era FATZZC01 (fila ZZC). Deslizou uma letra porque NFe Devolucao ganhou |
|   fila propria (ZZB), empurrando Entrada->ZZC e NFCe->ZZD.               |
| [FIX-MOTOR] Jose Carlos - Artiq - 07/2026                                 |
|   O motor estava chamando U_FATPI08NF (SEM FISCAL, do FATPI08) � errado,  |
|   isso e o motor do Recibo. NFCe usa LOJA701 (U_PI_LOJA_X). Corrigido. |
| [MOTOR-FATURAMENTO] Jose Carlos - Artiq - 08/2026 - DECISAO REVISTA       |
|   O [FIX-MOTOR] acima mantinha LOJA701 (SL1/SIGALOJA) por decisao        |
|   consciente, citando risco de recalculo fiscal indevido (NFCe ja        |
|   autorizada pela SEFAZ com valores do PDV). Analise do legado           |
|   (FATPI01__2_.prw, monolito pre-refatoracao que tratava NFe e NFCe      |
|   juntos) mostrou que o padrao correto e NFCe morar no Faturamento       |
|   (SF2/SD2), igual NFe, so marcada com F2_ESPECIE/F3_ESPECIE := "NFCE" - |
|   nao em SL1/SIGALOJA. Motor trocado de U_PI_LOJA_X pra U_PI_SAIDA_X     |
|   (o mesmo que FATZZA01 ja usa). O risco de recalculo fiscal continua    |
|   existindo (aceito conscientemente, mesmo trade-off que ja existe pra   |
|   NFe) - nao foi resolvido pela troca, passou a ser compartilhado com o  |
|   mesmo motor que a NFe ja usa em producao. Ganhou numeracao/duplicidade |
|   propria (F2_DOC via GetSxeNum) e validacao de serie (SX5), que nao     |
|   eram necessarias com LOJA701 (gerava o proprio L1_NUM sozinho).        |
| [REV2-SYNC-FIX] Jose Carlos - Artiq - 07/2026                             |
|   Resolucao de cliente, numeracao e CFOP/TES foram movidas do FATPI09     |
|   (endpoint) pra ca � o endpoint agora so valida/classifica/enfileira,    |
|   sem depender de U_FATCFOP01 no caminho sincrono. Mesmo motivo do        |
|   ajuste ja feito no FATPI01_V2 pra NFe: quem processa e o Job, nao o     |
|   endpoint.                                                               |
| [FIX-DUPLICIDADE] Jose Carlos - Artiq - 07/2026                          |
|   Eu tinha reimplementado U_PI_LOJA_X aqui do zero (com base na doc   |
|   generica da TOTVS), sem saber que ja existia uma versao completa e     |
|   correta em FATPI01S.prw (SL1/L1_*, nao SLQ/LQ_* � tabela diferente da  |
|   doc generica). Gerava duplicidade de User Function no RPO. Removida a  |
|   minha versao daqui; a chamada agora usa a original (7 parametros, sem  |
|   cNF � ela gera o proprio numero via GetSxeNum("SL1","L1_NUM")).        |
| [FIX-10CHAR] Jose Carlos - Artiq - 07/2026                               |
|   U_FZ_PROS_LOJA colidia com U_PI_SAIDA_X (AdvPL so considera os          |
|   primeiros 10 chars do nome, incluindo o U_, na resolucao de simbolo).  |
|   Renomeada para PI_LOJA_X em FATPI01S.prw. Chamada aqui atualizada.     |
+----------------------------------------------------------------------------+
*/

User Function FATZZD01()
    Local cAliZZD  := GetNextAlias()
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
    Local aFila    := {}
    Local nJ       := 0
    // [TIMING] Jose Carlos - Artiq - 08/2026 - instrumentacao temporaria
    // pra medir onde o tempo de processamento vai (~8s/nota observados em
    // teste real) - tirar depois de ter os numeros, nao e pra ficar no
    // codigo definitivo.
    Local nTIni    := 0

    Private __cBatch := "1"

    ConOut("[FATZZD01] Iniciando NFCe - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    // [FIX-MEMO] Nao seleciona ZZD_JSON aqui � campo memo/CLOB nao atravessa
    // resultset TOPCONN de forma confiavel. Le via R_E_C_N_O_ + DbGoto na
    // area nativa, mais abaixo (mesmo fix aplicado no FATZZF01).
    cQry := "SELECT ZZD_COD, ZZD_CHVNFE, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZD") + " "
    cQry += "WHERE ZZD_STATUS IN ('P','A') AND ZZD_PRDPEN = 'N' "
    cQry += "AND ZZD_FILIAL = '" + xFilial("ZZD") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZD_DTINCL, ZZD_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZD, .T., .T.)

    // [FIX-ALIAS-EVICTION] Jose Carlos - Artiq - 08/2026
    // Erro reproduzido em teste real: "Alias does not exist <alias>" no
    // (cAliZZD)->(DbSkip()) logo apos processar a 1a nota. Causa: cAliZZD
    // (cursor TOPCONN via GetNextAlias) ficava aberto durante o loop
    // inteiro, inclusive durante a chamada a ZZD_MotorNFCe -> U_PI_SAIDA_X
    // -> MaNfs2Nfs (FATPI01S.prw) - o motor nativo de faturamento mexe
    // pesado em work areas internamente (SE1/SE5/SD1/SFT/SF3, motor de
    // impostos etc.) e pode evictar/reciclar o slot do cursor mais antigo
    // ainda aberto. Corrigido materializando a fila inteira numa array
    // ANTES de processar qualquer nota - o cursor TOPCONN fecha logo
    // depois de ler a fila, entao nao sobrevive a nenhuma chamada ao motor.
    While (cAliZZD)->(!Eof())
        aAdd(aFila, {AllTrim((cAliZZD)->ZZD_COD), AllTrim((cAliZZD)->ZZD_CHVNFE), (cAliZZD)->RECNO})
        (cAliZZD)->(DbSkip())
    EndDo
    (cAliZZD)->(DbCloseArea())

    For nJ := 1 To Len(aFila)
        cCod    := aFila[nJ][1]
        cChvNFe := aFila[nJ][2]
        nRecno  := aFila[nJ][3]
        cErrMsg := ""
        cSub    := ""
        cFilCb  := ""
        cDocCb  := ""
        lOk     := .F.

        // Reposiciona na area nativa ZZD so pra ler o memo certo
        DbSelectArea("ZZD")
        ZZD->(DbGoto(nRecno))
        cJson := ZZD->ZZD_JSON

        U_UPDSTAT("ZZD", cCod, "A", "")
        ConOut("[FATZZD01] Processando: " + cCod + " | Chave: " + cChvNFe)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            nTIni := Seconds()
            aRet  := ZZD_MotorNFCe(jJson)
            ConOut("[TIMING][FATZZD01] ZZD_MotorNFCe: " + cValToChar(Seconds() - nTIni) + "s | " + cCod)
            lOk  := aRet[1]
            cSub := IIF(Len(aRet) >= 3, cValToChar(aRet[3]), "")
            If lOk
                cFilCb := IIF(Len(aRet) >= 5, cValToChar(aRet[4]), "")
                cDocCb := IIF(Len(aRet) >= 5, cValToChar(aRet[5]), "")
            Else
                cErrMsg := cValToChar(aRet[2])
            EndIf
        Else
            cErrMsg := "JSON invalido na fila ZZD. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZD", cCod, "S", "")
            nTIni := Seconds()
            U_ZZCALLBK("ZZD", cChvNFe, cSub, .T., cFilCb, cDocCb, "")
            ConOut("[TIMING][FATZZD01] Callback iPaaS: " + cValToChar(Seconds() - nTIni) + "s | " + cCod)
            nOk++
            ConOut("[FATZZD01] OK: " + cCod)
        Else
            U_UPDSTAT("ZZD", cCod, "E", cErrMsg)
            nTIni := Seconds()
            U_ZZCALLBK("ZZD", cChvNFe, cSub, .F., "", "", cErrMsg)
            ConOut("[TIMING][FATZZD01] Callback iPaaS: " + cValToChar(Seconds() - nTIni) + "s | " + cCod)
            nErr++
            ConOut("[FATZZD01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf
    Next nJ

    ConOut("[FATZZD01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

// ==========================================================================
// ZZD_MotorNFCe � resolve cliente, numeracao, CFOP/TES e dispara U_PI_SAIDA_X
// (Faturamento/MaNfs2Nfs � grava SF2/SD2, mesmo motor de FATZZA01/NFe Saida.
// Ver [MOTOR-FATURAMENTO] no cabecalho do arquivo). Assume que produto ja
// existe (endpoint FATPI09 ja represou na ZZF/ZZD-PRDPEND=S se faltasse algo
// � so chega aqui com PRDPEND='N'). Mantido um fallback defensivo mesmo assim.
// ==========================================================================
Static Function ZZD_MotorNFCe(jJson)
//    Local aInv         := {}
    Local oData        := Nil
    Local aEmp         := {}
    Local aRet         := {.F., ""}
    Local aPrd         := {}
    Local cSub         := ""

    Local cCod         := ""
    Local cLoja        := ""
    Local cFil         := ""
    Local cCliD        := "000001"
    Local cTab         := "SA1"
    Local dVencto      := CToD("//")
    Local cCondSafe    := ""
    Local oMotorRegras := Nil
    Local cAuxC        := ""
    Local cCnpjEmit    := ""
    Local cUsuario     := ""
    Local cQryAux      := ""
    Local cAliAux      := ""
    Local nValNF       := 0
    Local cNF          := ""
    Local cSer         := ""
    Local nI           := 0
    Local cProdLeg     := ""
    Local cProdInt     := ""
    Local lCest        := .T.
    Local lNcm         := .T.
    Local aRetCfop     := {}
    Local nTIni        := 0  // [TIMING] instrumentacao temporaria, ver FATZZD01()

    If ValType(jJson['notas']) == "A" .And. Len(jJson['notas']) > 0
        oData := jJson['notas'][1]
    Else
        oData := jJson
    EndIf
    aPrd := oData['itens']
    cSub := cValToChar(U_PI_VAL_X(oData, 'cod_Subseccao'))

    aEmp := U_PI_FILIAL_X(U_PI_LIMPA_X(U_PI_STR_X(oData, "num_SubseccaoCNPJ")))
    If Len(aEmp) < 2 ; Return {.F., "Filial nao encontrada (ZZD/NFCe)", cSub} ; EndIf
    If aEmp[1] != cEmpAnt .Or. aEmp[2] != cFilAnt ; RpcClearEnv() ; RpcSetEnv(aEmp[1], aEmp[2], Nil, Nil, "FAT") ; EndIf

    // --- Resolucao de cliente (sempre consumidor/SA1, NFCe e so venda) ---
    dVencto := U_PI_DATA_X(U_PI_STR_X(oData, 'dta_Emissao', 'dta_Vencimento'))
    If !Empty(dVencto)
        dDataBase := dVencto
    EndIf

    cCondSafe    := PadR(U_PI_COND_X("004"), 3)
    oMotorRegras := U_FATCFOP01()
    cCnpjEmit    := U_PI_LIMPA_X(U_PI_STR_X(oData, 'des_EmitDocumento', 'cnpJ_FORNECEDOR'))
    cUsuario     := AllTrim(U_PI_STR_X(oData, 'cod_Exportacao'))

    If !Empty(cUsuario)
        cQryAux := "SELECT A1_COD, A1_LOJA FROM " + RetSqlName("SA1") + " WHERE TRIM(A1_LEGADO) = '" + cUsuario + "' AND D_E_L_E_T_ = ' '"
        cAliAux := GetNextAlias()
        MpSysOpenQuery(cQryAux, cAliAux)
        If (cAliAux)->(!Eof())
            cCod  := (cAliAux)->A1_COD
            cLoja := (cAliAux)->A1_LOJA
        EndIf
        (cAliAux)->(DbCloseArea())
    EndIf

    If Empty(cCod)
        cCod  := cCliD
        cLoja := "01"
    EndIf

    U_PI_BUSCA_X(cTab, cCod, aEmp[2], @cCod, @cLoja, @cFil)

    // --- Serie ---
    cSer := AllTrim(U_PI_STR_X(oData, 'cod_Serie', 'num_Serie'))
    If Empty(cSer)
        cSer := "1"
    EndIf
    cSer := PadR(cSer, TamSx3("F2_SERIE")[1], " ")

    // --- NUMERACAO E DUPLICIDADE REAL (contra SF2) ---
    // [MOTOR-FATURAMENTO] Jose Carlos - Artiq - 08/2026
    // NFCe passou a morar no Faturamento (U_PI_SAIDA_X/SF2, ver Parte 1 do
    // instrucao_nfce_motor_faturamento.md) igual NFe Saida - deixou de
    // existir o numero proprio que LOJA701/GetSxeNum("SL1","L1_NUM") gerava
    // sozinho. Mesmo padrao de numeracao + duplicidade real ja usado em
    // ZZ901_Classifica (FATZZ901.prw), adaptado: cOper e sempre "S" aqui
    // (NFCe e sempre saida), nao precisa do Do Case que a NFe tem.
    nValNF := U_PI_VAL_X(oData, 'num_NF', 'num_NotaFiscal')
    If nValNF == 0
        cNF := GetSxeNum("SF2", "F2_DOC")
        While .T.
            cQryAux := "SELECT F2_DOC FROM " + RetSqlName("SF2") + " WHERE F2_DOC = '" + PadL(AllTrim(cNF), TamSx3("F2_DOC")[1], "0") + "' AND D_E_L_E_T_ = ' '"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(Eof())
                (cAliAux)->(DbCloseArea())
                Exit
            EndIf
            (cAliAux)->(DbCloseArea())
            cNF := Soma1(cNF)
        EndDo
        ConfirmSx8()
        cNF := PadL(AllTrim(cNF), TamSx3("F2_DOC")[1], "0")
    Else
        cNF := PadL(AllTrim(cValToChar(nValNF)), TamSx3("F2_DOC")[1], "0")
    EndIf

    // Duplicidade real - nota ja processada anteriormente (SF2). Antes nao
    // existia esse risco (SL1 e uma tabela diferente da NFe); agora que
    // passa a escrever em SF2, o mesmo risco de duplicidade da NFe existe.
    cQryAux := "SELECT F2_DOC FROM " + RetSqlName("SF2") + " WHERE F2_DOC = '" + cNF + "' AND F2_SERIE = '" + cSer + "' AND F2_CLIENTE = '" + cCod + "' AND F2_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
    cAliAux := GetNextAlias()
    MpSysOpenQuery(cQryAux, cAliAux)
    If (cAliAux)->(!Eof())
        (cAliAux)->(DbCloseArea())
        Return {.T., "NFCe: " + xFilial("SF2") + " - " + cNF + " (ja processada anteriormente)", cSub, xFilial("SF2"), cNF}
    EndIf
    (cAliAux)->(DbCloseArea())

    // Validacao previa de serie (SX5) - mesma protecao que a NFe ja tem
    // (ZZ901_Classifica, bloco cOper == "S") contra o erro fatal do
    // Protheus "Problema Numeracao NF" quando a serie nao esta cadastrada.
    cQryAux := "SELECT X5_CHAVE FROM " + RetSqlName("SX5") + " WHERE X5_FILIAL = '" + xFilial("SX5") + "' AND X5_TABELA = '01' AND X5_CHAVE = '" + cSer + "' AND D_E_L_E_T_ = ' '"
    cAliAux := GetNextAlias()
    MpSysOpenQuery(cQryAux, cAliAux)
    If (cAliAux)->(Eof())
        (cAliAux)->(DbCloseArea())
        Return {.F., "Serie '" + AllTrim(cSer) + "' nao cadastrada na Tabela 01 (SX5) da filial " + xFilial("SX5") + ".", cSub}
    EndIf
    (cAliAux)->(DbCloseArea())

    // --- Resolucao de produto / CFOP / TES ---
    For nI := 1 To Len(aPrd)
        cProdLeg := AllTrim(U_PI_STR_X(aPrd[nI], 'cod_Produto'))
        cProdInt := ""
        lCest    := .T.
        lNcm     := .T.

        DbSelectArea("SB1")
        SB1->(DbOrderNickName("LEGADO"))
        If SB1->(DbSeek(xFilial("SB1") + PadR(cProdLeg, TamSx3("B1_LEGADO")[1])))
            cProdInt := AllTrim(SB1->B1_COD)
            aPrd[nI]['cod_Produto'] := cProdInt

            If !Empty(aPrd[nI]['des_ProdutoCEST'])
                lCest := U_BUSCACAD(aPrd[nI]['des_ProdutoCEST'], 1)
            EndIf
            If !Empty(aPrd[nI]['des_ProdutoNCM'])
                lNcm := U_BUSCACAD(aPrd[nI]['des_ProdutoNCM'], 2)
            EndIf

            If lCest .And. lNcm
                If RecLock("SB1", .F.)
                    SB1->B1_POSIPI := aPrd[nI]['des_ProdutoNCM']
                    SB1->B1_CEST   := aPrd[nI]['des_ProdutoCEST']
                    SB1->(MsUnlock())
                EndIf
            Else
                Return {.F., "NCM/CEST nao cadastrado. Item " + cValToChar(nI) + ": " + IIF(!Empty(aPrd[nI]['des_ProdutoNCM']), aPrd[nI]['des_ProdutoNCM'], 'Nil') + '/' + IIF(!Empty(aPrd[nI]['des_ProdutoCEST']), aPrd[nI]['des_ProdutoCEST'], 'Nil'), cSub}
            EndIf
        EndIf

        If Empty(cProdInt)
            // [DEFENSIVO] Endpoint ja garantiu existencia antes de gravar com PRDPEND='N'. Nao deveria cair aqui.
            Return {.F., "Produto nao cadastrado (Item " + cValToChar(nI) + ") Legado: " + cProdLeg, cSub}
        EndIf

        U_PI_FIXPROD(cProdInt, aPrd[nI])

        cAuxC := U_PI_LIMPA_X(U_PI_STR_X(aPrd[nI], 'cod_ProdutoCFOP', 'cfop'))
        cAuxC := U_PI_INVCFOP(cAuxC, "S")

        aRetCfop := oMotorRegras:ProcessaRegras(aPrd[nI], cAuxC, "")

        If Len(AllTrim(aRetCfop[1])) == 3 .And. Len(AllTrim(aRetCfop[2])) >= 4
            aPrd[nI]['cod_ProdutoCFOP'] := PadR(aRetCfop[2], 5)
            aPrd[nI]['_TES_CACHE']      := PadR(aRetCfop[1], 3)
        Else
            aPrd[nI]['cod_ProdutoCFOP'] := PadR(aRetCfop[1], 5)
            aPrd[nI]['_TES_CACHE']      := PadR(aRetCfop[2], 3)
        EndIf

        If Empty(aPrd[nI]['cod_ProdutoCFOP'])
            aPrd[nI]['cod_ProdutoCFOP'] := cAuxC
        EndIf

        DbSelectArea("SF4")
        SF4->(DbSetOrder(1))

        If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .Or. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
            cQryAux := "SELECT F4_CODIGO FROM " + RetSqlName("SF4") + " WHERE F4_CF='" + PadR(AllTrim(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("F4_CF")[1]) + "' AND F4_MSBLQL <> '1' AND D_E_L_E_T_=' ' ORDER BY F4_ESTOQUE DESC"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(!Eof())
                aPrd[nI]['_TES_CACHE'] := (cAliAux)->F4_CODIGO
            EndIf
            (cAliAux)->(DbCloseArea())
        EndIf

        If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .Or. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
            Return {.F., "TES nao localizado no cadastro (SF4) para o CFOP " + AllTrim(aPrd[nI]['cod_ProdutoCFOP']) + ". Verifique as configuracoes fiscais.", cSub}
        EndIf
    Next nI

    // --- Disparo do motor (Faturamento - MaNfs2Nfs, mesmo motor da NFe Saida) ---
    // [MOTOR-FATURAMENTO] Jose Carlos - Artiq - 08/2026
    // cLeg/cFil/cSerNF/cLegT sao parametros mortos de U_PI_SAIDA_X (nunca
    // lidos dentro da funcao - conferido direto no fonte, FATPI01S.prw
    // linha 641), vao vazios sem risco. .F. no lugar de lIsTransf porque
    // NFCe nao tem fluxo de transferencia/CONVENIOS (exclusivo de NFe
    // Saida comum).
    U_PI_SETFCA(cTab, cCod, cLoja, cCondSafe, oData)

    nTIni := Seconds()
    aRet  := U_PI_SAIDA_X(aPrd, oData, cCod, cLoja, "", cSer, "", cTab, .F., cNF, "", "", cCondSafe)
    ConOut("[TIMING][ZZD_MotorNFCe] U_PI_SAIDA_X (MaNfs2Nfs): " + cValToChar(Seconds() - nTIni) + "s")

    If !aRet[1]
        Return {.F., "MANFS2NFS: " + cValToChar(aRet[2]), cSub}
    EndIf

    // [MOTOR-FATURAMENTO] U_PI_SAIDA_X so grava F2_ESPECIE/F3_ESPECIE como
    // "SPED" ou "NFE" (nunca "NFCE") - patch pos-gravacao pra marcar
    // corretamente, igual o legado (FATPI01__2_.prw, linhas 1873-1879/
    // 2110-2122 e 2940-2946/3019) ja fazia pra modelo 65.
    TCSqlExec("UPDATE " + RetSqlName("SF2") + " SET F2_ESPECIE = '" + PadR("NFCE", TamSx3("F2_ESPECIE")[1]) + "' WHERE F2_DOC = '" + PadL(AllTrim(cValToChar(aRet[2])), TamSx3("F2_DOC")[1], "0") + "' AND F2_SERIE = '" + cSer + "' AND F2_CLIENTE = '" + cCod + "' AND F2_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '")
    TCSqlExec("UPDATE " + RetSqlName("SF3") + " SET F3_ESPECIE = '" + PadR("NFCE", TamSx3("F3_ESPECIE")[1]) + "' WHERE F3_NFISCAL = '" + PadL(AllTrim(cValToChar(aRet[2])), TamSx3("F2_DOC")[1], "0") + "' AND F3_SERIE = '" + cSer + "' AND F3_CLIEFOR = '" + cCod + "' AND F3_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '")

Return {.T., "NFCe: " + xFilial("SF2") + " - " + cValToChar(aRet[2]), cSub, xFilial("SF2"), cValToChar(aRet[2])}
