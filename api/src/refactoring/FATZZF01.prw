#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'

// [BOOTSTRAP] Empresa/filial padrao para o RpcSetEnv inicial do Job.
// Nao da pra usar SuperGetMv aqui � SX6/cEmpAnt ainda nao existem antes
// do primeiro RpcSetEnv (erro 'variable does not exist CFILANT'). Hardcode
// e o padrao correto nesse bootstrap; isolado em #Define para ficar facil
// de achar/trocar se o ambiente mudar.
STATIC CEMPPAD "01"
STATIC CFILPAD "01001"

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

        aRet := ZZF_CADPRD(cCodLeg)
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
            If ZZF_ALL_OK(cChvRef, cCod)
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
                ZZF_LIBNF(cTabPai, cChvRef)
                ConOut("[FATZZF01] Nota liberada na " + cTabPai + " | Chave: " + cChvRef)

                // [FIX-CALLBACK-PRODUTO] Jose Carlos - Artiq - 08/2026
                // Pedido do Arthur: mesmo endpoint oficial de Notas Fiscais na
                // liberacao de produto, nao so no processamento final. Recibo (ZZE)
                // fica no mecanismo antigo - callback oficial de Recibo ainda nao
                // existe.
                If cTabPai == "ZZE"
                    U_ZZCALLBK("ZZF", cChvRef, "ProdutosCadastrados", "Todos os produtos cadastrados. Nota liberada para processamento.")
                Else
                    U_ZZCALLBK(cTabPai, cChvRef, "", .T., "", "", "", "Produtos cadastrados. Nota em processamento.")
                EndIf
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

            If cTabPai == "ZZE"
                U_ZZCALLBK("ZZE", cChvRef, "Falha", "Produto pendente nao cadastrado: " + cErrMsg)
            Else
                U_ZZCALLBK(cTabPai, cChvRef, "", .F., "", "", "Produto pendente nao cadastrado: " + cErrMsg)
            EndIf
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
    //   3) Token Bearer vem de MV_XCPTOK (parametro SX6, mesmo padrao do
    //      MV_XIPURL usado no callback do Recibo) - precisa ser cadastrado
    //      no ambiente antes deste Job rodar. O token de teste era um JWT
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
    Local cToken    := AllTrim(SuperGetMv("MV_XCPTOK", .F., ""))
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
        cBody := HttpGet(cUrl + "?int_PaginaAtual=1&int_ItemsPorPagina=1&cod_Produto=" + AllTrim(cCodLeg), "", nTimeOut, aHeader, @cHeadRet)

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

    aRes := U_PI_PROD_X(jProd)
    If aRes[1]
        aRet := {.T., "Produto cadastrado: " + aRes[3]}
    Else
        aRet := {.F., aRes[2]}
    EndIf
    FreeObj(jResp)
Return aRet

Static Function ZZF_ALL_OK(cChvRef, cCodAtual)
    Local cAli := GetNextAlias()
    Local lRet := .F.
    Local nQtd := 0
    Local cQry := "SELECT COUNT(*) AS QTD FROM " + RetSqlName("ZZF") + " "
    cQry += "WHERE ZZF_CHVREF = '" + cChvRef + "' AND ZZF_STATUS IN ('P','A','E') "
    cQry += "AND ZZF_COD != '" + cCodAtual + "' "
    cQry += "AND D_E_L_E_T_ = ' '"
    MpSysOpenQuery(cQry, cAli)
    If (cAli)->(!Eof())
        nQtd := (cAli)->QTD
        lRet := (nQtd == 0)
    EndIf
    (cAli)->(DbCloseArea())
    ConOut("[FATZZF01] ZZF_ALL_OK | Chave: " + cChvRef + " | Pendentes (excl. atual): " + cValToChar(nQtd) + " | " + IIF(lRet, "LIBERA", "AGUARDA OUTROS ITENS"))
Return lRet

Static Function ZZF_LIBNF(cTabPai, cChvRef)
    Local cCampChv := cTabPai + "_CHVNFE"
    Local cCampPrd := cTabPai + "_PRDPEN"
    // [REV2] Recibo agora e ZZE (era ZZD) � excecao de campo-chave (CODRCB, nao CHVNFE)
    If cTabPai == "ZZE" ; cCampChv := "ZZE_CODRCB" ; EndIf
    TCSqlExec("UPDATE " + RetSqlName(cTabPai) + " SET " + cCampPrd + " = 'N' WHERE " + cCampChv + " = '" + cChvRef + "' AND D_E_L_E_T_ = ' '")
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
User Function ZZX_Gravar(cTabMuro, cProc, cCampoChave, cChvRef, cJsonPayload, cCampoExtra, cValorExtra, cPrdPend)
    Local lOk  := .F.
    Local cCod := ""

    Default cCampoExtra := ""
    Default cValorExtra := ""
    Default cPrdPend    := "N"

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
// [REV-ZZCALLBK-ARTHUR] Jose Carlos - Artiq - 08/2026
// Reescrito pra bater com a especificacao real do Arthur (doc "Retorno de
// integracao de notas CAASP"). So Notas Fiscais (ZZA/ZZB/ZZC/ZZD, que
// incluem NFCe � confirmado que usa o mesmo retorno de Nota Fiscal, ~95%
// de certeza, a confirmar 100% com o Arthur) foi implementado.
// ZZE (Recibo) mantido com o comportamento ANTIGO, intacto � vai ganhar
// tratamento proprio quando chegarem nesse ponto (provavelmente com
// funcoes especificas, conforme combinado).
// Assinaturas diferentes por tabela � cTab decide qual:
//   ZZA/ZZB/ZZC/ZZD: ZZCALLBK(cTab, cChave, cSubSeccao, lSucesso, cFilNota, cDocumento, cMsgErro, cMsgCustom)
//   ZZE:             ZZCALLBK(cTab, cChave, cResultado, cMensagem)   -- formato antigo
// [FIX-CALLBACK-PRODUTO] cMsgCustom (8o, opcional) - ver CBackNotaF abaixo.
// ==========================================================================
User Function ZZCALLBK(cTab, cChave, p3, p4, p5, p6, p7, p8)
    If cTab == "ZZE" //.Or. cTab == "ZZF"
        CBackRecib(cTab, cChave, p3, p4)
    Else
        CBackNotaF({cTab, cChave, p3, p4, p5, p6, p7, p8})
    EndIf
Return()

// ==========================================================================
// CBackNotaF � Notas Fiscais (ZZA/ZZB/ZZC/ZZD, inclui NFCe)
// Payload e URL conforme doc "Retorno de integracao de notas CAASP" do Arthur.
// des_Processamento sucesso: "Nota: [filial] - [documento]"
//   documento = numero do motor (F2_DOC/F1_DOC) para NFe, L1_NUM para NFCe
// des_Processamento erro: mensagem de erro tratada
// flg_Processamento: "S" ou "E"
// [FIX-CALLBACK-PRODUTO] Jose Carlos - Artiq - 08/2026
// Assinatura trocada de parametros posicionais para array (aDados) - o
// pedido do Arthur (chamar este mesmo endpoint oficial tambem na liberacao
// de produto pendente, nao so no processamento final) precisou de um 8o
// elemento opcional (mensagem customizada) que sobrescreve a montagem
// automatica de des_Processamento/flg_Processamento (tanto sucesso quanto
// erro). Array em vez de mais um parametro posicional pra nao estourar a
// lista de argumentos ja longa.
// ==========================================================================
Static Function CBackNotaF(aDados)
    Local aHeader     := {}
    Local cHeadRet    := ""
    Local jPayload    := JsonObject():New()
    Local cTab        := aDados[1]
    Local cChave      := aDados[2]
    Local cSubSeccao  := aDados[3]
    Local lSucesso    := aDados[4]
    Local cFilNota    := aDados[5]
    Local cDocumento  := aDados[6]
    Local cMsgErro    := aDados[7]
    Local cMsgCustom  := IIF(Len(aDados) >= 8, aDados[8], "")
    Local cUrl        := "https://api-ipaas.totvs.app/ipaas/api/v1/integrations/9aa6e2ae-1ece-4907-ba77-61c33d07bd79/api-key/6df64a64-4fc2-4b31-9c36-0958f06fcf33"

    If cSubSeccao == Nil ; cSubSeccao := "" ; EndIf
    If lSucesso   == Nil ; lSucesso   := .F. ; EndIf
    If cFilNota   == Nil ; cFilNota   := "" ; EndIf
    If cDocumento == Nil ; cDocumento := "" ; EndIf
    If cMsgErro   == Nil ; cMsgErro   := "" ; EndIf

    jPayload['cod_ChaveNFe']  := cChave
    jPayload['cod_Subseccao'] := Val(cSubSeccao)

    If !Empty(cMsgCustom)
        jPayload['des_Processamento'] := cMsgCustom
        jPayload['flg_Processamento'] := IIF(lSucesso, "S", "E")
    ElseIf lSucesso
        jPayload['des_Processamento'] := "Nota: " + AllTrim(cFilNota) + " - " + AllTrim(cDocumento)
        jPayload['flg_Processamento'] := "S"
    Else
        jPayload['des_Processamento'] := cMsgErro
        jPayload['flg_Processamento'] := "E"
    EndIf

    aAdd(aHeader, "Content-Type: application/json")
    HttpPost(cUrl, "", jPayload:toJSON(), 30, aHeader, @cHeadRet)

    If "200" $ cHeadRet .Or. "201" $ cHeadRet .Or. "204" $ cHeadRet
        ConOut("[ZZCALLBK-NF] OK: " + cTab + " | " + cChave + " | " + jPayload['flg_Processamento'])
    Else
        ConOut("[ZZCALLBK-NF] AVISO HTTP - Header resposta: " + cHeadRet + " | " + cChave)
    EndIf

    FreeObj(jPayload)
Return

// ==========================================================================
// CBackRecib � Recibo de Venda (ZZE). COMPORTAMENTO ANTIGO, intacto.
// [PENDENTE] O documento do Arthur ja especifica o formato real de Recibo
// (URL propria, payload com num_PedidoReciboVenda) mas ficou combinado de
// tratar isso quando chegarmos nesse ponto � motor ainda nao gera o numero
// de pedido/ODT necessario. Por ora, mantido o mecanismo generico anterior
// (MV_XIPURL + /protheus/callback) para nao regredir o que ja funcionava.
// ==========================================================================
Static Function CBackRecib(cTab, cChave, cResultado, cMensagem)
    Local aHeader  := {}
    Local cHeadRet := ""
    Local jPayload := JsonObject():New()
    Local cUrl     := SuperGetMv("MV_XIPURL", .F., "")

    If Empty(cUrl)
        ConOut("[ZZCALLBK-Recibo] MV_XIPURL nao configurado � callback nao enviado.")
        FreeObj(jPayload)
        Return
    EndIf

    jPayload['tabela']    := cTab
    jPayload['chave']     := cChave
    jPayload['resultado'] := cResultado
    jPayload['mensagem']  := cMensagem
    jPayload['filial']    := xFilial("SX6")
    jPayload['dtHora']    := DToS(Date()) + " " + Time()

    aAdd(aHeader, "Content-Type: application/json")
    HttpPost(cUrl + "/protheus/callback", "", jPayload:toJSON(), 30, aHeader, @cHeadRet)

    If "200" $ cHeadRet .Or. "201" $ cHeadRet .Or. "204" $ cHeadRet
        ConOut("[ZZCALLBK-Recibo] OK: " + cTab + " | " + cChave + " | " + cResultado)
    Else
        ConOut("[ZZCALLBK-Recibo] AVISO HTTP - Header resposta: " + cHeadRet + " | " + cChave)
    EndIf

    FreeObj(jPayload)
Return
