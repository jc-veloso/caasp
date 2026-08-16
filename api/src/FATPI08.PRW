#Include 'Protheus.ch'
#Include 'RestFul.ch'
#Include 'TopConn.ch'

/*/{Protheus.doc} FATPI08
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Hub de Vendas - SIGALOJA (Endpoint REST e Motor Principal de Integracao)
@type class
@version 12
@author Antonio Nunes O Jr
/*/
WSRESTFUL FATPI08 DESCRIPTION 'Hub de Vendas - SIGALOJA'
	WSMETHOD POST DESCRIPTION 'Processamento' WSSYNTAX "/fatpi08" PATH "/fatpi08" PRODUCES APPLICATION_JSON
END WSRESTFUL

/*/{Protheus.doc} POST
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Metodo POST da API FATPI08. Responsavel por ler o Body, preparar o ambiente e acionar a gravacao.
/*/
WSMETHOD POST WSRECEIVE WSSERVICE FATPI08
	// --- Declaracao de Variaveis Locais ---
	Local lRet       := .T.
	Local jJson      := JsonObject():New()
	Local jRes       := JsonObject():New()
	Local cJson      := Self:GetContent()
	Local cError     := ""
	Local oData      := Nil
	Local aEmpFil    := {}
	Local cCnpjU     := ""
	Local cEmpAPI    := "01"
	Local cFilAPI    := "01001"
	Local lAbreEnv   := .F.

	Private __cXEvento := "LOJ"

	If Type("cEmpAnt") == "U" .Or. Empty(cEmpAnt) .Or. Select("SX6") == 0
		RpcSetEnv(cEmpAPI, cFilAPI, Nil, Nil, "LOJ")
		lAbreEnv := .T.
	EndIf

	Self:SetContentType('application/json')
	cError := jJson:FromJson(cJson)

	If !Empty(cError)
		jRes['status']    := 400
		jRes['resultado'] := "Erro"
		jRes['erro']      := "Payload"
		jRes['mensagem']  := "JSON Invalido"

		Self:setStatus(jRes['status'])
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))

		If lAbreEnv
			RpcClearEnv()
		EndIf

		Return lRet
	EndIf

	If ValType(jJson['notas']) == "A"
		oData := jJson['notas'][1]
	Else
		oData := jJson
	EndIf

	cCnpjU  := U_FZ_LIMPA_X(U_FZ_STR_X(oData, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
	aEmpFil := FATPI0804(cCnpjU)

	If Len(aEmpFil) < 2
		jRes['status']    := 201
		jRes['resultado'] := "Erro"
		jRes['erro']      := "Filial"
		jRes['mensagem']  := "Filial nao encontrada para o CNPJ: " + AllTrim(cCnpjU)

		Self:setStatus(jRes['status'])
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))

		If lAbreEnv
			RpcClearEnv()
		EndIf

		Return lRet
	EndIf

	If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
		RPCClearEnv()
		RpcSetEnv(aEmpFil[1], aEmpFil[2], Nil, Nil, "LOJ")
	EndIf

	jRes := u_FATPI0801(oData, aEmpFil[2])

	If jRes:HasProperty('status')
		Self:setStatus(jRes['status'])
	Else
		Self:setStatus(200)
	EndIf

	Self:SetResponse(EncodeUTF8(jRes:toJSON()))

	If lAbreEnv
		RpcClearEnv()
	EndIf
Return lRet

/*/{Protheus.doc} FATPI0801
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Gravacao Varejo NFS2 - Motor U_FZ_PROS_X + Cirurgia Direta (SF2/SD2/SE1/SL) - SEM FISCAL
/*/
User Function FATPI0801(oData, cFilDest)
	// --- 1. DECLARACAO DE VARIAVEIS LOCAIS (TODAS NO TOPO) ---
	Local jRes          := JsonObject():New()
	Local nX            := 0
	Local cEntC         := ""
	Local cEntL         := ""
	Local cTipoCli      := "F"
	Local oItnsJ        := Nil
	Local nTamDoc       := TamSX3("F2_DOC")[1]
	Local nTamL2Item    := TamSX3("L2_ITEM")[1]
	Local cHistPad      := ""
	Local cExpCli       := ""
	Local dConf         := U_FZ_DATA_X(U_FZ_STR_X(oData, 'dta_Conferencia', 'dta_Emissao'))
	Local cVendPad      := PadR("000001", TamSX3("L1_VEND")[1])
	Local cOperador     := PadR(U_FZ_STR_X(oData, 'cod_LoginEmissao'), TamSx3("L1_OPERADO")[1])
	Local cPdvPad       := PadR("001", TamSx3("L1_PDV")[1])
	Local cOrcamento    := ""
	Local cCliVarejo    := ""
	Local cNumVenGer    := ""
	Local cSerie        := "1"
	Local cDocJson      := U_FZ_LIMPA_X(U_FZ_STR_X(oData, 'cod_ReciboVenda', 'num_NF'))
	Local cDocPad       := ""
	Local cDesOrig      := U_FZ_STR_X(oData, 'des_Origem')
	Local cChaveNFe     := U_FZ_STR_X(oData, 'cod_ChaveNFe')
	Local cCpfCnpj      := ""
	Local cNomeCli      := ""
	Local cFuncionario  := ""
	Local oUsrJ         := Nil
	Local cNomeFin      := ""
	Local cItemL2       := ""
	Local cEvtMod       := U_FZ_STR_X(oData, "cod_EventoModalidade", "cod_Evento")
	Local cTransacao    := U_FZ_STR_X(oData, "num_Transacao")
	Local cAutoriz      := U_FZ_STR_X(oData, "des_Autorizacao")
	Local nVlrMercN     := U_FZ_VAL_X(oData, 'vlr_TotalProduto', 'vlr_ReciboVendaTotal')
	Local nVlrDescN     := U_FZ_VAL_X(oData, 'vlr_Desconto', 'vlr_ReciboVendaDesconto')
	Local nVlrSegN      := U_FZ_VAL_X(oData, 'vlr_Seguro')
	Local nVlrOutrN     := U_FZ_VAL_X(oData, 'vlr_Outros')
	Local nVlrLiqN      := U_FZ_VAL_X(oData, 'vlr_NotaFiscal', 'vlr_ReciboVendaTotal')
	Local cCustoHead    := U_FZ_STR_X(oData, 'cod_CentroCusto')
	Local cSerPad       := PadR("1", TamSx3("F2_SERIE")[1], " ")
	Local cCliPad       := ""
	Local cLojPad       := ""
	Local lIsDevol      := .F.
	Local cNatOp        := Upper(U_FZ_STR_X(oData, 'des_NatOp'))
	Local cQryCli       := ""
	Local cAliCli       := ""
	Local cTipoOper     := "N"
	Local cMsgNota      := ""
	Local lCliFound     := .F.
	Local aRet          := {}
	Local cQryRec       := ""
	Local cAliRec       := ""
	Local cQryChk       := ""
	Local cAliChk       := ""
	Local cItemSql      := ""
	Local nQtdItm       := 0
	Local nVlrUniItm    := 0
	Local nDescItm      := 0
	Local nVlrBrutItm   := 0
	Local nVlrLiqItm    := 0
	Local nPercDesc     := 0
	Local cCustoSD2     := ""
	Local cLogProd      := ""
	Local cProdLeg      := ""
	Local cDescProd     := ""
	Local aProdDados    := {}
	Local cInternoDB    := ""
	Local aPagamentos   := {}
	Local nPag          := 0
	Local oPag          := Nil
	Local cNatItm       := ""
	Local cCCItm        := ""
	Local cFormaRec     := ""
	Local cBandeira     := ""
	Local cTransac      := ""
	Local cAutorizPg    := ""
	Local nVlrTitulo    := 0
	Local cFormaTrat    := ""
	Local cAliSE1       := ""
	Local cQrySE1       := ""
	Local cParc         := 'A'
	Local cTipoTit

	// --- 2. EXTRACAO SEGURA DE ARRAYS (HASPROPERTY) ---
	If ValType(oData) == "J" .Or. ValType(oData) == "O"
		If oData:HasProperty("itens")
			If ValType(oData["itens"]) == "A"
				oItnsJ := oData["itens"]
			EndIf
		EndIf
	EndIf

	// --- 3. INICIO DA EXECUCAO E CHECAGENS ---
	ChkFile("SFT")
	ChkFile("SLQ")
	ChkFile("SLR")
	ChkFile("SL4")

	If Empty(cEvtMod)
		cEvtMod := "LOJ"
	EndIf
	If Empty(cOperador)
		cOperador := "API"
	EndIf
	If Empty(cDocJson)
		cDocJson := U_FZ_LIMPA_X(U_FZ_STR_X(oData, 'num_NF'))
	EndIf

	If Empty(cDocJson)
		jRes['status']    := 400
		jRes['resultado'] := "Erro"
		jRes['erro']      := "Documento"
		jRes['mensagem']  := "Numero do Cupom/Recibo nao encontrado."
		Return jRes
	Else
		cDocPad   := PadL(AllTrim(cDocJson), nTamDoc, "0")
		cNumDupl  := PadL(AllTrim(cDocJson), TamSx3("F2_DUPL")[1], "0")
	EndIf

	cQryChk := "SELECT R_E_C_N_O_ AS REC FROM " + RetSqlName("SF2") + " WHERE F2_DOC='" + cDocPad + "' AND F2_SERIE='" + cSerPad + "' AND F2_FILIAL='" + xFilial("SF2") + "' AND D_E_L_E_T_=' '"
	cAliChk := GetNextAlias()
	MpSysOpenQuery(cQryChk, cAliChk)
	If (cAliChk)->(!Eof())
		(cAliChk)->(DbCloseArea())
		jRes['status']    := 200
		jRes['resultado'] := "Sucesso"
		jRes['mensagem']  := "Nota ja existe: " + xFilial("SF2") + " - " + AllTrim(cDocJson)
		jRes['info']      := FATPI0802(cDocPad)
		Return jRes
	EndIf
	(cAliChk)->(DbCloseArea())

	If ValType(oItnsJ) == "A" .And. Len(oItnsJ) > 0
		If ValType(oItnsJ[1]) == "O" .Or. ValType(oItnsJ[1]) == "J"
			If Empty(cCustoHead)
				cCustoHead := U_FZ_STR_X(oItnsJ[1], 'cod_CentroCusto')
			EndIf
		EndIf
	EndIf

	If "DEVOLUCAO" $ cNatOp
		lIsDevol := .T.
	EndIf

	// ---> EXTRACAO DOS DADOS DO USUARIO (CLIENTE E FUNCIONARIO) <---
	If ValType(oData) == "J" .Or. ValType(oData) == "O"
		If oData:HasProperty("usuario")
			If ValType(oData["usuario"]) == "O" .Or. ValType(oData["usuario"]) == "J"
				oUsrJ        := oData['usuario']
				cExpCli      := U_FZ_STR_X(oUsrJ, "cod_Exportacao", "codigo")
				cCpfCnpj     := U_FZ_LIMPA_X(U_FZ_STR_X(oUsrJ, "cpf", "cnpj"))
				cNomeCli     := U_FZ_STR_X(oUsrJ, "des_Nome", "nome")
				cFuncionario := U_FZ_STR_X(oUsrJ, "cod_Funcionario")
			EndIf
		EndIf
	EndIf

	If Empty(cExpCli)
		cExpCli  := U_FZ_STR_X(oData, "cod_Exportacao")
	EndIf
	If Empty(cFuncionario)
		cFuncionario := U_FZ_STR_X(oData, "cod_Funcionario")
	EndIf
	If Empty(cCpfCnpj)
		cCpfCnpj := U_FZ_LIMPA_X(U_FZ_STR_X(oData, 'des_DestDocumento', 'num_Documento'))
	EndIf
	If Empty(cNomeCli)
		cNomeCli := U_FZ_STR_X(oData, 'des_Nome', 'des_DestNome')
	EndIf
	If Empty(cNomeCli)
		cNomeCli := "CONSUMIDOR FINAL"
	EndIf

	cNomeFin := cNomeCli

	// ---> BUSCA DE CLIENTE COM TRAVA 201 <---
	If lIsDevol
		cTipoOper := "D"
		If !Empty(cCpfCnpj)
			cQryCli := "SELECT A2_COD, A2_LOJA, A2_TIPO FROM " + RetSqlName("SA2") + " WHERE A2_CGC ='" + AllTrim(cCpfCnpj) + "' AND D_E_L_E_T_=' '"
			cAliCli := GetNextAlias()
			MpSysOpenQuery(cQryCli, cAliCli)
			If (cAliCli)->(!Eof())
				cEntC    := (cAliCli)->A2_COD
				cEntL    := (cAliCli)->A2_LOJA
				cTipoCli := (cAliCli)->A2_TIPO
				lCliFound := .T.
			EndIf
			(cAliCli)->(DbCloseArea())
		EndIf
		If !lCliFound
			jRes['status']    := 400
			jRes['resultado'] := "Erro"
			jRes['erro']      := "Fornecedor"
			jRes['mensagem']  := "Fornecedor nao cadastrado na SA2. CNPJ: " + cCpfCnpj
			Return jRes
		EndIf
	Else
		cTipoOper := "N"

		If !Empty(cExpCli)
			lCliFound := FATPI0805("LEG", cExpCli, @cEntC, @cEntL)
			If lCliFound
				cTipoCli := Posicione("SA1", 1, xFilial("SA1") + cEntC + cEntL, "A1_TIPO")
			EndIf
		EndIf

		If !lCliFound
			jRes['status']    := 201
			jRes['resultado'] := "Erro"
			jRes['erro']      := "Cliente"
			jRes['mensagem']  := "Cliente nao encontrado para o cod_Exportacao: " + AllTrim(cExpCli)
			Return jRes
		EndIf
	EndIf

	cCliPad := PadR(cEntC, TamSx3("A1_COD")[1], " ")
	cLojPad := PadR(cEntL, TamSx3("A1_LOJA")[1], " ")
	cCliVarejo := cCliPad

	// ---------------------------------------------------------
	// 4. DISPARO DO MOTOR ORIGINAL DE NOTA (NF2NFS)
	// ---------------------------------------------------------
	cNumVenGer := GetSxeNum("SL1", "L1_NUM")
	cOrcamento := cNumVenGer
	ConfirmSX8()

	If cTipoOper == "D"
		aRet := U_FZ_PRDEV_X(oItnsJ, oData, cEntC, cEntL, cDocPad, cSerie, "SA2", xFilial("SF1"), 0, "001")
	Else
		aRet := U_FZ_PROS_X(oItnsJ, oData, cEntC, cEntL, cDocPad, cSerie, xFilial("SF2"), "SA1", .F., cDocPad, cSerie, cDocPad, "001")
	EndIf

	If !aRet[1]
		jRes['status']    := 400
		jRes['resultado'] := "Erro"
		jRes['erro']      := "GERACAO_NF"
		jRes['mensagem']  := cValToChar(aRet[2])
		Return jRes
	EndIf

	// ---------------------------------------------------------
	// 5. CIRURGIA DIRETA NO BANCO (NFS2) - SF2/SD2/SL
	// ---------------------------------------------------------
	cQryRec := "SELECT R_E_C_N_O_ AS REC FROM " + RetSqlName("SF2") + " WHERE F2_DOC='" + cDocPad + "' AND F2_SERIE='" + cSerPad + "' AND F2_CLIENTE='" + cCliPad + "' AND F2_LOJA='" + cLojPad + "' AND D_E_L_E_T_=' '"
	cAliRec := GetNextAlias()
	MpSysOpenQuery(cQryRec, cAliRec)

	If (cAliRec)->(!Eof())
		DbSelectArea("SF2")
		SF2->(DbGoTo((cAliRec)->REC))

		If RecLock("SF2", .F.)
			If SF2->(FieldPos("F2_VALBRUT")) > 0 ; SF2->F2_VALBRUT := nVlrLiqN ; EndIf
				If SF2->(FieldPos("F2_VALFAT")) > 0  ; SF2->F2_VALFAT  := nVlrLiqN ; EndIf
					If SF2->(FieldPos("F2_VALMERC")) > 0 ; SF2->F2_VALMERC := nVlrMercN ; EndIf
						If SF2->(FieldPos("F2_DESCONT")) > 0 ; SF2->F2_DESCONT := nVlrDescN  ; EndIf
							If SF2->(FieldPos("F2_CHVNFE")) > 0  ; SF2->F2_CHVNFE  := PadR(cChaveNFe, TamSx3("F2_CHVNFE")[1]) ; EndIf
								If SF2->(FieldPos("F2_ESPECIE")) > 0 ; SF2->F2_ESPECIE := PadR("NFCE", TamSx3("F2_ESPECIE")[1]) ; EndIf

									// Grava Condicao 999 para habilitar multiplos pagamentos
									If SF2->(FieldPos("F2_COND")) > 0
										SF2->F2_COND := PadR("999", TamSx3("F2_COND")[1])
									EndIf

									SF2->(MsUnlock())
								EndIf
							EndIf
							(cAliRec)->(DbCloseArea())

							If ValType(oItnsJ) == "A"
								For nX := 1 To Len(oItnsJ)
									If ValType(oItnsJ[nX]) == "J" .Or. ValType(oItnsJ[nX]) == "O"
										cItemSql   := PadL(cValToChar(nX), TamSx3("D2_ITEM")[1], "0")
										nQtdItm     := Max(U_FZ_VAL_X(oItnsJ[nX], 'qtd_Produto'), 1)
										nVlrUniItm  := U_FZ_VAL_X(oItnsJ[nX], 'vlr_Produto', 'valorunitario')
										nDescItm    := Round(U_FZ_VAL_X(oItnsJ[nX], 'vlr_ProdutoDesconto') * nQtdItm, 2)
										nVlrBrutItm := Round(nQtdItm * nVlrUniItm, 2)

										nPercDesc   := 0
										If nVlrBrutItm > 0
											nPercDesc := Round((nDescItm / nVlrBrutItm) * 100, 2)
										EndIf

										cCustoSD2 := U_FZ_STR_X(oItnsJ[nX], 'cod_CentroCusto')
										If Empty(cCustoSD2)
											cCustoSD2 := cCustoHead
										EndIf

										cQryRec := "UPDATE " + RetSqlName("SD2") + " SET "
										cQryRec += "D2_CCUSTO = '" + PadR(cCustoSD2,TamSx3("D2_CCUSTO")[1]) + "', "
										cQryRec += "D2_PRCVEN = " + StrTran(cValToChar(nVlrUniItm),",",".") + ", "
										cQryRec += "D2_TOTAL = " + StrTran(cValToChar(nVlrBrutItm),",",".") + ", "
										cQryRec += "D2_DESCON = " + StrTran(cValToChar(nDescItm),",",".") + ", "
										cQryRec += "D2_DESC = " + StrTran(cValToChar(nPercDesc),",",".")
										cQryRec += " WHERE D2_DOC='" + cDocPad + "' AND D2_SERIE='" + cSerPad + "'"
										cQryRec += " AND D2_CLIENTE='" + cCliPad + "' AND D2_LOJA='" + cLojPad + "'"
										cQryRec += " AND D2_ITEM='" + cItemSql + "' AND D_E_L_E_T_=' '"
										TCSqlExec(cQryRec)
									EndIf
								Next nX
							EndIf

							// ---------------------------------------------------------
							// ATUALIZACAO E GRAVACAO FINANCEIRA (SE1 e SL4 Multiplos)
							// ---------------------------------------------------------
							If oData:HasProperty("recebimentos") .And. ValType(oData["recebimentos"]) == "A"
								aPagamentos := oData["recebimentos"]
							ElseIf oData:HasProperty("pagamentos") .And. ValType(oData["pagamentos"]) == "A"
								aPagamentos := oData["pagamentos"]
							EndIf

							If Len(aPagamentos) == 0
								AAdd(aPagamentos, oData)
							EndIf

							cAliSE1 := GetNextAlias()
							cQrySE1 := "SELECT R_E_C_N_O_ AS REC FROM " + RetSqlName("SE1")
							cQrySE1 += " WHERE E1_NUM='" + cDocPad + "' AND E1_PREFIXO='" + cSerPad + "' AND E1_CLIENTE='" + cCliPad + "' AND E1_LOJA='" + cLojPad + "'"
							cQrySE1 += " AND D_E_L_E_T_=' '"
							MpSysOpenQuery(cQrySE1, cAliSE1)


							For nPag := 1 To Len(aPagamentos)
								oPag := aPagamentos[nPag]

								cNatItm    := U_FZ_STR_X(oPag, "cod_NaturezaFinanceira")
								cCCItm     := U_FZ_STR_X(oPag, "cod_CentroCusto")
								cFormaRec  := U_FZ_STR_X(oPag, "des_FormaRecebimento", "des_FormaPagamento")
								cBandeira  := U_FZ_STR_X(oPag, "des_Bandeira")
								cTransac   := U_FZ_STR_X(oPag, "num_Transacao")
								cAutorizPg := U_FZ_STR_X(oPag, "des_Autorizacao")
								cTipoTit   := U_FZ_STR_X(oPag, "des_FormaPag")

								nVlrTitulo := U_FZ_VAL_X(oPag, "vlr_Recebimento", "vlr_Pagamento")
								If nVlrTitulo <= 0 ; nVlrTitulo := U_FZ_VAL_X(oPag, "vlr_Transacao") ; EndIf
									If nVlrTitulo <= 0 ; nVlrTitulo := nVlrLiqN ; EndIf

										If Empty(cNatItm) ; cNatItm := "OUTROS" ; EndIf
											If Empty(cCCItm)  ; cCCItm  := cCustoHead ; EndIf

												cFormaRec := Upper(AllTrim(cFormaRec))
												cFormaTrat := ""

												If "CARTAO" $ cFormaRec .Or. "CARTÃO" $ cFormaRec .Or. "CREDITO" $ cFormaRec .Or. "DEBITO" $ cFormaRec
													cFormaTrat := "CC "
												ElseIf "PIX" $ cFormaRec
													cFormaTrat := "PIX"
												ElseIf "DINHEIRO" $ cFormaRec .Or. "DIN" $ cFormaRec
													cFormaTrat := "DH "
												ElseIf "BOLETO" $ cFormaRec
													cFormaTrat := "BOL"
												Else
													cFormaTrat := Left(cFormaRec, TamSx3("E1_FORMAPG")[1])
												EndIf

												If Empty(cAutorizPg)
													cHistPad := "API: Orig:" + AllTrim(cDesOrig) + " Aut:" + AllTrim(cAutorizPg) + " Trans:" + AllTrim(cTransac)
												Else
													cHistPad := AllTrim(cAutorizPg)
												EndIf

												dVenc := U_FZ_DATA_X(U_FZ_STR_X(oPag, 'dta_Vencimento'))

												// Grava no Contas a Receber (SE1)
												If (cAliSE1)->(Eof())
													RecLock("SE1", .T.)
													SE1->E1_FILIAL  := xFilial("SE1")
													SE1->E1_FILORIG := xFilial("SE1")
													SE1->E1_PREFIXO := cSerPad
													SE1->E1_NUM     := cDocPad
													SE1->E1_PARCELA := cParc
													SE1->E1_TIPO    := IIF(!Empty(cTipoTit),cTipoTit,'RC')
													SE1->E1_XTIPO   := 'RC'
													SE1->E1_NATUREZ := PadR(cNatItm, TamSx3("E1_NATUREZ")[1])
													SE1->E1_CLIENTE := cCliPad
													SE1->E1_LOJA    := cLojPad
													SE1->E1_NOMCLI  := Posicione('SA1', 1, FWxFilial('SA1') + SE1->E1_CLIENTE + SE1->E1_LOJA, 'A1_NOME')
													SE1->E1_EMISSAO := dConf
													SE1->E1_VENCTO  := dVenc
													SE1->E1_VENCREA := dVenc
													SE1->E1_VALOR   := nVlrTitulo
													SE1->E1_VALLIQ  := nVlrTitulo
													SE1->E1_SALDO   := nVlrTitulo
													SE1->E1_VLCRUZ  := nVlrTitulo
													SE1->E1_CCUSTO  := PadR(cCCItm, TamSx3("E1_CCUSTO")[1])
													SE1->E1_XEVENTO := PadR(cDesOrig, TamSx3("E1_XEVENTO")[1])
													SE1->E1_HIST    := Left(cHistPad, TamSx3("E1_HIST")[1])

													If !Empty(cFormaTrat)
														SE1->E1_FORMAPG := PadR(cFormaTrat, TamSx3("E1_FORMAPG")[1])
													EndIf
													If !Empty(cBandeira)
														SE1->E1_CARTAO  := PadR(cBandeira, TamSx3("E1_CARTAO")[1])
													EndIf
													If !Empty(cTransac)
														SE1->E1_NSUTEF  := PadR(cTransac, TamSx3("E1_NSUTEF")[1])
													EndIf
													If !Empty(cAutorizPg)
														SE1->E1_CARTAUT := PadR(cAutorizPg, TamSx3("E1_CARTAUT")[1])
													EndIf

													// Grava Nome do Cliente no SE1
													If SE1->(FieldPos("E1_NOMCLI")) > 0
														SE1->E1_NOMCLI := PadR(cNomeFin, TamSx3("E1_NOMCLI")[1])
													EndIf

													If !Empty(cFuncionario)
														If SE1->(FieldPos("E1_VEND1")) > 0
															SE1->E1_VEND1 := PadR(cFuncionario, TamSx3("E1_VEND1")[1])
														EndIf
														If SE1->(FieldPos("E1_CODFUNC")) > 0
															SE1->E1_CODFUNC := PadR(cFuncionario, TamSx3("E1_CODFUNC")[1])
														EndIf
													EndIf
													cParc := SOMA1(cParc)
													SE1->(MsUnlock())
												Else
													cQrySE1 := "UPDATE " + RetSqlName("SE1") + " SET "
													cQrySE1 += "E1_TIPO = '" + PadR("RC", TamSx3("E1_TIPO")[1]) + "', "
													cQrySE1 += "E1_NATUREZ = '" + PadR(cNatItm, TamSx3("E1_NATUREZ")[1]) + "', "
													cQrySE1 += "E1_CCUSTO = '" + PadR(cCCItm, TamSx3("E1_CCUSTO")[1]) + "', "
													cQrySE1 += "E1_XEVENTO = '" + PadR(cDesOrig, TamSx3("E1_XEVENTO")[1]) + "', "
													cQrySE1 += "E1_VALOR = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
													cQrySE1 += "E1_SALDO = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
													cQrySE1 += "E1_VALLIQ = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
													cQrySE1 += "E1_VLCRUZ = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
													cQrySE1 += "E1_HIST = '" + Left(cHistPad, TamSx3("E1_HIST")[1]) + "', "

													If !Empty(cFormaTrat) ; cQrySE1 += "E1_FORMAPG = '" + PadR(cFormaTrat, TamSx3("E1_FORMAPG")[1]) + "', " ; EndIf
														If !Empty(cBandeira)  ; cQrySE1 += "E1_CARTAO = '" + PadR(cBandeira, TamSx3("E1_CARTAO")[1]) + "', " ; EndIf
															If !Empty(cTransac)   ; cQrySE1 += "E1_NSUTEF = '" + PadR(cTransac, TamSx3("E1_NSUTEF")[1]) + "', " ; EndIf
																If !Empty(cAutorizPg) ; cQrySE1 += "E1_CARTAUT = '" + PadR(cAutorizPg, TamSx3("E1_CARTAUT")[1]) + "', " ; EndIf

																	// Grava Nome do Cliente no SE1
																	If Len(TamSx3("E1_NOMCLI")) > 0
																		cQrySE1 += "E1_NOMCLI = '" + PadR(cNomeFin, TamSx3("E1_NOMCLI")[1]) + "', "
																	EndIf

																	If !Empty(cFuncionario)
																		If Len(TamSx3("E1_VEND1")) > 0
																			cQrySE1 += "E1_VEND1 = '" + PadR(cFuncionario, TamSx3("E1_VEND1")[1]) + "', "
																		EndIf
																		If Len(TamSx3("E1_CODFUNC")) > 0
																			cQrySE1 += "E1_CODFUNC = '" + PadR(cFuncionario, TamSx3("E1_CODFUNC")[1]) + "', "
																		EndIf
																	EndIf

																	cQrySE1 := SubStr(cQrySE1, 1, Len(cQrySE1) - 2)
																	cQrySE1 += " WHERE R_E_C_N_O_ = " + cValToChar((cAliSE1)->REC)
																	TCSqlExec(cQrySE1)
																	(cAliSE1)->(DbSkip())
																EndIf

																// Grava no Multiplos Pagamentos do LOJA (SL4)
																RecLock("SL4", .T.)
																SL4->L4_FILIAL  := xFilial("SL4")
																SL4->L4_NUM     := cNumVenGer
																SL4->L4_DATA    := dConf
																SL4->L4_VALOR   := nVlrTitulo
																SL4->L4_FORMA   := PadR(cFormaTrat, TamSx3("L4_FORMA")[1])

																If SL4->(FieldPos("L4_ADMINIS")) > 0 .And. !Empty(cBandeira)
																	SL4->L4_ADMINIS := PadR(cBandeira, TamSx3("L4_ADMINIS")[1])
																EndIf
																If SL4->(FieldPos("L4_AUTORIZ")) > 0 .And. !Empty(cAutorizPg)
																	SL4->L4_AUTORIZ := PadR(cAutorizPg, TamSx3("L4_AUTORIZ")[1])
																EndIf
																If SL4->(FieldPos("L4_NSUTEF")) > 0 .And. !Empty(cTransac)
																	SL4->L4_NSUTEF := PadR(cTransac, TamSx3("L4_NSUTEF")[1])
																EndIf
																If SL4->(FieldPos("L4_CLIENTE")) > 0
																	SL4->L4_CLIENTE := cCliPad
																EndIf
																If SL4->(FieldPos("L4_LOJA")) > 0
																	SL4->L4_LOJA := cLojPad
																EndIf
																If SL4->(FieldPos("L4_MOEDA")) > 0
																	SL4->L4_MOEDA := 1
																EndIf
																SL4->(MsUnlock())

															Next nPag
															(cAliSE1)->(DbCloseArea())

															// ---------------------------------------------------------
															// 6. INJECAO VAREJO: SL1 e SLQ (Cupom / NFCE)
															// ---------------------------------------------------------
															RecLock("SL1", .T.)
															SL1->L1_FILIAL  := xFilial("SL1")
															SL1->L1_NUM     := cNumVenGer
															SL1->L1_DOC     := cDocPad
															SL1->L1_CLIENTE := cCliVarejo
															SL1->L1_LOJA    := cLojPad
															SL1->L1_VLRTOT  := nVlrLiqN
															SL1->L1_DESCONT := nVlrDescN
															SL1->L1_LEGADO  := cDocPad
															SL1->L1_TIPO    := "V"
															SL1->L1_SERIE   := cSerPad
															SL1->L1_EMISSAO := dConf
															SL1->L1_VEND    := cVendPad
															SL1->L1_SEGURO  := nVlrSegN
															SL1->L1_DESPESA := nVlrOutrN
															SL1->L1_VLRLIQ  := nVlrLiqN

															If SL1->(FieldPos("L1_CONDPG")) > 0
																SL1->L1_CONDPG := PadR("999", TamSx3("L1_CONDPG")[1])
															EndIf
															If SL1->(FieldPos("L1_TIPOCLI")) > 0 ; SL1->L1_TIPOCLI := cTipoCli ; EndIf
																If SL1->(FieldPos("L1_NOME")) > 0 .And. !Empty(cNomeFin)
																	SL1->L1_NOME := PadR(Left(cNomeFin, TamSx3("L1_NOME")[1]), TamSx3("L1_NOME")[1])
																EndIf
																If SL1->(FieldPos("L1_PDV")) > 0 ; SL1->L1_PDV := cPdvPad ; EndIf
																	If SL1->(FieldPos("L1_OPERADO")) > 0 ; SL1->L1_OPERADO := cOperador ; EndIf
																		If SL1->(FieldPos("L1_NOMCLI")) > 0 .And. !Empty(cNomeFin)
																			SL1->L1_NOMCLI := PadR(Left(cNomeFin, TamSx3("L1_NOMCLI")[1]), TamSx3("L1_NOMCLI")[1])
																		EndIf
																		If SL1->(FieldPos("L1_CGCCLI")) > 0 .And. !Empty(cCpfCnpj)
																			SL1->L1_CGCCLI := PadR(cCpfCnpj, TamSx3("L1_CGCCLI")[1])
																		EndIf
																		If SL1->(FieldPos("L1_DTOCORZ")) > 0 ; SL1->L1_DTOCORZ := dConf ; EndIf
																			If SL1->(FieldPos("L1_DESORIG")) > 0 ; SL1->L1_DESORIG := PadR(cDesOrig, TamSx3("L1_DESORIG")[1]) ; EndIf
																				MsUnlock()

																				RecLock("SLQ", .T.)
																				SLQ->LQ_FILIAL  := xFilial("SLQ")
																				SLQ->LQ_NUM     := cOrcamento
																				SLQ->LQ_CLIENTE := cCliVarejo
																				SLQ->LQ_LOJA    := cLojPad
																				SLQ->LQ_VLRTOT  := nVlrLiqN
																				SLQ->LQ_DESCONT := nVlrDescN
																				SLQ->LQ_TIPO    := "V"
																				SLQ->LQ_EMISSAO := dConf
																				SLQ->LQ_VEND    := cVendPad

																				If SLQ->(FieldPos("LQ_CONDPG")) > 0
																					SLQ->LQ_CONDPG := PadR("999", TamSx3("LQ_CONDPG")[1])
																				EndIf
																				If SLQ->(FieldPos("LQ_TIPOCLI")) > 0 ; SLQ->LQ_TIPOCLI := cTipoCli ; EndIf
																					If SLQ->(FieldPos("LQ_NOME")) > 0 .And. !Empty(cNomeFin)
																						SLQ->LQ_NOME := PadR(Left(cNomeFin, TamSx3("LQ_NOME")[1]), TamSx3("LQ_NOME")[1])
																					EndIf
																					If SLQ->(FieldPos("LQ_NOMCLI")) > 0 .And. !Empty(cNomeFin)
																						SLQ->LQ_NOMCLI := PadR(Left(cNomeFin, TamSx3("LQ_NOMCLI")[1]), TamSx3("LQ_NOMCLI")[1])
																					EndIf
																					If SLQ->(FieldPos("LQ_CGCCLI")) > 0 .And. !Empty(cCpfCnpj)
																						SLQ->LQ_CGCCLI := PadR(cCpfCnpj, TamSx3("LQ_CGCCLI")[1])
																					EndIf
																					If SLQ->(FieldPos("LQ_LEGADO")) > 0 ; SLQ->LQ_LEGADO := PadR(cDocPad, TamSx3("LQ_LEGADO")[1]) ; EndIf
																						MsUnlock()

																						If ValType(oItnsJ) == "A"
																							For nX := 1 To Len(oItnsJ)
																								If ValType(oItnsJ[nX]) == "J" .Or. ValType(oItnsJ[nX]) == "O"
																									cItemL2 := PadL(cValToChar(nX), nTamL2Item, "0")
																									cLogProd := ""
																									cProdLeg := U_FZ_STR_X(oItnsJ[nX], 'cod_Produto')

																									aProdDados := FATPI0806(cProdLeg, @cLogProd)
																									cInternoDB := ""
																									cDescProd  := ""

																									If Len(aProdDados) > 0
																										cInternoDB := aProdDados[1]
																										If Len(aProdDados) >= 5
																											cDescProd := aProdDados[5]
																										EndIf
																									Else
																										cInternoDB := cProdLeg
																									EndIf

																									If Empty(cDescProd)
																										cDescProd := U_FZ_STR_X(oItnsJ[nX], "des_Produto")
																									EndIf

																									nQtdItm     := Max(U_FZ_VAL_X(oItnsJ[nX], 'qtd_Produto'), 1)
																									nVlrUniItm  := U_FZ_VAL_X(oItnsJ[nX], 'vlr_Produto', 'valorunitario')
																									nDescItm    := Round(U_FZ_VAL_X(oItnsJ[nX], 'vlr_ProdutoDesconto') * nQtdItm, 2)
																									nVlrBrutItm := Round(nQtdItm * nVlrUniItm, 2)
																									nVlrLiqItm  := Round(nVlrBrutItm - nDescItm, 2)

																									RecLock("SL2", .T.)
																									SL2->L2_FILIAL  := xFilial("SL2")
																									SL2->L2_NUM     := cNumVenGer
																									SL2->L2_ITEM    := cItemL2
																									SL2->L2_PRODUTO := cInternoDB
																									SL2->L2_QUANT   := nQtdItm
																									SL2->L2_VRUNIT  := nVlrUniItm
																									SL2->L2_VLRITEM := nVlrBrutItm
																									SL2->L2_DOC     := cDocPad
																									SL2->L2_VALDESC := nDescItm

																									If SL2->(FieldPos("L2_DESCRI")) > 0  ; SL2->L2_DESCRI  := PadR(cDescProd, TamSx3("L2_DESCRI")[1]) ; EndIf
																										If SL2->(FieldPos("L2_VLRLIQ")) > 0  ; SL2->L2_VLRLIQ  := nVlrLiqItm ; EndIf
																											If SL2->(FieldPos("L2_VEND")) > 0    ; SL2->L2_VEND    := cVendPad ; EndIf
																												If SL2->(FieldPos("L2_LOCAL")) > 0   ; SL2->L2_LOCAL   := PadR("01", TamSx3("L2_LOCAL")[1]) ; EndIf
																													If SL2->(FieldPos("L2_SERIE")) > 0   ; SL2->L2_SERIE   := cSerPad ; EndIf
																														MsUnlock()

																														RecLock("SLR", .T.)
																														SLR->LR_FILIAL  := xFilial("SLR")
																														SLR->LR_NUM     := cOrcamento
																														SLR->LR_ITEM    := cItemL2
																														SLR->LR_PRODUTO := cInternoDB
																														SLR->LR_QUANT   := nQtdItm
																														SLR->LR_VRUNIT  := nVlrUniItm
																														SLR->LR_VLRITEM := nVlrBrutItm
																														SLR->LR_VALDESC := nDescItm
																														If SLR->(FieldPos("LR_VEND")) > 0  ; SLR->LR_VEND := cVendPad ; EndIf
																															If SLR->(FieldPos("LR_LOCAL")) > 0 ; SLR->LR_LOCAL := PadR("01", TamSx3("LR_LOCAL")[1]) ; EndIf
																																MsUnlock()
																															EndIf
																														Next nX
																													EndIf

																													jRes['status']    := 201
																													jRes['resultado'] := "Sucesso"
																													jRes['mensagem']  := "Nota Varejo Processada: " + xFilial("SF2") + " - " + AllTrim(cDocJson)
																													jRes['info']      := FATPI0802(cDocPad)

																													Return jRes

/*/{Protheus.doc} FATPI0802
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Gera PDF do Cupom Lendo da SF2/SD2. 
/*/
Static Function FATPI0802(cDocPad)
	Local oP        := Nil
	Local f         := "VENDA_" + AllTrim(cDocPad) + ".pdf"
	Local cP        := FATPI0803() + f
	Local nL        := 10
	Local nI        := 1
	Local nT        := 0
	Local oF8       := TFont():New("Courier New",, -8)
	Local oFB       := TFont():New("Courier New",, -10, .T.)
	Local cA        := GetNextAlias()
	Local cQ        := ""
	Local cCli      := ""
	Local cDocCli   := ""

	DbSelectArea("SF2")
	SF2->(DbSetOrder(1))

	If SF2->(DbSeek(xFilial("SF2") + cDocPad + "1"))
		cCli    := Posicione("SA1", 1, xFilial("SA1") + SF2->F2_CLIENTE + SF2->F2_LOJA, "A1_NOME")
		cDocCli := Posicione("SA1", 1, xFilial("SA1") + SF2->F2_CLIENTE + SF2->F2_LOJA, "A1_CGC")
	EndIf

	oP := FWMSPrinter():New(f, 6, .F., FATPI0803(), .T.)
	oP:SetPortrait()
	oP:SetPaperSize(18)
	oP:SetMargin(10, 10, 10, 10)
	oP:StartPage()

	oP:Say(nL, 40, "CAASP - VENDA FINALIZADA", oFB)
	nL += 15
	oP:Say(nL, 10, "DOC NF: " + AllTrim(cDocPad), oF8)
	nL += 12
	oP:Say(nL, 10, "CLIENTE: " + Left(cCli, 30), oF8)
	nL += 12
	oP:Say(nL, 10, "CPF/CNPJ: " + cDocCli, oF8)
	nL += 15

	cQ := "SELECT D2_COD, D2_QUANT, D2_TOTAL FROM " + RetSqlName("SD2") + " WHERE D2_DOC = '" + cDocPad + "' AND D_E_L_E_T_ = ' '"
	MpSysOpenQuery(cQ, cA)

	While (cA)->(!Eof())
		oP:Say(nL, 10, StrZero(nI, 2), oF8)
		oP:Say(nL, 40, (cA)->D2_COD, oF8)
		oP:Say(nL, 135, Transform((cA)->D2_QUANT, "@E 999"), oF8)
		oP:Say(nL, 210, Transform((cA)->D2_TOTAL, "@E 99,999.99"), oF8)
		nT += (cA)->D2_TOTAL
		nI += 1
		nL += 12
		(cA)->(DbSkip())
	EndDo

	(cA)->(DbCloseArea())

	nL += 10
	oP:Say(nL, 120, "SUBTOTAL R$:", oF8)
	oP:Say(nL, 210, Transform(nT, "@E 99,999.99"), oF8)

	If SF2->F2_DESCONT > 0
		nL += 12
		oP:Say(nL, 120, "DESCONTO R$:", oF8)
		oP:Say(nL, 210, Transform(SF2->F2_DESCONT, "@E 99,999.99"), oF8)
	EndIf

	If SF2->F2_FRETE > 0
		nL += 12
		oP:Say(nL, 120, "FRETE R$:", oF8)
		oP:Say(nL, 210, Transform(SF2->F2_FRETE, "@E 99,999.99"), oF8)
	EndIf

	nL += 12
	oP:Say(nL, 120, "TOTAL NF R$:", oFB)
	oP:Say(nL, 210, Transform(SF2->F2_VALBRUT, "@E 99,999.99"), oFB)

	oP:EndPage()
	oP:Print()
Return cP

/*/{Protheus.doc} FATPI0803
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Recupera ou cria diretorio para gravacao dos arquivos.
/*/
Static Function FATPI0803()
	Local d := "\" + AllTrim(GetSrvProfString("StartDir", "system")) + "\BATCH_LOJA\"
	If !File(d)
		MakeDir(d)
	EndIf
Return d

/*/{Protheus.doc} FATPI0804
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Recupera Empresa e Filial da SM0 via CNPJ formatado. 
/*/
Static Function FATPI0804(c)
	Local aR := {}
	Local cA := GetNextAlias()
	Local cQ := ""

	cQ := "SELECT M0_CODIGO, M0_CODFIL FROM " + RetSqlName("SM0") + " WHERE REPLACE(REPLACE(REPLACE(M0_CGC, '.', ''), '-', ''), '/', '') = '" + c + "'"
	MpSysOpenQuery(cQ, cA)

	If (cA)->(!Eof())
		aAdd(aR, AllTrim((cA)->M0_CODIGO))
		aAdd(aR, AllTrim((cA)->M0_CODFIL))
	EndIf
	(cA)->(DbCloseArea())
Return aR

/*/{Protheus.doc} FATPI0805
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Busca o Cadastro de Clientes (A1_COD e A1_LOJA) via Legado. 
/*/
Static Function FATPI0805(cTipoBusca, cChaveBusca, cCodCli, cLojaCli)
	Local lRetorno  := .F.
	Local cAliasQry := GetNextAlias()
	Local cQuery    := ""

	cQuery := "SELECT A1_COD, A1_LOJA FROM " + RetSqlName("SA1") + " WHERE A1_LEGADO = '" + AllTrim(cChaveBusca) + "' AND D_E_L_E_T_ = ' '"
	MpSysOpenQuery(cQuery, cAliasQry)

	If (cAliasQry)->(!Eof())
		cCodCli  := (cAliasQry)->(FieldGet(1))
		cLojaCli := (cAliasQry)->(FieldGet(2))
		lRetorno := .T.
	EndIf
	(cAliasQry)->(DbCloseArea())
Return lRetorno

/*/{Protheus.doc} FATPI0806
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Busca Produto via Legado e retorna Array com Dados Cadastrais e Descricao (SB1).
/*/
Static Function FATPI0806(cProdLeg, cLogProd)
	Local cB1Cod  := ""
	Local cB1Um   := ""
	Local cB1Grp  := ""
	Local cB1Cta  := ""
	Local cB1Desc := ""
	Local aR      := {}

	DbSelectArea("SB1")
	SB1->(DbOrderNickName("LEGADO"))

	If SB1->(DbSeek(xFilial("SB1") + PadR(AllTrim(cProdLeg), TamSx3("B1_LEGADO")[1])))
		cB1Cod  := SB1->B1_COD
		cB1Um   := SB1->B1_UM
		cB1Grp  := SB1->B1_GRUPO
		cB1Cta  := SB1->B1_CONTA
		cB1Desc := SB1->B1_DESC
	EndIf

	If !Empty(cB1Cod)
		aAdd(aR, cB1Cod)
		aAdd(aR, cB1Um)
		aAdd(aR, cB1Grp)
		aAdd(aR, cB1Cta)
		aAdd(aR, cB1Desc)
	Else
		cLogProd := cProdLeg
	EndIf
Return aR

/*/{Protheus.doc} FATPI0807
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Funcao de Apoio para Extracao Anti-Leak JsonObject.
/*/
Static Function FATPI0807(oHead, cCampoReq, cCampoPag, nVlrFall)
	Local cRet    := ""
	Local oItm    := Nil
	Local xRecVal := Nil
	Local aPag    := Nil

	If ValType(oHead) == "J" .Or. ValType(oHead) == "O"
		If oHead:HasProperty("recebimentos")
			xRecVal := oHead["recebimentos"]
			If ValType(xRecVal) == "A"
				If Len(xRecVal) > 0
					oItm := xRecVal[1]
				EndIf
			EndIf
		ElseIf oHead:HasProperty("pagamentos")
			aPag := oHead["pagamentos"]
			If ValType(aPag) == "A"
				If Len(aPag) > 0
					oItm := aPag[1]
				EndIf
			EndIf
		EndIf
	EndIf

	If ValType(oItm) == "O" .Or. ValType(oItm) == "J"
		If cCampoReq == "VLR"
			If oItm:HasProperty("vlr_Recebimento")
				cRet := oItm["vlr_Recebimento"]
			EndIf

			If ValType(cRet) != "N" .Or. cRet <= 0
				If oItm:HasProperty("vlr_Pagamento")
					cRet := oItm["vlr_Pagamento"]
				EndIf
			EndIf

			If ValType(cRet) != "N" .Or. cRet <= 0
				If oItm:HasProperty("vlr_Transacao")
					cRet := oItm["vlr_Transacao"]
				EndIf
			EndIf
		Else
			If oItm:HasProperty(cCampoReq)
				cRet := cValToChar(oItm[cCampoReq])
			ElseIf !Empty(cCampoPag) .And. oItm:HasProperty(cCampoPag)
				cRet := cValToChar(oItm[cCampoPag])
			EndIf
		EndIf
	EndIf

	If cCampoReq == "VLR" .And. ValType(cRet) != "N"
		cRet := 0
	EndIf

	If cCampoReq == "VLR" .And. cRet <= 0
		cRet := nVlrFall
	EndIf

Return cRet
