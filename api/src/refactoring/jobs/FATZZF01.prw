#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

// [BOOTSTRAP] Empresa/filial padrao para o RpcSetEnv inicial do Job.
// Nao da pra usar SuperGetMv aqui � SX6/cEmpAnt ainda nao existem antes
// do primeiro RpcSetEnv (erro 'variable does not exist CFILANT'). Hardcode
// e o padrao correto nesse bootstrap; isolado em #Define para ficar facil
// de achar/trocar se o ambiente mudar.
STATIC CEMPPAD := "01"
STATIC CFILPAD := "01001"

/*
+----------------------------------------------------------------------------+
| Autor: Jose Carlos - Artiq                                                 |
| Data: 07/2026                                                              |
| Descritivo: FATZZF01 - Job Schedule - Fila ZZF (Produtos Pendentes)      |
|             Para cada produto pendente: chama FATPI02 para cadastro SB1   |
|             Ao concluir todos os produtos de uma chave ZZF_CHVREF:        |
|               Atualiza PRDPEND = 'N' na tabela Muro pai (ZZA/ZZB/ZZC/ZZD/ |
|               ZZE) e libera a nota para processamento                     |
| [REV2] Jose Carlos - Artiq - 07/2026                                       |
|   Era FATZZE01 (fila ZZE). Deslizou uma letra: Devolucao ganhou fila      |
|   propria (ZZB), empurrando Entrada->ZZC, NFCe->ZZD, Recibo->ZZE,        |
|   Produtos->ZZF. Do Case de roteamento (NFS/NFD/NFE/NFC/RCV) e a          |
|   excecao de campo-chave do Recibo em LiberaNota foram atualizados.       |
|   ESTE JOB PRECISA COMPILAR PRIMEIRO ENTRE OS FATZZ* � contem UPDSTAT|
|   e ZZCALLBK, usadas por todos os outros Jobs.                        |
+----------------------------------------------------------------------------+
*/

User Function FATZZF01()
    Local cAliZZF  := GetNextAlias()
    Local cQry     := ""
    Local cCod     := ""
//  Local nRecno   := 0
//  Local cJson    := ""
    Local cChvRef  := ""
    Local cTipoNF  := ""
    Local cCodLeg  := ""
    Local cErrMsg  := ""
    Local lOk      := .F.
    Local nOk      := 0
    Local nErr     := 0
//  Local jJson    := Nil
    Local aRet     := {}
    Local cTabPai  := ""
    // [TIMING] Jose Carlos - Artiq - 08/2026 - instrumentacao temporaria,
    // ver mesma nota em FATZZD01.prw - tirar depois de ter os numeros.
    Local nTIni    := 0

    Private __cBatch := "1"

    ConOut("[FATZZF01] Iniciando Produtos Pendentes - " + DToS(Date()) + " " + Time())

    RpcSetEnv(CEMPPAD, CFILPAD, Nil, Nil, "FAT")

    // [PROD-PENDENTE] ZZF_JSON nao e mais lida/usada aqui - o cadastro agora
    // busca o produto definitivo direto na API da CAASP por ZZF_CODLEG (ver
    // ZZF_CADPRD mais abaixo), entao nao precisa mais reabrir a area nativa
    // so pra ler o memo (o motivo original do [FIX-MEMO] deixou de existir).
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

            // Verifica se todos os produtos desta chave estao prontos
            // [FIX-VISIBILIDADE] Jose Carlos - Artiq - 08/2026
            // Passa cCod para excluir o registro atual da contagem � ja
            // sabemos que ele teve sucesso, nao precisa confiar numa
            // releitura via outra conexao/query que pode nao enxergar o
            // UPDATE que acabou de commitar (U_UPDSTAT e este SELECT
            // usam mecanismos de leitura diferentes: TCSqlExec vs MpSysOpenQuery).
            If U_ZZPENDOK(cChvRef, cCod, "ZZF")
                // [REV2] Mapeamento atualizado: NFS=ZZA / NFD=ZZB / NFE=ZZC / NFC=ZZD / RCV=ZZE
                // [ZZ9] ZZ9 - nota NFe ainda nao classificada pelo FATZZ901 quando o
                // produto pendente foi avisado (caso comum, ver FATPI10.prw)
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

                // [FIX-CALLBACK-PRODUTO] Jose Carlos - Artiq - 08/2026
                // Pedido do Arthur: mesmo endpoint oficial de Notas Fiscais na
                // liberacao de produto, nao so no processamento final.
                // [REV-ZZCALLBK-UNIFICADO] Jose Carlos - Artiq - 08/2026
                // Recibo (ZZE) agora usa o mesmo callback unificado das Notas
                // Fiscais (ver ZZCALLBK/CBackIpaas) - so a mensagem customizada
                // continua distinta por dominio. cTab corrigido de "ZZF" pra
                // "ZZE" (a fila "ZZF" nunca foi um dominio de callback de
                // verdade - era so um resquicio do dispatch antigo).
                nTIni := Seconds()
                // [TEMP-CALLBACK-OFF] Jose Carlos - Artiq - 08/2026
                // Callback intermediario de liberacao desativado - pendente
                // alinhar com Arthur a semantica exata de
                // flg_Processamento="A". Reavaliar antes de reativar. So o
                // callback do processamento final da nota (FATZZA01/B01/
                // C01/D01/E01) continua ativo.
                // If cTabPai == "ZZE"
                //     U_ZZCALLBK("ZZE", cChvRef, "", .T., "", "", "", "Todos os produtos cadastrados. Nota liberada para processamento.")
                // Else
                //     U_ZZCALLBK(cTabPai, cChvRef, "", .T., "", "", "", "Produtos cadastrados. Nota em processamento.")
                // EndIf
                ConOut("[TIMING][FATZZF01] Callback iPaaS: " + cValToChar(Seconds() - nTIni) + "s | " + cChvRef)
            EndIf
        Else
            U_UPDSTAT("ZZF", cCod, "E", cErrMsg)
            nErr++
            ConOut("[FATZZF01] ERRO produto: " + cCodLeg + " | " + Left(cErrMsg, 100))

            // [NOTIFICA-FALHA] Jose Carlos - Artiq - 08/2026
            // Produto nao pode ser cadastrado apos esgotar o retry - a nota
            // nunca vai liberar sozinha, avisa o Arthur em vez de deixar
            // represada silenciosamente. cod_Subseccao vai vazio (decisao
            // consciente - o payload de aviso de produto pendente nao traz
            // esse dado, e nao vale reabrir a nota pai so pra buscar).
            Do Case
                Case cTipoNF == "ZZ9" ; cTabPai := "ZZ9"
                Case cTipoNF == "NFS" ; cTabPai := "ZZA"
                Case cTipoNF == "NFD" ; cTabPai := "ZZB"
                Case cTipoNF == "NFE" ; cTabPai := "ZZC"
                Case cTipoNF == "NFC" ; cTabPai := "ZZD"
                Case cTipoNF == "RCV" ; cTabPai := "ZZE"
                Otherwise              ; cTabPai := "ZZA"
            EndCase

            // [REV-ZZCALLBK-UNIFICADO] Mensagem ja era identica nos dois
            // ramos - colapsado numa chamada so, sem Do Case.
            nTIni := Seconds()
            // [TEMP-CALLBACK-OFF] Jose Carlos - Artiq - 08/2026
            // Callback intermediario de liberacao desativado - pendente
            // alinhar com Arthur a semantica exata de
            // flg_Processamento="A". Reavaliar antes de reativar. So o
            // callback do processamento final da nota (FATZZA01/B01/
            // C01/D01/E01) continua ativo.
            // U_ZZCALLBK(cTabPai, cChvRef, "", .F., "", "", "Produto pendente nao cadastrado: " + cErrMsg)
            ConOut("[TIMING][FATZZF01] Callback iPaaS (erro): " + cValToChar(Seconds() - nTIni) + "s | " + cChvRef)
        EndIf

        (cAliZZF)->(DbSkip())
    EndDo
    (cAliZZF)->(DbCloseArea())

    ConOut("[FATZZF01] Fim. OK: " + cValToChar(nOk) + " | Erro: " + cValToChar(nErr))
    RpcClearEnv()
Return

Static Function ZZF_CADPRD(cCodLeg)
    // [FIX-EXTRACAO] Jose Carlos - Artiq - 08/2026
    // Chamava U_FATPI02_PROC, que nunca existiu (suposicao incorreta, nao
    // conferida contra o fonte real na epoca). O FATPI02.prw foi refatorado
    // e a logica de upsert de produto extraida para U_PI_PROD_X (nome com
    // 10 caracteres � o nome anterior tinha 14, estourava o limite do
    // AdvPL). Retorno agora e sempre array {lOk, cMensagem, cCodProtheus},
    // entao a checagem defensiva de tipo (Array/Objeto) nao e mais necessaria.
    //
    // [PROD-PENDENTE] Jose Carlos - Artiq - 08/2026
    // Antes montava o produto a partir do item da nota (nomenclatura fiscal
    // - cod_Produto/des_ProdutoNCM/nom_Produto/vlr_Produto - mapeada "no
    // achismo" pra nomenclatura de produto). Agora busca o cadastro
    // definitivo direto na API da CAASP por cod_Produto (legado), que ja
    // devolve exatamente os campos que U_PI_PROD_X espera (cod, descricao,
    // tipo_Produto, grupo, origem, unidade, armazem, pos_IPI_NCM,
    // preco_Venda, des_ProdutoCEST, cod_ProdutoEAN, cod_ContaContabil,
    // peso) - sem mapeamento manual nenhum.
    //
    // ATENCAO - pontos assumidos que precisam de confirmacao/teste real:
    //   1) [CONFIRMADO 08/2026] A classe FWHTTPClient inteira nao esta
    //      disponivel nesta build - nem :AddHeader nem :SetHeader existem
    //      em runtime (os dois testados, os dois com "Cannot find method").
    //      Trocado por completo pelas funcoes nativas HttpGet/HttpPost
    //      (TDN oficial), testado com sucesso aqui com o produto
    //      02.139948. Mesma troca aplicada em CBackNotaF/CBackRecib mais
    //      abaixo. Nenhuma das duas funcoes devolve status code numerico -
    //      sucesso e inferido checando o cHeadRet (cabecalho de resposta,
    //      preenchido por referencia) por substring do codigo HTTP.
    //   2) Query string testada pelo Jose Carlos via curl (funciona hoje):
    //      int_PaginaAtual=1&int_ItemsPorPagina=1&cod_Produto=<codigo>
    //      (reparar: "int_ItemsPorPagina" na query, mas a resposta JSON
    //      vem com "int_ItensPorPagina" - grafias diferentes, mantido
    //      literal do que foi testado, nao "corrigido").
    //   3) Token Bearer vem de MV_XCPTOK (parametro SX6) - precisa ser
    //      cadastrado no ambiente antes deste Job rodar. O token de teste era um JWT
    //      com exp de 1h nos claims, mas continuou validando ~8h depois -
    //      aparentemente o exp nao e checado pelo servidor na pratica,
    //      mas isso pode mudar; se a API comecar a devolver 401, e sinal
    //      de token vencido/revogado e o MV_XCPTOK precisa ser atualizado.
    //
    // [RETRY-CAASP] Jose Carlos - Artiq - 08/2026
    // API da CAASP e instavel (confirmado com o Arthur) - so a chamada HTTP
    // reentra (rede/HTTP), nunca o "produto nao encontrado" (items vazio):
    // isso e resultado definitivo, nao instabilidade, retry nao ajuda nesse
    // caso. MV_XCPRET = tentativas adicionais (default 5, "0" desativa).
    // MV_XCPWAIT = segundos de espera entre tentativas (default 2).
    Local aRet      := {.F., ""}
    Local aRes      := {}
    Local aHeader   := {}
    Local cUrl      := "https://api.caasp.org.br/integracoes/totvs/produtos/listar"
    // [FIX-TOKEN-TAMANHO] Jose Carlos - Artiq - 08/2026
    // Token JWT hardcoded como fallback default de MV_XCPTOK - decisao
    // temporaria e consciente, nao descuido: o campo X6_CONTEUD do SX6 nao
    // comporta o tamanho do JWT (excede o limite do parametro). Jose
    // Carlos vai alinhar com o time de arquitetura uma solucao definitiva
    // (provavelmente uma tabela em vez de SX6) - ate la, mantido assim.
    // Continua puxando MV_XCPTOK primeiro; o literal aqui so entra em jogo
    // se o parametro estiver vazio/nao cadastrado.
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
    Local nTIni     := 0  // [TIMING] instrumentacao temporaria, ver FATZZF01()

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

    // [FIX-FINDFUNCTION] Jose Carlos - Artiq - 08/2026
    // Type() checa TIPO DE VARIAVEL, nao existencia de FUNCAO � provavelmente
    // sempre retornava "U" aqui, travando a chamada de verdade sempre,
    // independente de PI_PROD_X estar compilada ou nao. FindFunction() e a
    // forma correta (retorna .T. se a funcao existe no repositorio atual).
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

// ==========================================================================
// ZZPENDOK — checa se uma nota (cChvRef) esta totalmente livre de
// pendencias, olhando as DUAS filas de pendencia (ZZF/produto e
// ZZG/cliente-fornecedor), nao so a que acabou de terminar.
// [ZZG] Jose Carlos - Artiq - 08/2026
// Promovida de Static (ZZF_ALL_OK, so olhava ZZF) pra User Function -
// FATZZG01.prw (lote de compilacao separado) precisa chamar isso tambem,
// mesma razao de sempre (Static Function nao atravessa lote). Uma nota
// pode ter produto pendente resolvido mas cliente/fornecedor nao, e
// vice-versa - so libera quando as duas filas estao zeradas pra aquela
// chave (ver Parte 5 da instrucao_zzg_cliente_fornecedor.md).
// cTabAtual ("ZZF" ou "ZZG") indica qual fila o chamador acabou de
// atualizar - so essa fila usa cCodAtual pra excluir o proprio registro
// da contagem (mesmo motivo do [FIX-VISIBILIDADE] original: nao confiar
// numa releitura via MpSysOpenQuery que pode nao enxergar um UPDATE que
// acabou de commitar via TCSqlExec). A OUTRA fila e checada sem exclusao -
// nao ha risco de leitura-stale nela, ja que nenhum UPDATE acabou de
// rodar la nesta mesma chamada.
// ==========================================================================
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

// ==========================================================================
// ZZ_LIBNF — libera a nota pai, zerando PRDPEN sempre e CLIPEN/FORPEN
// quando a tabela tiver esses campos (ZZ9/ZZD - ver Parte 5 da
// instrucao_zzg_cliente_fornecedor.md; ZZA/ZZB/ZZC/ZZE nao tem esses
// campos, o FieldPos guarda contra isso).
// [ZZG] Jose Carlos - Artiq - 08/2026
// Promovida de Static (ZZF_LIBNF, so zerava PRDPEN) pra User Function -
// FATZZG01.prw tambem precisa chamar isso.
// ==========================================================================
User Function ZZ_LIBNF(cTabPai, cChvRef)
    Local cCampChv := cTabPai + "_CHVNFE"
    Local cSql     := ""
    // [REV2] Recibo agora e ZZE (era ZZD) � excecao de campo-chave (CODRCB, nao CHVNFE)
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

// ==========================================================================
// FUNCOES COMPARTILHADAS � usadas por todos os Jobs FATZZ*
// Publicadas como User Function para serem acessiveis entre fontes.
// Este arquivo (FATZZF01) precisa compilar ANTES dos demais Jobs FATZZ*.
// ==========================================================================

User Function UPDSTAT(cTab, cCod, cStatus, cMsg)
    Local cCampCod := cTab + "_COD"
    Local cCampSts := cTab + "_STATUS"
    Local cCampMsg := cTab + "_ERRMSG"
    Local cCampDtP := cTab + "_DTPROC"
    Local cCampHrP := cTab + "_HRPROC"
    Local cQry     := ""
    Local nRet     := 0

    cQry := "UPDATE " + RetSqlName(cTab) + " SET " + cCampSts + " = '" + cStatus + "'"
    // [FIX-ZZF-DTPROC] Jose Carlos - Artiq - 08/2026
    // ZZF nao tem _DTPROC/_HRPROC (estrutura diferente de ZZA-ZZE � nao tem
    // "processamento pelo Job" no mesmo sentido, so cadastro de produto).
    // Gravar essas colunas pra ZZF fazia o UPDATE inteiro falhar (coluna
    // inexistente), silenciosamente, porque o retorno do TCSqlExec nunca
    // era checado � status ficava travado no ultimo valor valido ('A').
    If cStatus == "S" .And. cTab != "ZZF"
        cQry += ", " + cCampDtP + " = '" + DToS(Date()) + "'"
        cQry += ", " + cCampHrP + " = '" + Time() + "'"
    EndIf
    If !Empty(cMsg)
        cQry += ", " + cCampMsg + " = '" + StrTran(Left(cMsg, 2000), "'", "''") + "'"
    EndIf
    cQry += " WHERE " + cCampCod + " = '" + cCod + "' AND D_E_L_E_T_ = ' '"

    nRet := TCSqlExec(cQry)
    ConOut("[UPDSTAT] Tab: " + cTab + " | Cod: " + cCod + " | Status: " + cStatus + " | TCSqlExec retorno: " + cValToChar(nRet))
Return

// ==========================================================================
// ZZF_GRV � Grava produto pendente na fila ZZF
// [PROD-PENDENTE] Jose Carlos - Artiq - 08/2026
// Promovida a User Function compartilhada (antes era Static Function
// duplicada em FATPI09.prw, orfa depois que a checagem de produto saiu do
// endpoint). Agora e o unico ponto de gravacao na ZZF, chamado pelo novo
// endpoint FATPI10 (fila de produtos pendentes vinda do iPaaS).
// Estrutura conforme ja consumida por FATZZF01 acima: ZZF_CHVREF + ZZF_TIPONF
// identificam a nota pai (mesma chave usada em ZZA/ZZB/ZZC/ZZD_CHVNFE ou
// ZZE_CODRCB), ZZF_CODLEG e o codigo legado do produto que falta cadastrar.
// cJsonPayload e o item completo da nota (mesmo formato que ZZF_CADPRD
// espera para chamar U_PI_PROD_X).
// ==========================================================================
User Function ZZF_GRV(cChvRef, cTipoNF, cCodLeg, cJsonPayload)
    Local lOk  := .F.
    Local cCod := ""

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
        ZZF->(MsUnlock())
        ConfirmSx8()
        lOk := .T.
    Else
        RollBackSx8()
    EndIf
Return lOk

// ==========================================================================
// ZZX_Gravar Grava registro generico na tabela Muro Z
// [ZZ9] Jose Carlos - Artiq - 08/2026
// Movida de FATPI01_V2.prw pra ca e promovida de Static para User Function
// (mesmo motivo de sempre: FATZZ901.prw, lote de compilacao separado,
// precisa chamar isso pra gravar bruto na ZZ9 e depois, ja classificada,
// gravar em ZZA/ZZB/ZZC). Ganhou o parametro cPrdPend (a copia antiga em
// FATPI01_V2.prw nunca tinha recebido essa extensao - hardcoded "N" -
// diferente das copias de FATPI08_V2.prw/FATPI09.prw, que ja tinham).
// [ZZ9-SEM-PROC] A tabela ZZ9 nao tem campo _PROC (diferente de ZZA-ZZE) -
// FieldPut de _PROC agora e condicional a FieldPos > 0, senao quebraria
// pra ZZ9. Chamar com cProc := "" pra ZZ9 (valor ignorado de qualquer jeito).
// Parametrizada por cCampoChave (antes fixava "_CHVNFE") para suportar
// ZZA/ZZB/ZZC/ZZD (campo _CHVNFE) e ZZE - Recibo (campo _CODRCB) e ZZ9.
// cCampoExtra/cValorExtra: opcional - campo adicional generico (ex:
// ZZA_TRANSF).
// ==========================================================================
User Function ZZX_Gravar(cTabMuro, cProc, cCampoChave, cChvRef, cJsonPayload, cCampoExtra, cValorExtra, cPrdPend, cQtProd)
    Local lOk  := .F.
    Local cCod := ""

    Default cCampoExtra := ""
    Default cValorExtra := ""
    Default cPrdPend    := "N"
    Default cQtProd     := ""

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
        // [FIX-CLIFOR-BRANCO] Jose Carlos - Artiq - 08/2026
        // ZZ9_CLIPEN/ZZ9_FORPEN ficavam em branco num registro novo (RecLock
        // nao aplica o default do SIGACFG num INCLUI feito assim, fora de
        // MVC) - a query dos Jobs (FATZZ901.prw/FATZZD01.prw) filtra por
        // "= 'N'" literal, entao branco nunca batia e a nota ficava presa
        // pra sempre. So ZZ9/ZZD tem esses campos - guarda FieldPos (as
        // demais tabelas nao tem).
        If FieldPos(cTabMuro + "_CLIPEN") > 0
            (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_CLIPEN"), "N"))
        EndIf
        If FieldPos(cTabMuro + "_FORPEN") > 0
            (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_FORPEN"), "N"))
        EndIf
        // [QTPROD] Jose Carlos - Artiq - 08/2026 - parametro dedicado (nao
        // cCampoExtra/cValorExtra) porque QTPROD e universal as 6 tabelas de
        // nota, enquanto cCampoExtra ja esta ocupado por campo especifico em
        // pelo menos um call site (ZZA/TRANSF, ver ZZ901_Classifica em
        // FATZZ901.prw) - mesmo raciocinio ja usado pra cPrdPend. Guarda
        // FieldPos por seguranca, ainda que hoje o campo exista nas 6.
        // Campo numerico (N) no SIGACFG - Val() no texto vindo do JSON, nao
        // FieldPut direto (confirmado com Jose Carlos, ver instrucao_qtprod.md).
        If FieldPos(cTabMuro + "_QTPROD") > 0
            (cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_QTPROD"), Val(cQtProd)))
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

// ==========================================================================
// BUSCACAD valida existencia de CEST (F0G)/NCM (SYD) no cadastro fiscal
// [MOTOR-FATURAMENTO] Jose Carlos - Artiq - 08/2026
// Promovida a User Function compartilhada (era Static Function BuscaCad em
// FATPI01U.prw, so visivel naquele arquivo/lote de compilacao). Agora
// chamada tanto por FATZZD01.prw (motor de NFCe, migrado pra U_PI_SAIDA_X)
// quanto por FATZZ901.prw (classificacao NFe) - mesmo motivo de sempre:
// Static Function nao atravessa lote de compilacao diferente. A copia
// original em FATPI01U.prw fica intacta por ora (decisao do Antonio, que
// mexe naquele arquivo separadamente).
// nOpc: 1 = CEST (F0G), 2 = NCM (SYD).
// ==========================================================================
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

// ==========================================================================
// ZZCALLBK roteador
// [REV-ZZCALLBK-UNIFICADO] Jose Carlos - Artiq - 08/2026
// Notas Fiscais (ZZ9/ZZA/ZZB/ZZC/ZZD, inclui NFCe) e Recibo (ZZE) agora
// compartilham o MESMO formato de payload (cod_Subseccao/des_Processamento/
// flg_Processamento), conforme os dois docs do Arthur ("Notas Fiscais (01)"
// e "Recibos de Venda (08)") - so mudam a URL do endpoint iPaaS e o nome do
// campo-chave (cod_ChaveNFe pra Nota Fiscal, num_PedidoReciboVenda pra
// Recibo). Antes o Recibo usava um mecanismo generico a parte (MV_XIPURL +
// /protheus/callback, formato tabela/chave/resultado/mensagem) - substituido
// pela mesma funcao CBackIpaas usada pelas Notas Fiscais. Assinatura unica
// pra todos os dominios:
//   ZZCALLBK(cTab, cChave, cSubSeccao, lSucesso, cFilNota, cDocumento, cMsgErro, cMsgCustom)
// cMsgCustom (8o, opcional) sobrescreve a montagem automatica de
// des_Processamento/flg_Processamento - usado na liberacao de produto
// pendente (mensagem "em processamento", ver FATZZF01 mais acima) e pelo
// Recibo (que ja recebe a mensagem pronta de U_FATPI08NF, formato "Nota
// Varejo Processada: [filial] - [documento]" - nao ha cFilNota/cDocumento
// separados nesse caminho).
// ==========================================================================
User Function ZZCALLBK(cTab, cChave, cSubSeccao, lSucesso, cFilNota, cDocumento, cMsgErro, cMsgCustom)
    Local cUrl        := ""
    Local cCampoChave := ""
    Local cMsgPad     := ""

    Do Case
        Case cTab == "ZZE"
            cUrl        := "https://api-ipaas.totvs.app/ipaas/api/v1/integrations/2246e04c-65ec-4b83-b298-f8ec1643420c/api-key/67e28815-d2ff-4501-9f2f-e99271e6a3d7"
            cCampoChave := "num_PedidoReciboVenda"
            cMsgPad     := "Nota Varejo Processada"
        Otherwise
            cUrl        := "https://api-ipaas.totvs.app/ipaas/api/v1/integrations/9aa6e2ae-1ece-4907-ba77-61c33d07bd79/api-key/6df64a64-4fc2-4b31-9c36-0958f06fcf33"
            cCampoChave := "cod_ChaveNFe"
            cMsgPad     := "Nota"
    EndCase

    CBackIpaas(cUrl, cCampoChave, cMsgPad, cTab, cChave, cSubSeccao, lSucesso, cFilNota, cDocumento, cMsgErro, cMsgCustom)
Return()

// ==========================================================================
// CBackIpaas � envia o callback de processamento pro iPaaS. Unifica o que
// antes eram CBackNotaF (Notas Fiscais) e CBackRecib (Recibo, mecanismo
// generico antigo via MV_XIPURL) - ver ZZCALLBK acima pra roteamento por
// dominio (URL/campo-chave/prefixo de mensagem).
// Payload conforme docs do Arthur ("Notas Fiscais (01)" e "Recibos de Venda
// (08)"): { <cCampoChave>: cChave, cod_Subseccao: n, des_Processamento: "...",
// flg_Processamento: "S"/"E" }
// des_Processamento sucesso: "<cMsgPad>: [filial] - [documento]"
//   documento = numero do motor (F2_DOC/F1_DOC) para NFe, L1_NUM para NFCe;
//   pro Recibo, U_FATPI08NF ja devolve a mensagem pronta nesse formato -
//   chega aqui via cMsgCustom, nao via cFilNota/cDocumento separados.
// des_Processamento erro: mensagem de erro tratada (cMsgErro)
// flg_Processamento: Protheus so envia "S" ou "E" aqui - os valores "P"
//   (produto pendente) e "A" (nota em andamento) do doc do Arthur sao
//   setados do lado do iPaaS, no armazenamento do proprio iPaaS.
// ==========================================================================
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
