#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

// [BOOTSTRAP] Empresa/filial padrao para o RpcSetEnv inicial do Job.
// Nao da pra usar SuperGetMv aqui — SX6/cEmpAnt ainda nao existem antes
// do primeiro RpcSetEnv (erro 'variable does not exist CFILANT'). Hardcode
// e o padrao correto nesse bootstrap; isolado em #Define para ficar facil
// de achar/trocar se o ambiente mudar. Padrao copiado do FATZZA01.prw.
#DEFINE CEMPPAD "01"
#DEFINE CFILPAD "01001"

/*
+----------------------------------------------------------------------------+
| Autor: Jose Carlos - Artiq                                                 |
| Data: 08/2026                                                              |
| Descritivo: FATZZ901 - Job Schedule - Fila ZZ9 (Classificacao NFe)        |
|             Le a ZZ9 (gravada bruta pelo FATPI01_V2.prw), classifica a    |
|             nota (roteamento fiscal SA1/SA2, cOper, numeracao, loop de    |
|             produtos/CFOP/TES) e grava o resultado ja classificado em     |
|             ZZA (Saida) / ZZB (Devolucao) / ZZC (Entrada).                |
| [ZZ9] Jose Carlos - Artiq - 08/2026                                       |
|   Job novo. A logica de classificacao daqui e a mesma que existia dentro  |
|   do WSMETHOD do FATPI01_V2.prw ate 08/2026 - so movida pra ca, com as    |
|   saidas HTTP (Self:SetResponse/Return .T.) trocadas por retorno de       |
|   funcao (ZZ901_Classifica) e gravacao de erro na propria ZZ9.            |
|   Motivo da mudanca: o aviso de produto pendente do FATPI10 nao traz      |
|   CFOP, entao a classificacao nao pode mais acontecer na hora do          |
|   recebimento do payload - precisa esperar confirmacao de que nao ha      |
|   produto pendente (ZZ9_PRDPEN='N', ver query principal abaixo).          |
|   ESTE JOB DEPENDE DE FATZZF01 (contem U_ZZX_Gravar/U_UPDSTAT, ambos      |
|   usados aqui) - respeitar a ordem de compilacao ja documentada.          |
+----------------------------------------------------------------------------+
*/

User Function FATZZ901()
    Local cAliZZ9    := GetNextAlias()
    Local cQry       := ""
    Local cCod       := ""
    Local cJson      := ""
    Local cChvNFe    := ""
    Local cFilOri    := ""
    Local nRecno     := 0
    Local cErrMsg    := ""
    Local cSub       := ""
    Local cTabPai    := ""
    Local cTipoPen   := ""
    Local cProdPend  := ""
    Local lOk        := .F.
    Local lDup       := .F.
    Local nOk        := 0
    Local nErr       := 0
    Local nPark      := 0
    Local jJson      := Nil
    Local aRet       := {}
    Local dDataBaseSis := CToD("")
    Local bErrOld    := Nil
    Local oErrRT     := Nil

    Private __cBatch := "1"

    ConOut("[FATZZ901] Iniciando Classificacao NFe (ZZ9) - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    // [FIX-DATABASE-LEAK] Jose Carlos - Artiq - 08/2026
    // dDataBase real do sistema, capturada uma unica vez logo apos o
    // RpcSetEnv - usada pra resetar dDataBase a cada iteracao do loop
    // abaixo (ver 2.5.3), evitando que o valor de uma nota vaze pra
    // proxima quando dVencto vier vazio.
    dDataBaseSis := dDataBase

    // [FIX-MEMO] Nao seleciona ZZ9_JSON aqui — le via R_E_C_N_O_ + DbGoto
    // na area nativa, mais abaixo (mesmo fix aplicado no FATZZF01/demais Jobs).
    // ZZ9_PRDPEN = 'N': registros com produto pendente ficam parados na ZZ9
    // ate serem liberados (fluxo do FATPI10, fora de escopo aqui).
    // [ZZG] Jose Carlos - Artiq - 08/2026
    // ZZ9_CLIPEN/ZZ9_FORPEN = 'N' - mesmo mecanismo do PRDPEN, agora pra
    // cliente/fornecedor pendente (ver instrucao_zzg_cliente_fornecedor.md
    // e [FIX-CLIFOR-PENDENTE] mais abaixo). Uma nota com qualquer uma das
    // tres pendencias fica de fora da fila ate ser liberada.
    // [FIX-DESTMU-FILIAL] Jose Carlos - Artiq - 08/2026
    // ZZ9_FILIAL agora vai no SELECT - capturada por linha e usada no UPDATE
    // de ZZ9_DESTMU mais abaixo em vez de xFilial("ZZ9") (ver 2.5.2).
    cQry := "SELECT ZZ9_COD, ZZ9_CHVNFE, ZZ9_FILIAL, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZ9") + " "
    cQry += "WHERE ZZ9_STATUS IN ('P','A') AND ZZ9_PRDPEN = 'N' AND ZZ9_CLIPEN = 'N' AND ZZ9_FORPEN = 'N' "
    cQry += "AND ZZ9_FILIAL = '" + xFilial("ZZ9") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZ9_DTINCL, ZZ9_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZ9, .T., .T.)

    While (cAliZZ9)->(!Eof())
        cCod    := AllTrim((cAliZZ9)->ZZ9_COD)
        cChvNFe := AllTrim((cAliZZ9)->ZZ9_CHVNFE)
        cFilOri := AllTrim((cAliZZ9)->ZZ9_FILIAL)
        nRecno  := (cAliZZ9)->RECNO
        cErrMsg := ""
        cSub    := ""
        cTabPai := ""
        cTipoPen:= ""
        cProdPend := ""
        lOk     := .F.
        lDup    := .F.

        // [FIX-DATABASE-LEAK] Reseta dDataBase pra data real do sistema a
        // cada nota, antes de classificar - ZZ901_Classifica so sobrescreve
        // se a nota tiver dVencto preenchido (ver 2.5.3).
        dDataBase := dDataBaseSis

        // Reposiciona na area nativa ZZ9 so pra ler o memo certo
        DbSelectArea("ZZ9")
        ZZ9->(DbGoto(nRecno))
        cJson := ZZ9->ZZ9_JSON

        U_UPDSTAT("ZZ9", cCod, "A", "")
        ConOut("[FATZZ901] Classificando: " + cCod + " | Chave: " + cChvNFe)

        jJson := JsonObject():New()
        If Empty(jJson:FromJson(cJson))
            // [FIX-EXCEPTION-MOTOR] 08/2026 - Begin
            // Sequence/Recover em volta da classificacao - excecao de
            // runtime nao tratada vira erro normal em vez de derrubar o
            // Job inteiro sem callback. Ver U_PI_ERRO_RT (FATZZF01.prw).
            bErrOld := ErrorBlock({|oErr| Break(oErr)})
            Begin Sequence
                aRet := ZZ901_Classifica(jJson)
            Recover Using oErrRT
                aRet := {.F., "EXCEPTION: " + U_PI_ERRO_RT(oErrRT)}
            End Sequence
            ErrorBlock(bErrOld)
            lOk  := aRet[1]
            If lOk
                cTabPai := IIF(Len(aRet) >= 3, aRet[3], "")
                lDup    := IIF(Len(aRet) >= 4, aRet[4], .F.)
            Else
                cErrMsg  := IIF(Len(aRet) >= 2, cValToChar(aRet[2]), "Erro desconhecido na classificacao")
                cSub     := IIF(Len(aRet) >= 3, cValToChar(aRet[3]), "")
                // [FIX-CLIFOR-PENDENTE]/[FIX-PROD-PENDENTE-CLASSIF] 4o
                // elemento "CLI"/"FOR"/"PRD" (quando presente) distingue
                // "estacionada" de erro real - ver contrato no cabecalho
                // de ZZ901_Classifica. "PRD" ganha um 5o elemento com o
                // codigo legado do produto faltante.
                cTipoPen  := IIF(Len(aRet) >= 4 .And. (aRet[4] == "CLI" .Or. aRet[4] == "FOR" .Or. aRet[4] == "PRD"), aRet[4], "")
                cProdPend := IIF(cTipoPen == "PRD" .And. Len(aRet) >= 5, cValToChar(aRet[5]), "")
            EndIf
        Else
            cErrMsg := "JSON invalido na fila ZZ9. COD: " + cCod
        EndIf
        FreeObj(jJson)

        If lOk
            U_UPDSTAT("ZZ9", cCod, "S", "")
            If !Empty(cTabPai)
                // [FIX-DESTMU-FILIAL] cFilOri (capturada da propria linha
                // lida) usada em vez de xFilial("ZZ9") por seguranca - nao
                // muda mais nada na pratica desde que ZZ901_Classifica
                // parou de trocar de ambiente ([MOVIDO-ZZ901], ver
                // instrucao_mover_numeracao_para_jobs.md), mas mantido:
                // reflete exatamente a filial da linha que a query
                // principal leu, sem depender de nenhum estado de ambiente.
                TCSqlExec("UPDATE " + RetSqlName("ZZ9") + " SET ZZ9_DESTMU = '" + cTabPai + "' WHERE ZZ9_COD = '" + cCod + "' AND ZZ9_FILIAL = '" + cFilOri + "' AND D_E_L_E_T_ = ' '")
            EndIf
            nOk++
            ConOut("[FATZZ901] OK: " + cCod + " | Destino: " + cTabPai + IIF(lDup, " (nota ja existia, nao duplicou)", ""))
        ElseIf cTipoPen == "PRD"
            // [FIX-PROD-PENDENTE-CLASSIF] Jose Carlos - Artiq - 08/2026
            // Produto nao cadastrado NA HORA da classificacao - alinhado
            // com o time iPaaS: em vez de falhar (STATUS='E'), estaciona a
            // nota igual ao fluxo do FATPI10 - grava o produto faltante na
            // ZZF (U_ZZF_GRV, mesma funcao que o endpoint usa; cJsonPayload
            // vazio, ZZF_CADPRD busca o cadastro definitivo na API externa
            // por codigo, nao precisa do JSON aqui) e marca ZZ9_PRDPEN='S'
            // (cFilOri, mesmo motivo do [FIX-DESTMU-FILIAL]). Sem callback
            // pro iPaaS - economia de mensagens, mesma decisao do
            // [TEMP-CALLBACK-OFF] ja aplicado aos callbacks intermediarios.
            U_UPDSTAT("ZZ9", cCod, "P", "")
            U_ZZF_GRV(cChvNFe, "ZZ9", cProdPend, "")
            TCSqlExec("UPDATE " + RetSqlName("ZZ9") + " SET ZZ9_PRDPEN = 'S' WHERE ZZ9_COD = '" + cCod + "' AND ZZ9_FILIAL = '" + cFilOri + "' AND D_E_L_E_T_ = ' '")
            nPark++
            ConOut("[FATZZ901] ESTACIONADA (produto pendente): " + cCod + " | Produto: " + cProdPend)
        ElseIf !Empty(cTipoPen)
            // [FIX-CLIFOR-PENDENTE] Jose Carlos - Artiq - 08/2026
            // Cliente/fornecedor nao encontrado NA HORA da classificacao -
            // em vez de falhar (STATUS='E'), estaciona a nota: marca
            // CLIPEN/FORPEN='S' (cFilOri, mesmo motivo do
            // [FIX-DESTMU-FILIAL] - xFilial("ZZ9") aqui bateria na filial
            // ja trocada) e reseta STATUS pra 'P' (fica de fora do WHERE
            // ate a pendencia resolver - mesmo mecanismo ja usado pro
            // PRDPEN). Nao dispara callback de erro nem conta como falha -
            // decisao consciente (Jose Carlos, 08/2026): quem detecta e
            // notifica cliente/fornecedor faltante e o iPaaS, via
            // cliente_Pendente/fornecedor_Pendente na ingestao (mesmo
            // padrao do prod_Pendente); isso aqui e so um fallback
            // defensivo caso aquela deteccao upfront tenha falhado ou
            // ficado desatualizada. Ver instrucao_zzg_cliente_fornecedor.md.
            U_UPDSTAT("ZZ9", cCod, "P", "")
            TCSqlExec("UPDATE " + RetSqlName("ZZ9") + " SET ZZ9_" + IIF(cTipoPen == "CLI", "CLIPEN", "FORPEN") + " = 'S' WHERE ZZ9_COD = '" + cCod + "' AND ZZ9_FILIAL = '" + cFilOri + "' AND D_E_L_E_T_ = ' '")
            nPark++
            ConOut("[FATZZ901] ESTACIONADA (" + cTipoPen + " pendente): " + cCod + " | " + Left(cErrMsg, 100))
        Else
            U_UPDSTAT("ZZ9", cCod, "E", cErrMsg)
            // [FIX-CALLBACK-ERRO] Jose Carlos - Artiq - 08/2026
            // Antes nenhum erro de classificacao chegava ao iPaaS - a nota
            // ficava presa na ZZ9 com STATUS='E' pra sempre, sem nunca ser
            // roteada pra ZZA/ZZB/ZZC (onde o callback de erro normalmente
            // dispara). "ZZ9" como cTab cai no Otherwise de ZZCALLBK (dominio
            // Nota Fiscal - cod_ChaveNFe), igual ja acontecia na liberacao de
            // produto pendente (FATZZF01.prw) pra notas ainda nao classificadas.
            U_ZZCALLBK("ZZ9", cChvNFe, cSub, .F., "", "", cErrMsg)
            nErr++
            ConOut("[FATZZ901] ERRO: " + cCod + " | " + Left(cErrMsg, 100))
        EndIf

        (cAliZZ9)->(DbSkip())
    EndDo
    (cAliZZ9)->(DbCloseArea())

    ConOut("[FATZZ901] Fim. OK: " + cValToChar(nOk) + " | Estacionadas: " + cValToChar(nPark) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

// ==========================================================================
// ZZ901_Classifica — Motor de classificacao NFe (roteamento fiscal +
// numeracao + loop de produtos + gravacao final em ZZA/ZZB/ZZC).
// Transcricao 1:1 da logica que existia no WSMETHOD do FATPI01_V2.prw
// (secoes 3, 5, 6 e 7 do fonte original) ate 08/2026 - so trocado o
// padrao de "monta jRes e Self:SetResponse/Return .T." por early-return
// {lOk, cMensagem}, equivalente em comportamento (mesmo padrao ja usado
// em ZZA_MotorSaida/ZZB_MotorDevolucao/ZZC_MotorEntrada).
//
// Retorno: {lOk, cErrMsg, cTabPai, lJaProcessada}
//   lOk == .T.  -> cTabPai = "ZZA"/"ZZB"/"ZZC" (pra onde foi/seria roteada),
//                  lJaProcessada = .T. se a nota ja existia em SF2/SF1 (a
//                  gravacao final em ZZA/ZZB/ZZC nao roda de novo nesse caso)
//   lOk == .F.  -> cErrMsg = motivo da falha, cSub = cod_Subseccao (3o
//                  elemento, quando ja disponivel - ver [FIX-CALLBACK-ERRO]
//                  no loop principal, FATZZ901()). "Estacionada" (cliente/
//                  fornecedor pendente, ver [FIX-CLIFOR-PENDENTE]): array
//                  de 4 elementos, 4o = "CLI" ou "FOR" - o loop principal
//                  marca ZZ9_CLIPEN/ZZ9_FORPEN='S' e reseta STATUS pra 'P'
//                  em vez de 'E', sem callback de erro. "Estacionada" por
//                  produto pendente (ver [FIX-PROD-PENDENTE-CLASSIF]):
//                  array de 5 elementos, 4o = "PRD", 5o = codigo legado do
//                  produto faltante - o loop principal grava na ZZF via
//                  U_ZZF_GRV e marca ZZ9_PRDPEN='S', tambem sem callback.
//                  Falha real de verdade: array de 3 elementos (sem 4o),
//                  como sempre.
// ==========================================================================
Static Function ZZ901_Classifica(jJson)
    Local aInv         := jJson['notas']
    Local oHead        := Nil
    Local aPrd         := {}
    Local aEmp         := {}
    Local cSub         := ""
    Local cCnpj        := ""
    Local cSer         := ""
    Local cOper        := ""
    Local cTab         := ""
    Local cCod         := ""
    Local cLoja        := ""
    Local cFil         := ""
    Local cCliD        := "000001"
    Local dVencto      := CToD("//")
    Local cCondSafe    := ""
    Local nI           := 0
    Local cQryAux      := ""
    Local cAliAux      := ""
    Local cAuxC        := ""
    Local cProdLeg     := ""
    Local cProdInt     := ""
    Local cCheckCFOP   := ""
    Local cKeyDest     := ""
    Local lIsTransf    := .F.
    Local oMotorRegras := Nil
    Local aRetCfop     := {}
    Local cNatOp       := ""
    Local cCnpjEmit    := ""
    Local cCnpjDest    := ""
    Local cUsuario     := ""
    Local lCest
    Local lNcm
    Local cModDoc      := ""
    Local cTabPai      := ""

    If ValType(aInv) != "A" .Or. Len(aInv) == 0
        Return {.F., "Array notas ausente (ZZ9)"}
    EndIf
    oHead   := aInv[1]
    cModDoc := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')
    aPrd    := oHead['itens']
    cNatOp  := Upper(AllTrim(U_PI_STR_X(oHead, 'des_NatOp')))
    // [FIX-CALLBACK-ERRO] Jose Carlos - Artiq - 08/2026
    // cod_Subseccao extraido cedo (igual os outros motores ja fazem) pra
    // alimentar o callback de erro que o loop principal (FATZZ901()) passou
    // a disparar - antes nenhum erro de classificacao chegava ao iPaaS.
    cSub    := cValToChar(U_PI_VAL_X(oHead, 'cod_Subseccao'))

    If ValType(aPrd) == "A" .And. Len(aPrd) > 0
        cCheckCFOP := Upper(U_PI_STR_X(aPrd[1], 'cod_ProdutoCFOP', 'cfop'))

        If ("REM P/ VENDA FORA" $ cNatOp .Or. "REMESSA P/ VENDA FORA" $ cNatOp) .AND. SUBSTR(cCheckCFOP,1,1) $ '5/6'
            cCheckCFOP := "5904"
        EndIf

        If "5557" $ cCheckCFOP .Or. "TRANSF" $ cCheckCFOP .Or. "TRANSF" $ cNatOp .Or. "5152" $ cCheckCFOP
            lIsTransf := .T.
        EndIf
    EndIf

    cCnpj := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ', 'num_SubseccaoCNPJ'))
    aEmp := U_PI_FILIAL_X(cCnpj)

    If Len(aEmp) < 2
        Return {.F., "Filial nao encontrada para CNPJ: " + AllTrim(cCnpj), cSub}
    EndIf

    // [MOVIDO-ZZ901] Jose Carlos - Artiq - 08/2026
    // Troca de ambiente REMOVIDA - era o bug (ZZ901_Classifica trocava pra
    // filial real e nunca voltava antes de gravar via U_ZZX_Gravar, que usa
    // xFilial() e refletia a filial ja trocada - ZZA/ZZC gravavam com
    // filial errada). SA1/SA2/SF4/SX5 (tudo usado daqui pra baixo) sao
    // cadastro compartilhado entre filiais - nao precisam da filial real.
    // A unica coisa que precisava mesmo da filial real era numeracao
    // (GetSxeNum/SX8) e gravacao fiscal final - ambas migraram pros Jobs de
    // destino (FATZZA01/B01/C01), que ja trocam de ambiente antes de chamar
    // o motor. Ver instrucao_mover_numeracao_para_jobs.md.

    // --- ROTEAMENTO FISCAL (SA1 vs SA2 E CONTRAPARTE) ---
    dVencto := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Emissao', 'dta_Vencimento'))
    If !Empty(dVencto)
        dDataBase := dVencto
    EndIf

    cCondSafe := PadR(U_PI_COND_X("004"), 3)
    oMotorRegras := U_FATCFOP01()
    cAuxC := cCheckCFOP

    cCnpjEmit := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'des_EmitDocumento', 'cnpJ_FORNECEDOR'))
    cCnpjDest := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'des_DestDocumento', 'cpf'))

    If U_PI_STR_X(oHead, 'des_Finalidade') == "4" .And. "DEVOLUCAO DE VENDA" $ cNatOp
        If ValType(aPrd) == "A" .And. Len(aPrd) > 0
            cUsuario := AllTrim(U_PI_STR_X(oHead, 'cod_Exportacao'))
        EndIf
    EndIf

    If !Empty(cUsuario)
        cQryAux := "SELECT A1_COD, A1_LOJA FROM " + RetSqlName("SA1") + " WHERE TRIM(A1_LEGADO) = '" + cUsuario + "' AND D_E_L_E_T_ = ' '"
        cAliAux := GetNextAlias()
        MpSysOpenQuery(cQryAux, cAliAux)
        If (cAliAux)->(!Eof())
            cCod  := (cAliAux)->A1_COD
            cLoja := (cAliAux)->A1_LOJA
            cFil  := xFilial("SA1")
        EndIf
        (cAliAux)->(DbCloseArea())

        cTab  := "SA1"
        cKeyDest := cUsuario
        cOper := "D"
    Else
        If cCnpj == cCnpjEmit
            cKeyDest := cCnpjDest
        Else
            cKeyDest := cCnpjEmit
        EndIf

        If lIsTransf .Or. cAuxC $ "5557/1557/5152/5409/1152/1409"
            If cCnpj == cCnpjDest .And. cCnpj != cCnpjEmit
                cOper := "E"
                cTab  := "SA2"
            ElseIf cCnpj == cCnpjEmit .And. cCnpj != cCnpjDest
                // [FIX-TRANSF-CTAB] Jose Carlos - Artiq - 08/2026 - era
                // "SA2", divergente do original (FZ_PROS_X) - origem =
                // fornecedor (SA2, ja confirmado pela validacao logo
                // abaixo), destino = cliente (SA1). Ver
                // instrucoes_pendentes_pos_debug_transf.md, Parte A.1.
                cOper := "S"
                cTab  := "SA1"
            Else
                If Left(cAuxC, 1) $ "1/2"
                    cOper := "E"
                Else
                    cOper := "S"
                EndIf
                cTab  := "SA2"
            EndIf

        ElseIf cAuxC $ "1202/1411/2202"
            cOper := "D"
            cTab  := "SA1"
        ElseIf cAuxC $ "5202/5411/6202"
            cOper := "S"
            cTab  := "SA2"
        ElseIf Left(cAuxC, 1) $ "1/2/3"
            cOper := "E"
            cTab  := "SA2"
        ElseIf Left(cAuxC, 1) $ "5/6/7"
            cOper := "S"
            cTab  := "SA1"
        Else
            cOper := "E"
            cTab  := "SA2"
        EndIf

        U_PI_BUSCA_X(cTab, cKeyDest, aEmp[2], @cCod, @cLoja, @cFil)

        If Empty(cCod) .And. cTab == "SA1" .And. cOper == "S"
            cCod := cCliD
            cLoja := "01"
            U_PI_BUSCA_X(cTab, cCod, aEmp[2], @cCod, @cLoja, @cFil)
        EndIf
    EndIf

    IF cOper == 'D' .AND. cTab == 'SA2'
        SA2->(DbSetOrder(3))
        If SA2->(DbSeek(xFilial("SA2") + cCnpjEmit))
            cCod := SA2->A2_COD
            cLoja := SA2->A2_LOJA
        Endif
    ENDIF

    If Empty(cCod)
        // [FIX-CLIFOR-PENDENTE] cTab diz se era cliente (SA1) ou
        // fornecedor (SA2) que nao foi encontrado - ver contrato de
        // retorno no cabecalho da funcao e instrucao_zzg_cliente_fornecedor.md.
        Return {.F., "Destinatario nao localizado. Doc: " + cKeyDest, cSub, IIF(cTab == "SA1", "CLI", "FOR")}
    Endif

    // [REV2-EXTRACAO-NFCE] Validacao de emitente em SA2 - sempre aplicavel (NFCe nunca chega aqui)
    SA2->(DbSetOrder(3))
    If !SA2->(DbSeek(xFilial("SA2") + cCnpjEmit))
        SA2->(DbSetOrder(1))
        // [FIX-CLIFOR-PENDENTE] Emitente e sempre fornecedor (SA2) aqui.
        Return {.F., "Emitente nao esta cadastrado como fornecedor na filial destino. CNPJ: " + cCnpjEmit, cSub, "FOR"}
    EndIf
    SA2->(DbSetOrder(1))

    // cTabPai calculado cedo - precisa dele tanto no atalho de duplicidade
    // quanto na gravacao final (mesmo mapeamento ja usado em FATZZF01).
    Do Case
        Case cOper == "D" ; cTabPai := "ZZB"
        Case cOper == "S" ; cTabPai := "ZZA"
        Otherwise          ; cTabPai := "ZZC"
    EndCase

    // [MOVIDO-ZZ901] Numeracao real (GetSxeNum/duplicidade contra SF2/SF1/
    // limpeza SFT-SF3) migrou pra U_PI_NUMERA_X, chamada dentro de cada Job
    // de destino (FATZZA01/B01/C01) - so la o ambiente ja esta trocado pra
    // filial real. Serie continua sendo resolvida aqui (cadastro,
    // compartilhado entre filiais - so filtro/fallback, nao gera nada).
    cSer := AllTrim(U_PI_STR_X(oHead, 'cod_Serie', 'num_Serie'))
    If Empty(cSer)
        cSer := "1"
    EndIf
    cSer := PadR(cSer, TamSx3("F2_SERIE")[1], " ")

    For nI := 1 To Len(aPrd)
        cProdLeg := AllTrim(U_PI_STR_X(aPrd[nI], 'cod_Produto'))
        cProdInt := ""

        lCest := .T.
        lNcm  := .T.

        DbSelectArea("SB1")
        SB1->(DbOrderNickName("LEGADO"))
        If SB1->(DbSeek(xFilial("SB1") + PadR(cProdLeg, TamSx3("B1_LEGADO")[1])))
            cProdInt := AllTrim(SB1->B1_COD)
            aPrd[nI]['cod_Produto'] := cProdInt

            if !Empty(aPrd[nI]['des_ProdutoCEST'])
                lCest := U_BUSCACAD(aPrd[nI]['des_ProdutoCEST'],1)
            Endif

            if !Empty(aPrd[nI]['des_ProdutoNCM'])
                lNcm  := U_BUSCACAD(aPrd[nI]['des_ProdutoNCM'],2)
            Endif

            if lCest .and. lNcm
                If RecLock("SB1", .F.)
                    SB1->B1_POSIPI := aPrd[nI]['des_ProdutoNCM']
                    SB1->B1_CEST   := aPrd[nI]['des_ProdutoCEST']
                    SB1->(MsUnlock())
                Endif
            else
                Return {.F., "NCM e/ou CEST nao cadastrado. " + IIF(!Empty(aPrd[nI]['des_ProdutoNCM']),aPrd[nI]['des_ProdutoNCM'],'Nil') + '/' + IIF(!Empty(aPrd[nI]['des_ProdutoCEST']),aPrd[nI]['des_ProdutoCEST'],'Nil'), cSub}
            EndIf
        EndIf

        If Empty(cProdInt)
            // [FIX-PROD-PENDENTE-CLASSIF] Jose Carlos - Artiq - 08/2026
            // Alinhado com o time iPaaS (08/2026): produto nao cadastrado
            // NA HORA da classificacao (deteccao upfront do iPaaS via
            // prod_Pendente falhou ou ficou desatualizada) nao e mais erro
            // definitivo - estaciona a nota (5o elemento "PRD" + 6o
            // elemento com o codigo legado do produto faltante). O loop
            // principal (FATZZ901()) grava o produto na ZZF via
            // U_ZZF_GRV e marca ZZ9_PRDPEN='S', mesmo mecanismo ja usado
            // pelo fluxo do FATPI10. Sem callback pro iPaaS (economia de
            // mensagens - decisao consciente, mesma linha dos callbacks
            // intermediarios ja desativados, [TEMP-CALLBACK-OFF]).
            // Descoberta incremental: para no primeiro produto faltante
            // (nao escaneia o restante do item) - nota com varios produtos
            // faltantes leva um ciclo de estacionar/resolver por produto.
            Return {.F., "Produto nao cadastrado (Item " + cValToChar(nI) + ") Legado: " + cProdLeg, cSub, "PRD", cProdLeg}
        EndIf

        U_PI_FIXPROD(cProdInt, aPrd[nI])

        cAuxC := U_PI_LIMPA_X(U_PI_STR_X(aPrd[nI], 'cod_ProdutoCFOP', 'cfop'))

        If "REM P/ VENDA FORA" $ cNatOp .Or. "REMESSA P/ VENDA FORA" $ cNatOp
            cAuxC := "5904"
        EndIf

        cAuxC := U_PI_INVCFOP(cAuxC, cOper)

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

        If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .OR. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
            cQryAux := "SELECT F4_CODIGO FROM " + RetSqlName("SF4") + " WHERE F4_CF='" + PadR(AllTrim(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("F4_CF")[1]) + "' AND F4_MSBLQL <> '1' AND D_E_L_E_T_=' ' ORDER BY F4_ESTOQUE DESC"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(!Eof())
                aPrd[nI]['_TES_CACHE'] := (cAliAux)->F4_CODIGO
            EndIf
            (cAliAux)->(DbCloseArea())
        EndIf

        If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .OR. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
            Return {.F., "TES nao localizado no cadastro (SF4) da filial atual para o CFOP " + AllTrim(aPrd[nI]['cod_ProdutoCFOP']) + ". Verifique as configuracoes fiscais.", cSub}
        EndIf

        If cOper == "D"
            cQryAux := "SELECT D2_DOC, D2_SERIE, D2_ITEM FROM " + RetSqlName("SD2") + " WHERE D2_FILIAL = '" + xFilial("SD2") + "' AND D2_CLIENTE = '" + cCod + "' AND D2_LOJA = '" + cLoja + "' AND D2_COD = '" + aPrd[nI]['cod_Produto'] + "' AND D_E_L_E_T_ = ' ' ORDER BY D2_EMISSAO DESC"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(!Eof())
                aPrd[nI]['_NFORI']   := (cAliAux)->D2_DOC
                aPrd[nI]['_SERIORI'] := (cAliAux)->D2_SERIE
                aPrd[nI]['_ITEMORI'] := (cAliAux)->D2_ITEM
            EndIf
            (cAliAux)->(DbCloseArea())
        EndIf
    Next nI

    // [FIX-MOTOR-2X] Enriquece o oHead com os campos sinteticos que os
    // Jobs finais (FATZZA01/B01/C01) precisam pra rodar o motor sozinhos -
    // mesma logica que ja existia no FATPI01_V2.prw antes da migracao pra ZZ9.
    // [MOVIDO-ZZ901] _NF/_LEG removidos daqui - numeracao real (e o cLeg
    // que sempre foi igual a ela) agora e resolvida dentro de cada Job via
    // U_PI_NUMERA_X, no ambiente ja trocado pra filial real.
    oHead['_COD']      := cCod
    oHead['_LOJA']     := cLoja
    oHead['_SER']      := cSer
    oHead['_FIL']      := cFil
    oHead['_TAB']      := cTab
    oHead['_TRANSF']   := IIF(lIsTransf, "S", "N")
    oHead['_COND']     := cCondSafe
    oHead['_CNPJEMIT'] := cCnpjEmit
    oHead['_CNPJDEST'] := cCnpjDest

    // --- GRAVACAO FINAL EM ZZA/ZZB/ZZC ---
    Do Case
        Case cOper == "D"
            If !U_ZZX_Gravar("ZZB", "NFD", "CHVNFE", AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe')), jJson:toJSON(), "", "", "N", AllTrim(U_PI_STR_X(oHead, 'qt_Produto')))
                Return {.F., "Falha ao gravar na fila ZZB.", cSub}
            EndIf

        Case cOper == "S"
            // Validacao SX5 continua aqui - pre-flight antes de gravar,
            // evita erro fatal do Protheus "Problema Numeracao NF" mais tarde
            cQryAux := "SELECT X5_CHAVE FROM " + RetSqlName("SX5") + " WHERE X5_FILIAL = '" + xFilial("SX5") + "' AND X5_TABELA = '01' AND X5_CHAVE = '" + cSer + "' AND D_E_L_E_T_ = ' '"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(Eof())
                (cAliAux)->(DbCloseArea())
                Return {.F., "Serie '" + AllTrim(cSer) + "' nao cadastrada na Tabela 01 (SX5) da filial " + xFilial("SX5") + ".", cSub}
            EndIf
            (cAliAux)->(DbCloseArea())

            If !U_ZZX_Gravar("ZZA", "NFS", "CHVNFE", AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe')), jJson:toJSON(), "TRANSF", IIF(lIsTransf, "S", "N"), "N", AllTrim(U_PI_STR_X(oHead, 'qt_Produto')))
                Return {.F., "Falha ao gravar na fila ZZA.", cSub}
            EndIf

        Otherwise
            If !U_ZZX_Gravar("ZZC", "NFE", "CHVNFE", AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe')), jJson:toJSON(), "", "", "N", AllTrim(U_PI_STR_X(oHead, 'qt_Produto')))
                Return {.F., "Falha ao gravar na fila ZZC.", cSub}
            EndIf
    EndCase

Return {.T., "", cTabPai, .F.}
