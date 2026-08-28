#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

// POST /fatpi09/v2 - endpoint NFCe (modelo 65): valida/dedupe/enfileira o payload na ZZD

WSRESTFUL FATPI09_V2 DESCRIPTION 'NFCe - Venda ao Consumidor CAASP'
	WSMETHOD POST DESCRIPTION 'Processamento NFCe' WSSYNTAX "/fatpi09/v2" PATH "/fatpi09/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI09_V2
	Local lRet         := .T.
	Local cJson        := Self:GetContent()
	Local jJson        := JsonObject():New()
	Local jRes         := JsonObject():New()
	Local nStat        := 200
	Local cModDoc      := ""
	Local aInv         := {}
	Local oHead        := Nil
	Local aPrd         := {}
	Local aEmp         := {}
	Local cCnpj        := ""
	Local cChvNFe      := ""
	Local cQryAux      := ""
	Local cAliAux      := ""
	Local cProdPend    := ""

	Local cCheckCFOP   := ""
	Local cNatOp       := ""

	Local cOldRestNfe  := ""
	Local cStatusFila  := ""
	Local cErrMsgFila  := ""
	Local cIdIpaas     := ""

	Private __cBatch    := "1"
	Private __cXEvento  := "LOJ"

	cOldRestNfe := SuperGetMv("MV_RESTNFE", .F., "S")
	PutMv("MV_RESTNFE", "N")

	Self:SetContentType('application/json')

	If !Empty(jJson:FromJson(cJson))
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['detalhe']   := "Estrutura JSON"
		jRes['mensagem']  := "JSON invalido ou vazio."

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf

	aInv := jJson['notas']
	If ValType(aInv) != "A"
		aInv := jJson['items']
	EndIf

	If ValType(aInv) != "A" .Or. Len(aInv) == 0
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['mensagem']  := "Array 'notas' ausente ou vazio."

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf

	oHead   := aInv[1]
	cModDoc := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')
	aPrd    := oHead['itens']
	cNatOp  := Upper(AllTrim(U_PI_STR_X(oHead, 'des_NatOp')))
	cChvNFe := AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe'))

	cProdPend := AllTrim(U_PI_STR_X(jJson, 'prod_Pendente'))
	If Empty(cProdPend) ; cProdPend := "N" ; EndIf

	cIdIpaas := AllTrim(U_PI_STR_X(oHead, 'id_Ipaas')) // id do envelope iPaaS, cabecalho ou raiz
	If Empty(cIdIpaas) ; cIdIpaas := AllTrim(U_PI_STR_X(jJson, 'id_Ipaas')) ; EndIf

	If cModDoc != "65"
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "ModeloIncorreto"
		jRes['mensagem']  := "FATPI09 aceita apenas NFCe (modelo 65). Documento recebido: modelo " + cModDoc + ". Envie para /fatpi01/v2."

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf

	If ValType(aPrd) == "A" .And. Len(aPrd) > 0
		cCheckCFOP := Upper(U_PI_STR_X(aPrd[1], 'cod_ProdutoCFOP', 'cfop'))
	EndIf

	cCnpj := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ', 'num_SubseccaoCNPJ'))
	aEmp  := U_PI_FILIAL_X(cCnpj)

	If Len(aEmp) < 2
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Filial"
		jRes['detalhe']   := cCnpj
		jRes['mensagem']  := "Filial nao encontrada para CNPJ: " + AllTrim(cCnpj)

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf

	cQryAux := "SELECT ZZD_STATUS, ZZD_ERRMSG FROM " + RetSqlName("ZZD") + " WHERE ZZD_CHVNFE = '" + cChvNFe + "' AND ZZD_FILIAL = '" + xFilial("ZZD") + "' AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	If (cAliAux)->(!Eof())
		cStatusFila := AllTrim((cAliAux)->ZZD_STATUS)
		cErrMsgFila := AllTrim((cAliAux)->ZZD_ERRMSG)
		(cAliAux)->(DbCloseArea())

		nStat := 200
		jRes['status']     := nStat
		jRes['resultado']  := "Sucesso"
		jRes['doc']        := "Nota: " + aEmp[2] + " - " + cChvNFe
		jRes['statusFila'] := cStatusFila
		Do Case
			Case cStatusFila == "P"
				jRes['info'] := "NFCe ja recebida, aguardando processamento na fila."
			Case cStatusFila == "A"
				jRes['info'] := "NFCe ja recebida, em processamento no momento."
			Case cStatusFila == "S"
				jRes['info'] := "NFCe ja processada com sucesso anteriormente."
			Case cStatusFila == "E"
				jRes['info'] := "NFCe ja recebida, mas o processamento anterior falhou: " + IIF(Empty(cErrMsgFila), "(sem detalhe registrado)", cErrMsgFila)
			Otherwise
				jRes['info'] := "NFCe ja existe na fila."
		EndCase
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf
	(cAliAux)->(DbCloseArea())

	If ZZX_Gravar("ZZD", "NFC", "CHVNFE", cChvNFe, jJson:toJSON(), "", "", cProdPend, AllTrim(U_PI_STR_X(oHead, 'qt_Produto')), cIdIpaas)
		nStat := 201
		jRes['status']    := nStat
		jRes['resultado'] := "Sucesso"
		jRes['doc']       := "NFCe enfileirada: " + cChvNFe
		jRes['info']      := "Nota registrada para processamento assincrono."
	Else
		nStat := 230
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "FilaMuroZ"
		jRes['mensagem']  := "Falha ao gravar na fila ZZD. Tente novamente."
	EndIf

	Self:setStatus(nStat)
	Self:SetResponse(EncodeUTF8(jRes:toJSON()))
	FreeObj(jJson)
	FreeObj(jRes)

Return lRet

// Grava um registro generico na tabela Muro ZZD
Static Function ZZX_Gravar(cTabMuro, cProc, cCampoChave, cChvRef, cJsonPayload, cCampoExtra, cValorExtra, cPrdPend, cQtProd, cIdIpaas)
	Local lOk  := .F.
	Local cCod := ""

	Default cCampoExtra := ""
	Default cValorExtra := ""
	Default cPrdPend    := "N"
	Default cQtProd     := ""
	Default cIdIpaas    := ""

	cCod := GetSxeNum(cTabMuro, cTabMuro + "_COD")

	DbSelectArea(cTabMuro)
	If RecLock(cTabMuro, .T.)
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_FILIAL"), xFilial(cTabMuro)))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_COD"),    PadR(cCod, TamSx3(cTabMuro + "_COD")[1])))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_PROC"),   PadR(cProc, TamSx3(cTabMuro + "_PROC")[1])))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_STATUS"), "P"))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_" + cCampoChave), PadR(cChvRef, TamSx3(cTabMuro + "_" + cCampoChave)[1])))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_JSON"),   cJsonPayload))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_DTINCL"), Date()))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_HRINCL"), Time()))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_PRDPEN"),cPrdPend))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_ERRMSG"), ""))
		If FieldPos(cTabMuro + "_CLIPEN") > 0
			(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_CLIPEN"), "N"))
		EndIf
		If FieldPos(cTabMuro + "_FORPEN") > 0
			(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_FORPEN"), "N"))
		EndIf
		If FieldPos(cTabMuro + "_QTPROD") > 0
			(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_QTPROD"), Val(cQtProd)))
		EndIf
		If FieldPos(cTabMuro + "_IDIPS") > 0
			(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_IDIPS"), PadR(cIdIpaas, TamSx3(cTabMuro + "_IDIPS")[1])))
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

