#Include 'totvs.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

/*
+----------------------------------------------------------------------------+
| Autor: Jose Carlos - Artiq                                                 |
| Data: 08/2026                                                              |
| Descritivo: FATPI10 - Fila de Produtos Pendentes (ZZF)                     |
|             Endpoint: POST /fatpi10/v2                                    |
|                                                                             |
| [PROD-PENDENTE] O iPaaS agora detecta o produto faltante do lado dele e    |
|   avisa aqui, em vez do endpoint de ingestao (FATPI01_V2/FATPI08_V2/       |
|   FATPI09) checar o SB1. Payload:                                          |
|     { "tipo": "NFE"/"NFC"/"RCV", "chave": "...", "cod_Produto": [...] }    |
|   tipo NFE cobre Saida/Devolucao/Entrada (todas modelo 55) - o iPaaS nao   |
|   distingue qual das tres, entao a chave e procurada em ZZ9, ZZA, ZZB e    |
|   ZZC nessa ordem ate achar. NFC vai direto na ZZD (NFCe, modelo 65). RCV  |
|   vai direto na ZZE, onde 'chave' e o codigo do recibo (ex:                |
|   "ODT_534931"), nao uma chave de acesso.                                  |
|                                                                             |
| [ZZ9] Jose Carlos - Artiq - 08/2026                                        |
|   ZZ9 entrou na busca de NFE porque, desde a migracao pra tabela           |
|   intermediaria (ver CLAUDE.md), toda nota NFe cai primeiro na ZZ9 e so    |
|   vai pra ZZA/ZZB/ZZC depois de classificada pelo FATZZ901 - e o produto   |
|   pendente normalmente chega ANTES da classificacao (e ate impede ela:     |
|   FATZZ901 so classifica linha com ZZ9_PRDPEN='N'). ZZ9 primeiro na        |
|   ordem de busca porque e o caso comum; ZZA/ZZB/ZZC continuam na lista     |
|   pro caso raro de aviso tardio, depois de ja classificada.                |
|                                                                             |
|   O payload so traz o codigo do produto, sem descricao/preco/NCM - e nao  |
|   precisa trazer mais que isso: o cadastro em si (ZZF_CADPRD, em          |
|   FATZZF01.prw) busca os dados definitivos do produto direto na API da    |
|   CAASP por codigo, no momento do processamento pelo Job. Este endpoint   |
|   so precisa achar em qual tabela pai a chave esta (pra classificar       |
|   ZZF_TIPONF e marcar _PRDPEN='S') e gravar um item de fila por codigo.   |
|                                                                             |
|   A gravacao na ZZF em si e via U_ZZF_GRV (FATZZF01.prw - compilar antes  |
|   deste fonte, mesma regra ja valida pros outros Jobs FATZZ*).            |
+----------------------------------------------------------------------------+
*/

WSRESTFUL FATPI10_V2 DESCRIPTION 'Fila de Produtos Pendentes CAASP'
	WSMETHOD POST DESCRIPTION 'Produtos Pendentes' WSSYNTAX "/fatpi10/v2" PATH "/fatpi10/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI10_V2
	// --- 1. DECLARACAO GERAL DE VARIAVEIS ---
	Local cJson       := Self:GetContent()
	Local jJson       := JsonObject():New()
	Local jRes        := JsonObject():New()
	Local nStat       := 200
	Local cTipo       := ""
	Local cChave      := ""
	Local aCods       := {}
	Local aTabs       := {}
	Local cTabAch     := ""
	Local cTipoAch    := ""
	Local cCampChv    := ""
	Local nI          := 0
	Local cQryAux     := ""
	Local cAliAux     := ""
	Local cCodProd    := ""
	Local lJa         := .F.
	Local lGravou     := .T.
	Local nGravados   := 0

	// --- 2. PREPARACAO DE AMBIENTE ---
	// [PREPAREIN] Jose Carlos - Artiq - 08/2026
	// RpcSetEnv/RpcClearEnv removidos - nao se usa dentro de WSRESTFUL (TDN
	// oficial, "Abertura de ambiente em Web Service", a partir da 12.1.27).
	// O ambiente ja vem pronto via PREPAREIN do appserver.ini, e
	// empresa/filial resolvidos pelo header TenantId da requisicao. Chamar
	// RpcSetEnv de novo aqui conflitava com esse ambiente ja aberto - foi a
	// causa do erro visto em teste (confirmado primeiro no FATPI09). Vale
	// so pros endpoints REST; os Jobs (FATZZA01...FATZZF01) continuam
	// precisando, eles rodam via Schedule sem PREPAREIN.
	Self:SetContentType('application/json')

	If !Empty(jJson:FromJson(cJson))
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['mensagem']  := "JSON invalido ou vazio."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	// --- 3. EXTRACAO E VALIDACAO DO PAYLOAD ---
	cTipo  := Upper(AllTrim(U_PI_STR_X(jJson, 'tipo')))
	cChave := AllTrim(U_PI_STR_X(jJson, 'chave'))
	If ValType(jJson['cod_Produto']) == "A"
		aCods := jJson['cod_Produto']
	EndIf

	If Empty(cTipo) .Or. Empty(cChave) .Or. Len(aCods) == 0
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['mensagem']  := "Campos obrigatorios: tipo, chave, cod_Produto (array nao vazio)."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	If !(cTipo $ "NFE/NFC/RCV")
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Tipo"
		jRes['mensagem']  := "Tipo invalido: " + cTipo + ". Esperado NFE, NFC ou RCV."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	// --- 4. LOCALIZA A NOTA PAI (ZZ9/ZZA/ZZB/ZZC p/ NFE, ZZD p/ NFC, ZZE p/ RCV) ---
	Do Case
		Case cTipo == "NFC"
			aTabs := {{"ZZD", "CHVNFE", "NFC"}}
		Case cTipo == "RCV"
			aTabs := {{"ZZE", "CODRCB", "RCV"}}
		Otherwise // NFE - ambiguo entre Saida/Devolucao/Entrada, procura na ZZ9 primeiro (caso comum - nota ainda nao classificada), depois nas tres finais
			aTabs := {{"ZZ9", "CHVNFE", "ZZ9"}, {"ZZA", "CHVNFE", "NFS"}, {"ZZB", "CHVNFE", "NFD"}, {"ZZC", "CHVNFE", "NFE"}}
	EndCase

	For nI := 1 To Len(aTabs)
		cCampChv := aTabs[nI][1] + "_" + aTabs[nI][2]
		cQryAux := "SELECT " + cCampChv + " FROM " + RetSqlName(aTabs[nI][1]) + " WHERE " + cCampChv + " = '" + cChave + "' AND D_E_L_E_T_ = ' '"
		cAliAux := GetNextAlias()
		MpSysOpenQuery(cQryAux, cAliAux)
		If (cAliAux)->(!Eof())
			cTabAch  := aTabs[nI][1]
			cTipoAch := aTabs[nI][3]
			(cAliAux)->(DbCloseArea())
			Exit
		EndIf
		(cAliAux)->(DbCloseArea())
	Next nI

	If Empty(cTabAch)
		nStat := 404
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "NotaNaoEncontrada"
		jRes['mensagem']  := "Nenhuma nota encontrada para chave: " + cChave + " (tipo " + cTipo + ")."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	// --- 5. GRAVA UM ITEM DE FILA POR CODIGO PENDENTE (com dedup contra retry) ---
	// Nao precisa mais buscar dado de produto aqui - ZZF_CADPRD (FATZZF01)
	// busca o cadastro definitivo direto na API da CAASP por codigo quando
	// o Job processar. ZZF_JSON aqui e so rastro do que foi pedido.
	For nI := 1 To Len(aCods)
		cCodProd := AllTrim(cValToChar(aCods[nI]))

		cQryAux := "SELECT ZZF_COD FROM " + RetSqlName("ZZF") + " WHERE ZZF_CHVREF = '" + cChave + "' AND ZZF_CODLEG = '" + cCodProd + "' AND ZZF_STATUS IN ('P','A','S') AND D_E_L_E_T_ = ' '"
		cAliAux := GetNextAlias()
		MpSysOpenQuery(cQryAux, cAliAux)
		lJa := (cAliAux)->(!Eof())
		(cAliAux)->(DbCloseArea())

		If !lJa
			lGravou := U_ZZF_GRV(cChave, cTipoAch, cCodProd, '{"cod_Produto":"' + cCodProd + '","tipo":"' + cTipo + '"}') .And. lGravou
			nGravados++
		EndIf
	Next nI

	// --- 6. GARANTE PRDPEN='S' NA NOTA PAI (idempotente - ingestao ja deveria ter marcado) ---
	TCSqlExec("UPDATE " + RetSqlName(cTabAch) + " SET " + cTabAch + "_PRDPEN = 'S' WHERE " + cCampChv + " = '" + cChave + "' AND D_E_L_E_T_ = ' '")

	If lGravou
		nStat := 201
		jRes['status']    := nStat
		jRes['resultado'] := "Sucesso"
		jRes['tabela']    := cTabAch
		jRes['mensagem']  := cValToChar(nGravados) + " produto(s) pendente(s) enfileirado(s) na ZZF."
	Else
		nStat := 230  // [IPASS-FIX] Falha de sistema (grava��o na fila) - 2xx pra nao quebrar o iPaaS em transporte, distinto de 200 (falha de payload/validacao)
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "FilaMuroZ"
		jRes['mensagem']  := "Falha ao gravar produto(s) pendente(s) na ZZF."
	EndIf

	Self:setStatus(nStat)
	Self:SetResponse(EncodeUTF8(jRes:toJSON()))
	FreeObj(jJson)
	FreeObj(jRes)
Return .T.
