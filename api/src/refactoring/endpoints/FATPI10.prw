#Include 'totvs.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

// POST /fatpi10/v2 - intake de produto pendente: resolve a nota pai e enfileira cada codigo na ZZF

WSRESTFUL FATPI10_V2 DESCRIPTION 'Fila de Produtos Pendentes CAASP'
	WSMETHOD POST DESCRIPTION 'Produtos Pendentes' WSSYNTAX "/fatpi10/v2" PATH "/fatpi10/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI10_V2
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

	Do Case
		Case cTipo == "NFC"
			aTabs := {{"ZZD", "CHVNFE", "NFC"}}
		Case cTipo == "RCV"
			aTabs := {{"ZZE", "CODRCB", "RCV"}}
		Otherwise
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

	TCSqlExec("UPDATE " + RetSqlName(cTabAch) + " SET " + cTabAch + "_PRDPEN = 'S' WHERE " + cCampChv + " = '" + cChave + "' AND D_E_L_E_T_ = ' '")

	If lGravou
		nStat := 201
		jRes['status']    := nStat
		jRes['resultado'] := "Sucesso"
		jRes['tabela']    := cTabAch
		jRes['mensagem']  := cValToChar(nGravados) + " produto(s) pendente(s) enfileirado(s) na ZZF."
	Else
		nStat := 230
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
