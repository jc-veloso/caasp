#Include "Totvs.ch"
#Include "RESTFul.ch"
#Include "TopConn.ch"
#Include "FWMVCDef.ch"

/*/{Protheus.doc} FATPI06
API Importador CAASP - Clientes (MVC)
@author André Luiz Monteiro
@since 18/05/2026
/*/

WSRESTFUL FATPI06 DESCRIPTION 'Importador CAASP - Clientes MVC'

	WSMETHOD POST NewClient DESCRIPTION 'Inclusao' ;
		WSSYNTAX '/FATPI06' ;
		PATH '' ;
		PRODUCES APPLICATION_JSON

	WSMETHOD GET GetClient DESCRIPTION 'Consulta' ;
		WSSYNTAX '/FATPI06/{codigo}' ;
		PATH '/{codigo}' ;
		PRODUCES APPLICATION_JSON

END WSRESTFUL

//===================================================================
// POST
//===================================================================

WSMETHOD POST NewClient WSSERVICE FATPI06
Return DoPost(Self)

//===================================================================
// GET
//===================================================================

WSMETHOD GET GetClient WSSERVICE FATPI06
Return DoGet(Self)

//===================================================================
// POST - MVC
//===================================================================

Static Function DoPost(oSelf)

	Local lRet       := .T.
	Local oJson      := JsonObject():New()
	Local oResp      := JsonObject():New()
	Local cBody      := oSelf:GetContent()
	Local cClean     := StrTran(StrTran(cBody, Chr(239)+Chr(187)+Chr(191), ""), Chr(0), "")
	Local bErrBlock
	Local cErrorMsg  := ""
	Local cProxCod   := ""
	Local cVLeg      := ""
	Local cEstAux    := ""
	Local lAbreEnv   := .F.
	Local oModel     := Nil
	Local oSA1Mod    := Nil

	Local cEmpAPI := "01"
	Local cFilAPI := "01001"

	oSelf:SetContentType("application/json")

	bErrBlock := ErrorBlock({ |e| cErrorMsg := e:Description, Break(e) })

	If Type("cEmpAnt") == "U" .Or. Empty(cEmpAnt)
		RpcSetEnv(cEmpAPI, cFilAPI)
		lAbreEnv := .T.
	EndIf

	Begin Sequence

		If !Empty(oJson:FromJson(cClean))
			oSelf:SetStatus(400)
			oResp["erro"]     := "JSON"
			oResp["mensagem"] := "JSON invalido"
			Break
		EndIf

		cVLeg := SubStr(GetJ(oJson, "codigo"), 1, 15)

		If !Empty(cVLeg) .And. !CheckLeg(cVLeg)
			oSelf:SetStatus(200)
			oResp["Resultado"]:= "Sucesso"
			oResp["mensagem"] := "Cliente ja cadastrado: " + cVLeg
			Break
		EndIf

		cEstAux := Upper(GetJ(oJson, "estado"))

		If "SAO PAULO" $ cEstAux .Or. "SÃO PAULO" $ cEstAux
			cEstAux := "SP"
		Else
			cEstAux := Left(cEstAux, 2)
		EndIf

		cProxCod := GetSxeNum("SA1", "A1_COD")

		oModel := FWLoadModel("CRMA980")
		oModel:SetOperation(MODEL_OPERATION_INSERT)
		oModel:Activate()

		oSA1Mod := oModel:GetModel("SA1MASTER")

		oSA1Mod:SetValue("A1_COD"    , cProxCod)
		oSA1Mod:SetValue("A1_LOJA"   , "01")
		oSA1Mod:SetValue("A1_NOME"   , Upper(GetJ(oJson, "nome")))
		oSA1Mod:SetValue("A1_NREDUZ" , SubStr(Upper(GetJ(oJson, "nome")), 1, 20))
		oSA1Mod:SetValue("A1_CGC"    , GetJ(oJson, "cpf"))
		oSA1Mod:SetValue("A1_END"    , Upper(GetJ(oJson, "endereco")))
		oSA1Mod:SetValue("A1_BAIRRO" , Upper(GetJ(oJson, "bairro")))
		oSA1Mod:SetValue("A1_MUN"    , Upper(GetJ(oJson, "municipio")))
		oSA1Mod:SetValue("A1_EST"    , cEstAux)
		oSA1Mod:SetValue("A1_CEP"    , GetJ(oJson, "cep"))
		oSA1Mod:SetValue("A1_DDD"    , GetJ(oJson, "ddd"))
		oSA1Mod:SetValue("A1_TEL"    , GetJ(oJson, "telefone"))
		oSA1Mod:SetValue("A1_EMAIL"  , Lower(GetJ(oJson, "email")))
		oSA1Mod:SetValue("A1_TIPO"   , "F")
		If LEN(GetJ(oJson, "cpf")) = 11
			oSA1Mod:SetValue("A1_PESSOA" , "F")
		ELSEIF LEN(GetJ(oJson, "cpf")) = 14
			oSA1Mod:SetValue("A1_PESSOA" , "J")
		ENDIF
		oSA1Mod:SetValue("A1_COD_MUN", GetJ(oJson, "cod_Municipio"))
		oSA1Mod:SetValue("A1_LEGADO" , cVLeg)

		If !Empty(GetJ(oJson, "cod_ibge"))
			oSA1Mod:SetValue("A1_COD_MUN", GetJ(oJson, "cod_ibge"))
		EndIf

		If oModel:VldData()
			If oModel:CommitData()
				ConfirmSX8()
				oSelf:SetStatus(201)
				oResp["resultado"]    := "Sucesso"
				oResp["protheus_cod"] := cProxCod
			Else
				RollBackSX8()
				oSelf:SetStatus(200)
				oResp["resultado"] := "Erro"
				oResp["mensagem"]  := oModel:GetErrorMessage()
			EndIf
		Else
			RollBackSX8()
			oSelf:SetStatus(200)
			oResp["resultado"] := "Erro"
			oResp["mensagem"]  := oModel:GetErrorMessage()
		EndIf

		If oModel <> Nil
			oModel:DeActivate()
			oModel:Destroy()
			oModel := Nil
		EndIf

	End Sequence

	ErrorBlock(bErrBlock)

	oSelf:SetResponse(EncodeUTF8(oResp:ToJson()))

	If lAbreEnv
		RpcClearEnv()
	EndIf

Return lRet

//===================================================================
// GET
//===================================================================

Static Function DoGet(oSelf)

	Local oResp  := JsonObject():New()
	Local cAli   := GetNextAlias()
	Local cBusca := ""

	If Len(oSelf:aURLParms) > 0
		cBusca := oSelf:aURLParms[1]
	EndIf

	oSelf:SetContentType("application/json")

	TCQuery ;
		"SELECT A1_COD, A1_NOME, A1_CGC " + ;
		"FROM " + RetSqlName("SA1") + " " + ;
		"WHERE A1_LEGADO = '" + cBusca + "' " + ;
		"AND D_E_L_E_T_ = ' '" ;
		New Alias (cAli)

	If (cAli)->(Eof())

		oSelf:SetStatus(200)

		oResp["resultado"] := "Cliente"
		oResp["mensagem"]  := "Cliente nao cadastrado"

	Else

		oSelf:SetStatus(201)

		oResp["resultado"]    := "Sucesso"
		oResp["protheus_cod"] := AllTrim((cAli)->A1_COD)
		oResp["nome"]         := AllTrim((cAli)->A1_NOME)

	EndIf

	(cAli)->(DbCloseArea())

	oSelf:SetResponse(EncodeUTF8(oResp:ToJson()))

Return .T.

//===================================================================
// AUX
//===================================================================

Static Function GetJ(oObj, cKey)

	Local cVal := ""

	If oObj:HasProperty(cKey) .And. oObj[cKey] <> Nil
		cVal := cValToChar(oObj[cKey])
	EndIf

Return cVal

//===================================================================

Static Function CheckLeg(cVal)

	Local lOk := .T.
	Local cAl := GetNextAlias()

	TCQuery ;
		"SELECT A1_COD " + ;
		"FROM " + RetSqlName("SA1") + " " + ;
		"WHERE A1_LEGADO = '" + cVal + "' " + ;
		"AND D_E_L_E_T_ = ' '" ;
		New Alias (cAl)

	If !(cAl)->(Eof())
		lOk := .F.
	EndIf

	(cAl)->(DbCloseArea())

Return lOk
