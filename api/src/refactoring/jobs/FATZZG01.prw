#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

// [BOOTSTRAP] Empresa/filial padrao para o RpcSetEnv inicial do Job.
// Nao da pra usar SuperGetMv aqui - SX6/cEmpAnt ainda nao existem antes
// do primeiro RpcSetEnv (erro 'variable does not exist CFILANT'). Mesmo
// padrao ja usado nos outros seis Jobs FATZZ*.
Static CEMPPAD := "01"
Static CFILPAD := "01001"

/*
+----------------------------------------------------------------------------+
| Autor: Jose Carlos - Artiq                                                 |
| Data: 08/2026                                                              |
| Descritivo: FATZZG01 - Job Schedule - Fila ZZG (Cliente/Fornecedor       |
|             Pendente)                                                     |
|             Para cada pendencia: chama U_PI_CLI_X ou U_PI_FORN_X          |
|             conforme ZZG_TIPOPE. Ao concluir TODAS as pendencias de uma  |
|             chave ZZG_CHVREF (e tambem nao haver mais pendencia de        |
|             produto na ZZF pra essa mesma chave - ver U_ZZPENDOK em       |
|             FATZZF01.prw), zera CLIPEN/FORPEN/PRDPEN na tabela Muro pai   |
|             (ZZ9/ZZD) e libera a nota.                                    |
|                                                                             |
| [ZZG] Jose Carlos - Artiq - 08/2026                                       |
|   Job novo - ver instrucao_zzg_cliente_fornecedor.md pro contexto        |
|   completo (gargalo de 12h no envio de notas, causado pela cadeia        |
|   sincrona GET CAASP -> POST FATPI03/FATPI06 -> espera resposta que o    |
|   iPaaS fazia antes de mandar a nota). Mesmo padrao ja validado pra       |
|   produto pendente (ZZF/FATPI10/FATZZF01), mais simples que aquele -     |
|   nao ha consulta a API externa nenhuma aqui: o iPaaS ja manda o        |
|   cadastro TRATADO e pronto (ZZG_JSON), U_PI_CLI_X/U_PI_FORN_X so        |
|   fazem o upsert direto.                                                  |
|                                                                             |
|   ESTE JOB DEPENDE DE FATZZF01 (contem U_UPDSTAT/U_ZZCALLBK/U_ZZPENDOK/   |
|   U_ZZ_LIBNF, todos usados aqui) - compilar depois dele, mesma regra ja   |
|   valida pros outros Jobs FATZZ*.                                        |
|                                                                             |
| [ESCOPO] So ZZ9 (NFe) e ZZD (NFCe) tem os campos CLIPEN/FORPEN - ver      |
|   Parte 5 da instrucao. ZZA/ZZB/ZZC nunca tem nota com cliente/           |
|   fornecedor pendente (so sao gravadas depois que ZZ901_Classifica ja     |
|   resolveu com sucesso) e ZZE (Recibo) fica fora de escopo por decisao    |
|   consciente (Mauricio/iPaaS). ZZG_TIPONF portanto so assume "ZZ9" ou    |
|   "NFC" na pratica hoje.                                                  |
+----------------------------------------------------------------------------+
*/

User Function FATZZG01()
    Local cAliZZG  := GetNextAlias()
    Local cQry     := ""
    Local cCod     := ""
    Local cJson    := ""
    Local cChvRef  := ""
    Local cTipoPen := ""
    Local cTipoNF  := ""
    Local cErrMsg  := ""
    Local nRecno   := 0
    Local lOk      := .F.
    Local nOk      := 0
    Local nErr     := 0
    Local jJson    := Nil
    Local aRet     := {}
    Local cTabPai  := ""
    Local nTIni    := 0  // [TIMING] mesmo padrao ja usado em FATZZD01/FATZZF01

    Private __cBatch := "1"

    ConOut("[FATZZG01] Iniciando Cliente/Fornecedor Pendente - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    // [FIX-MEMO] Nao seleciona ZZG_JSON aqui - le via R_E_C_N_O_ + DbGoto
    // na area nativa, mais abaixo (mesmo fix aplicado em todos os outros
    // Jobs FATZZ*, ver [FIX-MEMO] em FATZZF01.prw).
    cQry := "SELECT ZZG_COD, ZZG_CHVREF, ZZG_TIPOPE, ZZG_TIPONF, R_E_C_N_O_ AS RECNO FROM " + RetSqlName("ZZG") + " "
    cQry += "WHERE ZZG_STATUS IN ('P','A') "
    cQry += "AND ZZG_FILIAL = '" + xFilial("ZZG") + "' "
    cQry += "AND D_E_L_E_T_ = ' ' "
    cQry += "ORDER BY ZZG_DTINCL, ZZG_HRINCL"

    DbUseArea(.T., "TOPCONN", TcGenQry(,, cQry), cAliZZG, .T., .T.)

    While (cAliZZG)->(!Eof())
        cCod    := AllTrim((cAliZZG)->ZZG_COD)
        cChvRef := AllTrim((cAliZZG)->ZZG_CHVREF)
        cTipoPen:= AllTrim((cAliZZG)->ZZG_TIPOPE)
        cTipoNF := AllTrim((cAliZZG)->ZZG_TIPONF)
        nRecno  := (cAliZZG)->RECNO
        cErrMsg := ""
        lOk     := .F.

        // Reposiciona na area nativa ZZG so pra ler o memo certo
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

            // Verifica se a nota (ZZG_CHVREF) esta totalmente livre de
            // pendencias - tanto de cliente/fornecedor (outras linhas da
            // ZZG, ex: nota CONVENIOS com CLI e FOR pendentes ao mesmo
            // tempo) quanto de produto (ZZF) - ver U_ZZPENDOK.
            If U_ZZPENDOK(cChvRef, cCod, "ZZG")
                cTabPai := IIF(cTipoNF == "ZZ9", "ZZ9", "ZZD")
                U_ZZ_LIBNF(cTabPai, cChvRef)
                ConOut("[FATZZG01] Nota liberada na " + cTabPai + " | Chave: " + cChvRef)

                nTIni := Seconds()
                // [TEMP-CALLBACK-OFF] Jose Carlos - Artiq - 08/2026
                // Callback intermediario de liberacao desativado - pendente
                // alinhar com iPaaS a semantica exata de
                // flg_Processamento="A". Reavaliar antes de reativar. So o
                // callback do processamento final da nota (FATZZA01/B01/
                // C01/D01/E01) continua ativo.
                // U_ZZCALLBK(cTabPai, cChvRef, "", .T., "", "", "", "Cadastro de " + IIF(cTipoPen == "CLI", "cliente", "fornecedor") + " concluido. Nota em processamento.")
                ConOut("[TIMING][FATZZG01] Callback iPaaS: " + cValToChar(Seconds() - nTIni) + "s | " + cChvRef)
            EndIf
        Else
            U_UPDSTAT("ZZG", cCod, "E", cErrMsg)
            nErr++
            ConOut("[FATZZG01] ERRO: " + cCod + " | " + Left(cErrMsg, 100))

            // [NOTIFICA-FALHA] Mesmo padrao do FATZZF01: cadastro nao pode
            // ser feito apos falha - a nota nunca vai liberar sozinha,
            // avisa o iPaaS em vez de deixar represada silenciosamente.
            cTabPai := IIF(cTipoNF == "ZZ9", "ZZ9", "ZZD")
            // [TEMP-CALLBACK-OFF] Jose Carlos - Artiq - 08/2026
            // Callback intermediario de liberacao desativado - pendente
            // alinhar com iPaaS a semantica exata de
            // flg_Processamento="A". Reavaliar antes de reativar. So o
            // callback do processamento final da nota (FATZZA01/B01/
            // C01/D01/E01) continua ativo.
            // U_ZZCALLBK(cTabPai, cChvRef, "", .F., "", "", "Cadastro de " + IIF(cTipoPen == "CLI", "cliente", "fornecedor") + " pendente falhou: " + cErrMsg)
        EndIf

        (cAliZZG)->(DbSkip())
    EndDo
    (cAliZZG)->(DbCloseArea())

    ConOut("[FATZZG01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

// ==========================================================================
// ZZG_GRV - Grava pendencia de cliente/fornecedor na fila ZZG
// [ZZG] Jose Carlos - Artiq - 08/2026
// Mesmo padrao de U_ZZF_GRV (FATZZF01.prw) - nao usa ZZX_Gravar porque
// ZZG precisa de DOIS campos extras (TIPOPEN e TIPONF), e ZZX_Gravar so
// suporta um campo extra generico (ver comentario [FIX-ZZG-GRV] em
// FATPI11.prw). Unico ponto de gravacao na ZZG, chamado pelo endpoint
// FATPI11.prw (fila de cliente/fornecedor pendente vinda do iPaaS).
// ==========================================================================
User Function ZZG_GRV(cChvRef, cTipoPen, cTipoNF, cJsonPayload)
    Local lOk  := .F.
    Local cCod := ""

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
        ZZG->(MsUnlock())
        ConfirmSx8()
        lOk := .T.
    Else
        RollBackSx8()
    EndIf
Return lOk
