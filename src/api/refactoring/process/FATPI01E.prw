#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

// Motor de entrada (compra) - gera pedido de compra (MATA120) e nota fiscal de entrada (MATA103)

// Gera pedido de compra (SC7) via MATA120 e ajusta valores fiscais do item por SQL
User Function PI_GERAPC_X(aPrd, oHead, cForn, cLoja, cLeg, aEmp, cTab, cFil, cTpC, cCnd)
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
	Local cOper    := ""

	Local aTamQtd  := TamSx3("C7_QUANT")
	Local aTamPrc  := TamSx3("C7_PRECO")
	Local nTamQtd  := IIf(ValType(aTamQtd) == "A" .And. Len(aTamQtd) >= 2, aTamQtd[2], 4)
	Local nTamPrc  := IIf(ValType(aTamPrc) == "A" .And. Len(aTamPrc) >= 2, aTamPrc[2], 4)

	Private lMsErroAuto := .F.
	Private lAutoErrNoFile := .T.
	Private __cBatch := "1"

	cCnpjU  := U_PI_LIMPA_X(U_PI_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
	aEmpFil := U_FATPIEMP(cCnpjU)

	if Len(aEmpFil) > 0
		If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
			RPCClearEnv()
			RpcSetEnv(aEmpFil[1], aEmpFil[2])
		EndIf
	Endif

	cCnd := PadR(cCnd, 3)
	dEmissao := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Emissao'))

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
		ConfirmSx8() // confirma (queima) o numero ja usado fisicamente, senao o SXE nunca aprende e o gap so cresce
		cPC := GetSxeNum("SC7", "C7_NUM")
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
		cLoc := U_PI_LOCAL_X(cPrd)
		cCC  := U_PI_STR_X(aPrd[nI], 'cod_CentroCusto')
		cCta := U_PI_CONTA_X(cPrd)

		If Empty(cCC)
			cCC := U_PI_CCUSTO_X(cPrd)
		EndIf

		DbSelectArea("SB1")
		SB1->(DbSetOrder(1))
		SB1->(DbSeek(xFilial("SB1") + cPrd))
		cUm := SB1->B1_UM

		If Empty(cCta)
			cCta := SuperGetMv("MV_XCCPAD", .F., "11100901")
		EndIf

		nQtd := Round(U_PI_VAL_X(aPrd[nI], 'qtd_Produto'), nTamQtd)
		nPrc := Round(U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario',), nTamPrc)
		nDespesa := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoOutros')


		nPrcArr := nPrc
		If nPrcArr <= 0
			nPrcArr := 0.0001
		EndIf
		If nQtd <= 0
			nQtd := 1
		EndIf

		cItemSeq := PadL(cValToChar(nI), TamSx3("C7_ITEM")[1], "0")
		aPrd[nI]['num_Sequencial'] := cItemSeq

		nDescItm := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario') * nQtd
		cOper := ALLTRIM(U_RetOpera(aPrd[nI]['des_ProdutoImposto'],aPrd[nI]['cod_ProdutoCST']))

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

	aEx := U_PI_EXE120_X(aCab, aIt)
	If aEx[1]
/*		For nI := 1 To Len(aPrd)
			cItemSql := aPrd[nI]['num_Sequencial']

			nQtd     := Round(U_PI_VAL_X(aPrd[nI], 'qtd_Produto'), nTamQtd)
			nPrc     := Round(U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), nTamPrc)
			nDescItm := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario') * nQtd
			nTotItem := Round((nQtd * nPrc) - nDescItm, 2)

			nVlrIcm  := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoICMS')
			nBasIcm  := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoICMSBaseCalculo')
			nPctIcm  := U_PI_VAL_X(aPrd[nI], 'pct_ProdutoICMS')
			nVlrIpi  := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoIPI')
			nPctIpi  := U_PI_VAL_X(aPrd[nI], 'pct_ProdutoIPI')
			nVlrST   := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoICMSST')
			nBasST   := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoICMSSTBaseCalculo')
			nVlrPis  := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoPIS')
			nVlrCof  := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoConfins', 'vlr_ProdutoCOFINS')

			cQryUpd := "UPDATE " + RetSqlName("SC7") + " SET "
			cQryUpd += "C7_CONAPRO = 'L', C7_RESIDUO = '', "
			cQryUpd += "C7_PRECO = " + StrTran(cValToChar(nPrc), ",", ".") + ", "
			cQryUpd += "C7_TOTAL = " + StrTran(cValToChar(nTotItem), ",", ".") + ", "
			cQryUpd += "C7_VLDESC = " + StrTran(cValToChar(nDescItm), ",", ".") + ", "
			cQryUpd += "C7_VALICM = " + StrTran(cValToChar(nVlrIcm), ",", ".")  + ", "
			cQryUpd += "C7_BASEICM = " + StrTran(cValToChar(nBasIcm), ",", ".")  + ", "
			cQryUpd += "C7_PICM = " + StrTran(cValToChar(nPctIcm), ",", ".")  + ", "
			cQryUpd += "C7_VALIPI = " + StrTran(cValToChar(nVlrIpi), ",", ".")  + ", "
			cQryUpd += "C7_IPI = " + StrTran(cValToChar(nPctIpi), ",", ".")  + ", "
			cQryUpd += "C7_ICMSRET = " + StrTran(cValToChar(nVlrST), ",", ".")   + ", "
//			cQryUpd += "C7_BRICMS = " + StrTran(cValToChar(nBasST), ",", ".")   + ", "
			cQryUpd += "C7_VALPIS = " + StrTran(cValToChar(nVlrPis), ",", ".")  + ", "
			cQryUpd += "C7_VALCOF = " + StrTran(cValToChar(nVlrCof), ",", ".")  + " "
			cQryUpd += "WHERE C7_NUM = '" + cPC + "' AND C7_ITEM = '" + cItemSql + "' AND C7_FILIAL = '" + xFilial("SC7") + "' AND D_E_L_E_T_ = ' '"
			TCSqlExec(cQryUpd)
		Next nI*/
		aRet := {.T., "Ok", cPC}
	Else
		aRet := {.F., aEx[2], ""}
	EndIf
Return aRet


// Gera a nota fiscal de entrada (SF1/SD1) via MATA103, vincula ao pedido de compra e ajusta titulos (SE2)
User Function PI_GERANF_X(aPrd, oHead, cForn, cLoja, cDoc, cSer, cPC, cTab, cFil, nAval, cCond, lIsTransf)
	Local aRet       := {.F.,""}
	Local aCab       := {}
	Local aIt        := {}
	Local aLin       := {}
	Local nI         := 0
	Local cTE        := ""
	Local nQtd       := 0
	Local nPrc       := 0
	Local nDescItm   := 0
	Local nDespesa   := 0
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

	Local nVlrFrete  := U_PI_VAL_X(oHead, 'vlr_Frete')
	Local nValFrete  := Round(U_PI_VAL_X(oHead, 'vlr_Frete'), 4)
	Local nValFreteUnit := 0
	Local nVlrSeg    := U_PI_VAL_X(oHead, 'vlr_Seguro')
	Local nVlrDesc   := U_PI_VAL_X(oHead, 'vlr_Desconto')
	Local nVlrOutr   := U_PI_VAL_X(oHead, 'vlr_Outros')
	Local nVlrMercV  := 0
	Local nVlrBrutV  := 0
	Local cDocSql    := PadL(AllTrim(cValToChar(cDoc)), TamSx3("F1_DOC")[1], "0")
	Local cSerSql    := PadR(AllTrim(cValToChar(cSer)), TamSx3("F1_SERIE")[1], " ")
	Local cFornSql   := PadR(AllTrim(cValToChar(cForn)), TamSx3("F1_FORNECE")[1], " ")
	Local cLojaSql   := PadR(AllTrim(cValToChar(cLoja)), TamSx3("F1_LOJA")[1], " ")
	Local cItemSql   := ""
	Local cQryRec    := ""
	Local cAliRec    := ""
	Local cCondReal  := PadR(U_PI_COND1_X(), 3)
	Local cHistPad   := ""
	Local cNatReal   := ""
	Local cNomeFin   := ""
	Local cNomeFor   := ""
	Local nRecTarget := 0
	Local cModDoc    := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')
	Local cEspecie   := ""
	Local cOper      := ''
	Local nTamNat    := TamSx3("E2_NATUREZ")[1]
	Local aEmpFil
	Local cCnpjU
	Local dDataDigit

	Local cEvtMod    := U_PI_STR_X(oHead, "cod_EventoModalidade", "cod_Evento")
	Local cNatJson   := U_PI_STR_X(oHead, "cod_NaturezaFinanceira")
	Local cTransacao := U_PI_STR_X(oHead, "num_Transacao")

	Default lIsTransf := .F.

	If lIsTransf
		cCnpjU := U_PI_LIMPA_X(U_PI_STR_X(oHead, "des_DestDocumento", "des_DestDocumento"))
	Else
		cCnpjU := U_PI_LIMPA_X(U_PI_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
	EndIf
	aEmpFil := U_FATPIEMP(cCnpjU)

	ConOut("[DEBUG-TRANSF] PI_GERANF_X entrada | cCnpjU=" + cCnpjU + " | aEmpFil=" + IIF(Len(aEmpFil)>=2, aEmpFil[1]+"/"+aEmpFil[2], "VAZIO") + " | ambiente atual=" + cEmpAnt + "/" + cFilAnt)

	if Len(aEmpFil) > 0
		If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
			ConOut("[DEBUG-TRANSF] PI_GERANF_X VAI TROCAR ambiente de " + cEmpAnt + "/" + cFilAnt + " para " + aEmpFil[1] + "/" + aEmpFil[2])
			RPCClearEnv()
			RpcSetEnv(aEmpFil[1], aEmpFil[2])
		Else
			ConOut("[DEBUG-TRANSF] PI_GERANF_X NAO trocou - ambiente ja bate")
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

	dEmissao := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Emissao'))
	dDataDigit := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Conferencia'))
	cUFEntity := PadR(U_PI_UF_X("SA2", cForn, cLoja), 2)
	cCond := PadR(cValToChar(cCond), 3)

	dDataBase := dDataDigit

	cNomeFor := U_PI_STR_X(oHead, 'des_DestNome')
	If Empty(cNomeFor)
		cNomeFor := U_PI_STR_X(oHead, 'des_NomeCliente', 'nome')
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
			cNumP := cValToChar(U_PI_VAL_X(oParcItem, 'num_Parcela'))
			dVencP := U_PI_DATA_X(U_PI_STR_X(oParcItem, 'dta_ParcelaVencimento'))
			nVlrP := U_PI_VAL_X(oParcItem, 'vlr_Parcela')

			If Empty(cNumP) .Or. cNumP == "0"
				cNumP := "1"
			EndIf

			If Empty(dVencP)
				dVencP := dEmissao
			EndIf

			AAdd(aParcLegacy, {PadL(cNumP, TamSx3("E2_PARCELA")[1], "0"), dVencP, nVlrP})
		Next nX
	EndIf

	For nI := 1 To Len(aPrd)
		nTotNF += Round(U_PI_VAL_X(aPrd[nI], 'qtd_Produto') * U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), 2)
	Next nI

	nVlrMercV := nTotNF
	nVlrBrutV := nTotNF + nVlrFrete + nVlrSeg + nVlrOutr - nVlrDesc

	If Len(aParcLegacy) == 0 .And. nVlrBrutV > 0
		AAdd(aParcLegacy, {"1", dEmissao, nVlrBrutV})
	EndIf

	If !Empty(cNatJson)
		cNatReal := PadR(cNatJson, TamSx3("E2_NATUREZ")[1])
	Else
		cNatReal := PadR(U_PI_NAT_X(cFornSql, cLojaSql, oHead), TamSx3("E2_NATUREZ")[1])
	EndIf

	AAdd(aCab, {"F1_DOC", PadR(cValToChar(cDoc), 9), Nil})
	AAdd(aCab, {"F1_SERIE", PadR(cValToChar(cSer), 3), Nil})
	AAdd(aCab, {"F1_FORNECE", PadR(cValToChar(cForn), 6), Nil})
	AAdd(aCab, {"F1_LOJA", PadR(cValToChar(cLoja), 2), Nil})
	AAdd(aCab, {"F1_TIPO", "N", Nil})
	AAdd(aCab, {"F1_FORMUL", "N", Nil})
	AAdd(aCab, {"F1_EMISSAO", dEmissao, Nil})
	AAdd(aCab, {"F1_DTDIGIT", dDataDigit, Nil})
	AAdd(aCab, {"F1_ESPECIE", cEspecie, Nil})
	AAdd(aCab, {"F1_CHVNFE", U_PI_STR_X(oHead, 'cod_ChaveNFe'), Nil})
	AAdd(aCab, {"F1_COND", cCond, Nil})
	AAdd(aCab, {"F1_VALBRUT", nVlrBrutV, Nil})
	AAdd(aCab, {"F1_VALMERC", nVlrMercV, Nil})
	AAdd(aCab, {"F1_DESCONT", nVlrDesc, Nil})
	AAdd(aCab, {"F1_EST", cUFEntity, Nil})
	AAdd(aCab, {"F1_FRETE", nValFrete, Nil})
	AAdd(aCab, {"E2_NATUREZ", PADR(ALLTRIM(cNatReal),nTamNat,''), Nil})

	For nI := 1 To Len(aPrd)
		cTE := PadR(cValToChar(aPrd[nI]['_TES_CACHE']), 3)
		nQtd := Round(U_PI_VAL_X(aPrd[nI], 'qtd_Produto'), 4)

		If nQtd <= 0 ; nQtd := 1 ; EndIf

			nPrc := Round(U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), 4)
			nDescItm := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario') * nQtd
			nDespesa := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoOutros')
			nValFreteUnit := Round(U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoFrete'), 4)

			cProdKey := AllTrim(PadR(cValToChar(AllTrim(aPrd[nI]['cod_Produto'])), 30))
			cItemSeq := PadL(cValToChar(nI), TamSx3("D1_ITEM")[1], "0")
			cCta := PadR(cValToChar(U_PI_CONTA_X(cProdKey)), 20)
			cCC  := U_PI_STR_X(aPrd[nI], 'cod_CentroCusto')

			If Empty(cCC)
				cCC := U_PI_CCUSTO_X(cProdKey)
			EndIf
			cCC := PadR(cCC, TamSx3("D1_CC")[1])

			DbSelectArea("SB1")
			SB1->(DbSetOrder(1))
			SB1->(DbSeek(xFilial("SB1") + PadR(cProdKey, 30)))
			cUm := SB1->B1_UM
			cOper := U_RetOpera(aPrd[nI]['des_ProdutoImposto'],aPrd[nI]['cod_ProdutoCST'])

			aLin := {}
			AAdd(aLin, {"D1_FILIAL", xFilial("SD1"), Nil})
			AAdd(aLin, {"D1_ITEM", cItemSeq, Nil})
			AAdd(aLin, {"D1_COD", cProdKey, Nil})
			AAdd(aLin, {"D1_UM", cUm, Nil})
			AAdd(aLin, {"D1_QUANT", nQtd, Nil})
			AAdd(aLin, {"D1_VUNIT", nPrc, Nil})
			AAdd(aLin, {"D1_TOTAL", Round(nQtd * nPrc, 2), Nil})
			AAdd(aLin, {"D1_VALDESC", nDescItm, Nil})
			AAdd(aLin, {"D1_DESPESA", nDespesa, Nil})
			AAdd(aLin, {"D1_VALFRE", nValFreteUnit, Nil})
			AAdd(aLin, {"D1_TES", cTE, Nil})
			AAdd(aLin, {"D1_CONTA", cCta, Nil})
			AAdd(aLin, {"D1_CC", cCC, Nil})
			AAdd(aLin, {"D1_OPER", cOper, Nil})
			AAdd(aLin, {"D1_CF", PadR(cValToChar(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("D1_CF")[1]), Nil})
			AAdd(aLin, {"D1_FORNECE", PadR(cValToChar(cForn), 6), Nil})
			AAdd(aLin, {"D1_LOJA", PadR(cValToChar(cLoja), 2), Nil})
			AAdd(aLin, {"D1_LOCAL", PadR(cValToChar(U_PI_LOCAL_X(cProdKey)), 2), Nil})

			If !Empty(cPC)
				AAdd(aLin, {"D1_PEDIDO", cPC, Nil})
				AAdd(aLin, {"D1_ITEMPC", cItemSeq, Nil})
			EndIf

			AAdd(aIt, aLin)
		Next nI

		aEx := U_PI_EXE103_X(aCab, aIt, "N")

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
								SC7->C7_TOTAL := Round(U_PI_VAL_X(aPrd[nI], 'qtd_Produto') * U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), 2)
							EndIf
							If SC7->(FieldPos("C7_VALICM")) > 0
								SC7->C7_VALICM := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoICMS')
							EndIf
							If SC7->(FieldPos("C7_BASEICM")) > 0
								SC7->C7_BASEICM := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoICMSBaseCalculo')
							EndIf
							If SC7->(FieldPos("C7_PICM")) > 0
								SC7->C7_PICM := U_PI_VAL_X(aPrd[nI], 'pct_ProdutoICMS')
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
				cNatReal := PadR(U_PI_NAT_X(cFornSql, cLojaSql, oHead), TamSx3("E2_NATUREZ")[1])
			EndIf

			cHistPad := "API: Orig:" + U_PI_STR_X(oHead, "des_Origem") + " Aut:" + U_PI_STR_X(oHead, "des_Autorizacao") + " Trans:" + cTransacao

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

// Reforca via SQL direto no SF1/SD1/SE2 os campos que o MATA103 nao grava (impostos, historico, natureza)
User Function JSON_COMPRA(cDoc, cSer, cForn, cLoja, aPrd, oHead, cTab)
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
    Local cChaveNFe   := U_PI_STR_X(oHead, 'cod_ChaveNFe') 
    Local cModDoc     := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')
    Local cEspecie    := ""

    Local cTipoE2     := "NF "
    Local cHistPad    := "API: Entrada NF/RC"
    Local cNatJson    := U_PI_STR_X(oHead, "cod_NaturezaFinanceira")

    Local nVlrMercV   := U_PI_VAL_X(oHead, 'vlr_TotalProduto')
    Local nVlrBrutV   := U_PI_VAL_X(oHead, 'vlr_NotaFiscal')
    Local nDescTot    := U_PI_VAL_X(oHead, 'vlr_Desconto')
    Local nFreteTot   := U_PI_VAL_X(oHead, 'vlr_Frete')
    Local nSegTot     := U_PI_VAL_X(oHead, 'vlr_Seguro')
    Local nOutrTot    := U_PI_VAL_X(oHead, 'vlr_Outros')
    
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

    Local nVlrIcmN    := U_PI_VAL_X(oHead, 'vlr_ICMS')
    Local nBasIcmN    := U_PI_VAL_X(oHead, 'vlr_ICMSBaseCalculo')
    Local nVlrIpiN    := U_PI_VAL_X(oHead, 'vlr_IPI')
    Local nVlrPisN    := U_PI_VAL_X(oHead, 'vlr_PIS')
    Local nVlrCofN    := U_PI_VAL_X(oHead, 'vlr_COFINS')

    Local cDocPad     := PadL(AllTrim(cDocSql), nTamF1Doc, "0")
    Local cSerPad     := PadR(AllTrim(cSerSql), nTamF1Ser, " ")
    Local cFornPad    := PadR(AllTrim(cFornSql), nTamF1Forn, " ")
    Local cLojaPad    := PadR(AllTrim(cLojaSql), nTamF1Loja, " ")
    
    Local cCustoHead  := U_PI_STR_X(oHead, 'cod_CentroCusto')
    Local cCustoSD1   := ""
    
    Local cNatItm     := ""
    Local cCCItm      := ""
    Local nVlrTitulo  := 0
    Local cParcela    := ""

    Local nPicmItem   := 0
    Local nBicmItem   := 0
    Local nVicmItem   := 0
    Local nBicmStItem := 0
    Local nVicmStItem := 0
    Local nVicmDeson  := 0
    Local nPReducIcm  := 0
    Local nPReducSt   := 0

    cNatItm     := U_GET_REC_JSON(oHead, "cod_NaturezaFinanceira", "", "")
    cCCItm      := U_GET_REC_JSON(oHead, "cod_CentroCusto", "", "")
    nVlrTitulo  := U_GET_REC_JSON(oHead, "VLR", "", nVlrBrutV)

    If ValType(aPrd) == "A"
        If Len(aPrd) > 0
            If ValType(aPrd[1]) == "O" .Or. ValType(aPrd[1]) == "J"
                For nX := 1 To Len(aPrd) 
                    nQtdItm     := Max(U_PI_VAL_X(aPrd[nX], 'qtd_Produto'), 1) 
                    nVlrUniItm  := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoUnitario') 
                    
                    nDescItm    := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoDescontoUnitario') * nQtdItm 
                    
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
                cCustoHead := U_PI_STR_X(aPrd[1], 'cod_CentroCusto')
            EndIf
        EndIf
    EndIf

    If cModDoc == "55" .Or. cModDoc == "65"
        cEspecie := "SPED"
    Else
        cEspecie := "NFE"
    EndIf

    dEmiss := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Emissao'))

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

    If ValType(aPrd) == "A"
        For nX := 1 To Len(aPrd)
            If ValType(aPrd[nX]) == "O" .Or. ValType(aPrd[nX]) == "J"
                cTesItm    := PadR(cValToChar(aPrd[nX]['_TES_CACHE']), nTamD1Tes)
                cCfopItm   := PadR(U_PI_LIMPA_X(U_PI_STR_X(aPrd[nX], 'cod_ProdutoCFOP', 'cfop')), nTamD1Cf)
                cItemSql   := PadL(cValToChar(nX), nTamD1Item, "0")
                
                nQtdItm     := Max(U_PI_VAL_X(aPrd[nX], 'qtd_Produto'), 1)
                nVlrUniItm  := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoUnitario')
                
                nDescItm    := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoDescontoUnitario') * nQtdItm
                nVlrBrutItm := Round(nQtdItm * nVlrUniItm, 2)
                nVlrLiqItm  := Round(nVlrBrutItm - nDescItm, 2) 

                nPicmItem   := U_PI_VAL_X(aPrd[nX], 'pct_ProdutoICMS')
                nBicmItem   := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMSBaseCalculo')
                nVicmItem   := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMS')
                nBicmStItem := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMSSTBaseCalculo')
                nVicmStItem := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMSST')
                nVicmDeson  := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMSDesonerado')
                nPReducIcm  := U_PI_VAL_X(aPrd[nX], 'pct_ProdutoReducaoICMS')
                nPReducSt   := U_PI_VAL_X(aPrd[nX], 'pct_ProdutoReducaoICMSST')

                nPercDesc := 0
                If nVlrBrutItm > 0
                    nPercDesc := Round((nDescItm / nVlrBrutItm) * 100, 2)
                EndIf

                cCustoSD1  := U_PI_STR_X(aPrd[nX], 'cod_CentroCusto')
                If Empty(cCustoSD1) ; cCustoSD1 := cCustoHead ; EndIf

                cQryRec := "UPDATE " + RetSqlName("SD1") + " SET "
                cQryRec += "D1_CF = '" + cCfopItm + "', "
                
                If Len(TamSx3("D1_CC")) > 0
                    cQryRec += "D1_CC = '" + PadR(cCustoSD1, nTamD1CC) + "', "
                EndIf
                
                cQryRec += "D1_TES = '" + cTesItm + "', "
                cQryRec += "D1_VUNIT = " + StrTran(cValToChar(nVlrUniItm), ",", ".") + ", "
                cQryRec += "D1_TOTAL = " + StrTran(cValToChar(nVlrBrutItm), ",", ".") + ", " 
                cQryRec += "D1_VALDESC = " + StrTran(cValToChar(nDescItm), ",", ".") + ", "
                cQryRec += "D1_DESC = " + StrTran(cValToChar(nPercDesc), ",", ".")

                cQryRec += " WHERE D1_DOC='" + cDocPad + "' AND D1_SERIE='" + cSerPad + "' AND D1_FORNECE='" + cFornPad + "' AND D1_LOJA='" + cLojaPad + "' AND D1_ITEM='" + cItemSql + "' AND D_E_L_E_T_=' '"
                TCSqlExec(cQryRec)
            EndIf
        Next nX
    EndIf

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

// Recria as parcelas de um titulo (SE2) a partir do array de pagamentos do JSON
User Function PI_GER_E2(cDoc, cSer, cForn, cLoja, aPrd, oHead, cTab, nRecno)

	Local cQryAux
	Local aParcJson := {}
	Local xParcVal  := {}
	Local cNumP
	Local dVencP
	Local nVlrP
	Local cNaturez
	Local cCusto
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
			cNumP := cValToChar(U_PI_VAL_X(oParcItem, 'num_Parcela'))
			dVencP := U_PI_DATA_X(U_PI_STR_X(oParcItem, 'dta_ParcelaVencimento'))
			nVlrP := U_PI_VAL_X(oParcItem, 'vlr_Parcela')

			If Empty(cNumP) .Or. cNumP == "0"
				cNumP := "1"
			EndIf

			RecLock("SE2", .T.)
			SE2->E2_FILIAL  := xFilial("SE2")
			SE2->E2_PREFIXO := cSer
			SE2->E2_NUM     := cDoc
			SE2->E2_PARCELA := PadL(cNumP, TamSx3("E2_PARCELA")[1], "0")
			SE2->E2_TIPO    := 'NF'
			SE2->E2_NATUREZ := cNaturez
			SE2->E2_FORNECE := cForn
			SE2->E2_LOJA    := cLoja
			SE2->E2_EMISSAO := SF1->F1_EMISSAO
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

