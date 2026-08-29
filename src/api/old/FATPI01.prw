#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

//V1 GIT
/*
+----------------------------------------------------------------------------+
| Autor: Antonio Nunes O Jr | Data: 03/04/2026                               |
| Descritivo: FATPI01 - API REST Integracao CAASP (v3900.302)                |
|             Completo: Unicidade, Bancos, Financeiro, Custos e Impostos     |
|             Fixes: Mapeamento de D2_DESCON nativo na FZ_PROS_X             |
+----------------------------------------------------------------------------+
*/

WSRESTFUL FATPI01 DESCRIPTION 'Hub de Vendas e Compras CAASP'
	WSMETHOD POST DESCRIPTION 'Processamento Global' WSSYNTAX "/fatpi01" PATH "" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI01
	// --- 1. DECLARACAO GERAL DE VARIAVEIS ---
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
	Local aRet         := {}
	Local cCnpj        := ""
	Local cNF          := ""
	Local cSer         := ""
	Local cOper        := ""
	Local lOk          := .T.
	Local cTab         := ""
	Local cCod         := ""
	Local cLoja        := ""
	Local cFil         := ""
	Local cCliD        := "000001"
	Local dVencto      := CToD("//")
	Local cCondSafe    := ""
	Local cPCNew       := ""
	Local cLeg         := ""
	Local nI           := 0
	Local cQryAux      := ""
	Local cAliAux      := ""
	Local cAuxC        := ""
	Local cProdLeg     := ""
	Local cProdInt     := ""

	// Variaveis de Roteamento e Filtros
	Local cCheckCFOP   := ""
	Local cKeyDest     := ""
	Local lIsTransf    := .F.
	Local oMotorRegras := Nil
	Local aRetCfop     := {}
	Local nValNF       := 0
	Local cNatOp       := ""
	Local cCnpjEmit    := ""
	Local cCnpjDest    := ""
	Local cUsuario     := ""

	// Variaveis do Salto de Transferencia CONVENIOS
	Local aEmpDest     := {}
	Local cFilDest     := ""
	Local aRetTransf   := {}

	// Variaveis de Ambiente
	Local cEmpAPI      := "01"
	Local cFilAPI      := "01001"
	Local lAbreEnv     := .F.
	Local cOldRestNfe  := ""
	//Local aEmp  := {}
	Local cCn
	Local lCest
	Local lNcm
	Local cPesqEmit
	Local cPesqDest
	Local lCli
	Local lFor

	Private __cBatch   := "1"

	// --- 2. PREPARACAO DE AMBIENTE ---
	If Type("cEmpAnt") == "U" .Or. Empty(cEmpAnt) .Or. Select("SX6") == 0
		//RpcSetEnv(cEmpAPI, cFilAPI, Nil, Nil, "FAT")
		cFilAnt := cFilAPI
		lAbreEnv := .T.
	EndIf

	cOldRestNfe := SuperGetMv("MV_RESTNFE", .F., "S")
	PutMv("MV_RESTNFE", "N")

	Self:SetContentType('application/json')

	If !Empty(jJson:FromJson(cJson))
		lOk := .F.
		nStat := 400
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['detalhe']   := "Estrutura JSON"
		jRes['mensagem']  := "JSON invalido ou vazio."

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		If lAbreEnv
			//RpcClearEnv()
		EndIf
		Return .T.
	EndIf

	// --- 3. IDENTIFICACAO DO OBJETO E NATUREZA ---
	aInv := jJson['notas']
	If ValType(aInv) != "A"
		aInv := jJson['items']
	EndIf

	If ValType(aInv) == "A" .And. Len(aInv) > 0
		oHead   := aInv[1]
		cModDoc := U_FZ_STR_X(oHead, 'cod_Mod', 'modelo')
		aPrd    := oHead['itens']

		cNatOp := Upper(AllTrim(U_FZ_STR_X(oHead, 'des_NatOp')))

		If ValType(aPrd) == "A" .And. Len(aPrd) > 0
			cCheckCFOP := Upper(U_FZ_STR_X(aPrd[1], 'cod_ProdutoCFOP', 'cfop'))

			If ("REM P/ VENDA FORA" $ cNatOp .Or. "REMESSA P/ VENDA FORA" $ cNatOp) .AND. SUBSTR(cCheckCFOP,1,1) $ '5/6'
				cCheckCFOP := "5904"
			EndIf

			If "5557" $ cCheckCFOP .Or. "TRANSF" $ cCheckCFOP .Or. "TRANSF" $ cNatOp .Or. "5152" $ cCheckCFOP
				lIsTransf := .T.
			EndIf
		EndIf

		cCnpj := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, 'num_SubseccaoCNPJ', 'num_SubseccaoCNPJ'))
		aEmp := U_FZ_SM0_X(cCnpj)

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
			// --- 5. ROTEAMENTO FISCAL (SA1 vs SA2 E CONTRAPARTE) ---
			dVencto := U_FZ_DATA_X(U_FZ_STR_X(oHead, 'dta_Emissao', 'dta_Vencimento'))
			If !Empty(dVencto)
				dDataBase := dVencto
			EndIf

			cCondSafe := PadR(U_FZ_COND_X("004"), 3)
			oMotorRegras := U_FATCFOP01()
			cAuxC := cCheckCFOP

			cCnpjEmit := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, 'des_EmitDocumento', 'cnpJ_FORNECEDOR'))
			cCnpjDest := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, 'des_DestDocumento', 'cpf'))

			If (U_FZ_STR_X(oHead, 'des_Finalidade') == "4" .And. "DEVOLUCAO DE VENDA" $ cNatOp) .Or. ;
					("VENDA" $ cNatOp .And. cModDoc == "65")
				If ValType(aPrd) == "A" .And. Len(aPrd) > 0
					cUsuario := AllTrim(U_FZ_STR_X(oHead, 'cod_Exportacao'))
				EndIf
			EndIf

			If "TRANSF" $ cNatOp .And. ValType(aPrd) == "A" .And. Len(aPrd) > 0
				cCnpjEmit := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, 'des_EmitDocumento', 'cnpJ_FORNECEDOR'))
			EndIf

			If !Empty(cUsuario)
				cQryAux := "SELECT A1_COD, A1_LOJA FROM " + RetSqlName("SA1") + " WHERE TRIM(A1_LEGADO) = '" + cUsuario + "' AND D_E_L_E_T_ = ' '"
				cAliAux := GetNextAlias()
				MpSysOpenQuery(cQryAux, cAliAux)
				If (cAliAux)->(!Eof())
					cCod  := (cAliAux)->A1_COD
					cLoja := (cAliAux)->A1_LOJA
					cFil  := xFilial("SA1")
				EndIf
				(cAliAux)->(DbCloseArea())

				cTab  := "SA1"
				cKeyDest := cUsuario

				If cModDoc == "65"
					cOper := "S"
				Else
					cOper := "D"
				EndIf
			Else
				If cCnpj == cCnpjEmit
					cKeyDest := cCnpjDest
				Else
					cKeyDest := cCnpjEmit
				EndIf

				If lIsTransf .Or. cAuxC $ "5557/1557/5152/5409/1152/1409"
					If cCnpj == cCnpjDest .And. cCnpj != cCnpjEmit
						cOper := "E"
						cTab  := "SA2"
					ElseIf cCnpj == cCnpjEmit .And. cCnpj != cCnpjDest
						cOper := "S"
						cTab  := "SA1"
					Else
						If Left(cAuxC, 1) $ "1/2"
							cOper := "E"
						Else
							cOper := "S"
						EndIf
						cTab  := "SA2"
					EndIf

				ElseIf cAuxC $ "1202/1411/2202"
					cOper := "D"
					cTab  := "SA1"
				ElseIf cAuxC $ "5202/5411/6202"
					cOper := "S"
					cTab  := "SA2"
				ElseIf Left(cAuxC, 1) $ "1/2/3"
					cOper := "E"
					cTab  := "SA2"
				ElseIf Left(cAuxC, 1) $ "5/6/7"
					cOper := "S"
					cTab  := "SA1"
				Else
					cOper := "E"
					cTab  := "SA2"
				EndIf

				U_FZ_SQL_X(cTab, cKeyDest, aEmp[2], @cCod, @cLoja, @cFil)

				If Empty(cCod) .And. cTab == "SA1" .And. cOper == "S"
					cCod := cCliD
					cLoja := "01"
					U_FZ_SQL_X(cTab, cCod, aEmp[2], @cCod, @cLoja, @cFil)
				EndIf
			EndIf

			IF cOper == 'D' .AND. cTab == 'SA2'
				SA2->(DbSetOrder(3))
				If SA2->(DbSeek(xFilial("SA2") + cCnpjEmit))
					cCod := SA2->A2_COD
					cLoja := SA2->A2_LOJA
				Endif
			ENDIF

			cNat := U_FZ_STR_X(oHead, "cod_NaturezaFinanceira")
			cNat := PADR(ALLTRIM(cNat),TamSx3("ED_CODIGO")[1],'')

			DbSelectArea("SED")
			SED->(DbSetOrder(1))

			If !SED->(DbSeek(xFilial("SED") + cNat))
				lOk := .F.
				nStat := 201
				jRes['status']    := nStat
				jRes['resultado'] := "Falha"
				jRes['erro']      := "Natureza"
				jRes['detalhe']   := cNat
				jRes['mensagem']  := "Natureza (cod_NaturezaFinanceira) não está cadastrada no sistema." + cNat
			EndIf

			If lIsTransf
				cPesqDest := U_FZ_STR_X(oHead, "des_DestDocumento")
				cPesqEmit := U_FZ_STR_X(oHead, "num_SubseccaoCNPJ")
				DbSelectArea("SA1")
				SA1->(DbSetOrder(3))
				DbSelectArea("SA2")
				SA2->(DbSetOrder(3))
				lFor := .T.
				lCli := .T.

				If !SA2->(DbSeek(xFilial("SA2") + cPesqEmit))
					lFor := .F.
					lOk := .F.
					nStat := 201
					jRes['status']    := nStat
					jRes['resultado'] := "Falha"
					jRes['erro']      := 'Fornecedor'
					jRes['detalhe']   := cPesqEmit
					jRes['mensagem']  := "Filial Origem não está cadastrada como Fornecedor."
				Endif

				If !SA1->(DbSeek(xFilial("SA1") + cPesqDest))
					lCli := .F.
					lOk := .F.
					nStat := 201
					jRes['status']    := nStat
					jRes['resultado'] := "Falha"
					jRes['erro']      := 'Cliente'
					jRes['detalhe']   := AllTrim(U_FZ_STR_X(oHead, 'cod_Exportacao'))
					jRes['mensagem']  := "Filial Destino não está cadastrada como Cliente."
				Endif

			Endif

			If Empty(cCod)
				//If fContemStr(',', cCod)
				lOk := .F.
				nStat := 201
				jRes['status']    := nStat
				jRes['resultado'] := "Falha"
				jRes['erro']      := IIF(cOper=='S' .OR. cOper=='D','Cliente',"Fornecedor")
				jRes['detalhe']   := cKeyDest
				jRes['mensagem']  := "Destinatario nao localizado. Doc: " + cKeyDest
				//else
				//EndIf
			Endif

			SA2->(DbSetOrder(3))

			If !SA2->(DbSeek(xFilial("SA2") + cCnpjEmit))
				lOk := .F.
				nStat := 201
				jRes['status']    := nStat
				jRes['resultado'] := "Falha"
				jRes['erro']      := "Fornecedor"
				jRes['detalhe']   := cCnpjEmit
				jRes['mensagem']  := "Emitente não está cadastrado como fornecedor na filial destino. CNPJ: " + cCnpjEmit
			EndIf

			SA2->(DbSetOrder(1))

			// --- 6. NUMERACAO E TRATAMENTO PRODUTOS ---
			If lOk
				nValNF := U_FZ_VAL_X(oHead, 'num_NF', 'num_NotaFiscal')
				If nValNF == 0
					nValNF := U_FZ_VAL_X(oHead, 'cod_ReciboVenda')
				EndIf

				If nValNF == 0
					cNF := GetSxeNum("SF2", "F2_DOC")
					While .T.
						cQryAux := "SELECT F2_DOC FROM " + RetSqlName("SF2") + " WHERE F2_DOC = '" + PadL(AllTrim(cNF), TamSx3("F2_DOC")[1], "0") + "' AND D_E_L_E_T_ = ' '"
						cAliAux := GetNextAlias()
						MpSysOpenQuery(cQryAux, cAliAux)
						If (cAliAux)->(Eof())
							(cAliAux)->(DbCloseArea())
							Exit
						EndIf
						(cAliAux)->(DbCloseArea())
						cNF := Soma1(cNF)
					EndDo
					ConfirmSx8()
					cNF := PadL(AllTrim(cNF), TamSx3("F2_DOC")[1], "0")
				Else
					cNF := PadL(AllTrim(cValToChar(nValNF)), TamSx3("F2_DOC")[1], "0")
				EndIf

				cSer := AllTrim(U_FZ_STR_X(oHead, 'cod_Serie', 'num_Serie'))
				If Empty(cSer)
					cSer := "1"
				EndIf
				cSer := PadR(cSer, TamSx3("F2_SERIE")[1], " ")
				cLeg := cNF

				If cOper == "S"
					cQryAux := "SELECT F2_DOC FROM " + RetSqlName("SF2") + " WHERE F2_DOC = '" + cNF + "' AND F2_SERIE = '" + cSer + "' AND F2_CLIENTE = '" + cCod + "' AND F2_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
				Else
					cQryAux := "SELECT F1_DOC FROM " + RetSqlName("SF1") + " WHERE F1_DOC = '" + cNF + "' AND F1_SERIE = '" + cSer + "' AND F1_FORNECE = '" + cCod + "' AND F1_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
				EndIf

				cAliAux := GetNextAlias()
				MpSysOpenQuery(cQryAux, cAliAux)
				If (cAliAux)->(!Eof())
					cCn  := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
					aEmp := FATPIEMP(cCn)

					nStat := 200
					jRes['status']    := nStat
					jRes['resultado'] := "Sucesso"
					jRes['doc']       := "Nota: " + IIF(Len(aEmp) > 0,iif(aEmp[2] != cFilAnt,aEmp[2],cFilAnt),cFilAnt) + " - " + cNF
					jRes['info']      := "Nota ja processada anteriormente."
					Self:setStatus(nStat)
					Self:SetResponse(EncodeUTF8(jRes:toJSON()))
					(cAliAux)->(DbCloseArea())
					PutMv("MV_RESTNFE", cOldRestNfe)
					Return .T.
				EndIf
				(cAliAux)->(DbCloseArea())

				cQryAux := "UPDATE " + RetSqlName("SFT") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE FT_NFISCAL = '" + cNF + "' AND FT_SERIE = '" + cSer + "' AND FT_CLIEFOR = '" + cCod + "' AND FT_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
				TCSqlExec(cQryAux)
				cQryAux := "UPDATE " + RetSqlName("SF3") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE F3_NFISCAL = '" + cNF + "' AND F3_SERIE = '" + cSer + "' AND F3_CLIEFOR = '" + cCod + "' AND F3_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
				TCSqlExec(cQryAux)

				For nI := 1 To Len(aPrd)
					cProdLeg := AllTrim(U_FZ_STR_X(aPrd[nI], 'cod_Produto'))
					cProdInt := ""

					lCest := .T.
					lNcm  := .T.

					DbSelectArea("SB1")
					SB1->(DbOrderNickName("LEGADO"))
					If SB1->(DbSeek(xFilial("SB1") + PadR(cProdLeg, TamSx3("B1_LEGADO")[1])))
						cProdInt := AllTrim(SB1->B1_COD)
						aPrd[nI]['cod_Produto'] := cProdInt

						if !Empty(aPrd[nI]['des_ProdutoCEST'])
							lCest := BuscaCad(aPrd[nI]['des_ProdutoCEST'],1)
						Endif

						if !Empty(aPrd[nI]['des_ProdutoNCM'])
							lNcm  := BuscaCad(aPrd[nI]['des_ProdutoNCM'],2)
						Endif

						if lCest .and. lNcm
							If RecLock("SB1", .F.)
								SB1->B1_POSIPI := aPrd[nI]['des_ProdutoNCM']
								SB1->B1_CEST   := aPrd[nI]['des_ProdutoCEST']
								SB1->(MsUnlock())
							Endif
						else
							lOk := .F.
							nStat := 201
							jRes['status']    := nStat
							jRes['resultado'] := "Falha"
							jRes['erro']      := "NCM/CEST"
							jRes['detalhe']   := IIF(!Empty(aPrd[nI]['des_ProdutoNCM']),aPrd[nI]['des_ProdutoNCM'],'Nil') + '/' + IIF(!Empty(aPrd[nI]['des_ProdutoCEST']),aPrd[nI]['des_ProdutoCEST'],'Nil')
							jRes['mensagem']  := "NCM e/ou CEST não cadastrado." + Space(1) + IIF(!Empty(aPrd[nI]['des_ProdutoNCM']),aPrd[nI]['des_ProdutoNCM'],'Nil') + '/' + IIF(!Empty(aPrd[nI]['des_ProdutoCEST']),aPrd[nI]['des_ProdutoCEST'],'Nil')
							Self:setStatus(nStat)
							Self:SetResponse(EncodeUTF8(jRes:toJSON()))
							PutMv("MV_RESTNFE", cOldRestNfe)
							If lAbreEnv
								//RpcClearEnv()
							EndIf
							Return .T.
						EndIf
					EndIf

					If Empty(cProdInt)
						lOk := .F.
						nStat := 201
						jRes['status']    := nStat
						jRes['resultado'] := "Falha"
						jRes['erro']      := "Produto"
						jRes['detalhe']   := cProdLeg
						jRes['mensagem']  := "Produto nao cadastrado (Item " + cValToChar(nI) + ") Legado: " + cProdLeg

						Self:setStatus(nStat)
						Self:SetResponse(EncodeUTF8(jRes:toJSON()))
						PutMv("MV_RESTNFE", cOldRestNfe)
						If lAbreEnv
							//RpcClearEnv()
						EndIf
						Return .T.
					EndIf

					U_FZ_FIX_PROD(cProdInt, aPrd[nI])

					cAuxC := U_FZ_LIMPA_X(U_FZ_STR_X(aPrd[nI], 'cod_ProdutoCFOP', 'cfop'))

					If "REM P/ VENDA FORA" $ cNatOp .Or. "REMESSA P/ VENDA FORA" $ cNatOp
						cAuxC := "5904"
					EndIf

					cAuxC := U_FZ_INVERT_CFOP(cAuxC, cOper)

					aRetCfop := oMotorRegras:ProcessaRegras(aPrd[nI], cAuxC, "")

					If Len(AllTrim(aRetCfop[1])) == 3 .And. Len(AllTrim(aRetCfop[2])) >= 4
						aPrd[nI]['cod_ProdutoCFOP'] := PadR(aRetCfop[2], 5)
						aPrd[nI]['_TES_CACHE']      := PadR(aRetCfop[1], 3)
					Else
						aPrd[nI]['cod_ProdutoCFOP'] := PadR(aRetCfop[1], 5)
						aPrd[nI]['_TES_CACHE']      := PadR(aRetCfop[2], 3)
					EndIf

					If Empty(aPrd[nI]['cod_ProdutoCFOP'])
						aPrd[nI]['cod_ProdutoCFOP'] := cAuxC
					EndIf

					DbSelectArea("SF4")
					SF4->(DbSetOrder(1))

					If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .OR. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
						cQryAux := "SELECT F4_CODIGO FROM " + RetSqlName("SF4") + " WHERE F4_CF='" + PadR(AllTrim(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("F4_CF")[1]) + "' AND F4_MSBLQL <> '1' AND D_E_L_E_T_=' ' ORDER BY F4_ESTOQUE DESC"
						cAliAux := GetNextAlias()
						MpSysOpenQuery(cQryAux, cAliAux)
						If (cAliAux)->(!Eof())
							aPrd[nI]['_TES_CACHE'] := (cAliAux)->F4_CODIGO
						EndIf
						(cAliAux)->(DbCloseArea())
					EndIf

					If Empty(AllTrim(aPrd[nI]['_TES_CACHE'])) .OR. !SF4->(DbSeek(xFilial("SF4") + AllTrim(aPrd[nI]['_TES_CACHE'])))
						lOk := .F.
						nStat := 201
						jRes['status']    := nStat
						jRes['resultado'] := "Falha"
						jRes['erro']      := "TES"
						jRes['mensagem']  := "TES nao localizado no cadastro (SF4) da filial atual para o CFOP " + AllTrim(aPrd[nI]['cod_ProdutoCFOP']) + ". Verifique as configuracoes fiscais."
						Exit
					EndIf

					If cOper == "D"
						cQryAux := "SELECT D2_DOC, D2_SERIE, D2_ITEM FROM " + RetSqlName("SD2") + " WHERE D2_FILIAL = '" + xFilial("SD2") + "' AND D2_CLIENTE = '" + cCod + "' AND D2_LOJA = '" + cLoja + "' AND D2_COD = '" + aPrd[nI]['cod_Produto'] + "' AND D_E_L_E_T_ = ' ' ORDER BY D2_EMISSAO DESC"
						cAliAux := GetNextAlias()
						MpSysOpenQuery(cQryAux, cAliAux)
						If (cAliAux)->(!Eof())
							aPrd[nI]['_NFORI']   := (cAliAux)->D2_DOC
							aPrd[nI]['_SERIORI'] := (cAliAux)->D2_SERIE
							aPrd[nI]['_ITEMORI'] := (cAliAux)->D2_ITEM
						EndIf
						(cAliAux)->(DbCloseArea())
					EndIf
				Next nI

				// --- 7. DISPARO DOS MOTORES ---
				If lOk
					U_FZ_SETFCA(cTab, cCod, cLoja, cCondSafe, oHead)

					If cOper == "D" .AND. ALLTRIM(cAuxC) $ "1202/1411/2202"
						aRet := U_FZ_PRDEV_X(aPrd, oHead, cCod, cLoja, cNF, cSer, cTab, cFil, 0, cCondSafe)
						If aRet[1]
							nStat := 201
							jRes['status']    := nStat
							jRes['resultado'] := "Sucesso"
							jRes['doc']       := "Nota: " + xFilial("SF1") + " - " + cValToChar(aRet[2])
							jRes['info']      := "NFE Devolucao Gerada e Classificada."

							// ---> GATILHO DA MARRETA FINANCEIRA PARA COMPRAS (SE2) <---
							JSON_COMPRA(cNF, cSer, cCod, cLoja, aPrd, oHead, cTab)
						Else
							lOk := .F.
							nStat := 201
							jRes['status']    := nStat
							jRes['resultado'] := "Falha"
							jRes['erro']      := IIF(aRet[3],"NFORIGEM","MATA103_DEV")
							jRes['mensagem']  := cValToChar(aRet[2])
						EndIf

					ElseIf cOper == "S"

						cQryAux := "SELECT X5_CHAVE FROM " + RetSqlName("SX5") + " WHERE X5_FILIAL = '" + xFilial("SX5") + "' AND X5_TABELA = '01' AND X5_CHAVE = '" + cSer + "' AND D_E_L_E_T_ = ' '"
						cAliAux := GetNextAlias()
						MpSysOpenQuery(cQryAux, cAliAux)
						If (cAliAux)->(Eof())
							lOk := .F.
							nStat := 201
							jRes['status']    := nStat
							jRes['resultado'] := "Falha"
							jRes['erro']      := "SERIE_SX5"
							jRes['mensagem']  := "Serie '" + AllTrim(cSer) + "' nao cadastrada na Tabela 01 (SX5) da filial " + xFilial("SX5") + ". O Protheus abortou a execucao para evitar o erro fatal 'Problema Numeracao NF'."
						EndIf

						(cAliAux)->(DbCloseArea())

						If lOk
							aRet := U_FZ_PROS_X(aPrd, oHead, cCod, cLoja, cLeg, cSer, cFil, cTab, lIsTransf, cNF, cSer, cLeg, cCondSafe)
							If aRet[1]
								nStat := 201
								jRes['status']    := nStat
								jRes['resultado'] := "Sucesso"
								jRes['doc']       := "Nota: " + xFilial("SF2") + " - " + cValToChar(aRet[2])
								jRes['info']      := "Faturamento Direto Realizado"

								If lIsTransf .And. cCnpjEmit != cCnpjDest
									aEmpDest := U_FZ_SM0_X(cCnpjDest)
									If Len(aEmpDest) >= 2
										cFilDest := aEmpDest[2]
										aRetTransf := U_FATPI0101(aPrd, oHead, cCnpjEmit, cNF, cSer, aEmpDest,lIsTransf)

										If aRetTransf[1]
											jRes['info'] += " | CONVENIOS: Entrada automatica gerada na filial " + cFilDest + "."
										Else
											FZ_ROLLBACK_NF(cNF, cSer, cCod, cLoja)

											nStat := 201
											jRes['status']    := nStat
											jRes['resultado'] := "Falha"
											jRes['erro']      := "ROLLBACK_CONVENIOS"
											jRes['mensagem']  := "Falha ao gerar Entrada na filial " + cFilDest + ". Motivo: " + cValToChar(aRetTransf[2]) + " | A Saida (SF2) na origem foi totalmente ESTORNADA para manter a integridade."

											jRes:DelName('doc')
											jRes:DelName('info')
										EndIf
									EndIf
								EndIf

							Else
								lOk := .F.
								nStat := 201
								jRes['status']    := nStat
								jRes['resultado'] := "Falha"
								jRes['erro']      := IIF(aRet[3],'NFORIGEM',"MANFS2NFS")
								jRes['mensagem']  := cValToChar(aRet[2])
							EndIf
						EndIf


					Else
						aRet := U_FZ_PROC_X(aPrd, oHead, cCod, cLoja, cLeg, aEmp, cTab, cFil, "", cCondSafe)
						If aRet[1]

							cPCNew := aRet[3]
							aRet := U_FZ_PRON_X(aPrd, oHead, cCod, cLoja, cNF, cSer, cPCNew, cTab, cFil, 0, cCondSafe,lIsTransf)
							If aRet[1]
								nStat := 201
								jRes['status']    := nStat
								jRes['resultado'] := "Sucesso"
								jRes['doc']       := "Nota: " + xFilial("SF1") + " - " + cValToChar(aRet[2])
								jRes['info']      := "Pedido e NFE Gerados: " + cPCNew

								// ---> GATILHO DA MARRETA FINANCEIRA PARA COMPRAS (SE2) <---
								JSON_COMPRA(cNF, cSer, cCod, cLoja, aPrd, oHead, cTab)
								FZ_GER_E2(cNF, cSer, cCod, cLoja, aPrd, oHead, cTab,SE2->(RECNO()))

							Else
								lOk := .F.
								nStat := 200
								jRes['status']    := nStat
								jRes['resultado'] := "Falha"
								jRes['erro']      := "MATA103"
								jRes['mensagem']  := cValToChar(aRet[2])
							EndIf
						Else
							lOk := .F.
							nStat := 201
							jRes['status']    := nStat
							jRes['resultado'] := "Falha"
							jRes['erro']      := "MATA120"
							jRes['mensagem']  := cValToChar(aRet[2])
						EndIf
					EndIf
				EndIf

				If !jRes:HasProperty('status')
					lOk := .F.
					nStat := 400
					jRes['status']    := nStat
					jRes['resultado'] := "Falha"
					jRes['erro']      := "Roteamento"
					jRes['mensagem']  := "Erro desconhecido no roteamento do Motor."
				EndIf
			EndIf
		EndIf
	EndIf

	PutMv("MV_RESTNFE", cOldRestNfe)

	Self:setStatus(nStat)
	Self:SetResponse(EncodeUTF8(jRes:toJSON()))
	FreeObj(jJson)
	FreeObj(jRes)

	If lAbreEnv
		//RpcClearEnv()
	EndIf

Return lRet

// ==========================================================================
// FUNCAO DE ROLLBACK - ESTORNA SAIDA (SF2) SE A ENTRADA FALHAR
// ==========================================================================
Static Function FZ_ROLLBACK_NF(cDoc, cSer, cCli, cLoja)
	Local cQryAux := ""
	Local cAliAux := ""
	Local nQtd    := 0
	Local cProd   := ""
	Local cLoc    := ""

	// 1. Estornar Saldo em Estoque (SB2)
	cQryAux := "SELECT D2_COD, D2_LOCAL, D2_QUANT FROM " + RetSqlName("SD2") + " WHERE D2_DOC = '" + cDoc + "' AND D2_SERIE = '" + cSer + "' AND D2_CLIENTE = '" + cCli + "' AND D2_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	While (cAliAux)->(!Eof())
		cProd := (cAliAux)->D2_COD
		cLoc  := (cAliAux)->D2_LOCAL
		nQtd  := (cAliAux)->D2_QUANT

		DbSelectArea("SB2")
		SB2->(DbSetOrder(1))
		If SB2->(DbSeek(xFilial("SB2") + cProd + cLoc))
			If RecLock("SB2", .F.)
				SB2->B2_QATU += nQtd
				SB2->(MsUnlock())
			EndIf
		EndIf
		(cAliAux)->(DbSkip())
	EndDo
	(cAliAux)->(DbCloseArea())

	// 2. Soft Delete nas Tabelas Fiscais e Financeiras
	cQryAux := "UPDATE " + RetSqlName("SF2") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE F2_DOC = '" + cDoc + "' AND F2_SERIE = '" + cSer + "' AND F2_CLIENTE = '" + cCli + "' AND F2_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	TCSqlExec(cQryAux)

	cQryAux := "UPDATE " + RetSqlName("SD2") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE D2_DOC = '" + cDoc + "' AND D2_SERIE = '" + cSer + "' AND D2_CLIENTE = '" + cCli + "' AND D2_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	TCSqlExec(cQryAux)

	cQryAux := "UPDATE " + RetSqlName("SF3") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE F3_NFISCAL = '" + cDoc + "' AND F3_SERIE = '" + cSer + "' AND F3_CLIEFOR = '" + cCli + "' AND F3_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	TCSqlExec(cQryAux)

	cQryAux := "UPDATE " + RetSqlName("SFT") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE FT_NFISCAL = '" + cDoc + "' AND FT_SERIE = '" + cSer + "' AND FT_CLIEFOR = '" + cCli + "' AND FT_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	TCSqlExec(cQryAux)

	cQryAux := "UPDATE " + RetSqlName("SE1") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE E1_NUM = '" + cDoc + "' AND E1_PREFIXO = '" + cSer + "' AND E1_CLIENTE = '" + cCli + "' AND E1_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	TCSqlExec(cQryAux)
Return


// ==========================================================================
// COMPRAS (ENTRADAS) - MOTOR MATA120
// ==========================================================================
User Function FZ_PROC_X(aPrd, oHead, cForn, cLoja, cLeg, aEmp, cTab, cFil, cTpC, cCnd)
	Local aRet     :={.F.,"", ""}
	Local aCab     := {}
	Local aIt      := {}
	Local aLin     := {}
	Local nI       := 0
	Local cTE      := ""
	Local cPrd     := ""
	Local cLoc     := ""
	Local cCta     := ""
	Local cUm      := ""
	Local nQtd     := 0
	Local nPrc     := 0
	Local nPrcArr  := 0
	Local nDescItm := 0
	Local cCC      := ""
	Local dEmissao := CToD("//")
	Local aEx      := {}
	Local cPC      := ""
	Local cItemSeq := ""
	Local cItemSql := ""
	Local cQryUpd  := ""
	Local nTotItem := 0
	Local nVlrIcm  := 0
	Local nBasIcm  := 0
	Local nPctIcm  := 0
	Local nVlrIpi  := 0
	Local nPctIpi  := 0
	Local nVlrST   := 0
	Local nBasST   := 0
	Local nVlrPis  := 0
	Local nVlrCof  := 0
	Local cQryAux  := ""
	Local cAliAux  := ""
	Local aEmpFil
	Local cCnpjU
	Local nDespesa
	Local cNewSC7

	// ---> PROTECAO ANTI-ERRO 500: Busca Segura no Dicionario <---
	Local aTamQtd  := TamSx3("C7_QUANT")
	Local aTamPrc  := TamSx3("C7_PRECO")
	Local nTamQtd  := IIf(ValType(aTamQtd) == "A" .And. Len(aTamQtd) >= 2, aTamQtd[2], 4)
	Local nTamPrc  := IIf(ValType(aTamPrc) == "A" .And. Len(aTamPrc) >= 2, aTamPrc[2], 4)

	Private lMsErroAuto := .F.
	Private lAutoErrNoFile := .T.
	Private __cBatch := "1"

	cCnpjU  := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
	aEmpFil := FATPIEMP(cCnpjU)

	if Len(aEmpFil) > 0
		If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
			//RPCClearEnv()
			//RpcSetEnv(aEmpFil[1], aEmpFil[2])
			cFilAnt := aEmpFil[2]
		EndIf
	Endif

	cCnd := PadR(cCnd, 3)
	dEmissao := U_FZ_DATA_X(U_FZ_STR_X(oHead, 'dta_Emissao'))

	cPC := GetSxeNum("SC7", "C7_NUM")
	While .T.
		cQryAux := "SELECT C7_NUM FROM " + RetSqlName("SC7") + " WHERE C7_NUM = '" + PadR(cPC, TamSx3("C7_NUM")[1]) + "' AND D_E_L_E_T_ = ' '"
		cAliAux := GetNextAlias()
		MpSysOpenQuery(cQryAux, cAliAux)
		If (cAliAux)->(Eof())
			(cAliAux)->(DbCloseArea())
			Exit
		EndIf
		(cAliAux)->(DbCloseArea())
		cPC := Soma1(cPC)
	EndDo
	ConfirmSx8()

	AAdd(aCab, {"C7_NUM", cPC, Nil})
	AAdd(aCab, {"C7_FILIAL", xFilial("SC7"), Nil})
	AAdd(aCab, {"C7_FORNECE", cForn, Nil})
	AAdd(aCab, {"C7_LOJA", cLoja, Nil})
	AAdd(aCab, {"C7_EMISSAO", dEmissao, Nil})
	AAdd(aCab, {"C7_DATPRF", dEmissao, Nil})
	AAdd(aCab, {"C7_COND", cCnd, Nil})
	AAdd(aCab, {"C7_CONAPRO", "L", Nil})

	For nI := 1 To Len(aPrd)
		cTE := PadR(cValToChar(aPrd[nI]['_TES_CACHE']), 3)

		cPrd := PadR(cValToChar(AllTrim(aPrd[nI]['cod_Produto'])), 30)
		cLoc := U_FZ_LOC_X(cPrd)
		cCC  := U_FZ_STR_X(aPrd[nI], 'cod_CentroCusto')
		cCta := U_FZ_ACC_X(cPrd)

		If Empty(cCC)
			cCC := U_FZ_CC_X(cPrd)
		EndIf

		DbSelectArea("SB1")
		SB1->(DbSetOrder(1))
		SB1->(DbSeek(xFilial("SB1") + cPrd))
		cUm := SB1->B1_UM

		If Empty(cCta)
			cCta := SuperGetMv("MV_XCCPAD", .F., "11100901")
		EndIf

		nQtd := Round(U_FZ_VAL_X(aPrd[nI], 'qtd_Produto'), nTamQtd)
		nPrc := Round(U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario',), nTamPrc)
		nDespesa := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoOutros',)

		nPrcArr := nPrc
		If nPrcArr <= 0
			nPrcArr := 0.0001
		EndIf
		If nQtd <= 0
			nQtd := 1
		EndIf

		cItemSeq := PadL(cValToChar(nI), TamSx3("C7_ITEM")[1], "0")
		aPrd[nI]['num_Sequencial'] := cItemSeq

		nDescItm := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario') * nQtd
		cOper := ALLTRIM(RetOpera(aPrd[nI]['des_ProdutoImposto'],aPrd[nI]['cod_ProdutoCST']))

		aLin := {}
		AAdd(aLin, {"C7_ITEM", cItemSeq, Nil})
		AAdd(aLin, {"C7_PRODUTO", cPrd, Nil})
		AAdd(aLin, {"C7_UM", cUm, Nil})
		AAdd(aLin, {"C7_QUANT", nQtd, Nil})
		AAdd(aLin, {"C7_PRECO", nPrcArr, Nil})
		AAdd(aLin, {"C7_DESPESA", nDespesa, Nil})
		AAdd(aLin, {"C7_VLDESC", nDescItm, Nil})
		// ---> C7_TOTAL foi omitido propositalmente! <---
		AAdd(aLin, {"C7_OPER", cOper, Nil})
		AAdd(aLin, {"C7_TES", cTE, Nil})
		AAdd(aLin, {"C7_CONTA", PadR(cCta, 20), Nil})
		AAdd(aLin, {"C7_CC", PadR(cCC, TamSx3("C7_CC")[1]), Nil})
		AAdd(aLin, {"C7_OBS", "Ref: " + cLeg, Nil})
		AAdd(aLin, {"C7_LOCAL", cLoc, Nil})
		AAdd(aLin, {"C7_LEGADO", cLeg, Nil})
		AAdd(aIt, aLin)
	Next nI

	aEx := U_FZ_EX120_X(aCab, aIt)
	If aEx[1]
		For nI := 1 To Len(aPrd)
			cItemSql := aPrd[nI]['num_Sequencial']

			nQtd     := Round(U_FZ_VAL_X(aPrd[nI], 'qtd_Produto'), nTamQtd)
			nPrc     := Round(U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), nTamPrc)
			nDescItm := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario') * nQtd
			nTotItem := Round((nQtd * nPrc) - nDescItm, 2)

			nVlrIcm  := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoICMS')
			nBasIcm  := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoICMSBaseCalculo')
			nPctIcm  := U_FZ_VAL_X(aPrd[nI], 'pct_ProdutoICMS')
			nVlrIpi  := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoIPI')
			nPctIpi  := U_FZ_VAL_X(aPrd[nI], 'pct_ProdutoIPI')
			nVlrST   := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoICMSST')
			nBasST   := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoICMSSTBaseCalculo')
			nVlrPis  := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoPIS')
			nVlrCof  := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoConfins', 'vlr_ProdutoCOFINS')
			nDespesa := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoOutros')

			cQryUpd := "UPDATE " + RetSqlName("SC7") + " SET "
			cQryUpd += "C7_CONAPRO = 'L', C7_RESIDUO = '', "
			cQryUpd += "C7_PRECO = " + StrTran(cValToChar(nPrc), ",", ".") + ", "
			cQryUpd += "C7_DESPESA = " + StrTran(cValToChar(nDespesa), ",", ".") + ", "
			cQryUpd += "C7_TOTAL = " + StrTran(cValToChar(nTotItem), ",", ".") + ", "
			cQryUpd += "C7_VLDESC = " + StrTran(cValToChar(nDescItm), ",", ".") + ", "
			cQryUpd += "C7_VALICM = " + StrTran(cValToChar(nVlrIcm), ",", ".")  + ", "
			cQryUpd += "C7_BASEICM = " + StrTran(cValToChar(nBasIcm), ",", ".")  + ", "
			cQryUpd += "C7_PICM = " + StrTran(cValToChar(nPctIcm), ",", ".")  + ", "
			cQryUpd += "C7_VALIPI = " + StrTran(cValToChar(nVlrIpi), ",", ".")  + ", "
			cQryUpd += "C7_IPI = " + StrTran(cValToChar(nPctIpi), ",", ".")  + ", "
			cQryUpd += "C7_ICMSRET = " + StrTran(cValToChar(nVlrST), ",", ".")   + ", "
			cQryUpd += "C7_BRICMS = " + StrTran(cValToChar(nBasST), ",", ".")   + ", "
			cQryUpd += "C7_VALPIS = " + StrTran(cValToChar(nVlrPis), ",", ".")  + ", "
			cQryUpd += "C7_VALCOF = " + StrTran(cValToChar(nVlrCof), ",", ".")  + " "
			cQryUpd += "WHERE C7_NUM = '" + cPC + "' AND C7_ITEM = '" + cItemSql + "' AND C7_FILIAL = '" + xFilial("SC7") + "' AND D_E_L_E_T_ = ' '"
			TCSqlExec(cQryUpd)
		Next nI
		aRet := {.T., "Ok", cPC}
	Else
		aRet := {.F., aEx[2], ""}
	EndIf

	For nI := 1 To Len(aPrd)
		nDespesa := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoOutros',)
		cItemSql := aPrd[nI]['num_Sequencial']

		//SC7
		cNewSC7 := GetNextAlias()
		BeginSQL Alias cNewSC7
					select 
                        SC7.R_E_C_N_O_ AS RECNO
                    from
                        %table:SC7% SC7
                     WHERE
                    SC7.%notDel%
		            AND TRIM(SC7.C7_NUM) = %exp:(ALLTRIM(cPC))%
					AND TRIM(SC7.C7_ITEM) = %exp:(ALLTRIM(cItemSql))%
		            AND TRIM(SC7.C7_FILIAL) = %exp:(ALLTRIM(SC7->C7_FILIAL))%
		ENDSQL

		(cNewSC7)->(dbGoTop())

		While !(cNewSC7)->(Eof())
			SC7->(DbGoTo((cNewSC7)->RECNO))
			If RecLock("SC7",.F.)
				SC7->C7_DESPESA  := nDespesa
				SC7->(MsUnlock())
			ENDIF
			(cNewSC7)->(DbSkip())
		End
		(cNewSC7)->(DbCloseArea())

	Next nI

Return aRet


// ==========================================================================
// COMPRAS (CLASSIFICACAO DA NOTA) - MOTOR MATA103
// ==========================================================================
User Function FZ_PRON_X(aPrd, oHead, cForn, cLoja, cDoc, cSer, cPC, cTab, cFil, nAval, cCond, lIsTransf)
	Local aRet       := {.F.,""}
	Local aCab       := {}
	Local aIt        := {}
	Local aLin       := {}
	Local nI         := 0
	Local cTE        := ""
	Local nQtd       := 0
	Local nPrc       := 0
	Local nDescItm   := 0
	Local cProdKey   := ""
	Local cCta       := ""
	Local cCC        := ""
	Local cUm        := ""
	Local cItemSeq   := ""
	Local nX         := 0
	Local aEx        := {}
	Local cUFEntity  := ""
	Local nTotNF     := 0
	Local dEmissao   := CToD("//")
	Local aParcJson  := {}
	Local oParcItem  := Nil
	Local dVencP     := CToD("//")
	Local xParcVal   := Nil
	Local cNumP      := ""
	Local nVlrP      := 0
	Local aParcLegacy:= {}

	Local nVlrFrete  := U_FZ_VAL_X(oHead, 'vlr_Frete')
	Local nVlrSeg    := U_FZ_VAL_X(oHead, 'vlr_Seguro')
	Local nVlrDesc   := U_FZ_VAL_X(oHead, 'vlr_Desconto')
	Local nVlrOutr   := U_FZ_VAL_X(oHead, 'vlr_Outros')
	Local nVlrMercV  := 0
	Local nVlrBrutV  := 0
	Local cDocSql    := PadL(AllTrim(cValToChar(cDoc)), TamSx3("F1_DOC")[1], "0")
	Local cSerSql    := PadR(AllTrim(cValToChar(cSer)), TamSx3("F1_SERIE")[1], " ")
	Local cFornSql   := PadR(AllTrim(cValToChar(cForn)), TamSx3("F1_FORNECE")[1], " ")
	Local cLojaSql   := PadR(AllTrim(cValToChar(cLoja)), TamSx3("F1_LOJA")[1], " ")
	Local cItemSql   := ""
	Local cQryRec    := ""
	Local cAliRec    := ""
	Local cCondReal  := PadR(U_FZ_COND9(), 3)
	Local cHistPad   := ""
	Local cNatReal   := ""
	Local cNomeFin   := ""
	Local cNomeFor   := ""
	Local nRecTarget := 0
	Local cModDoc    := U_FZ_STR_X(oHead, 'cod_Mod', 'modelo')
	Local cEspecie   := ""
	Local cOper      := ''
	Local nTamNat    := TamSx3("E2_NATUREZ")[1]
	Local aEmpFil
	Local cCnpjU
	Local dDataDigit
	Local nValFreteUnit
	Local nValFrete

	// Variaveis Financeiras/Bancarias
	Local cEvtMod    := U_FZ_STR_X(oHead, "cod_EventoModalidade", "cod_Evento")
	Local cNatJson   := U_FZ_STR_X(oHead, "cod_NaturezaFinanceira")
	Local cTransacao := U_FZ_STR_X(oHead, "num_Transacao")
	Local nDespesa

	If Empty(lIsTransf)
		lIsTransf := .F.
	Endif

	If lIsTransf
		cCnpjU  := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "des_DestDocumento", "des_DestDocumento"))
	else
		cCnpjU  := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
	Endif
	aEmpFil := FATPIEMP(cCnpjU)

	if Len(aEmpFil) > 0
		If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
			//RPCClearEnv()
			//RpcSetEnv(aEmpFil[1], aEmpFil[2])
			cFilAnt := aEmpFil[2]
		EndIf
	Endif

	If cModDoc == "55"
		cEspecie := "SPED"
	Else
		cEspecie := "NFE"
	EndIf

	If Empty(cEvtMod)
		cEvtMod := "571"
	EndIf

	dEmissao := U_FZ_DATA_X(U_FZ_STR_X(oHead, 'dta_Emissao'))
	dDataDigit := U_FZ_DATA_X(U_FZ_STR_X(oHead, 'dta_Conferencia'))
	cUFEntity := PadR(U_FZ_GETEST("SA2", cForn, cLoja), 2)
	cCond := PadR(cValToChar(cCond), 3)

	dDataBase := dDataDigit

	cNomeFor := U_FZ_STR_X(oHead, 'des_DestNome')
	If Empty(cNomeFor)
		cNomeFor := U_FZ_STR_X(oHead, 'des_NomeCliente', 'nome')
	EndIf
	If Empty(cNomeFor)
		If cTab == "SA1"
			cNomeFor := Posicione(cTab, 1, xFilial(cTab) + cForn + cLoja, "A1_NOME")
		Else
			cNomeFor := Posicione(cTab, 1, xFilial(cTab) + cForn + cLoja, "A2_NOME")
		EndIf
	EndIf
	cNomeFin := cNomeFor

	If oHead:HasProperty('pagamentos')
		xParcVal := oHead['pagamentos']
		If ValType(xParcVal) == "A"
			aParcJson := xParcVal
		EndIf
	Else
		If oHead:HasProperty('parcelas')
			xParcVal := oHead['parcelas']
			If ValType(xParcVal) == "A"
				aParcJson := xParcVal
			EndIf
		EndIf
	EndIf

	If Len(aParcJson) > 0
		For nX := 1 To Len(aParcJson)
			oParcItem := aParcJson[nX]
			cNumP := cValToChar(U_FZ_VAL_X(oParcItem, 'num_Parcela'))
			dVencP := U_FZ_DATA_X(U_FZ_STR_X(oParcItem, 'dta_ParcelaVencimento'))
			nVlrP := U_FZ_VAL_X(oParcItem, 'vlr_Parcela')

			If Empty(cNumP) .Or. cNumP == "0"
				cNumP := cValToChar(nX)
			EndIf

			If Empty(dVencP)
				dVencP := dEmissao
			EndIf

			AAdd(aParcLegacy, {cNumP, dVencP, nVlrP})
		Next nX
	EndIf

	For nI := 1 To Len(aPrd)
		nTotNF += Round(U_FZ_VAL_X(aPrd[nI], 'qtd_Produto') * U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), 2)
	Next nI

	nVlrMercV := nTotNF
	nVlrBrutV := nTotNF + nVlrFrete + nVlrSeg + nVlrOutr - nVlrDesc

	nDespesa := U_FZ_VAL_X(oHead, 'vlr_Outros')

	If Len(aParcLegacy) == 0 .And. nVlrBrutV > 0
		AAdd(aParcLegacy, {"1", dEmissao, nVlrBrutV})
	EndIf

	If !Empty(cNatJson)
		cNatReal := PadR(cNatJson, TamSx3("E2_NATUREZ")[1])
	Else
		cNatReal := PadR(U_FZ_NAT_X(cFornSql, cLojaSql, oHead), TamSx3("E2_NATUREZ")[1])
	EndIf

	nValFrete := Round(U_FZ_VAL_X(oHead, 'vlr_Frete'), 4)

	AAdd(aCab, {"F1_DOC", PadR(cValToChar(cDoc), 9), Nil})
	AAdd(aCab, {"F1_SERIE", PadR(cValToChar(cSer), 3), Nil})
	AAdd(aCab, {"F1_FORNECE", PadR(cValToChar(cForn), 6), Nil})
	AAdd(aCab, {"F1_LOJA", PadR(cValToChar(cLoja), 2), Nil})
	AAdd(aCab, {"F1_TIPO", "N", Nil})
	AAdd(aCab, {"F1_FORMUL", "N", Nil})
	AAdd(aCab, {"F1_EMISSAO", dEmissao, Nil})
	AAdd(aCab, {"F1_DTDIGIT", dDataDigit, Nil})
	AAdd(aCab, {"F1_ESPECIE", cEspecie, Nil})
	AAdd(aCab, {"F1_CHVNFE", U_FZ_STR_X(oHead, 'cod_ChaveNFe'), Nil})
	AAdd(aCab, {"F1_COND", cCond, Nil})
	AAdd(aCab, {"F1_VALBRUT", nVlrBrutV, Nil})
	AAdd(aCab, {"F1_VALMERC", nVlrMercV, Nil})
	//AAdd(aCab, {"F1_DESPESA", nDespesa, Nil})
	AAdd(aCab, {"F1_DESCONT", nVlrDesc, Nil}) // <--- CORREÇÃO: Injetando o desconto global no cabeçalho
	AAdd(aCab, {"F1_EST", cUFEntity, Nil})
	AAdd(aCab, {"F1_FRETE", nValFrete, Nil})
	AAdd(aCab, {"E2_NATUREZ", PADR(ALLTRIM(cNatReal),nTamNat,''), Nil})

	For nI := 1 To Len(aPrd)
		cTE := PadR(cValToChar(aPrd[nI]['_TES_CACHE']), 3)
		nQtd := Round(U_FZ_VAL_X(aPrd[nI], 'qtd_Produto'), 4)

		If nQtd <= 0 ; nQtd := 1 ; EndIf

			nPrc := Round(U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), 4)
			nDescItm := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario') * nQtd // <--- CORREÇÃO: Extraindo o desconto do item
			nValFreteUnit := Round(U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoFrete'), 4)

			cProdKey := AllTrim(PadR(cValToChar(AllTrim(aPrd[nI]['cod_Produto'])), 30))
			cItemSeq := PadL(cValToChar(nI), TamSx3("D1_ITEM")[1], "0")
			cCta := PadR(cValToChar(U_FZ_ACC_X(cProdKey)), 20)
			cCC  := U_FZ_STR_X(aPrd[nI], 'cod_CentroCusto')
			nDespesa := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoOutros')

			If Empty(cCC)
				cCC := U_FZ_CC_X(cProdKey)
			EndIf
			cCC := PadR(cCC, TamSx3("D1_CC")[1])

			DbSelectArea("SB1")
			SB1->(DbSetOrder(1))
			SB1->(DbSeek(xFilial("SB1") + PadR(cProdKey, 30)))
			cUm := SB1->B1_UM
			cOper := ALLTRIM(RetOpera(aPrd[nI]['des_ProdutoImposto'],aPrd[nI]['cod_ProdutoCST']))

			aLin := {}
			AAdd(aLin, {"D1_FILIAL", xFilial("SD1"), Nil})
			AAdd(aLin, {"D1_ITEM", cItemSeq, Nil})
			AAdd(aLin, {"D1_COD", cProdKey, Nil})
			AAdd(aLin, {"D1_UM", cUm, Nil})
			AAdd(aLin, {"D1_QUANT", nQtd, Nil})
			AAdd(aLin, {"D1_VUNIT", nPrc, Nil})
			AAdd(aLin, {"D1_TOTAL", Round(nQtd * nPrc, 2), Nil})
			AAdd(aLin, {"D1_VALDESC", nDescItm, Nil}) // <--- CORREÇÃO: Injetando o desconto do item para o MATA103
			AAdd(aLin, {"D1_OPER", cOper, Nil})
			AAdd(aLin, {"D1_TES", cTE, Nil})
			AAdd(aLin, {"D1_CONTA", cCta, Nil})
			AAdd(aLin, {"D1_CC", cCC, Nil})
			AAdd(aLin, {"D1_CF", PadR(cValToChar(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("D1_CF")[1]), Nil})
			AAdd(aLin, {"D1_FORNECE", PadR(cValToChar(cForn), 6), Nil})
			AAdd(aLin, {"D1_LOJA", PadR(cValToChar(cLoja), 2), Nil})
			AAdd(aLin, {"D1_LOCAL", PadR(cValToChar(U_FZ_LOC_X(cProdKey)), 2), Nil})
			AAdd(aLin, {"D1_VALFRE", nValFreteUnit, Nil})
			AAdd(aLin, {"D1_DESPESA", nDespesa, Nil})


			If !Empty(cPC)
				AAdd(aLin, {"D1_PEDIDO", cPC, Nil})
				AAdd(aLin, {"D1_ITEMPC", cItemSeq, Nil})
			EndIf

			AAdd(aIt, aLin)
		Next nI

		aEx := U_FZ_E103_GEN(aCab, aIt, "N")

		If aEx[1]
			aRet := {.T., cDoc}
			If !Empty(cPC)
				For nI := 1 To Len(aPrd)
					cItemSql := PadL(cValToChar(nI), TamSx3("C7_ITEM")[1], "0")
					cQryRec := "SELECT R_E_C_N_O_ AS REC FROM " + RetSqlName("SC7") + " WHERE C7_NUM = '" + cPC + "' AND C7_ITEM = '" + cItemSql + "' AND D_E_L_E_T_ = ' '"
					cAliRec := GetNextAlias()
					MpSysOpenQuery(cQryRec, cAliRec)

					If (cAliRec)->(!Eof())
						DbSelectArea("SC7")
						SC7->(DbGoTo((cAliRec)->REC))
						If RecLock("SC7", .F.)
							If SC7->(FieldPos("C7_TOTAL")) > 0
								SC7->C7_TOTAL := Round(U_FZ_VAL_X(aPrd[nI], 'qtd_Produto') * U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), 2)
							EndIf
							If SC7->(FieldPos("C7_VALICM")) > 0
								SC7->C7_VALICM := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoICMS')
							EndIf
							If SC7->(FieldPos("C7_BASEICM")) > 0
								SC7->C7_BASEICM := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoICMSBaseCalculo')
							EndIf
							If SC7->(FieldPos("C7_PICM")) > 0
								SC7->C7_PICM := U_FZ_VAL_X(aPrd[nI], 'pct_ProdutoICMS')
							EndIf
							SC7->(MsUnlock())
						EndIf
					EndIf
					(cAliRec)->(DbCloseArea())
				Next nI
			EndIf

			cQryRec := "SELECT R_E_C_N_O_ AS REC FROM " + RetSqlName("SF1") + " WHERE F1_DOC='" + cDocSql + "' AND F1_SERIE='" + cSerSql + "' AND F1_FORNECE='" + cFornSql + "' AND F1_LOJA='" + cLojaSql + "' AND D_E_L_E_T_=' '"
			cAliRec := GetNextAlias()
			MpSysOpenQuery(cQryRec, cAliRec)

			If (cAliRec)->(!Eof())
				nRecTarget := (cAliRec)->REC
				DbSelectArea("SF1")
				SF1->(DbGoTo(nRecTarget))
				If RecLock("SF1", .F.)
					SF1->F1_COND := cCondReal
					If SF1->(FieldPos("F1_VALBRUT")) > 0
						SF1->F1_VALBRUT := nVlrBrutV
					EndIf
					If SF1->(FieldPos("F1_VALMERC")) > 0
						SF1->F1_VALMERC := nVlrMercV
					EndIf
					If SF1->(FieldPos("F1_DESCONT")) > 0
						SF1->F1_DESCONT := nVlrDesc
					EndIf
					SF1->(MsUnlock())
				EndIf
			EndIf
			(cAliRec)->(DbCloseArea())

			If !Empty(cNatJson)
				cNatReal := PadR(cNatJson, TamSx3("E2_NATUREZ")[1])
			Else
				cNatReal := PadR(U_FZ_NAT_X(cFornSql, cLojaSql, oHead), TamSx3("E2_NATUREZ")[1])
			EndIf

			cHistPad := "API: Orig:" + U_FZ_STR_X(oHead, "des_Origem") + " Aut:" + U_FZ_STR_X(oHead, "des_Autorizacao") + " Trans:" + cTransacao

			If Len(aParcLegacy) > 0
				cQryRec := "SELECT R_E_C_N_O_ AS REC FROM " + RetSqlName("SE2") + " WHERE E2_NUM='" + cDocSql + "' AND E2_PREFIXO='" + cSerSql + "' AND E2_FORNECE='" + cFornSql + "' AND E2_LOJA='" + cLojaSql + "' AND D_E_L_E_T_=' ' ORDER BY E2_PARCELA"
				cAliRec := GetNextAlias()
				MpSysOpenQuery(cQryRec, cAliRec)

				nX := 1
				While (cAliRec)->(!Eof()) .And. nX <= Len(aParcLegacy)
					nRecTarget := (cAliRec)->REC
					DbSelectArea("SE2")
					SE2->(DbGoTo(nRecTarget))

					If RecLock("SE2", .F.)
						SE2->E2_VENCTO := aParcLegacy[nX][2]
						SE2->E2_VENCREA := aParcLegacy[nX][2]
						If SE2->(FieldPos("E2_PARCELA")) > 0
							SE2->E2_PARCELA := PadR(aParcLegacy[nX][1], TamSx3("E2_PARCELA")[1])
						EndIf
						If SE2->(FieldPos("E2_VALOR")) > 0
							SE2->E2_VALOR := aParcLegacy[nX][3]
						EndIf
						If SE2->(FieldPos("E2_SALDO")) > 0
							SE2->E2_SALDO := aParcLegacy[nX][3]
						EndIf
						If SE2->(FieldPos("E2_COND")) > 0
							SE2->E2_COND := cCondReal
						EndIf
						If SE2->(FieldPos("E2_NATUREZ")) > 0
							SE2->E2_NATUREZ := cNatReal
						EndIf
						If SE2->(FieldPos("E2_NOMFOR")) > 0
							SE2->E2_NOMFOR := PadR(Left(cNomeFin, TamSx3("E2_NOMFOR")[1]), TamSx3("E2_NOMFOR")[1])
						EndIf
						If SE2->(FieldPos("E2_HIST")) > 0
							SE2->E2_HIST := Left(cHistPad, TamSx3("E2_HIST")[1])
						EndIf
						If SE2->(FieldPos("E2_XEVENTO")) > 0
							SE2->E2_XEVENTO := PadR(cEvtMod, TamSx3("E2_XEVENTO")[1])
						EndIf

						SE2->(MsUnlock())
					EndIf

					nX++
					(cAliRec)->(DbSkip())
				EndDo

				While (cAliRec)->(!Eof())
					nRecTarget := (cAliRec)->REC
					DbSelectArea("SE2")
					SE2->(DbGoTo(nRecTarget))
					If RecLock("SE2", .F.)
						SE2->(DbDelete())
						SE2->(MsUnlock())
					EndIf
					(cAliRec)->(DbSkip())
				EndDo
				(cAliRec)->(DbCloseArea())
			EndIf
		Else
			aRet := {.F., aEx[2]}
		EndIf
		Return aRet

// ==========================================================================
// DEVOLUCOES (SAIDAS E ENTRADAS) - MOTOR MATA103
// ==========================================================================
User Function FZ_PRDEV_X(aPrd, oHead, cCli, cLoja, cDoc, cSer, cTab, cFil, nAval, cCond)
	Local aRet       := {.F.,""}
	Local aCab       := {}
	Local aIt        := {}
	Local aLin       := {}
	Local nI         := 0
	Local cTE        := ""
	Local nQtd       := 0
	Local nPrc       := 0
	Local cProdKey   := ""
	Local cCta       := ""
	Local cCC        := ""
	Local cUm        := ""
	Local dEmissao   := CToD("//")
	Local aEx        := {}
	Local cNotaOri     := ""
	Local cSerieOri    := ""
	Local cItemOri   := ""
	Local cUFEntity  := ""
	Local nTotNF     := 0
	Local aParcLegacy:= {}
	Local nX         := 0
	Local xParcVal   := Nil
	Local aParcJson  := {}
	Local oParcItem  := Nil
	Local cNumP      := ""
	Local dVencP     := CToD("//")
	Local nVlrP      := 0
	Local nDescItm   := 0
	Local nQtdItm    := 0
	Local nVlrUniItm := 0
	Local nVlrBrutItm:= 0
	Local nVlrLiqItm := 0

	Local nVlrFrete  := U_FZ_VAL_X(oHead, 'vlr_Frete')
	Local nVlrSeg    := U_FZ_VAL_X(oHead, 'vlr_Seguro')
	Local nVlrDesc   := U_FZ_VAL_X(oHead, 'vlr_Desconto')
	Local nVlrOutr   := U_FZ_VAL_X(oHead, 'vlr_Outros')
	Local nVlrMerc   := U_FZ_VAL_X(oHead, 'vlr_TotalProduto')
	Local nVlrBrut   := U_FZ_VAL_X(oHead, 'vlr_NotaFiscal')

	Local cDocPad    := PadL(AllTrim(cValToChar(cDoc)), TamSx3("F1_DOC")[1], "0")
	Local cSerPad    := PadR(AllTrim(cValToChar(cSer)), TamSx3("F1_SERIE")[1], " ")
	Local cCliPad    := PadR(AllTrim(cValToChar(cCli)), TamSx3("F1_FORNECE")[1], " ")
	Local cLojaPad   := PadR(AllTrim(cValToChar(cLoja)), TamSx3("F1_LOJA")[1], " ")
	Local cItemSeq   := ""

	// Financeiro/Banco JSON
	Local cEvtMod    := U_FZ_STR_X(oHead, "cod_EventoModalidade", "cod_Evento")
	Local cNatJson   := U_FZ_STR_X(oHead, "cod_NaturezaFinanceira")
	Local cTransacao := U_FZ_STR_X(oHead, "num_Transacao")
	Local cCondReal  := PadR(U_FZ_COND9(), 3)
	Local cHistPad   := ""
	Local cNatReal   := ""
	Local cNomeFin   := ""
	Local cNomeFor   := ""
	Local cAliSE2    := ""
	Local cQrySE2    := ""
	Local nRecSE2    := 0
	Local cUpdSF1    := ""
	Local cModDoc    := U_FZ_STR_X(oHead, 'cod_Mod', 'modelo')
	Local cEspecie   := ""
	Local cOper      := ''
	Local lDevol     := .T.
	Local cChaveOri
	Local nTamNat    := TamSx3("E2_NATUREZ")[1]
	Local nTamItemOri:= TamSx3("D1_ITEMORI")[1]
	Local nTamSerie  := TamSx3("D1_SERIORI")[1]
	Local cCnpjU
	Local aEmpFil
	Local dDataDigit

	// INTELIGENCIA PROTHEUS: Se for SA2 (Fornecedor), forca TIPO 'N' para nao bugar o MATA103
	Local cTipoDoc   := IIf(cTab == "SA2", "N", "D")
	Local cOldPcNfe  := SuperGetMv("MV_PCNFE", .F., "2")

	cCnpjU  := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
	aEmpFil := FATPIEMP(cCnpjU)

	If Len(aEmpFil) > 0
		If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
			//RPCClearEnv()
			//RpcSetEnv(aEmpFil[1], aEmpFil[2])
			cFilAnt := aEmpFil[2]
		EndIf
	Endif

	If cModDoc == "55"
		cEspecie := "SPED"
	Else
		cEspecie := "NFE"
	EndIf

	If Empty(cEvtMod)
		cEvtMod := "571"
	EndIf

	dEmissao := U_FZ_DATA_X(U_FZ_STR_X(oHead, 'dta_Emissao'))
	dDataDigit := U_FZ_DATA_X(U_FZ_STR_X(oHead, 'dta_Conferencia'))
	cUFEntity := PadR(U_FZ_GETEST(cTab, cCli, cLoja), 2)
	cCond := PadR(cValToChar(cCond), 3)

	dDataBase := dDataDigit

	cNomeFor := U_FZ_STR_X(oHead, 'des_DestNome')
	If Empty(cNomeFor)
		cNomeFor := U_FZ_STR_X(oHead, 'des_NomeCliente', 'nome')
	EndIf
	If Empty(cNomeFor)
		If cTab == "SA1"
			cNomeFor := Posicione(cTab, 1, xFilial(cTab) + cCli + cLoja, "A1_NOME")
		Else
			cNomeFor := Posicione(cTab, 1, xFilial(cTab) + cCli + cLoja, "A2_NOME")
		EndIf
	EndIf
	cNomeFin := cNomeFor

	For nI := 1 To Len(aPrd)
		nTotNF += Round(U_FZ_VAL_X(aPrd[nI], 'qtd_Produto') * U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), 2)
	Next nI

	If nVlrMerc <= 0
		nVlrMerc := nTotNF
	EndIf
	If nVlrBrut <= 0
		nVlrBrut := nTotNF + nVlrFrete + nVlrSeg + nVlrOutr - nVlrDesc
	EndIf

	If !Empty(cNatJson)
		cNatReal := PadR(cNatJson, TamSx3("E2_NATUREZ")[1])
	Else
		cNatReal := PadR(U_FZ_NAT_X(cFornSql, cLojaSql, oHead), TamSx3("E2_NATUREZ")[1])
	EndIf

	// ---> TIPO DOC DINAMICO APLICADO AQUI <---
	AAdd(aCab, {"F1_TIPO", cTipoDoc, Nil})
	AAdd(aCab, {"F1_DOC", PadR(cValToChar(cDoc), 9), Nil})
	AAdd(aCab, {"F1_SERIE", PadR(cValToChar(cSer), 3), Nil})
	AAdd(aCab, {"F1_FORNECE", PadR(cValToChar(cCli), 6), Nil})
	AAdd(aCab, {"F1_LOJA", PadR(cValToChar(cLoja), 2), Nil})
	AAdd(aCab, {"F1_FORMUL", "N", Nil})
	AAdd(aCab, {"F1_EMISSAO", dEmissao, Nil})
	AAdd(aCab, {"F1_DTDIGIT", dDataDigit, Nil})
	AAdd(aCab, {"F1_ESPECIE", cEspecie, Nil})
	AAdd(aCab, {"F1_CHVNFE", U_FZ_STR_X(oHead, 'cod_ChaveNFe'), Nil})
	AAdd(aCab, {"F1_COND", cCond, Nil})
	AAdd(aCab, {"F1_VALBRUT", nVlrBrut, Nil})
	AAdd(aCab, {"F1_VALMERC", nVlrMerc, Nil})
	AAdd(aCab, {"F1_EST", cUFEntity, Nil})
	AAdd(aCab, {"E2_NATUREZ", PADR(ALLTRIM(cNatReal),nTamNat,''), Nil})

	If nAval > 0
		AAdd(aCab, {"F1_AVALNOT", nAval, Nil})
	EndIf

	For nI := 1 To Len(aPrd)
		cTE := PadR(cValToChar(aPrd[nI]['_TES_CACHE']), 3)

		cProdKey := PadR(cValToChar(AllTrim(aPrd[nI]['cod_Produto'])), 30)

		DbSelectArea("SB1")
		SB1->(DbSetOrder(1))
		SB1->(DbSeek(xFilial("SB1") + cProdKey))
		cUm := SB1->B1_UM

		nQtdItm     := Max(U_FZ_VAL_X(aPrd[nI], 'qtd_Produto'), 1)
		nVlrUniItm  := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario')

		// MULTIPLICANDO O DESCONTO PELA QUANTIDADE (CORRIGIDO PARA USO DE nI)
		nDescItm    := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario') * nQtdItm

		nVlrBrutItm := Round(nQtdItm * nVlrUniItm, 2)
		nVlrLiqItm  := Round(nVlrBrutItm - nDescItm, 2)

		cItemSeq := PadL(cValToChar(nI), TamSx3("D1_ITEM")[1], "0")
		cCta := PadR(cValToChar(U_FZ_ACC_X(cProdKey)), 20)
		cCC  := U_FZ_STR_X(aPrd[nI], 'cod_CentroCusto')

		If Empty(cCC)
			cCC := U_FZ_CC_X(cProdKey)
		EndIf

        /*cNfOri   := PadR(U_FZ_STR_X(aPrd[nI], '_NFORI', 'num_NFOri'), TamSx3("D1_NFORI")[1]) 
        cSerOri  := PadR(U_FZ_STR_X(aPrd[nI], '_SERIORI', 'num_SerOri'), TamSx3("D1_SERIORI")[1]) 
        cItemOri := PadR(U_FZ_STR_X(aPrd[nI], '_ITEMORI', 'num_ItemOri'), TamSx3("D1_ITEMORI")[1])*/

        cNotaOri := PadL(U_FZ_STR_X(aPrd[nI], 'num_NFOrigem'), 9, '0')
        cSerieOri := U_FZ_STR_X(aPrd[nI], 'cod_SerieOrigem')
        cItemOri := U_FZ_STR_X(aPrd[nI], 'num_ProdutoSequencialOrigem')
		cChaveOri := U_FZ_STR_X(aPrd[nI], 'cod_ChaveNFeOrigem')

		IF !Empty(cNotaOri)
		   IF lDevol
	          lDevol := FZ_VALID_DEV(cChaveOri,cNotaOri,'V')
		   Endif
		ENDIF

        cOper := RetOpera(aPrd[nI]['des_ProdutoImposto'],aPrd[nI]['cod_ProdutoCST'])

        aLin := {}
        AAdd(aLin, {"D1_FILIAL", xFilial("SD1"), Nil})
        AAdd(aLin, {"D1_ITEM", cItemSeq, Nil}) 
        AAdd(aLin, {"D1_COD", cProdKey, Nil}) 
        AAdd(aLin, {"D1_UM", cUm, Nil}) 
        AAdd(aLin, {"D1_QUANT", nQtdItm, Nil}) 
        AAdd(aLin, {"D1_VUNIT", nVlrUniItm, Nil}) 
        AAdd(aLin, {"D1_TOTAL", Round(nQtdItm * nVlrUniItm, 2), Nil}) 
        AAdd(aLin, {"D1_VLDESC", nDescItm, Nil}) 
        AAdd(aLin, {"D1_TES", cTE, Nil}) 
        AAdd(aLin, {"D1_CONTA", cCta, Nil}) 
        AAdd(aLin, {"D1_OPER", cOper, Nil}) 
        AAdd(aLin, {"D1_CC", PadR(cCC, TamSx3("D1_CC")[1]), Nil}) 
        AAdd(aLin, {"D1_CF", PadR(cValToChar(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("D1_CF")[1]), Nil}) 
        AAdd(aLin, {"D1_LOCAL", PadR(cValToChar(U_FZ_LOC_X(cProdKey)), 2), Nil})
        AAdd(aLin, {"D1_NFORI", cNotaOri, Nil}) 
        AAdd(aLin, {"D1_SERIORI", PADR(ALLTRIM(cSerieOri), nTamSerie, ''), Nil}) 
        AAdd(aLin, {"D1_ITEMORI", PadL(ALLTRIM(cItemOri), nTamItemOri, '0') , Nil}) 
        
        AAdd(aIt, aLin)
    Next nI

    If oHead:HasProperty('parcelas')
        xParcVal := oHead['parcelas'] 
        If ValType(xParcVal) == "A" 
            aParcJson := xParcVal 
        Else
            If xParcVal != Nil 
                aParcJson := { xParcVal } 
            EndIf
        EndIf
    EndIf

    If Len(aParcJson) > 0
        For nX := 1 To Len(aParcJson)
            oParcItem := aParcJson[nX] 
            cNumP := cValToChar(U_FZ_VAL_X(oParcItem, 'num_Parcela')) 
            dVencP := U_FZ_DATA_X(U_FZ_STR_X(oParcItem, 'dta_ParcelaVencimento')) 
            nVlrP := U_FZ_VAL_X(oParcItem, 'vlr_Parcela')
            
            If Empty(cNumP) .Or. cNumP == "0" 
                cNumP := cValToChar(nX) 
            EndIf
            
            If Empty(dVencP) 
                dVencP := dEmissao 
            EndIf
            
            AAdd(aParcLegacy, {cNumP, dVencP, nVlrP})
        Next nX
    Else
        If nVlrBrut > 0 
            AAdd(aParcLegacy, {"1", dEmissao, nVlrBrut}) 
        EndIf
    EndIf

    // Desliga a trava de Pedido de Compras para permitir a Devolucao SA2 passar como Entrada
    PutMv("MV_PCNFE", "2")

If lDevol
    // Motor roda com o tipo dinamico ('N' ou 'D')
    aEx := U_FZ_E103_GEN(aCab, aIt, cTipoDoc)


    // Restaura a trava de sistema
    PutMv("MV_PCNFE", cOldPcNfe)

    If aEx[1]
        aRet := {.T., cDoc,.T.}
        cUpdSF1 := "UPDATE " + RetSqlName("SF1") + " SET F1_COND = '" + cCondReal + "' WHERE F1_DOC = '" + cDocPad + "' AND F1_SERIE = '" + cSerPad + "' AND F1_FORNECE = '" + cCliPad + "' AND D_E_L_E_T_ = ' '"
        TCSqlExec(cUpdSF1)

        If !Empty(cNatJson)
            cNatReal := PadR(cNatJson, TamSx3("E2_NATUREZ")[1])
        Else
            cNatReal := PadR(U_FZ_NAT_X(cCli, cLoja, oHead), TamSx3("E2_NATUREZ")[1])
        EndIf
        
        cHistPad := "API: Orig:" + U_FZ_STR_X(oHead, "des_Origem") + " Aut:" + U_FZ_STR_X(oHead, "des_Autorizacao") + " Trans:" + cTransacao

        If Len(aParcLegacy) > 0
            cAliSE2 := GetNextAlias() 
            cQrySE2 := "SELECT R_E_C_N_O_ AS REC, E2_FILIAL FROM " + RetSqlName("SE2") + " WHERE E2_NUM = '" + cDocPad + "' AND E2_FORNECE = '" + cCliPad + "' AND D_E_L_E_T_ = ' ' ORDER BY E2_PARCELA" 
            MpSysOpenQuery(cQrySE2, cAliSE2)
            
            nX := 1
            While (cAliSE2)->(!Eof()) .And. nX <= Len(aParcLegacy)
                nRecSE2 := (cAliSE2)->REC 
                If ValType(nRecSE2) == "C" 
                    nRecSE2 := Val(nRecSE2) 
                EndIf
                
                SE2->(DbGoTo(nRecSE2)) 
                If RecLock("SE2", .F.)
                    SE2->E2_PARCELA := PadR(aParcLegacy[nX][1], TamSx3("E2_PARCELA")[1])
                    SE2->E2_VENCTO  := aParcLegacy[nX][2] 
                    SE2->E2_VENCREA := aParcLegacy[nX][2] 
                    
                    If SE2->(FieldPos("E2_VALOR")) > 0 
                        SE2->E2_VALOR := aParcLegacy[nX][3] 
                    EndIf
                    If SE2->(FieldPos("E2_SALDO")) > 0 
                        SE2->E2_SALDO := aParcLegacy[nX][3] 
                    EndIf
                    If SE2->(FieldPos("E2_COND")) > 0 
                        SE2->E2_COND := cCondReal 
                    EndIf
                    If SE2->(FieldPos("E2_NATUREZ")) > 0 
                        SE2->E2_NATUREZ := cNatReal 
                    EndIf
                    If SE2->(FieldPos("E2_NOMFOR")) > 0 
                        SE2->E2_NOMFOR := PadR(Left(cNomeFin, TamSx3("E2_NOMFOR")[1]), TamSx3("E2_NOMFOR")[1]) 
                    EndIf
                    If SE2->(FieldPos("E2_HIST")) > 0 
                        SE2->E2_HIST := Left(cHistPad, TamSx3("E2_HIST")[1]) 
                    EndIf
                    If SE2->(FieldPos("E2_XEVENTO")) > 0 
                        SE2->E2_XEVENTO := PadR(cEvtMod, TamSx3("E2_XEVENTO")[1])
                    EndIf
                    
                    SE2->(MsUnlock())
                EndIf
                
                nX++ 
                (cAliSE2)->(DbSkip())
            EndDo

            While (cAliSE2)->(!Eof())
                nRecSE2 := (cAliSE2)->REC 
                If ValType(nRecSE2) == "C" 
                    nRecSE2 := Val(nRecSE2) 
                EndIf
                SE2->(DbGoTo(nRecSE2)) 
                If RecLock("SE2", .F.) 
                    SE2->(DbDelete()) 
                    SE2->(MsUnlock()) 
                EndIf
                (cAliSE2)->(DbSkip())
            EndDo
            (cAliSE2)->(DbCloseArea())
        EndIf
    Else
        aRet := {.F., aEx[2], .F.}
    EndIf
Else
	aRet := {.F., "(MATA103) Nota de origem não existe na SF2. Favor verificar.",.T.}
Endif
Return aRet

/*
+----------------------------------------------------------------------------+
| Autor: Antonio Nunes O Jr | Data: 18/04/2026                               |
| Descritivo: Funcao de Apoio (Extracao Anti-Leak JsonObject em Escadinha)   |
+----------------------------------------------------------------------------+
*/
Static Function GET_REC_JSON(oHead, cCampoReq, cCampoPag, nVlrFall)
	// --- 1. DECLARACAO DE VARIAVEIS ---
	Local cRet    := ""
	Local oItm    := Nil
	Local xRecVal := Nil
	Local aPag    := Nil

	// --- 2. LOGICA DE PROCESSAMENTO ---
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
			If oItm:HasProperty("vlr_Recebimento") ; cRet := oItm["vlr_Recebimento"] ; EndIf
				If ValType(cRet) != "N" .Or. cRet <= 0
					If oItm:HasProperty("vlr_Pagamento") ; cRet := oItm["vlr_Pagamento"] ; EndIf
					EndIf
					If ValType(cRet) != "N" .Or. cRet <= 0
						If oItm:HasProperty("vlr_Transacao") ; cRet := oItm["vlr_Transacao"] ; EndIf
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

/*
+----------------------------------------------------------------------------+
| Autor: Antonio Nunes O Jr | Data: 18/04/2026                               |
| Descritivo: JSON_VENDA - Tratamento Cirurgico Pos-Gravacao (SQL/RecLock)   |
|             (Cofre V1 + Mapeamento Avancado e Condicional de ICMS/ST)      |
+----------------------------------------------------------------------------+
*/
Static Function JSON_VENDA(cDoc, cSer, cCli, cLoja, aPrd, oHead, cTab)
	// --- 1. DECLARACAO DE VARIAVEIS ---
	Local cDocSql     := AllTrim(cDoc)
	Local cSerSql     := AllTrim(cSer)
	Local cCliSql     := AllTrim(cCli)
	Local cLojaSql    := AllTrim(cLoja)
	Local cItemSql    := ""
	Local cQryRec     := ""
	Local cAliRec     := ""
	Local nX          := 0
	Local dEmiss      := CToD("//")
	Local cAliSE1     := ""
	Local cQrySE1     := ""
	Local cChaveNFe   := U_FZ_STR_X(oHead, 'cod_ChaveNFe')
	Local cModDoc     := U_FZ_STR_X(oHead, 'cod_Mod', 'modelo')
	Local cEspecie    := ""
	Local cNatOp      := Upper(AllTrim(U_FZ_STR_X(oHead, 'des_NatOp')))
	Local cEstCli     := ""

	Local cTipoE1     := "NF "
	Local cHistPad    := ""
	Local cTransacao  := U_FZ_STR_X(oHead, "num_Transacao")
	Local cAutoriz    := U_FZ_STR_X(oHead, "des_Autorizacao")
	Local cOrigem     := U_FZ_STR_X(oHead, "des_Origem")

	Local nVlrMercV   := U_FZ_VAL_X(oHead, 'vlr_TotalProduto', 'vlr_ReciboVendaTotal')
	Local nVlrBrutV   := U_FZ_VAL_X(oHead, 'vlr_NotaFiscal', 'vlr_ReciboVendaTotal')
	Local nDescTot    := U_FZ_VAL_X(oHead, 'vlr_Desconto', 'vlr_ReciboVendaDesconto')
	Local nFreteTot   := U_FZ_VAL_X(oHead, 'vlr_Frete')
	Local nSegTot     := U_FZ_VAL_X(oHead, 'vlr_Seguro')
	Local nOutrTot    := U_FZ_VAL_X(oHead, 'vlr_Outros')

	Local nSomaMerc   := 0
	Local nSomaDesc   := 0
	Local nVlrBrutItm := 0
	Local nDescItm    := 0
	Local nPercDesc   := 0
	Local nVlrLiqItm  := 0
	Local nQtdItm     := 0
	Local nVlrUniItm  := 0

	Local nAliqIcm    := 0
	Local nIcmItm     := 0
	Local cCfopItm    := ""
	Local cTesItm     := ""
	Local aGrpSF3     := {}
	Local nPosGrp     := 0
	Local cQrySF3     := ""

	Local nVlrIcmN    := U_FZ_VAL_X(oHead, 'vlr_ICMS')
	Local nBasIcmN    := U_FZ_VAL_X(oHead, 'vlr_ICMSBaseCalculo')
	Local nVlrIpiN    := U_FZ_VAL_X(oHead, 'vlr_IPI')
	Local nVlrPisN    := U_FZ_VAL_X(oHead, 'vlr_PIS')
	Local nVlrCofN    := U_FZ_VAL_X(oHead, 'vlr_COFINS')

	Local cDocPad     := PadL(AllTrim(cDocSql), TamSx3("F2_DOC")[1], "0")
	Local cSerPad     := PadR(AllTrim(cSerSql), TamSx3("F2_SERIE")[1], " ")
	Local cCliPad     := PadR(AllTrim(cCliSql), TamSx3("F2_CLIENTE")[1], " ")
	Local cLojaPad    := PadR(AllTrim(cLojaSql), TamSx3("F2_LOJA")[1], " ")

	Local cCustoHead  := U_FZ_STR_X(oHead, 'cod_CentroCusto')
	Local cCustoSD2   := ""

	Local cNatJson    := U_FZ_STR_X(oHead, "cod_NaturezaFinanceira")
	Local cFormaPag   := U_FZ_STR_X(oHead, "des_FormaRecebimento")

	Local cNatItm     := ""
	Local cCCItm      := ""
	Local cFormaRec   := ""
	Local cBandeira   := ""
	Local cTransac    := ""
	Local cAutorizF   := ""
	Local nVlrTitulo  := 0
	Local cFormaTrat  := ""
	Local cParcela    := ""
	Local nFrete := 0
	Local cCodCST     := ''

	Local nPicmItem   := 0
	Local nBicmItem   := 0
	Local nVicmItem   := 0
	Local nBicmStItem := 0
	Local nBIcmsIsen  := 0
	Local nVicmStItem := 0
	Local nVicmDeson  := 0
	Local nPReducIcm  := 0
	Local nPReducSt   := 0
	Local cNewSFT     := GetNextAlias()

	// --- 2. LOGICA DE PROCESSAMENTO ---
	cNatItm     := GET_REC_JSON(oHead, "cod_NaturezaFinanceira", "", "")
	cCCItm      := GET_REC_JSON(oHead, "cod_CentroCusto", "", "")
	cFormaRec   := GET_REC_JSON(oHead, "des_FormaRecebimento", "des_FormaPagamento", "")
	cBandeira   := GET_REC_JSON(oHead, "des_Bandeira", "", "")
	cTransac    := GET_REC_JSON(oHead, "num_Transacao", "", "")
	cAutorizF   := GET_REC_JSON(oHead, "des_Autorizacao", "", "")
	nVlrTitulo  := GET_REC_JSON(oHead, "VLR", "", nVlrBrutV)

	/*cCnpjU  := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
	aEmpFil := FATPIEMP(cCnpjU) */

	/*cQryRec := "UPDATE " + RetSqlName("SFT") + " SET "
	cQryRec += "FT_ESTADO = '" + SF2->F2_EST + "', "
	cQryRec += "FT_ESPECIE = '" + SF2->F2_ESPECIE + "', "
	cQryRec += "FT_CHVNFE = '" + SF2->F2_CHVNFE + "', "
	cQryRec += " WHERE FT_NFISCAL ='" + cDocPad + "' AND FT_SERIE='" + cSerPad + "' AND FT_CLIEFOR='" + cCliPad + "' AND FT_LOJA='" + cLojaPad + "' AND FT_TIPOMOV = 'S' AND D_E_L_E_T_=' '"
	TCSqlExec(cQryRec)*/

	/*if Len(aEmpFil) > 0
		If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
			RPCClearEnv()
			RpcSetEnv(aEmpFil[1], aEmpFil[2])
		EndIf
	Endif*/

	If ValType(aPrd) == "A"
		If Len(aPrd) > 0
			If ValType(aPrd[1]) == "O" .Or. ValType(aPrd[1]) == "J"
				For nX := 1 To Len(aPrd)
					nQtdItm     := Max(U_FZ_VAL_X(aPrd[nX], 'qtd_Produto'), 1)
					nVlrUniItm  := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoUnitario')

					// MULTIPLICANDO O DESCONTO PELA QUANTIDADE
					nDescItm    := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoDescontoUnitario') * nQtdItm

					nSomaMerc   += Round(nQtdItm * nVlrUniItm, 2)
					nSomaDesc   += nDescItm
				Next nX
			EndIf
		EndIf
	EndIf

	If nVlrMercV <= 0 ; nVlrMercV := nSomaMerc ; EndIf
		If nDescTot <= 0  ; nDescTot  := nSomaDesc ; EndIf
			If nVlrBrutV <= 0 ; nVlrBrutV := Round(nVlrMercV - nDescTot + nFreteTot + nSegTot + nOutrTot, 2) ; EndIf

				If Empty(cCustoHead)
					If ValType(aPrd) == "A" .And. Len(aPrd) > 0
						If ValType(aPrd[1]) == "O" .Or. ValType(aPrd[1]) == "J"
							cCustoHead := U_FZ_STR_X(aPrd[1], 'cod_CentroCusto')
						EndIf
					EndIf
				EndIf

				If cModDoc == "55"
				    cEspecie := "SPED"
				ElseIf cModDoc == "65"
					cEspecie := "NFCE"
				Else
					cEspecie := "NFE"
				EndIf

				dEmiss := U_FZ_DATA_X(U_FZ_STR_X(oHead, 'dta_Emissao'))

				If cTab == "SA2"
					cEstCli := Posicione("SA2", 1, xFilial("SA2") + cCliSql + cLojaSql, "A2_EST")
				Else
					cEstCli := Posicione("SA1", 1, xFilial("SA1") + cCliSql + cLojaSql, "A1_EST")
				EndIf

				// ATUALIZACAO DO CABECALHO (SF2)
				cQryRec := "SELECT R_E_C_N_O_ AS REC FROM " + RetSqlName("SF2") + " WHERE F2_DOC='" + cDocPad + "' AND F2_SERIE='" + cSerPad + "' AND F2_CLIENTE='" + cCliPad + "' AND F2_LOJA='" + cLojaPad + "' AND D_E_L_E_T_=' '"
				cAliRec := GetNextAlias()
				MpSysOpenQuery(cQryRec, cAliRec)

				If (cAliRec)->(!Eof())
					DbSelectArea("SF2")
					SF2->(DbGoTo((cAliRec)->REC))

					If RecLock("SF2", .F.)
						If SF2->(FieldPos("F2_VALBRUT")) > 0 ; SF2->F2_VALBRUT := nVlrBrutV ; EndIf
							If SF2->(FieldPos("F2_VALFAT")) > 0  ; SF2->F2_VALFAT  := nVlrBrutV ; EndIf
								If SF2->(FieldPos("F2_VALMERC")) > 0 ; SF2->F2_VALMERC := nVlrMercV ; EndIf
									If SF2->(FieldPos("F2_DESCONT")) > 0 ; SF2->F2_DESCONT := nDescTot  ; EndIf
										If SF2->(FieldPos("F2_VALICM")) > 0  ; SF2->F2_VALICM  := nVlrIcmN ; EndIf
											If SF2->(FieldPos("F2_BASEICM")) > 0 ; SF2->F2_BASEICM := nBasIcmN ; EndIf
												If SF2->(FieldPos("F2_VALIPI")) > 0  ; SF2->F2_VALIPI  := nVlrIpiN ; EndIf
													If SF2->(FieldPos("F2_VALPIS")) > 0  ; SF2->F2_VALPIS  := nVlrPisN ; EndIf
														If SF2->(FieldPos("F2_VALCOF")) > 0  ; SF2->F2_VALCOF  := nVlrCofN ; EndIf
															If SF2->(FieldPos("F2_CHVNFE")) > 0  ; SF2->F2_CHVNFE  := PadR(cChaveNFe, TamSx3("F2_CHVNFE")[1]) ; EndIf
																If SF2->(FieldPos("F2_UFDEST")) > 0  ; SF2->F2_UFDEST  := cEstCli ; EndIf
																	If SF2->(FieldPos("F2_ESPECIE")) > 0 ; SF2->F2_ESPECIE := PadR(cEspecie, TamSx3("F2_ESPECIE")[1]) ; EndIf

																		If cNatOp == "DEVOLUCAO DE COMPRA"
																			If SF2->(FieldPos("F2_NFORI")) > 0 ; SF2->F2_NFORI := PadR(U_FZ_STR_X(oHead, 'num_NFOrigem'), TamSx3("F2_NFORI")[1]) ; EndIf
																				If SF2->(FieldPos("F2_CHVCLE")) > 0 ; SF2->F2_CHVCLE := PadR(U_FZ_STR_X(oHead, 'cod_ChaveNFeOrigem'), TamSx3("F2_CHVCLE")[1]) ; EndIf
																					If SF2->(FieldPos("F2_XVLDEV")) > 0 ; SF2->F2_XVLDEV := U_FZ_VAL_X(oHead, 'vlr_NotaFiscalDevCAASP') ; EndIf
																					EndIf

																					SF2->(MsUnlock())
																				EndIf
																			EndIf
																			(cAliRec)->(DbCloseArea())

																			// ATUALIZACAO DOS ITENS (SD2) E LIVRO (SF3)
																			If Select("SF3") > 0
																				cQrySF3 := "DELETE FROM " + RetSqlName("SF3") + " WHERE F3_NFISCAL='" + cDocPad + "' AND F3_SERIE='" + cSerPad + "' AND F3_CLIEFOR='" + cCliPad + "' AND F3_LOJA='" + cLojaPad + "' AND D_E_L_E_T_=' '"
																				TCSqlExec(cQrySF3)

																				aGrpSF3 := {}

																				If ValType(aPrd) == "A"
																					For nX := 1 To Len(aPrd)
																						If ValType(aPrd[nX]) == "O" .Or. ValType(aPrd[nX]) == "J"
																							cTesItm    := PadR(cValToChar(aPrd[nX]['_TES_CACHE']), TamSx3("D2_TES")[1])
																							cCfopItm   := PadR(U_FZ_LIMPA_X(U_FZ_STR_X(aPrd[nX], 'cod_ProdutoCFOP', 'cfop')), TamSx3("D2_CF")[1])
																							cItemSql   := PadL(cValToChar(nX), TamSx3("D2_ITEM")[1], "0")

																							nQtdItm     := Max(U_FZ_VAL_X(aPrd[nX], 'qtd_Produto'), 1)
																							nVlrUniItm  := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoUnitario')
																							nDescItm    := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoDescontoUnitario') * nQtdItm
																							nVlrBrutItm := Round(nQtdItm * nVlrUniItm, 2)
																							nVlrLiqItm  := Round(nVlrBrutItm - nDescItm, 2)
																							cCodCST     := ALLTRIM(U_FZ_STR_X(aPrd[nX], 'cod_ProdutoCST'))

																							// Extracao Fiscal
																							nPicmItem   := U_FZ_VAL_X(aPrd[nX], 'pct_ProdutoICMS')
																							nBicmItem   := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMSBaseCalculo')
																							nVicmItem   := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMS')
																							nBicmStItem := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMSOutrosBaseCalculo')
																							nBIcmsIsen  := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMSIsentoBaseCalculo')
																							nVicmStItem := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMSST')
																							nVicmDeson  := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMSDesonerado')
																							nPReducIcm  := U_FZ_VAL_X(aPrd[nX], 'pct_ProdutoReducaoICMS')
																							nPReducSt   := U_FZ_VAL_X(aPrd[nX], 'pct_ProdutoReducaoICMSST')
																							nFrete      := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoFrete')
																							nOutros     := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoOutros')
																							nVlrLiqItm  := nVlrLiqItm + nFrete

																							nAliqIcm    := nPicmItem
																							nIcmItm     := nVicmItem

																							nPercDesc := 0
																							If nVlrBrutItm > 0
																								nPercDesc := Round((nDescItm / nVlrBrutItm) * 100, 2)
																							EndIf

																							cCustoSD2  := U_FZ_STR_X(aPrd[nX], 'cod_CentroCusto')
																							If Empty(cCustoSD2) ; cCustoSD2 := cCustoHead ; EndIf

																							If Empty(cCfopItm)
                                                                                            cCfopItm := '000'
																							Endif

																							If Empty(cTesItm)
                                                                                            cTesItm := '999'
																							Endif

                                                                                            cNewSFT := GetNextAlias()
																							BeginSQL Alias cNewSFT
																								select 
                                                                                                    SFT.R_E_C_N_O_ AS RECNO,
																									SFT.FT_PRODUTO
                                                                                                from
                                                                                                    %table:SFT% SFT
                                                                                               WHERE
                                                                                                    SFT.%notDel%
		                                                                                        AND TRIM(SFT.FT_NFISCAL) = %exp:(ALLTRIM(SF2->F2_DOC))%
		                                                                                        AND TRIM(SFT.FT_FILIAL) = %exp:(ALLTRIM(SF2->F2_FILIAL))%
		                                                                                        AND TRIM(SFT.FT_SERIE) = %exp:(ALLTRIM(SF2->F2_SERIE))%																					
		                                                                                        AND TRIM(SFT.FT_CLIEFOR) = %exp:(ALLTRIM(SF2->F2_CLIENTE))%
		                                                                                        AND TRIM(SFT.FT_LOJA) = %exp:(ALLTRIM(SF2->F2_LOJA))%
		                                                                                        AND TRIM(SFT.FT_TIPOMOV) = 'S'  
																								AND TRIM(SFT.FT_ITEM) = %exp:(ALLTRIM(cItemSql))%  
	                                                                                      ENDSQL

	                                                                                    (cNewSFT)->(dbGoTop())

	                                                                                    While !(cNewSFT)->(Eof())
                                                                                            SFT->(DbGoTo((cNewSFT)->RECNO))
		                                                                                    If RecLock("SFT",.F.)
		                                                                                        SFT->FT_ALIQICM  := nPicmItem
			                                                                                    SFT->FT_BASEICM  := nBicmItem
			                                                                                    SFT->FT_VALICM   := nVicmItem
																								SFT->FT_ISENICM  := nBIcmsIsen
			                                                                                    SFT->FT_OUTRICM  := nBicmStItem
			                                                                                    SFT->FT_CLASFIS  := ALLTRIM(Posicione('SB1', 1, FWxFilial('SB1') + (cNewSFT)->FT_PRODUTO, 'B1_ORIGEM') + cCodCST)
																								SFT->FT_RECISS   := '2'
			                                                                                    SFT->FT_DESPESA  := nOutros
			                                                                                    SFT->(MsUnlock())
	                                                                                      ENDIF
		                                                                                    (cNewSFT)->(DbSkip())
	                                                                                    End
	                                                                                    (cNewSFT)->(DbCloseArea())

																								cQryRec := "UPDATE " + RetSqlName("SD2") + " SET "
																								cQryRec += "D2_CF = '" + cCfopItm + "', "
																								cQryRec += "D2_CCUSTO = '" + PadR(cCustoSD2, TamSx3("D2_CCUSTO")[1]) + "', "
																								cQryRec += "D2_TES = '" + cTesItm + "', "
																								cQryRec += "D2_PRCVEN = " + StrTran(cValToChar(nVlrUniItm), ",", ".") + ", "
																								cQryRec += "D2_TOTAL = " + StrTran(cValToChar(nVlrBrutItm), ",", ".") + ", "
																								cQryRec += "D2_DESCON = " + StrTran(cValToChar(nDescItm), ",", ".") + ", "

																								// Sem virgula final para receber condicional
																								cQryRec += "D2_DESC = " + StrTran(cValToChar(nPercDesc), ",", ".")

																								// Injeções Fiscais Condicionais
																								If Len(TamSx3("D2_PICM")) > 0    ; cQryRec += ", D2_PICM = " + StrTran(cValToChar(nPicmItem), ",", ".") ; EndIf
																									If Len(TamSx3("D2_BASEICM")) > 0 ; cQryRec += ", D2_BASEICM = " + StrTran(cValToChar(nBicmItem), ",", ".") ; EndIf
																										If Len(TamSx3("D2_VALICM")) > 0  ; cQryRec += ", D2_VALICM = " + StrTran(cValToChar(nVicmItem), ",", ".") ; EndIf
																											If Len(TamSx3("D2_BASERET")) > 0 ; cQryRec += ", D2_BASERET = " + StrTran(cValToChar(nBicmStItem), ",", ".") ; EndIf
																												If Len(TamSx3("D2_VALRET")) > 0  ; cQryRec += ", D2_VALRET = " + StrTran(cValToChar(nVicmStItem), ",", ".") ; EndIf
																													If Len(TamSx3("D2_ICMDES")) > 0  ; cQryRec += ", D2_ICMDES = " + StrTran(cValToChar(nVicmDeson), ",", ".") ; EndIf
																														If Len(TamSx3("D2_PRDICM")) > 0  ; cQryRec += ", D2_PRDICM = " + StrTran(cValToChar(nPReducIcm), ",", ".") ; EndIf
																															If Len(TamSx3("D2_PRDRET")) > 0  ; cQryRec += ", D2_PRDRET = " + StrTran(cValToChar(nPReducSt), ",", ".") ; EndIf

                    /*If cNatOp == "DEVOLUCAO DE COMPRA"
                        cQryRec += ", D2_OUTROS = " + StrTran(cValToChar(U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoOutros')), ",", ".") 
                    EndIf*/
                    
                    cQryRec += " WHERE D2_DOC='" + cDocPad + "' AND D2_SERIE='" + cSerPad + "' AND D2_CLIENTE='" + cCliPad + "' AND D2_LOJA='" + cLojaPad + "' AND D2_ITEM='" + cItemSql + "' AND D_E_L_E_T_=' '"
                    TCSqlExec(cQryRec)
	

                    nPosGrp := AScan(aGrpSF3, {|x| x[1] == cCfopItm .And. x[2] == nAliqIcm})
                    If nPosGrp == 0
                        AAdd(aGrpSF3, {cCfopItm, nAliqIcm, nVlrLiqItm, nIcmItm,nBicmItem,nBicmStItem,nBIcmsIsen,nFrete,nOutros})
                    Else
                        aGrpSF3[nPosGrp][3] += nVlrLiqItm
                        aGrpSF3[nPosGrp][4] += nIcmItm
                        aGrpSF3[nPosGrp][5] += nBicmItem
                        aGrpSF3[nPosGrp][6] += nBicmStItem
                        aGrpSF3[nPosGrp][7] += nBIcmsIsen
						aGrpSF3[nPosGrp][8] += nFrete
						aGrpSF3[nPosGrp][9] += nOutros
                    EndIf
                EndIf
            Next nX
        EndIf

	DbSelectArea("SF2")
	SF2->(DbSetOrder(1))
	DbSelectArea("SFT")
	SFT->(DbSetOrder(1))
	SF2->(DbSeek(xFilial('SF2') + cDoc + cSer + cCli + cLoja))

	If RecLock("SF2", .F.)
		SF2->F2_EST := Posicione('SA1', 1, FWxFilial('SA1') + cCli + cLoja, 'A1_EST')
		SF2->(MsUnlock())
	ENDIF

	BeginSQL Alias cNewSFT
          select 
            SFT.R_E_C_N_O_ AS RECNO
          from
             %table:SFT% SFT
          WHERE
          SFT.%notDel%
		  AND TRIM(SFT.FT_NFISCAL) = %exp:(ALLTRIM(SF2->F2_DOC))%
		  AND TRIM(SFT.FT_FILIAL) = %exp:(ALLTRIM(SF2->F2_FILIAL))%
		  AND TRIM(SFT.FT_SERIE) = %exp:(ALLTRIM(SF2->F2_SERIE))%
		  AND TRIM(SFT.FT_CLIEFOR) = %exp:(ALLTRIM(SF2->F2_CLIENTE))%
		  AND TRIM(SFT.FT_LOJA) = %exp:(ALLTRIM(SF2->F2_LOJA))%
		  AND TRIM(SFT.FT_TIPOMOV) = 'S'     
	ENDSQL

	(cNewSFT)->(dbGoTop())

	While !(cNewSFT)->(Eof())
        SFT->(DbGoTo((cNewSFT)->RECNO))
		If RecLock("SFT",.F.)
		    SFT->FT_ESTADO  := SF2->F2_EST
			SFT->FT_ESPECIE := SF2->F2_ESPECIE
			SFT->FT_CHVNFE  := SF2->F2_CHVNFE
			SFT->(MsUnlock())
	    ENDIF
		(cNewSFT)->(DbSkip())
	End
	(cNewSFT)->(DbCloseArea())

        For nX := 1 To Len(aGrpSF3)
            RecLock("SF3", .T.)
            SF3->F3_FILIAL  := xFilial("SF3")
            SF3->F3_EMISSAO := dEmiss
			SF3->F3_ENTRADA := dEmiss
			SF3->F3_RECISS  := '2'
			SF3->F3_ESTADO  := SF2->F2_EST
			SF3->F3_CHVNFE  := SF2->F2_CHVNFE
            SF3->F3_NFISCAL := cDocPad
            SF3->F3_SERIE   := cSerPad
            SF3->F3_CLIEFOR := cCliPad
			SF3->F3_ESPECIE := SF2->F2_ESPECIE
            SF3->F3_LOJA    := cLojaPad
            SF3->F3_CFO     := aGrpSF3[nX][1]
            SF3->F3_ALIQICM := aGrpSF3[nX][2]
            SF3->F3_VALCONT := aGrpSF3[nX][3]
            SF3->F3_VALICM  := aGrpSF3[nX][4]
            SF3->F3_BASEICM := aGrpSF3[nX][5]
            SF3->F3_OUTRICM := aGrpSF3[nX][6]
            SF3->F3_ISENICM := aGrpSF3[nX][7]
			SF3->F3_DESPESA := aGrpSF3[nX][9]


            SF3->F3_ESPECIE := PadR(cEspecie, TamSx3("F3_ESPECIE")[1]) 
            SF3->(MsUnlock())
        Next nX
    EndIf

    // ATUALIZACAO DO FINANCEIRO (SE1) 
    cHistPad := "API: Orig:" + cOrigem + " Aut:" + cAutoriz + " Trans:" + cTransacao
    
    If Empty(cNatItm) ; cNatItm := cNatJson ; EndIf
    If Empty(cCCItm)  ; cCCItm  := cCustoHead ; EndIf 
    If Empty(cFormaRec) ; cFormaRec := Upper(AllTrim(cFormaPag)) ; EndIf
    
    cFormaRec := Upper(AllTrim(cFormaRec))

    If cModDoc == "55" .Or. cModDoc == "65"
        cTipoE1 := "NF "
    Else
        cTipoE1 := "RC " 
    EndIf

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

    cAliSE1 := GetNextAlias()
    cQrySE1 := "SELECT R_E_C_N_O_ AS REC, E1_PARCELA FROM " + RetSqlName("SE1") 
    cQrySE1 += " WHERE E1_NUM='" + cDocPad + "' AND E1_PREFIXO='" + cSerPad + "' AND E1_CLIENTE='" + cCliPad + "' AND E1_LOJA='" + cLojaPad + "'"
    cQrySE1 += " AND D_E_L_E_T_=' ' ORDER BY E1_PARCELA"
    MpSysOpenQuery(cQrySE1, cAliSE1)

    While (cAliSE1)->(!Eof())
        cParcela := (cAliSE1)->E1_PARCELA
        If Empty(AllTrim(cParcela)) ; cParcela := "1" ; EndIf
        
        cQrySE1 := "UPDATE " + RetSqlName("SE1") + " SET "
        cQrySE1 += "E1_TIPO = '" + PadR(cTipoE1, TamSx3("E1_TIPO")[1]) + "', "
        cQrySE1 += "E1_PARCELA = '" + PadR(cParcela, TamSx3("E1_PARCELA")[1]) + "', "
        cQrySE1 += "E1_NATUREZ = '" + PadR(cNatItm, TamSx3("E1_NATUREZ")[1]) + "', "
        cQrySE1 += "E1_CCUSTO = '" + PadR(cCCItm, TamSx3("E1_CCUSTO")[1]) + "', "
        cQrySE1 += "E1_XEVENTO = '" + PadR(cOrigem, TamSx3("E1_XEVENTO")[1]) + "', "
        
        cQrySE1 += "E1_VALOR = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
        cQrySE1 += "E1_SALDO = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
        cQrySE1 += "E1_VALLIQ = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
        cQrySE1 += "E1_VLCRUZ = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
        
        If !Empty(cFormaTrat) ; cQrySE1 += "E1_FORMAPG = '" + PadR(cFormaTrat, TamSx3("E1_FORMAPG")[1]) + "', " ; EndIf
        If !Empty(cBandeira)  ; cQrySE1 += "E1_CARTAO = '" + PadR(cBandeira, TamSx3("E1_CARTAO")[1]) + "', " ; EndIf
        If !Empty(cTransac)   ; cQrySE1 += "E1_NSUTEF = '" + PadR(cTransac, TamSx3("E1_NSUTEF")[1]) + "', " ; EndIf
        If !Empty(cAutorizF)  ; cQrySE1 += "E1_CARTAUT = '" + PadR(cAutorizF, TamSx3("E1_CARTAUT")[1]) + "', " ; EndIf
        
        cQrySE1 += "E1_HIST = '" + Left(cHistPad + " " + cFormaRec, TamSx3("E1_HIST")[1]) + "' "
        cQrySE1 += "WHERE R_E_C_N_O_ = " + cValToChar((cAliSE1)->REC)
        
        TCSqlExec(cQrySE1)
        (cAliSE1)->(DbSkip())
    EndDo
    (cAliSE1)->(DbCloseArea())

Return

// ==========================================================================
// COMPRAS (ENTRADAS) - JSON_COMPRA - Tratamento Cirurgico Pos-Gravacao
// ==========================================================================
Static Function JSON_COMPRA(cDoc, cSer, cForn, cLoja, aPrd, oHead, cTab)
    Local nTamF1Doc  := IIf(Len(TamSx3("F1_DOC"))>0, TamSx3("F1_DOC")[1], 9)
    Local nTamF1Ser  := IIf(Len(TamSx3("F1_SERIE"))>0, TamSx3("F1_SERIE")[1], 3)
    Local nTamF1Forn := IIf(Len(TamSx3("F1_FORNECE"))>0, TamSx3("F1_FORNECE")[1], 6)
    Local nTamF1Loja := IIf(Len(TamSx3("F1_LOJA"))>0, TamSx3("F1_LOJA")[1], 2)
    Local nTamF1Esp  := IIf(Len(TamSx3("F1_ESPECIE"))>0, TamSx3("F1_ESPECIE")[1], 5)
    Local nTamF1Chv  := IIf(Len(TamSx3("F1_CHVNFE"))>0, TamSx3("F1_CHVNFE")[1], 44)
    
    Local nTamD1Item := IIf(Len(TamSx3("D1_ITEM"))>0, TamSx3("D1_ITEM")[1], 4)
    Local nTamD1Tes  := IIf(Len(TamSx3("D1_TES"))>0, TamSx3("D1_TES")[1], 3)
    Local nTamD1Cf   := IIf(Len(TamSx3("D1_CF"))>0, TamSx3("D1_CF")[1], 5)
    Local nTamD1CC   := IIf(Len(TamSx3("D1_CCUSTO"))>0, TamSx3("D1_CCUSTO")[1], 9)

    Local nTamE2Tipo := IIf(Len(TamSx3("E2_TIPO"))>0, TamSx3("E2_TIPO")[1], 3)
    Local nTamE2Parc := IIf(Len(TamSx3("E2_PARCELA"))>0, TamSx3("E2_PARCELA")[1], 2)
    Local nTamE2Nat  := IIf(Len(TamSx3("E2_NATUREZ"))>0, TamSx3("E2_NATUREZ")[1], 10)
    Local nTamE2CC   := IIf(Len(TamSx3("E2_CCUSTO"))>0, TamSx3("E2_CCUSTO")[1], 9)
    Local nTamE2CCD  := IIf(Len(TamSx3("E2_CCD"))>0, TamSx3("E2_CCD")[1], 9)
    Local nTamE2Hist := IIf(Len(TamSx3("E2_HIST"))>0, TamSx3("E2_HIST")[1], 40)

    Local cDocSql     := AllTrim(cDoc)
    Local cSerSql     := AllTrim(cSer)
    Local cFornSql    := AllTrim(cForn)
    Local cLojaSql    := AllTrim(cLoja)
    Local cItemSql    := ""
    Local cQryRec     := ""
    Local cAliRec     := ""
    Local nX          := 0
    Local dEmiss      := CToD("//")
    Local cAliSE2     := ""
    Local cQrySE2     := ""
    Local cChaveNFe   := U_FZ_STR_X(oHead, 'cod_ChaveNFe') 
    Local cModDoc     := U_FZ_STR_X(oHead, 'cod_Mod', 'modelo')
    Local cEspecie    := ""

    Local cTipoE2     := "NF "
    Local cHistPad    := "API: Entrada NF/RC"
    Local cNatJson    := U_FZ_STR_X(oHead, "cod_NaturezaFinanceira")
    Local cFormaPag   := U_FZ_STR_X(oHead, "des_FormaPagamento")

    Local nVlrMercV   := U_FZ_VAL_X(oHead, 'vlr_TotalProduto')
    Local nVlrBrutV   := U_FZ_VAL_X(oHead, 'vlr_NotaFiscal')
    Local nDescTot    := U_FZ_VAL_X(oHead, 'vlr_Desconto')
    Local nFreteTot   := U_FZ_VAL_X(oHead, 'vlr_Frete')
    Local nSegTot     := U_FZ_VAL_X(oHead, 'vlr_Seguro')
    Local nOutrTot    := U_FZ_VAL_X(oHead, 'vlr_Outros')
    
    Local nSomaMerc   := 0
    Local nSomaDesc   := 0
    Local nVlrBrutItm := 0
    Local nDescItm    := 0
    Local nPercDesc   := 0
    Local nVlrLiqItm  := 0
    Local nQtdItm     := 0
    Local nVlrUniItm  := 0

    Local cCfopItm    := ""
    Local cTesItm     := ""

    Local nVlrIcmN    := U_FZ_VAL_X(oHead, 'vlr_ICMS')
    Local nBasIcmN    := U_FZ_VAL_X(oHead, 'vlr_ICMSBaseCalculo')
    Local nVlrIpiN    := U_FZ_VAL_X(oHead, 'vlr_IPI')
    Local nVlrPisN    := U_FZ_VAL_X(oHead, 'vlr_PIS')
    Local nVlrCofN    := U_FZ_VAL_X(oHead, 'vlr_COFINS')

    Local cDocPad     := PadL(AllTrim(cDocSql), nTamF1Doc, "0")
    Local cSerPad     := PadR(AllTrim(cSerSql), nTamF1Ser, " ")
    Local cFornPad    := PadR(AllTrim(cFornSql), nTamF1Forn, " ")
    Local cLojaPad    := PadR(AllTrim(cLojaSql), nTamF1Loja, " ")
    
    Local cCustoHead  := U_FZ_STR_X(oHead, 'cod_CentroCusto')
    Local cCustoSD1   := ""
    
    Local cNatItm     := ""
    Local cCCItm      := ""
    Local nVlrTitulo  := 0
    Local cParcela    := ""

    // Variaveis Fiscais Adicionais (ICMS/ST)
    Local nPicmItem   := 0
    Local nBicmItem   := 0
    Local nVicmItem   := 0
    Local nBicmStItem := 0
    Local nVicmStItem := 0
    Local nVicmDeson  := 0
    Local nPReducIcm  := 0
    Local nPReducSt   := 0
	Local nDespesa    := 0
	Local cNewSFT
	Local cNewSD1

    cNatItm     := GET_REC_JSON(oHead, "cod_NaturezaFinanceira", "", "")
    cCCItm      := GET_REC_JSON(oHead, "cod_CentroCusto", "", "")
    nVlrTitulo  := GET_REC_JSON(oHead, "VLR", "", nVlrBrutV)

    If ValType(aPrd) == "A"
        If Len(aPrd) > 0
            If ValType(aPrd[1]) == "O" .Or. ValType(aPrd[1]) == "J"
                For nX := 1 To Len(aPrd) 
                    nQtdItm     := Max(U_FZ_VAL_X(aPrd[nX], 'qtd_Produto'), 1) 
                    nVlrUniItm  := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoUnitario') 
                    
                    nDescItm    := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoDescontoUnitario') * nQtdItm 
                    
                    nVlrBrutItm := Round(nQtdItm * nVlrUniItm, 2) 
                    nVlrLiqItm  := Round(nVlrBrutItm - nDescItm, 2) 
                    
                    nSomaMerc   += nVlrBrutItm
                    nSomaDesc   += nDescItm
                Next nX 
            EndIf
        EndIf
    EndIf
 
    If nVlrMercV <= 0 ; nVlrMercV := nSomaMerc ; EndIf
    If nDescTot <= 0  ; nDescTot  := nSomaDesc ; EndIf
    If nVlrBrutV <= 0 ; nVlrBrutV := Round(nVlrMercV - nDescTot + nFreteTot + nSegTot + nOutrTot, 2) ; EndIf

    If Empty(cCustoHead)
        If ValType(aPrd) == "A" .And. Len(aPrd) > 0
            If ValType(aPrd[1]) == "O" .Or. ValType(aPrd[1]) == "J"
                cCustoHead := U_FZ_STR_X(aPrd[1], 'cod_CentroCusto')
            EndIf
        EndIf
    EndIf

    If cModDoc == "55" .Or. cModDoc == "65"
        cEspecie := "SPED"
    Else
        cEspecie := "NFE"
    EndIf

    dEmiss := U_FZ_DATA_X(U_FZ_STR_X(oHead, 'dta_Emissao'))

    // ATUALIZACAO DO CABECALHO (SF1)
    cQryRec := "SELECT R_E_C_N_O_ AS REC FROM " + RetSqlName("SF1") + " WHERE F1_DOC='" + cDocPad + "' AND F1_SERIE='" + cSerPad + "' AND F1_FORNECE='" + cFornPad + "' AND F1_LOJA='" + cLojaPad + "' AND D_E_L_E_T_=' '"
    cAliRec := GetNextAlias() 
    MpSysOpenQuery(cQryRec, cAliRec)

    If (cAliRec)->(!Eof())
        DbSelectArea("SF1") 
        SF1->(DbGoTo((cAliRec)->REC))
        
        If RecLock("SF1", .F.)
            If SF1->(FieldPos("F1_VALBRUT")) > 0 ; SF1->F1_VALBRUT := nVlrBrutV ; EndIf
            If SF1->(FieldPos("F1_VALMERC")) > 0 ; SF1->F1_VALMERC := nVlrMercV ; EndIf
            If SF1->(FieldPos("F1_DESCONT")) > 0 ; SF1->F1_DESCONT := nDescTot  ; EndIf
            If SF1->(FieldPos("F1_VALICM")) > 0  ; SF1->F1_VALICM  := nVlrIcmN ; EndIf
            If SF1->(FieldPos("F1_BASEICM")) > 0 ; SF1->F1_BASEICM := nBasIcmN ; EndIf
            If SF1->(FieldPos("F1_VALIPI")) > 0  ; SF1->F1_VALIPI  := nVlrIpiN ; EndIf
            If SF1->(FieldPos("F1_VALPIS")) > 0  ; SF1->F1_VALPIS  := nVlrPisN ; EndIf
            If SF1->(FieldPos("F1_VALCOFI")) > 0 ; SF1->F1_VALCOFI := nVlrCofN ; EndIf
            
            If Len(TamSx3("F1_CHVNFE")) > 0 .And. SF1->(FieldPos("F1_CHVNFE")) > 0  
                SF1->F1_CHVNFE := PadR(cChaveNFe, nTamF1Chv) 
            EndIf
            If SF1->(FieldPos("F1_ESPECIE")) > 0 ; SF1->F1_ESPECIE := PadR(cEspecie, nTamF1Esp) ; EndIf
            
            SF1->(MsUnlock())
        EndIf
    EndIf
    (cAliRec)->(DbCloseArea())

    // ATUALIZACAO DOS ITENS (SD1)
    If ValType(aPrd) == "A"
        For nX := 1 To Len(aPrd)
            If ValType(aPrd[nX]) == "O" .Or. ValType(aPrd[nX]) == "J"
                cTesItm    := PadR(cValToChar(aPrd[nX]['_TES_CACHE']), nTamD1Tes)
                cCfopItm   := PadR(U_FZ_LIMPA_X(U_FZ_STR_X(aPrd[nX], 'cod_ProdutoCFOP', 'cfop')), nTamD1Cf)
                cItemSql   := PadL(cValToChar(nX), nTamD1Item, "0")
                
                nQtdItm     := Max(U_FZ_VAL_X(aPrd[nX], 'qtd_Produto'), 1)
                nVlrUniItm  := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoUnitario')
                
                nDescItm    := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoDescontoUnitario') * nQtdItm
                nVlrBrutItm := Round(nQtdItm * nVlrUniItm, 2)
                nVlrLiqItm  := Round(nVlrBrutItm - nDescItm, 2) 

                nPicmItem   := U_FZ_VAL_X(aPrd[nX], 'pct_ProdutoICMS')
                nBicmItem   := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMSBaseCalculo')
                nVicmItem   := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMS')
                nBicmStItem := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMSSTBaseCalculo')
                nVicmStItem := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMSST')
                nVicmDeson  := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoICMSDesonerado')
                nPReducIcm  := U_FZ_VAL_X(aPrd[nX], 'pct_ProdutoReducaoICMS')
                nPReducSt   := U_FZ_VAL_X(aPrd[nX], 'pct_ProdutoReducaoICMSST')
				nDespesa    := U_FZ_VAL_X(aPrd[nX], 'vlr_ProdutoOutros')

                nPercDesc := 0
                If nVlrBrutItm > 0
                    nPercDesc := Round((nDescItm / nVlrBrutItm) * 100, 2)
                EndIf

                cCustoSD1  := U_FZ_STR_X(aPrd[nX], 'cod_CentroCusto')
                If Empty(cCustoSD1) ; cCustoSD1 := cCustoHead ; EndIf

                cQryRec := "UPDATE " + RetSqlName("SD1") + " SET "
                cQryRec += "D1_CF = '" + cCfopItm + "', "
                
                If Len(TamSx3("D1_CC")) > 0
                    cQryRec += "D1_CC = '" + PadR(cCustoSD1, nTamD1CC) + "', "
                EndIf
                
                // <--- CORREÇÃO: D1_VALDESC (Valor Monetário) e D1_DESC (Percentual) aplicados corretamente --->
                cQryRec += "D1_TES = '" + cTesItm + "', "
                //cQryRec += "D1_TOTAL = " + StrTran(cValToChar(nVlrBrutItm), ",", ".") + ", " 
                //cQryRec += "D1_VALDESC = " + StrTran(cValToChar(nDescItm), ",", ".") + ", "
                //cQryRec += "D1_DESC = " + StrTran(cValToChar(nPercDesc), ",", ".") 
                
                // Injeções Fiscais Condicionais
                /*If Len(TamSx3("D1_PICM")) > 0  ; cQryRec += ", D1_PICM = " + StrTran(cValToChar(nPicmItem), ",", ".") ; EndIf
                If Len(TamSx3("D1_BASEICM")) > 0 ; cQryRec += ", D1_BASEICM = " + StrTran(cValToChar(nBicmItem), ",", ".") ; EndIf
                If Len(TamSx3("D1_VALICM")) > 0  ; cQryRec += ", D1_VALICM = " + StrTran(cValToChar(nVicmItem), ",", ".") ; EndIf
                If Len(TamSx3("D1_BASERET")) > 0 ; cQryRec += ", D1_BASERET = " + StrTran(cValToChar(nBicmStItem), ",", ".") ; EndIf
                If Len(TamSx3("D1_VALRET")) > 0  ; cQryRec += ", D1_VALRET = " + StrTran(cValToChar(nVicmStItem), ",", ".") ; EndIf
                If Len(TamSx3("D1_ICMDES")) > 0  ; cQryRec += ", D1_ICMDES = " + StrTran(cValToChar(nVicmDeson), ",", ".") ; EndIf
                If Len(TamSx3("D1_PRDICM")) > 0  ; cQryRec += ", D1_PRDICM = " + StrTran(cValToChar(nPReducIcm), ",", ".") ; EndIf
                If Len(TamSx3("D1_PRDRET")) > 0  ; cQryRec += ", D1_PRDRET = " + StrTran(cValToChar(nPReducSt), ",", ".") ; EndIf*/

                cQryRec += " WHERE D1_DOC='" + cDocPad + "' AND D1_SERIE='" + cSerPad + "' AND D1_FORNECE='" + cFornPad + "' AND D1_LOJA='" + cLojaPad + "' AND D1_ITEM='" + cItemSql + "' AND D_E_L_E_T_=' '"
                TCSqlExec(cQryRec)


/*
                //SFT
				cNewSFT := GetNextAlias()
				BeginSQL Alias cNewSFT
					select 
                        SFT.R_E_C_N_O_ AS RECNO
                    from
                        %table:SFT% SFT
                     WHERE
                    SFT.%notDel%
		            AND TRIM(SFT.FT_NFISCAL) = %exp:(ALLTRIM(SF1->F1_DOC))%
		            AND TRIM(SFT.FT_FILIAL) = %exp:(ALLTRIM(SF1->F1_FILIAL))%
		            AND TRIM(SFT.FT_SERIE) = %exp:(ALLTRIM(SF1->F1_SERIE))%																					
		            AND TRIM(SFT.FT_CLIEFOR) = %exp:(ALLTRIM(SF1->F1_FORNECE))%
		            AND TRIM(SFT.FT_LOJA) = %exp:(ALLTRIM(SF1->F1_LOJA))%
		            AND TRIM(SFT.FT_TIPOMOV) = 'E'  
					AND TRIM(SFT.FT_ITEM) = %exp:(ALLTRIM(cItemSql))%  
	            ENDSQL

	            (cNewSFT)->(dbGoTop())

	            While !(cNewSFT)->(Eof())
                SFT->(DbGoTo((cNewSFT)->RECNO))
		        If RecLock("SFT",.F.)
			        SFT->FT_DESPESA  := nDespesa
			        SFT->(MsUnlock())
	            ENDIF
		        (cNewSFT)->(DbSkip())
	            End
	            (cNewSFT)->(DbCloseArea())

                //SD1
				cNewSD1 := GetNextAlias()
				BeginSQL Alias cNewSD1
					select 
                        SD1.R_E_C_N_O_ AS RECNO
                    from
                        %table:SD1% SD1
                     WHERE
                    SD1.%notDel%
		            AND TRIM(SD1.D1_DOC) = %exp:(ALLTRIM(SF1->F1_DOC))%
		            AND TRIM(SD1.D1_FILIAL) = %exp:(ALLTRIM(SF1->F1_FILIAL))%
		            AND TRIM(SD1.D1_SERIE) = %exp:(ALLTRIM(SF1->F1_SERIE))%																					
		            AND TRIM(SD1.D1_FORNECE) = %exp:(ALLTRIM(SF1->F1_FORNECE))%
		            AND TRIM(SD1.D1_LOJA) = %exp:(ALLTRIM(SF1->F1_LOJA))%
					AND TRIM(SD1.D1_ITEM) = %exp:(ALLTRIM(cItemSql))%  
	            ENDSQL

	            (cNewSD1)->(dbGoTop())

	            While !(cNewSD1)->(Eof())
                SD1->(DbGoTo((cNewSD1)->RECNO))
		        If RecLock("SD1",.F.)
			        SD1->D1_DESPESA  := nDespesa
			        SD1->(MsUnlock())
	            ENDIF
		        (cNewSD1)->(DbSkip())
	            End
	            (cNewSD1)->(DbCloseArea())*/
				
            EndIf
        Next nX
    EndIf

    // ATUALIZACAO DO FINANCEIRO (SE2)
    cHistPad := "API: Entrada NF/RC"
    
    If nVlrTitulo <= 0 ; nVlrTitulo := nVlrBrutV ; EndIf
    If Empty(cNatItm) ; cNatItm := cNatJson ; EndIf
    If Empty(cCCItm)  ; cCCItm  := cCustoHead ; EndIf 

    If cModDoc == "55" .Or. cModDoc == "65"
        cTipoE2 := "NF "
    Else
        cTipoE2 := "RC "
    EndIf

    cAliSE2 := GetNextAlias()
    cQrySE2 := "SELECT R_E_C_N_O_ AS REC, E2_PARCELA FROM " + RetSqlName("SE2") 
    cQrySE2 += " WHERE E2_NUM='" + cDocPad + "' AND E2_PREFIXO='" + cSerPad + "' AND E2_FORNECE='" + cFornPad + "' AND E2_LOJA='" + cLojaPad + "'"
    cQrySE2 += " AND D_E_L_E_T_=' ' ORDER BY E2_PARCELA"
    MpSysOpenQuery(cQrySE2, cAliSE2)

    While (cAliSE2)->(!Eof())
        cParcela := (cAliSE2)->E2_PARCELA
        If Empty(AllTrim(cParcela)) ; cParcela := "1" ; EndIf
        
        cQrySE2 := "UPDATE " + RetSqlName("SE2") + " SET "
        cQrySE2 += "E2_TIPO = '" + PadR(cTipoE2, nTamE2Tipo) + "', "
        cQrySE2 += "E2_PARCELA = '" + PadR(cParcela, nTamE2Parc) + "', "
        cQrySE2 += "E2_NATUREZ = '" + PadR(cNatItm, nTamE2Nat) + "', "
        
        If Len(TamSx3("E2_CCUSTO")) > 0
            cQrySE2 += "E2_CCUSTO = '" + PadR(cCCItm, nTamE2CC) + "', "
        ElseIf Len(TamSx3("E2_CCD")) > 0
            cQrySE2 += "E2_CCD = '" + PadR(cCCItm, nTamE2CCD) + "', "
        EndIf
        
        cQrySE2 += "E2_HIST = '" + Left(cHistPad, nTamE2Hist) + "' "
        
        cQrySE2 += "WHERE R_E_C_N_O_ = " + cValToChar((cAliSE2)->REC)
        
        TCSqlExec(cQrySE2)
        (cAliSE2)->(DbSkip())
    EndDo
    (cAliSE2)->(DbCloseArea())

Return

// ==========================================================================
// FUNCOES DE EXECUCAO E UTILITARIOS
// ==========================================================================
User Function FZ_EX120_X(c,i)
    Local cM := ""
    Private INCLUI := .T.
    Private lMsErroAuto := .F.
    Private lAutoErrNoFile := .T.
    Private __cBatch := "1"
    Private cCadastro := "PC"
    MSExecAuto({|x,y,z| MATA120(x,y,z)},1,c,i)
    If lMsErroAuto 
        RollBackSx8() 
        cM := U_FZ_LOG_X("MATA120") 
        Return {.F., cM} 
    EndIf
Return {.T., "OK"}

User Function FZ_E103_GEN(c, i, cTipo)
    Local cM := ""
    Private INCLUI := .T.
    Private lMsErroAuto := .F.
    Private lAutoErrNoFile := .T.
    Private __cBatch := "1"
    Private cCadastro := "NFE"
    MSExecAuto({|x, y, z| MATA103(x, y, z)}, c, i, 3)
    If lMsErroAuto
        RollBackSx8()
        If cTipo == "D" 
            cM := U_FZ_LOG_X("MATA103_DEV") 
        Else 
            cM := U_FZ_LOG_X("MATA103") 
        EndIf
        Return {.F., cM}
    EndIf
Return {.T., "OK"}

User Function FZ_STR_X(o, k1, k2)
    Local x := ""
    If o != Nil 
        x := o[k1]
        If x == Nil .And. k2 != Nil
            x := o[k2]
        EndIf
    EndIf
    
    If ValType(x) == "C"
        Return AllTrim(x)
    ElseIf ValType(x) == "N"
        Return cValToChar(x)
    ElseIf ValType(x) == "L"
        If x
            Return "S"
        Else
            Return ""
        EndIf
    EndIf
Return ""

User Function FZ_VAL_X(o, k1, k2)
    Local x := 0
    If o != Nil 
        x := o[k1]
        If x == Nil .And. k2 != Nil
            x := o[k2]
        EndIf
    EndIf

    If ValType(x) == "N"
        Return x
    ElseIf ValType(x) == "C"
        Return Val(x)
    EndIf
Return 0

User Function FZ_LIMPA_X(c)
    Local cRet := StrTran(AllTrim(c), ".", "")
    cRet := StrTran(cRet, "-", "")
    cRet := StrTran(cRet, "/", "")
Return cRet

User Function FZ_DATA_X(c)
    If Empty(c) 
        Return dDataBase 
    EndIf
    Return SToD(StrTran(SubStr(c, 1, 10), "-", ""))

User Function FZ_SM0_X(cCgc)
    Local aRet := {}
    Local cAliasSM0 := GetNextAlias()
    Local cQuery := "SELECT M0_CODIGO, M0_CODFIL FROM " + RetSqlName("SM0") + " WHERE M0_CGC = '" + U_FZ_LIMPA_X(cCgc) + "' AND D_E_L_E_T_ = ' '"
    
    DbUseArea(.T., "TOPCONN", TcGenQry(,,cQuery), cAliasSM0, .T., .T.)
    
    If (cAliasSM0)->(!Eof())
        AAdd(aRet, AllTrim((cAliasSM0)->M0_CODIGO))
        AAdd(aRet, AllTrim((cAliasSM0)->M0_CODFIL))
    EndIf
    
    (cAliasSM0)->(DbCloseArea())
Return aRet

User Function FZ_SQL_X(cT, cK, cF, cC, cL, cFi)
    Local cA := GetNextAlias()
    Local cField := ""
    Local cQ := ""

    If cT == "SA1"
        cField := "A1_CGC"
        cQ := "SELECT A1_COD AS COD, A1_LOJA AS LOJA FROM " + RetSqlName(cT) + " WHERE " + cField + " = '" + cK + "' AND D_E_L_E_T_ = ' '"
    Else
        cField := "A2_CGC"
        cQ := "SELECT A2_COD AS COD, A2_LOJA AS LOJA FROM " + RetSqlName(cT) + " WHERE " + cField + " = '" + cK + "' AND D_E_L_E_T_ = ' '"
    EndIf
    
    MpSysOpenQuery(cQ, cA)
    
    If (cA)->(!Eof())
        cC := (cA)->COD
        cL := (cA)->LOJA
        cFi := cF
    EndIf
    
    (cA)->(DbCloseArea())
Return

User Function FZ_CC_X(cProd)
    Local cCust := Posicione("SB1", 1, xFilial("SB1") + PadR(cProd, TamSx3("B1_COD")[1]), "B1_CC")
    If Empty(cCust)
        cCust := "03801"
    EndIf
Return cCust

User Function FZ_ACC_X(cProd)
    Local cConta := Posicione("SB1", 1, xFilial("SB1") + PadR(cProd, TamSx3("B1_COD")[1]), "B1_CONTA")
    If Empty(cConta)
        cConta := SuperGetMv("MV_XCCPAD", .F., "11100901")
    EndIf
Return cConta

User Function FZ_LOC_X(cProd)
    Local cLoc := Posicione("SB1", 1, xFilial("SB1") + PadR(cProd, TamSx3("B1_COD")[1]), "B1_LOCPAD")
    If Empty(cLoc)
        cLoc := "01"
    EndIf
Return cLoc

User Function FZ_NAT_X(cCli, cLoja, oJson)
    Local cNat := Posicione("SA1", 1, xFilial("SA1") + cCli + cLoja, "A1_NATUREZ")
    If Empty(cNat)
        cNat := "OUTROS"
    EndIf
Return cNat

User Function FZ_GETEST(cTab, cCod, cLoja)
    Local cEst := "SP"
    DbSelectArea(cTab)
    (cTab)->(DbSetOrder(1))
    If (cTab)->(DbSeek(xFilial(cTab) + cCod + cLoja))
        If cTab == "SA1"
            cEst := SA1->A1_EST
        Else
            cEst := SA2->A2_EST
        EndIf
    EndIf
Return cEst

User Function FZ_INF_X(cDoc, cLeg, cSer, oHead, cPed)
    Local cChave := U_FZ_STR_X(oHead, "cod_ChaveNFe")
    If Select("SF2") > 0
        DbSelectArea("SF2")
        SF2->(DbSetOrder(1))
        If SF2->(DbSeek(xFilial("SF2") + PadR(cDoc, TamSx3("F2_DOC")[1]) + PadR(cSer, TamSx3("F2_SERIE")[1])))
            RecLock("SF2", .F.)
            If SF2->(FieldPos("F2_CHVNFE")) > 0
                SF2->F2_CHVNFE := PadR(cChave, TamSx3("F2_CHVNFE")[1])
            EndIf
            If SF2->(FieldPos("F2_LEGADO")) > 0
                SF2->F2_LEGADO := cLeg
            EndIf
            SF2->(MsUnlock())
        EndIf
    EndIf
Return

User Function FZ_FIX_PROD(cProd, oItem)
Return

Static Function FZ_FIX_TES(cTES)
Return

User Function FZ_COND_X(c)
Return c

User Function FZ_COND9()
Return "001"

User Function FZ_SETFCA(cTab, cCod, cLoja, cCond, oHead)
Return

User Function FZ_LOG_X(cRotina)
    Local cErrLog := ""
    Local aLogAut := GetAutoGrLog()
    Local cFile   := ""
    Local nL      := 0
    Local cDt     := DToS(Date())
    Local cHr     := StrTran(Time(), ":", "-")
    
    cErrLog += "Rotina: " + cRotina + CRLF 
    cErrLog += "Data/Hora: " + cDt + " " + cHr + CRLF 
    cErrLog += "--------------------------------------------------" + CRLF
    
    If ValType(aLogAut) == "A"
        For nL := 1 To Len(aLogAut) 
            cErrLog += aLogAut[nL] + CRLF 
        Next nL
    Else
        cErrLog += "Erro generico sem log detalhado do ExecAuto." + CRLF
    EndIf
    
    cFile := "\system\FATPI01_" + cRotina + "_" + cDt + "_" + cHr + ".log"
    MemoWrite(cFile, cErrLog) 
    ConOut("[TRAT_ERR] Log gravado em: " + cFile)
Return cErrLog

// ==========================================================================
// INVERSAO DE PARZINHO DE CFOP (ESPELHAMENTO FISCAL)
// ==========================================================================
User Function FZ_INVERT_CFOP(cCFOP, cOper)
    Local cRet := AllTrim(cCFOP)

    If cOper == "E" .Or. cOper == "D"
        If Left(cRet, 1) == "5"
            cRet := "1" + SubStr(cRet, 2)
        ElseIf Left(cRet, 1) == "6"
            cRet := "2" + SubStr(cRet, 2)
        ElseIf Left(cRet, 1) == "7"
            cRet := "3" + SubStr(cRet, 2)
        EndIf
    ElseIf cOper == "S"
        If Left(cRet, 1) == "1"
            cRet := "5" + SubStr(cRet, 2)
        ElseIf Left(cRet, 1) == "2"
            cRet := "6" + SubStr(cRet, 2)
        ElseIf Left(cRet, 1) == "3"
            cRet := "7" + SubStr(cRet, 2)
        EndIf
    EndIf

Return PadR(cRet, TamSx3("D1_CF")[1])

/*
+----------------------------------------------------------------------------+
| Autor: Antonio Nunes O Jr | Data: 07/04/2026                               |
| Descritivo: FATPI0101 - Auto-Entrada de Transferencia (CONVENIOS)          |
+----------------------------------------------------------------------------+
*/
User Function FATPI0101(aPrd, oHead, cCnpjOrigem, cDoc, cSer, aEmpDest, lIsTransf)
	Local aRet       := {.F., ""}
	Local cEmpAtu    := cEmpAnt
	Local cFilAtu    := cFilAnt
	Local nI         := 0
	Local cAuxC      := ""
	Local oMotorRegras := Nil
	Local aRetCfop   := {}
	Local cForn      := ""
	Local cLoja      := ""
	Local cQryAux    := ""
	Local cAliAux    := ""
	Local cCondSafe  := ""
	Local cOldPcNfe  := ""
	Local lOkTes     := .T.
	Local cMsgTes    := ""

	// 1. Troca de Ambiente para Filial de Destino
	//RpcClearEnv()
	//RpcSetEnv(aEmpDest[1], aEmpDest[2], Nil, Nil, "FAT")
	cFilAnt := aEmpDest[2]

	// -> DESLIGA OBRIGATORIEDADE DE PEDIDO DE COMPRAS (APENAS PARA TRANSFERENCIA) <-
	cOldPcNfe := SuperGetMv("MV_PCNFE", .F., "2")
	PutMv("MV_PCNFE", "2")

	// 2. Localiza a Filial de Origem (A1/A2) na base da Filial Destino
	cQryAux := "SELECT A2_COD, A2_LOJA FROM " + RetSqlName("SA2") + " WHERE A2_CGC = '" + cCnpjOrigem + "' AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	If (cAliAux)->(!Eof())
		cForn := (cAliAux)->A2_COD
		cLoja := (cAliAux)->A2_LOJA
	EndIf
	(cAliAux)->(DbCloseArea())

	If Empty(cForn)
		aRet := {.F., "Filial de origem nao cadastrada como fornecedor na base de destino."}
	Else
		// 3. Recalcula as regras (TES/CFOP) sob a otica do novo ambiente
		oMotorRegras := U_FATCFOP01()
		cCondSafe := PadR(U_FZ_COND_X("004"), 3)

		For nI := 1 To Len(aPrd)
			cAuxC := U_FZ_LIMPA_X(U_FZ_STR_X(aPrd[nI], 'cod_ProdutoCFOP', 'cfop'))

			// Inverte CFOP para a Otica de Entrada (Ex: 5409 vira 1409)
			cAuxC := U_FZ_INVERT_CFOP(cAuxC, "E")

			aRetCfop := oMotorRegras:ProcessaRegras(aPrd[nI], cAuxC, "")

			If Len(AllTrim(aRetCfop[1])) == 3 .And. Len(AllTrim(aRetCfop[2])) >= 4
				aPrd[nI]['cod_ProdutoCFOP'] := PadR(aRetCfop[2], TamSx3("D1_CF")[1])
				aPrd[nI]['_TES_CACHE']      := PadR(aRetCfop[1], TamSx3("D1_TES")[1])
			Else
				aPrd[nI]['cod_ProdutoCFOP'] := PadR(aRetCfop[1], TamSx3("D1_CF")[1])
				aPrd[nI]['_TES_CACHE']      := PadR(aRetCfop[2], TamSx3("D1_TES")[1])
			EndIf

			If Empty(AllTrim(aPrd[nI]['cod_ProdutoCFOP']))
				aPrd[nI]['cod_ProdutoCFOP'] := PadR(cAuxC, TamSx3("D1_CF")[1])
			EndIf

			If Empty(AllTrim(aPrd[nI]['_TES_CACHE']))
				cQryAux := "SELECT F4_CODIGO FROM " + RetSqlName("SF4") + " WHERE F4_CF='" + PadR(AllTrim(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("F4_CF")[1]) + "' AND F4_ESTOQUE='S' AND F4_MSBLQL <> '1' AND D_E_L_E_T_=' '"
				cAliAux := GetNextAlias()
				MpSysOpenQuery(cQryAux, cAliAux)
				If (cAliAux)->(!Eof())
					aPrd[nI]['_TES_CACHE'] := (cAliAux)->F4_CODIGO
				EndIf
				(cAliAux)->(DbCloseArea())
			EndIf

			If Empty(AllTrim(aPrd[nI]['_TES_CACHE']))
				lOkTes  := .F.
				cMsgTes := "TES nao localizado no cadastro (SF4) para o CFOP " + AllTrim(aPrd[nI]['cod_ProdutoCFOP']) + " exigindo Atualiza Estoque = 'S'."
				Exit
			EndIf
		Next nI

		If lOkTes
			// 4. Chama o motor de Entrada
			aRet := U_FZ_PRON_X(aPrd, oHead, cForn, cLoja, cDoc, cSer, "", "SA2", aEmpDest[2], 0, cCondSafe,lIsTransf)
		Else
			aRet := {.F., cMsgTes}
		EndIf
	EndIf

	PutMv("MV_PCNFE", cOldPcNfe)

	// 5. Retorna ao Ambiente Original da API
	//RpcClearEnv()
	//RpcSetEnv(cEmpAtu, cFilAtu, Nil, Nil, "FAT")
	cFilAnt := cFilAtu

Return aRet

// ==========================================================================
// VENDAS (SAIDAS) - MOTOR DIRETO MANFS2NFS (SA1 E SA2 DINAMICOS E TRANSFERENCIA)
// ==========================================================================
User Function FZ_PROS_X(aPrd, oHead, cCli, cLoja, cLeg, cSer, cFil, cTab, lIsTransf, cNF, cSerNF, cLegT, cCond)
	Local aRet       := {.F.,""}
	Local cNfGerada  := ""
	Local aCabs      := {}
	Local aItens     := {}
	Local aStruSF2   := SF2->(DbStruct())
	Local aStruSD2   := SD2->(DbStruct())
	Local nX         := 0
	Local nI         := 0
	Local nPos       := 0
	Local aDocOri    := {}
	Local dEmissao   := U_FZ_DATA_X(U_FZ_STR_X(oHead, 'dta_Emissao'))
	Local cDocPad    := PadL(AllTrim(cValToChar(cNF)), TamSx3("F2_DOC")[1], "0")
	Local cSerPad    := PadR(AllTrim(cValToChar(cSer)), TamSx3("F2_SERIE")[1], " ")
	Local cTipoOper  := ""
	Local cCustItm   := ""
	Local cEstCli    := U_FZ_GETEST(cTab, cCli, cLoja)
	Local cUmDB      := ""
	Local cLocDB     := ""
	Local cModDoc    := U_FZ_STR_X(oHead, 'cod_Mod')
	Local cEspecie   := ""
	Local cNotaOri
	Local cSerieOri
	Local cItemOri
	Local lDevol := .T.

	Local bFiscalSF2 := {|| .T.}
	Local bFiscalSD2 := {|| .T.}

	Local nF2FILIAL, nF2TIPO, nF2DOC, nF2SERIE, nF2EMISSAO, nF2CLIENTE, nF2LOJA, nF2COND, nF2ESPECIE, nF2EST, nF2FRETE
	Local nD2FILIAL, nD2DOC, nD2SERIE, nD2CLIENTE, nD2LOJA, nD2TIPO, nD2COD, nD2QUANT, nD2PRCVEN, nD2TOTAL, nD2TES, nD2CF, nD2CC, nD2ITEM, nD2UM, nD2LOCAL, nD2DESCON, nD2FRETE

	Local nQtdCalc   := 0
	Local nPrcCalc   := 0
	Local nDescUnit  := 0
	Local nDescTotal := 0
	Local nTamItemOri:= TamSx3("D2_ITEMORI")[1]
	Local nTamSerie  := TamSx3("D2_SERIORI")[1]
	Local cCnpjU
	Local aEmpFil
	Local nValFrete := U_FZ_VAL_X(oHead, 'vlr_Frete')
	Local nFreteItem
	Local cCnpjCli  := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "des_DestDocumento", "des_DestDocumento"))

	Private lMsErroAuto := .F.

	cCnpjU  := U_FZ_LIMPA_X(U_FZ_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
	aEmpFil := FATPIEMP(cCnpjU)

	If Len(aEmpFil) > 0
		If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
			//RPCClearEnv()
			//RpcSetEnv(aEmpFil[1], aEmpFil[2])
			cFilAnt := aEmpFil[2]
		EndIf
	Endif

	If ALLTRIM(cModDoc) == "55"
		cEspecie := "SPED"
	Elseif ALLTRIM(cModDoc) == '65'
		cEspecie := "NFCE"
	ELSE
		cEspecie := "NFE"
	EndIf

	cTipoOper := IIF(Alltrim(cTab) == 'SA2', 'D','N')



	If lIsTransf
		DbSelectArea("SA1")
		SA1->(DbSetOrder(3))
		If SA1->(DbSeek(xFilial("SA1") + cCnpjCli))
			cCli  := SA1->A1_COD
			cLoja := SA1->A1_LOJA
		Endif
		cTipoOper := 'N'
	Endif

	dDataBase := dEmissao

	nF2FILIAL  := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_FILIAL"})
	nF2TIPO    := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_TIPO"})
	nF2DOC     := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_DOC"})
	nF2SERIE   := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_SERIE"})
	nF2EMISSAO := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_EMISSAO"})
	nF2CLIENTE := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_CLIENTE"})
	nF2LOJA    := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_LOJA"})
	nF2COND    := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_COND"})
	nF2ESPECIE := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_ESPECIE"})
	nF2EST     := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_EST"})
	nF2FRETE   := Ascan(aStruSF2,{|x| AllTrim(x[1]) == "F2_FRETE"})

	nD2FILIAL  := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_FILIAL"})
	nD2DOC     := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_DOC"})
	nD2SERIE   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_SERIE"})
	nD2CLIENTE := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_CLIENTE"})
	nD2LOJA    := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_LOJA"})
	nD2TIPO    := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_TIPO"})
	nD2ITEM    := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_ITEM"})
	nD2COD     := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_COD"})
	nD2QUANT   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_QUANT"})
	nD2PRCVEN  := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_PRCVEN"})
	nD2TOTAL   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_TOTAL"})
	nD2TES     := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_TES"})
	nD2CF      := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_CF"})
	nD2CC      := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_CCUSTO"})
	nD2UM      := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_UM"})
	nD2LOCAL   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_LOCAL"})
	nD2DESCON  := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_DESCON"})
	nD2NFORI   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_NFORI"})
	nD2SERORI  := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_SERIORI"})
	nD2ITORI   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_ITEMORI"})
	nD2FRETE   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_VALFRE"})

	For nI := 1 To Len(aStruSF2)
		If aStruSF2[nI][2] == "N"
			Aadd(aCabs, 0)
		ElseIf aStruSF2[nI][2] == "D"
			Aadd(aCabs, CToD(""))
		ElseIf aStruSF2[nI][2] == "L"
			Aadd(aCabs, .F.)
		Else
			Aadd(aCabs, "")
		EndIf
	Next nI

	If nF2FILIAL > 0  ; aCabs[nF2FILIAL]  := xFilial("SF2") ; EndIf
		If nF2DOC > 0     ; aCabs[nF2DOC]     := cDocPad ; EndIf
			If nF2SERIE > 0   ; aCabs[nF2SERIE]   := cSerPad ; EndIf
				If nF2EMISSAO > 0 ; aCabs[nF2EMISSAO] := dEmissao ; EndIf
					If nF2CLIENTE > 0 ; aCabs[nF2CLIENTE] := cCli ; EndIf
						If nF2LOJA > 0    ; aCabs[nF2LOJA]    := cLoja ; EndIf
							If nF2FRETE > 0    ; aCabs[nF2FRETE]    := nValFrete ; EndIf
								If nF2TIPO > 0    ; aCabs[nF2TIPO]    := cTipoOper ; EndIf
									If nF2COND > 0    ; aCabs[nF2COND]    := cCond ; EndIf
										If nF2ESPECIE > 0 ; aCabs[nF2ESPECIE] := PadR(cEspecie, TamSx3("F2_ESPECIE")[1]) ; EndIf
											If nF2EST > 0     ; aCabs[nF2EST]     := PadR(cEstCli, TamSx3("F2_EST")[1]) ; EndIf

												For nI := 1 To Len(aPrd)
													Aadd(aItens, Array(Len(aStruSD2)))
													nPos := Len(aItens)

													For nX := 1 To Len(aStruSD2)
														If aStruSD2[nX][2] $ "C/M"
															aItens[nPos, nX] := ""
														ElseIf aStruSD2[nX][2] == "D"
															aItens[nPos, nX] := CToD("")
														ElseIf aStruSD2[nX][2] == "N"
															aItens[nPos, nX] := 0
														ElseIf aStruSD2[nX][2] == "L"
															aItens[nPos, nX] := .F.
														EndIf
													Next nX

													cCustItm := U_FZ_STR_X(aPrd[nI], 'cod_CentroCusto')
													If Empty(cCustItm)
														cCustItm := U_FZ_CC_X(aPrd[nI]['cod_Produto'])
													EndIf

													cUmDB := Posicione("SB1", 1, xFilial("SB1") + PadR(aPrd[nI]['cod_Produto'], TamSx3("B1_COD")[1]), "B1_UM")
													cLocDB := Posicione("SB1", 1, xFilial("SB1") + PadR(aPrd[nI]['cod_Produto'], TamSx3("B1_COD")[1]), "B1_LOCPAD")
													If Empty(cUmDB) ; cUmDB := "UN" ; EndIf
														If Empty(cLocDB) ; cLocDB := "01" ; EndIf

															nQtdCalc   := Max(U_FZ_VAL_X(aPrd[nI], 'qtd_Produto'), 1)
															nPrcCalc   := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario')
															nDescUnit  := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario')
															nDescTotal := Round(nQtdCalc * nDescUnit, 2)
															nFreteItem := U_FZ_VAL_X(aPrd[nI], 'vlr_ProdutoFrete')

															cNotaOri := PadL(ALLTRIM(U_FZ_STR_X(aPrd[nI], 'num_NFOrigem')), 9, '0')
															cSerieOri := U_FZ_STR_X(aPrd[nI], 'cod_SerieOrigem')
															cItemOri := U_FZ_STR_X(aPrd[nI], 'num_ProdutoSequencialOrigem')
															cChaveOri := U_FZ_STR_X(aPrd[nI], 'cod_ChaveNFeOrigem')

															If nD2FILIAL > 0  ; aItens[nPos, nD2FILIAL] := xFilial("SD2") ; EndIf
																If nD2DOC > 0     ; aItens[nPos, nD2DOC]    := cDocPad ; EndIf
																	If nD2SERIE > 0   ; aItens[nPos, nD2SERIE]  := cSerPad ; EndIf
																		If nD2CLIENTE > 0 ; aItens[nPos, nD2CLIENTE]:= cCli ; EndIf
																			If nD2LOJA > 0    ; aItens[nPos, nD2LOJA]   := cLoja ; EndIf
																				If nD2TIPO > 0    ; aItens[nPos, nD2TIPO]   := cTipoOper ; EndIf
																					If nD2ITEM > 0    ; aItens[nPos, nD2ITEM]   := PadL(cValToChar(nI), TamSx3("D2_ITEM")[1], "0") ; EndIf
																						If nD2COD > 0     ; aItens[nPos, nD2COD]    := PadR(aPrd[nI]['cod_Produto'], TamSx3("D2_COD")[1]) ; EndIf

																							IF !Empty(cNotaOri) .AND. cTipoOper == 'D'
																								IF lDevol
																									lDevol := FZ_VALID_DEV(cChaveOri,cNotaOri,'C')
																								Endif
																								If nD2NFORI > 0   ; aItens[nPos, nD2NFORI]  := cNotaOri  ; EndIf
																									If nD2SERORI > 0  ; aItens[nPos, nD2SERORI] := PADR(ALLTRIM(cSerieOri), nTamSerie, '') ; EndIf
																										If nD2ITORI > 0   ; aItens[nPos, nD2ITORI]  := PadL(ALLTRIM(cItemOri), nTamItemOri, '0')  ; EndIf
																										ENDIF

																										If nD2QUANT > 0   ; aItens[nPos, nD2QUANT]  := nQtdCalc ; EndIf
																											If nD2PRCVEN > 0  ; aItens[nPos, nD2PRCVEN] := nPrcCalc ; EndIf
																												If nD2FRETE > 0  ; aItens[nPos, nD2FRETE] := nFreteItem ; EndIf
																													If nD2TOTAL > 0   ; aItens[nPos, nD2TOTAL]  := Round(nQtdCalc * nPrcCalc, 2) ; EndIf
																														If nD2DESCON > 0 .And. nDescTotal > 0 ; aItens[nPos, nD2DESCON] := nDescTotal ; EndIf

																															If nD2TES > 0     ; aItens[nPos, nD2TES]    := PadR(aPrd[nI]['_TES_CACHE'], TamSx3("D2_TES")[1]) ; EndIf
																																If nD2CF > 0      ; aItens[nPos, nD2CF]     := PadR(aPrd[nI]['cod_ProdutoCFOP'], TamSx3("D2_CF")[1]) ; EndIf
																																	If nD2CC > 0      ; aItens[nPos, nD2CC]     := PadR(cCustItm, TamSx3("D2_CCUSTO")[1]) ; EndIf
																																		If nD2UM > 0      ; aItens[nPos, nD2UM]     := PadR(cUmDB, TamSx3("D2_UM")[1]) ; EndIf
																																			If nD2LOCAL > 0   ; aItens[nPos, nD2LOCAL]  := PadR(cLocDB, TamSx3("D2_LOCAL")[1]) ; EndIf

																																				AADD(aDocOri,0)
																																			Next nI
																																			If cTipoOper == 'D'
																																				If lDevol
																																					cNfGerada := MaNfs2Nfs("", "", cCli, cLoja, cSerPad, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, aDocOri, aItens, aCabs, .T., bFiscalSF2, bFiscalSD2, NIL, cDocPad)
																																				Else
																																					aRet := {.F., "(MaNfs2Nfs) Nota de origem não existe na SF1. Favor verificar.",.T.}
																																				Endif
																																			ELSE
																																				cNfGerada := MaNfs2Nfs("", "", "", "", cSerPad, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, aDocOri, aItens, aCabs, .T., bFiscalSF2, bFiscalSD2, NIL, cDocPad)
																																			ENDIF
																																			If !Empty(cNfGerada)
																																				JSON_VENDA(cNfGerada, cSerPad, cCli, cLoja, aPrd, oHead, cTab)
																																				FZ_GER_E1(cNfGerada, cSerPad, cCli, cLoja, aPrd, oHead, cTab,SE1->(RECNO()))
																																				aRet := {.T., cNfGerada}
																																			Else
																																				If cTipoOper <> 'D'
																																					aRet := {.F., "Erro MaNfs2Nfs",.F.}
																																				Endif
																																			EndIf
																																			Return aRet

Static Function RetOpera(cOper,cCST)

	Local cNewSX5 := GetNextAlias()
	Local cDescri := cOper + Space(1) + cCST
	Local nCount := 0
	Local cRet := ''
	Local cCadOper

	BeginSQL Alias cNewSX5
    select
		SX5.X5_CHAVE
    from
        %table:SX5% SX5	                     
    where
		SX5.%notDel%
	AND SX5.X5_TABELA = 'DJ'
	AND RTRIM(SX5.X5_DESCRI) = %exp:(cDescri)%
	EndSQL

	(cNewSX5)->(dbGoTop())
	While ! (cNewSX5)->(Eof())
		if !Empty((cNewSX5)->X5_CHAVE)
			nCount++
			cRet := (cNewSX5)->X5_CHAVE
		Endif
		(cNewSX5)->(DbSkip())
	End
	(cNewSX5)->(DbCloseArea())

	if nCount = 0
		cNewSX5 := GetNextAlias()
		BeginSQL Alias cNewSX5
        SELECT MAX(SX5.X5_CHAVE) AS X5_CHAVE
        FROM
            %table:SX5% SX5
        WHERE
            SX5.%notDel%
        AND SX5.X5_TABELA = 'DJ'
        AND SX5.X5_CHAVE LIKE 'T%'
		EndSQL

		cCadOper := SOMA1(ALLTRIM((cNewSX5)->X5_CHAVE))
		DbSelectArea("SX5")
		RecLock('SX5',.T.)
		SX5->X5_TABELA := 'DJ'
		SX5->X5_CHAVE := cCadOper
		SX5->X5_DESCRI := cDescri
		SX5->X5_DESCSPA := cDescri
		SX5->X5_DESCENG := cDescri
		SX5->(MsUnlock())
		SX5->(DbCloseArea())
		cRet := cCadOper
	Endif
Return cRet

Static Function FZ_GER_E2(cDoc, cSer, cForn, cLoja, aPrd, oHead, cTab, nRecno)

	Local cQryAux
	Local aParcJson := {}
	Local xParcVal  := {}
	Local cNumP
	Local dVencP
	Local nVlrP
	Local cNaturez
	Local cCusto
	Local cEvento
	Local nX
	Local cHist

	DbSelectArea("SE2")
	SE2->(DbGoTo(nRecno))

	cNaturez := SE2->E2_NATUREZ
	cCusto   := SE2->E2_CCUSTO
	Evento   := SE2->E2_XEVENTO
	cHist    := SE2->E2_HIST

	If oHead:HasProperty('pagamentos')
		xParcVal := oHead['pagamentos']
		If ValType(xParcVal) == "A"
			aParcJson := xParcVal
		EndIf
	EndIf

	If Len(aParcJson) > 0
		cQryAux := "UPDATE " + RetSqlName("SE2") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE E2_NUM = '" + cDoc + "' AND E2_PREFIXO = '" + cSer + "' AND E2_FORNECE = '" + cForn + "' AND E2_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
		TCSqlExec(cQryAux)
		For nX := 1 To Len(aParcJson)
			oParcItem := aParcJson[nX]
			cNumP := cValToChar(U_FZ_VAL_X(oParcItem, 'num_Parcela'))
			dVencP := U_FZ_DATA_X(U_FZ_STR_X(oParcItem, 'dta_ParcelaVencimento'))
			nVlrP := U_FZ_VAL_X(oParcItem, 'vlr_Parcela')

			If Empty(cNumP) .Or. cNumP == "0"
				cNumP := cValToChar(nX)
			EndIf

			RecLock("SE2", .T.)
			SE2->E2_FILIAL  := xFilial("SE2")
			SE2->E2_PREFIXO := cSer
			SE2->E2_NUM     := cDoc
			SE2->E2_PARCELA := cNumP
			SE2->E2_TIPO    := 'NF'
			SE2->E2_NATUREZ := cNaturez
			SE2->E2_FORNECE := cForn
			SE2->E2_LOJA    := cLoja
			SE2->E2_EMISSAO := SF1->F1_EMISSAO
			SE2->E2_EMIS1   := SF1->F1_DTDIGIT
			SE2->E2_VENCTO  := dVencP
			SE2->E2_VENCREA := dVencP
			SE2->E2_VALOR   := nVlrP
			SE2->E2_VALLIQ  := nVlrP
			SE2->E2_SALDO   := nVlrP
			SE2->E2_VLCRUZ  := nVlrP
			SE2->E2_MOEDA   := 1
			SE2->E2_ORIGEM  := 'MATA100'
			SE2->E2_FLUXO   := 'S'
			SE2->E2_HIST    := cHist
			SE2->E2_FILORIG := xFilial("SE2")
			SE2->E2_FORBCO  := Posicione('SA2', 1, FWxFilial('SA2') + SE2->E2_FORNECE + SE2->E2_LOJA, 'A2_BANCO')
			SE2->E2_FORAGE  := Posicione('SA2', 1, FWxFilial('SA2') + SE2->E2_FORNECE + SE2->E2_LOJA, 'A2_AGENCIA')
			SE2->E2_FORCTA  := Posicione('SA2', 1, FWxFilial('SA2') + SE2->E2_FORNECE + SE2->E2_LOJA, 'A2_NUMCON')
			SE2->E2_CCUSTO  := cCusto
			SE2->(MsUnlock())
		Next nX
	EndIf
Return

Static Function FZ_GER_E1(cDoc, cSer, cCli, cLoja, aPrd, oHead, cTab, nRecno)

	Local cQryAux
	Local aParcJson := {}
	Local xParcVal  := {}
	Local cNumP
	Local dVencP
	Local nVlrP
	Local cNaturez
	Local cCusto
	Local cEvento
	Local cFormaTrat
	Local cBandeira
	Local cTransac
	Local cAutorizF
	Local nX
	Local cHist
	Local cParce := '01'
	Local cTipoTit
	Local cXTipo
	Local cFluxo

	DbSelectArea("SE1")
	SE1->(DbGoTo(nRecno))

	If !FWIsInCallStack("U_FATPI0801")

		cNaturez := oHead['cod_NaturezaFinanceira']
		cCusto   := oHead['itens'][1]['cod_CentroCusto']
		cEvento  := SE1->E1_XEVENTO
		cHist    := SE1->E1_HIST
		cXTipo   := oHead['des_TipoNF']

		If oHead:HasProperty('recebimentos')
			xParcVal := oHead['recebimentos']
			If ValType(xParcVal) == "A"
				aParcJson := xParcVal
			EndIf
		EndIf

		If Len(aParcJson) > 0
			cQryAux := "UPDATE " + RetSqlName("SE1") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE E1_NUM = '" + cDoc + "' AND E1_PREFIXO = '" + cSer + "' AND E1_CLIENTE = '" + cCli + "' AND E1_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
			TCSqlExec(cQryAux)
			For nX := 1 To Len(aParcJson)
				oParcItem := aParcJson[nX]
				cFormaPag   := U_FZ_STR_X(oParcItem, "des_FormaRecebimento")
				cFormaRec   := U_FZ_STR_X(oParcItem, 'des_FormaRecebimento')
				cBandeira   := U_FZ_STR_X(oParcItem, "des_Bandeira")
				cTransac    := U_FZ_STR_X(oParcItem, "num_Transacao")
				cAutorizF   := U_FZ_STR_X(oParcItem, "des_Autorizacao")
				cTipoTit    := U_FZ_STR_X(oParcItem, "des_FormaPag")
				cFormaRec := Upper(AllTrim(cFormaRec))
				cFluxo      := U_FZ_STR_X(oParcItem, "flg_FluxoCaixa")

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
				cNumP := cValToChar(U_FZ_VAL_X(oParcItem, 'num_Parcela'))
				dVencP := U_FZ_DATA_X(U_FZ_STR_X(oParcItem, 'dta_Vencimento'))
				nVlrP := U_FZ_VAL_X(oParcItem, 'vlr_Recebimento')

				If Empty(cNumP) .Or. cNumP == "0"
					cNumP := cValToChar(nX)
				EndIf

				RecLock("SE1", .T.)
				SE1->E1_FILIAL  := xFilial("SE1")
				SE1->E1_FILORIG := xFilial("SE1")
				SE1->E1_MSFIL   := xFilial("SE1")
				SE1->E1_PREFIXO := cSer
				SE1->E1_NUM     := cDoc
				SE1->E1_PARCELA := cParce
				SE1->E1_TIPO    := IIF(!Empty(cTipoTit),cTipoTit,'NF')
				SE1->E1_XTIPO   := 'NF'
				SE1->E1_NATUREZ := cNaturez
				SE1->E1_CLIENTE := cCli
				SE1->E1_LOJA    := cLoja
				SE1->E1_NOMCLI  := Posicione('SA1', 1, FWxFilial('SA1') + SE1->E1_CLIENTE + SE1->E1_LOJA, 'A1_NOME')
				SE1->E1_EMISSAO := SF2->F2_EMISSAO
				SE1->E1_EMIS1   := SF2->F2_EMISSAO
				SE1->E1_VENCTO  := dVencP
				SE1->E1_VENCREA := dVencP
				SE1->E1_VALOR   := nVlrP
				SE1->E1_VALLIQ  := nVlrP
				SE1->E1_SALDO   := nVlrP
				SE1->E1_VLCRUZ  := nVlrP
				SE1->E1_CCUSTO  := cCusto
				//SE1->E1_ORIGEM  := 'MATA460'
				SE1->E1_FLUXO   := cFluxo
				SE1->E1_HIST    := cHist
				SE1->E1_STATUS  := 'A'
				SE1->E1_SERIE   := cSer
				SE1->E1_CARTAO  := cBandeira
				SE1->E1_SITUACA := '0'
				SE1->E1_CARTAUT := cAutorizF
				SE1->E1_NSUTEF  := cTransac
				If AllTrim(cTipoTit) == 'CC' .OR. AllTrim(cTipoTit) == 'CD'
					SE1->E1_FORMAPG := cTipoTit
				else
					SE1->E1_FORMAPG := cFormaTrat
				Endif
				SE1->E1_XEVENTO := cEvento
				SE1->(MsUnlock())
				cParce := SOMA1(cParce)
			Next nX
		EndIf
	Endif
Return

Static Function FZ_VALID_DEV(cChave,cNota,cTipo)

	Local cNewSF1 := GetNextAlias()
	Local cNewSF2 := GetNextAlias()
	Local lRet    := .F.

	If cTipo == 'C'

		BeginSQL Alias cNewSF1
        select
			SF1.F1_DOC
        from
            %table:SF1% SF1	                     
        where
			SF1.%notDel%
			AND TRIM(SF1.F1_CHVNFE) = %exp:(ALLTRIM(cChave))% 
		EndSQL

		(cNewSF1)->(dbGoTop())

		While !(cNewSF1)->(Eof())
			IF ALLTRIM((cNewSF1)->F1_DOC) == ALLTRIM(cNota)
				lRet := .T.
			Endif
			(cNewSF1)->(DbSkip())
		End

	ELSEIF cTipo == 'V'

		BeginSQL Alias cNewSF2
        select
			SF2.F2_DOC
        from
            %table:SF2% SF2	                     
        where
			SF2.%notDel%
			AND TRIM(SF2.F2_CHVNFE) = %exp:(ALLTRIM(cChave))% 
		EndSQL

		(cNewSF2)->(dbGoTop())

		While !(cNewSF2)->(Eof())
			IF ALLTRIM((cNewSF2)->F2_DOC) == ALLTRIM(cNota)
				lRet := .T.
			Endif
			(cNewSF2)->(DbSkip())
		End

	ENDIF


Return lRet

/*/{Protheus.doc} FATPI0804
Fonte: FATPI08 - Antonio Nunes O Jr - 23/04/2026
Descritivo: Recupera Empresa e Filial da SM0 via CNPJ formatado. 
/*/
Static Function FATPIEMP(c)
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

Static Function BuscaCad(cCad,nOpc)

	Local lRet := .F.
	Local nTam := IIF(nOpc = 1,TamSx3("F0G_CEST")[1],TamSx3("YD_TEC")[1])

	cCad := PADR(ALLTRIM(cCad),nTam,'')

	If nOpc = 1
		DbSelectArea('F0G')
		F0G->(DbSetOrder(1))
		If F0G->(DbSeek(xFilial("F0G") + cCad))
			lRet := .T.
		Endif
	Elseif nOpc = 2
		DbSelectArea('SYD')
		SYD->(DbSetOrder(1))
		If SYD->(DbSeek(xFilial("SYD") + cCad))
			lRet := .T.
		Endif
	Endif

Return lRet
