#Include 'totvs.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

// POST /fatpi11/v2 - intake de cliente/fornecedor pendente: resolve a nota pai e enfileira na ZZG

WSRESTFUL FATPI11_V2 DESCRIPTION 'Fila de Cliente/Fornecedor Pendente CAASP'
	WSMETHOD POST DESCRIPTION 'Cliente/Fornecedor Pendente' WSSYNTAX "/fatpi11/v2" PATH "/fatpi11/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI11_V2
	Local cJson       := Self:GetContent()
	Local jJson       := JsonObject():New()
	Local jRes        := JsonObject():New()
	Local jDados      := Nil
	Local nStat       := 200
	Local cTipoNF     := ""
	Local cChave      := ""
	Local cTipoPen    := ""
	Local cTabAch     := ""
	Local cCampChv    := ""
	Local cQryAux     := ""
	Local cAliAux     := ""
	Local lJa         := .F.
	Local lGravou     := .F.
	Local cCampPen    := ""

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

	cTipoNF  := Upper(AllTrim(U_PI_STR_X(jJson, 'tipo')))
	cChave   := AllTrim(U_PI_STR_X(jJson, 'chave'))
	cTipoPen := Upper(AllTrim(U_PI_STR_X(jJson, 'tp_Participante')))
	jDados   := jJson['dados']

	If Empty(cTipoNF) .Or. Empty(cChave) .Or. Empty(cTipoPen) .Or. (ValType(jDados) != "J" .And. ValType(jDados) != "O")
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['mensagem']  := "Campos obrigatorios: tipo (ZZ9/NFC), chave, tp_Participante (CLI/FOR), dados (objeto)."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	If !(cTipoNF $ "ZZ9/NFE/NFC")
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Tipo"
		jRes['mensagem']  := "tipo invalido: " + cTipoNF + ". Esperado ZZ9, NFE ou NFC."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	If cTipoNF == "NFE"
		cTipoNF := "ZZ9"
	EndIf

	If !(cTipoPen $ "CLI/FOR")
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "TipoParticipante"
		jRes['mensagem']  := "tp_Participante invalido: " + cTipoPen + ". Esperado CLI ou FOR."
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf

	cTabAch  := IIF(cTipoNF == "NFC", "ZZD", "ZZ9")
	cCampChv := cTabAch + "_CHVNFE"

	cQryAux := "SELECT " + cCampChv + " FROM " + RetSqlName(cTabAch) + " WHERE " + cCampChv + " = '" + cChave + "' AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	If (cAliAux)->(Eof())
		(cAliAux)->(DbCloseArea())
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "NotaNaoEncontrada"
		jRes['mensagem']  := "Nota nao encontrada na " + cTabAch + " para chave: " + cChave
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		Return .T.
	EndIf
	(cAliAux)->(DbCloseArea())

	cQryAux := "SELECT ZZG_COD FROM " + RetSqlName("ZZG") + " WHERE ZZG_CHVREF = '" + cChave + "' AND ZZG_TIPOPE = '" + cTipoPen + "' AND ZZG_STATUS IN ('P','A','S') AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	lJa := (cAliAux)->(!Eof())
	(cAliAux)->(DbCloseArea())

	If !lJa
		lGravou := U_ZZG_GRV(cChave, cTipoPen, cTipoNF, jDados:toJSON())
	Else
		lGravou := .T.
	EndIf

	cCampPen := IIF(cTipoPen == "CLI", cTabAch + "_CLIPEN", cTabAch + "_FORPEN")
	TCSqlExec("UPDATE " + RetSqlName(cTabAch) + " SET " + cCampPen + " = 'S' WHERE " + cCampChv + " = '" + cChave + "' AND D_E_L_E_T_ = ' '")

	If lGravou
		nStat := 201
		jRes['status']    := nStat
		jRes['resultado'] := "Sucesso"
		jRes['tabela']    := cTabAch
		jRes['mensagem']  := IIF(cTipoPen == "CLI", "Cliente", "Fornecedor") + " pendente enfileirado na ZZG."
	Else
		nStat := 230
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "FilaMuroZ"
		jRes['mensagem']  := "Falha ao gravar pendencia na ZZG."
	EndIf

	Self:setStatus(nStat)
	Self:SetResponse(EncodeUTF8(jRes:toJSON()))
	FreeObj(jJson)
	FreeObj(jRes)
Return .T.
