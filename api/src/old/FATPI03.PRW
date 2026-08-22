#Include "Totvs.ch"
#Include "RESTFul.ch"
#Include "TopConn.ch"
#Include 'FWMVCDef.ch'
#INCLUDE "TBICONN.CH"

/*/{Protheus.doc} WSRESTFUL FATPI03V1
API de Fornecedores CAASP - Inclusao de campos bancarios e validacao de Municipio
@author ANTONIO NUNES
@since 24/02/2026
/*/

WSRESTFUL FATPI03V1 DESCRIPTION 'Fornecedor CAASP - Endpoint FATPI03V1'
	WSDATA cnpj AS STRING

	WSMETHOD GET SEARCH_CNPJ DESCRIPTION 'Busca fornecedor por CNPJ' PATH '/' PRODUCES APPLICATION_JSON
	WSMETHOD POST NEW         DESCRIPTION 'Upsert Fornecedor'        PATH '/' PRODUCES APPLICATION_JSON
END WSRESTFUL

// ============================================================================
// METODO GET - Busca por CNPJ
// ============================================================================
WSMETHOD GET SEARCH_CNPJ WSSERVICE FATPI03V1
	Local jResponse := JsonObject():New()
	Local cCGC      := ""

	cCGC := AllTrim(Self:cnpj)
	cCGC := StrTran(StrTran(StrTran(cCGC, '.', ''), '-', ''), '/', '')

	Self:SetContentType('application/json')

	If Empty(cCGC)
		Self:setStatus(400)
		jResponse['status']  := 'error'
		jResponse['message'] := 'Parametro cnpj nao informado.'
		Return .T.
	EndIf

	DbSelectArea("SA2")
	SA2->(DbSetOrder(3))

	If SA2->(MsSeek(FWxFilial("SA2") + cCGC))
		jResponse['status'] := 'success'
		jResponse['cod_Protheus'] := AllTrim(SA2->A2_COD)
		jResponse['loja']         := AllTrim(SA2->A2_LOJA)
		jResponse['nom_Fornecedor']:= AllTrim(SA2->A2_NOME)
		jResponse['num_CNPJ_CPF']  := SA2->A2_CGC
	Else
		Self:setStatus(404)
		jResponse['status']  := 'error'
		jResponse['message'] := 'Fornecedor nao localizado.'
	EndIf

	Self:SetResponse(EncodeUTF8(jResponse:toJSON()))
Return .T.

// ============================================================================
// METODO POST - Upsert com Dados Bancarios
// ============================================================================
WSMETHOD POST NEW WSRECEIVE WSSERVICE FATPI03V1
	Local aDados    := {}
	Local jJson     := JsonObject():New()
	Local jItems    := {}
	Local jItem     := JsonObject():New()
	Local oResult   := JsonObject():New()
	Local jResponse := JsonObject():New()
	Local aLogAuto  := {}
	Local nX        := 0
	Local nLinha    := 0
	Local nOpcao    := 0
	Local cCNPJ     := ""
	Local cProxCod  := ""
	Local cLoja     := ""
	Local cErrorLog := ""
	Local cMun      := ""
	Local oModel    := Nil

	Private lMsErroAuto := .F.
	Private lMsHelpAuto := .F.

	Self:SetContentType('application/json')
	If ! Empty(jJson:FromJson(Self:GetContent())); Self:setStatus(400); Return .F.; EndIf

		jItems := If(jJson:HasProperty("items"), jJson['items'], { jJson })
		jResponse['results'] := {}

		DbSelectArea("SA2")
		SA2->(DbSetOrder(3))

		For nX := 1 To Len(jItems)
			jItem := jItems[nX]
			aDados := {}
			lMsErroAuto := .F.
			oResult := JsonObject():New()

			cCNPJ := StrTran(StrTran(StrTran(cValToChar(jItem['num_CNPJ_CPF']), '.', ''), '-', ''), '/', '')
			cMun  := AllTrim(cValToChar(jItem['nom_Municipio']))

			// --- VALIDACAO PREVIA: MUNICIPIO VAZIO ---
			If Empty(cMun)
				oResult['status']  := 'error'
				oResult['message'] := 'O campo Municipio (nom_Municipio) e obrigatorio e nao foi preenchido.'
				aAdd(jResponse['results'], oResult)
				Loop
			EndIf

			oModel := FwLoadModel("MATA020")

			If !Empty(cCNPJ) .And. SA2->(MsSeek(FWxFilial("SA2") + cCNPJ))
				oModel:SetOperation(MODEL_OPERATION_UPDATE)
				cProxCod := SA2->A2_COD
				cLoja    := SA2->A2_LOJA
			Else
				oModel:SetOperation(MODEL_OPERATION_INSERT)
				cProxCod := GetSxeNum("SA2", "A2_COD")
				cLoja    := "01"
				ConfirmSX8()
			EndIf

			// Carrega Model do cadastro de fornecedor
			oModel:Activate()
			// --- BLOCO: IDENTIFICACAO ---
			oModel:SetValue("SA2MASTER", "A2_COD"   , cProxCod)
			oModel:SetValue("SA2MASTER", "A2_LOJA"  , cLoja)
			oModel:SetValue("SA2MASTER", "A2_NOME"  , Left(cValToChar(jItem["nom_Fornecedor"]), 40))
			oModel:SetValue("SA2MASTER", "A2_NREDUZ", Left(cValToChar(jItem["nom_Fantasia"]), 20))
			oModel:SetValue("SA2MASTER", "A2_TIPO"  , Upper(AllTrim(cValToChar(jItem["tpo_Pessoa"]))))
			oModel:SetValue("SA2MASTER", "A2_CGC"   , cCNPJ)

			// --- BLOCO: LOCALIZACAO ---
			oModel:SetValue("SA2MASTER", "A2_EST" , Upper(AllTrim(cValToChar(jItem["cod_UF"]))))
			oModel:SetValue("SA2MASTER", "A2_MUN" , Left(cMun, 30))
			oModel:SetValue("SA2MASTER", "A2_CEP" , StrTran(cValToChar(jItem["num_CEP"]), "-", ""))

			// --- BLOCO: ENDERECO E CONTATO ---
			oModel:SetValue("SA2MASTER", "A2_END"     , Left(cValToChar(jItem["nom_Logradouro"]), 40))
			oModel:SetValue("SA2MASTER", "A2_BAIRRO"  , Left(cValToChar(jItem["nom_Bairro"]), 30))
			oModel:SetValue("SA2MASTER", "A2_INSCR"   , AllTrim(cValToChar(jItem["num_InscricaoEstadual"])))
			oModel:SetValue("SA2MASTER", "A2_COD_MUN" , AllTrim(cValToChar(jItem["cod_IBGE"])))

			// --- BLOCO: DADOS BANCARIOS ---
			oModel:SetValue("SA2MASTER", "A2_BANCO"  , cValToChar(jItem["cod_Banco"]))
			oModel:SetValue("SA2MASTER", "A2_AGENCIA", cValToChar(jItem["num_Agencia"]))
			oModel:SetValue("SA2MASTER", "A2_NUMCON" , cValToChar(jItem["num_Conta"]))
			oModel:SetValue("SA2MASTER", "A2_DVCTA"  , cValToChar(jItem["num_ContaDig"]))
			oModel:SetValue("SA2MASTER", "A2_CODPAIS", cValToChar(jItem["cod_pais"]))

			// --- BLOCO: FINANCEIRO / STATUS ---
			oModel:SetValue("SA2MASTER", "A2_RISCO" , "A")
			oModel:SetValue("SA2MASTER", "A2_MSBLQL", If(Upper(cValToChar(jItem["flg_Ativo"])) == "S", "2", "1"))

			If oModel:VldData()
				If oModel:CommitData()
					oResult['resultado']    := 'Sucesso'
					oResult['mensagem'] := 'Fornecedor incluído com sucesso'
					oResult['cod_erp'] := cProxCod
				Else
					oResult['resultado']  := 'error'
					oResult['mensagem'] := oModel:GetErrorMessage()
				EndIf
			Else
				oResult['resultado']  := 'error'
				oResult['mensagem'] := oModel:GetErrorMessage()
			EndIf

			oModel:DeActivate()
			oModel:Destroy()
			oModel := Nil
			aAdd(jResponse['results'], oResult)
		Next nX

		Self:SetResponse(oResult)
		Return .T.
