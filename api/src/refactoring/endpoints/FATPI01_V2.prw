#Include "Protheus.ch"
#Include "TbiConn.ch"
#Include "TopConn.ch"
#Include "RestFul.ch"

// POST /fatpi01/v2 - endpoint NFe (modelo 55): valida/classifica o payload e enfileira na ZZ9

WSRESTFUL FATPI01_V2 DESCRIPTION 'Hub de Vendas e Compras CAASP'
	WSMETHOD POST DESCRIPTION 'Processamento Global' WSSYNTAX "/fatpi01/v2" PATH "/fatpi01/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI01_V2
	Local lRet         := .T.
	Local cJson        := Self:GetContent()
	Local jJson        := JsonObject():New()
	Local jRes         := JsonObject():New()
	Local nStat        := 200
	Local cModDoc      := ""
	Local aInv         := {}
	Local oHead        := Nil
	Local aEmp         := {}
	Local cCnpj        := ""
	Local cChave       := ""
	Local cProdPend    := ""
	Local lOk          := .T.
	Local cQryAux      := ""
	Local cAliAux      := ""
	Local cOldRestNfe  := ""

	Private __cBatch   := "1"

	cOldRestNfe := SuperGetMv("MV_RESTNFE", .F., "S")
	PutMv("MV_RESTNFE", "N")

	Self:SetContentType('application/json')

	If !Empty(jJson:FromJson(cJson))
		lOk := .F.
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

	cProdPend := jJson['prod_Pendente']
	If ValType(cProdPend) != "C" .Or. Empty(cProdPend)
		cProdPend := "N"
	EndIf

	aInv := jJson['notas']
	If ValType(aInv) != "A"
		aInv := jJson['items']
	EndIf

	If ValType(aInv) == "A" .And. Len(aInv) > 0
		oHead   := aInv[1]
		cModDoc := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')

		If cModDoc == "65"
			nStat := 200
			jRes['status']    := nStat
			jRes['resultado'] := "Falha"
			jRes['erro']      := "ModeloIncorreto"
			jRes['mensagem']  := "FATPI01_V2 aceita apenas NFe (modelo 55). NFCe deve ser enviada para /fatpi09/v2."

			Self:setStatus(nStat)
			Self:SetResponse(EncodeUTF8(jRes:toJSON()))
			PutMv("MV_RESTNFE", cOldRestNfe)
			Return .T.
		EndIf

		cChave := AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe'))

		cCnpj := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ', 'num_SubseccaoCNPJ'))
		aEmp := U_PI_FILIAL_X(cCnpj)

		If Len(aEmp) < 2
			lOk := .F.
			nStat := 200
			jRes['status']    := nStat
			jRes['resultado'] := "Falha"
			jRes['erro']      := "Filial"
			jRes['detalhe']   := cCnpj
			jRes['mensagem']  := "Filial nao encontrada para CNPJ: " + AllTrim(cCnpj)
		EndIf

		If lOk
			cQryAux := "SELECT ZZ9_COD FROM " + RetSqlName("ZZ9") + " WHERE ZZ9_CHVNFE = '" + cChave + "' AND ZZ9_STATUS IN ('P','A','S') AND D_E_L_E_T_ = ' '"
			cAliAux := GetNextAlias()
			MpSysOpenQuery(cQryAux, cAliAux)
			If (cAliAux)->(!Eof())
				(cAliAux)->(DbCloseArea())

				nStat := 200
				jRes['status']    := nStat
				jRes['resultado'] := "Sucesso"
				jRes['doc']       := "NFe: " + cChave
				jRes['info']      := "NFe ja enfileirada anteriormente."
				Self:setStatus(nStat)
				Self:SetResponse(EncodeUTF8(jRes:toJSON()))
				PutMv("MV_RESTNFE", cOldRestNfe)
				Return .T.
			EndIf
			(cAliAux)->(DbCloseArea())

			If U_ZZX_Gravar("ZZ9", "", "CHVNFE", cChave, jJson:toJSON(), "", "", cProdPend, AllTrim(U_PI_STR_X(oHead, 'qt_Produto')))
				nStat := 201
				jRes['status']    := nStat
				jRes['resultado'] := "Sucesso"
				jRes['doc']       := "NFe enfileirada na ZZ9: " + cChave
				jRes['info']      := "Nota registrada para classificacao e processamento assincrono."
			Else
				lOk := .F.
				nStat := 230
				jRes['status']    := nStat
				jRes['resultado'] := "Falha"
				jRes['erro']      := "FilaMuroZ"
				jRes['mensagem']  := "Falha ao gravar na fila ZZ9. Tente novamente."
			EndIf
		EndIf
	EndIf

	PutMv("MV_RESTNFE", cOldRestNfe)

	Self:setStatus(nStat)
	Self:SetResponse(EncodeUTF8(jRes:toJSON()))
	FreeObj(jJson)
	FreeObj(jRes)

Return lRet
