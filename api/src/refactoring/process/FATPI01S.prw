#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

/*
+----------------------------------------------------------------------------+
| Autor: Antonio Nunes O Jr / Jose Carlos - Artiq                            |
| Data: 07/2026                                                              |
| Descritivo: FATPI01S - Motor de Saida (Vendas)                            |
|             PI_ROLLBACK_NF - Estorno de saida em caso de falha            |
|             GET_REC_JSON   - Extracao segura de recebimentos do JSON       |
|             JSON_VENDA     - Pos-gravacao fiscal/financeiro saida          |
|             FZ_GER_E1      - Geracao titulos a receber (SE1)              |
|             FATPI01NF      - Auto-entrada transferencia (Convenios)        |
|             PI_SAIDA_X      - Motor MaNfs2Nfs                              |
|             RetOpera       - Resolve operacao/CST para TES                 |
|             PI_LOJA_X       - Motor LOJA701 (NFCe via SIGALOJA)            |
+----------------------------------------------------------------------------+
*/

// [MIGRADO-DO-ENDPOINT] Jose Carlos - Artiq - 08/2026
// Promovida de Static para User Function (e renomeada de FZ_ para PI_,
// seguindo a convencao do projeto) - antes so era chamada de dentro do
// proprio FATPI01_V2 (mesmo lote de compilacao), sem precisar de U_. Agora
// o CONVENIOS+rollback migrou para o FATZZA01.prw (Job, lote de compilacao
// separado), que so enxerga funcoes globais via U_.
User Function PI_ROLLBACK_NF(cDoc, cSer, cCli, cLoja)
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
// [FIX-LOTE-COMPILACAO] Jose Carlos - Artiq - 08/2026
// Promovida de Static Function pra User Function - mesma classe de bug
// ja corrigida em RetOpera/FZ_VALID_DEV: era so visivel dentro de
// FATPI01S.prw, mas U_JSON_COMPRA (FATPI01E.prw) tambem chama - erro
// reproduzido em teste real ("cannot find function GET_REC_JSON in
// AppMap" em U_JSON_COMPRA). Chamadores atualizados de GET_REC_JSON(...)
// pra U_GET_REC_JSON(...), inclusive os locais aqui embaixo (mesmo
// padrao ja usado em todo o codebase).
User Function GET_REC_JSON(oHead, cCampoReq, cCampoPag, nVlrFall)
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
	Local cChaveNFe   := U_PI_STR_X(oHead, 'cod_ChaveNFe')
	Local cModDoc     := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')
	Local cEspecie    := ""
	Local cNatOp      := Upper(AllTrim(U_PI_STR_X(oHead, 'des_NatOp')))
	Local cEstCli     := ""

	Local cTipoE1     := "NF "
	Local cHistPad    := ""
	Local cTransacao  := U_PI_STR_X(oHead, "num_Transacao")
	Local cAutoriz    := U_PI_STR_X(oHead, "des_Autorizacao")
	Local cOrigem     := U_PI_STR_X(oHead, "des_Origem")

	Local nVlrMercV   := U_PI_VAL_X(oHead, 'vlr_TotalProduto', 'vlr_ReciboVendaTotal')
	Local nVlrBrutV   := U_PI_VAL_X(oHead, 'vlr_NotaFiscal', 'vlr_ReciboVendaTotal')
	Local nDescTot    := U_PI_VAL_X(oHead, 'vlr_Desconto', 'vlr_ReciboVendaDesconto')
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

	Local nAliqIcm    := 0
	Local nIcmItm     := 0
	Local cCfopItm    := ""
	Local cTesItm     := ""
	Local aGrpSF3     := {}
	Local nPosGrp     := 0
	Local cQrySF3     := ""

	Local nVlrIcmN    := U_PI_VAL_X(oHead, 'vlr_ICMS')
	Local nBasIcmN    := U_PI_VAL_X(oHead, 'vlr_ICMSBaseCalculo')
	Local nVlrIpiN    := U_PI_VAL_X(oHead, 'vlr_IPI')
	Local nVlrPisN    := U_PI_VAL_X(oHead, 'vlr_PIS')
	Local nVlrCofN    := U_PI_VAL_X(oHead, 'vlr_COFINS')

	Local cDocPad     := PadL(AllTrim(cDocSql), TamSx3("F2_DOC")[1], "0")
	Local cSerPad     := PadR(AllTrim(cSerSql), TamSx3("F2_SERIE")[1], " ")
	Local cCliPad     := PadR(AllTrim(cCliSql), TamSx3("F2_CLIENTE")[1], " ")
	Local cLojaPad    := PadR(AllTrim(cLojaSql), TamSx3("F2_LOJA")[1], " ")

	Local cCustoHead  := U_PI_STR_X(oHead, 'cod_CentroCusto')
	Local cCustoSD2   := ""

	Local cNatJson    := U_PI_STR_X(oHead, "cod_NaturezaFinanceira")
	Local cFormaPag   := U_PI_STR_X(oHead, "des_FormaRecebimento")

	Local cNatItm     := ""
	Local cCCItm      := ""
	Local cFormaRec   := ""
	Local cBandeira   := ""
	Local cTransac    := ""
	Local cAutorizF   := ""
	Local nVlrTitulo  := 0
	Local cFormaTrat  := ""
	Local cParcela    := ""

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
	cNatItm     := U_GET_REC_JSON(oHead, "cod_NaturezaFinanceira", "", "")
	cCCItm      := U_GET_REC_JSON(oHead, "cod_CentroCusto", "", "")
	cFormaRec   := U_GET_REC_JSON(oHead, "des_FormaRecebimento", "des_FormaPagamento", "")
	cBandeira   := U_GET_REC_JSON(oHead, "des_Bandeira", "", "")
	cTransac    := U_GET_REC_JSON(oHead, "num_Transacao", "", "")
	cAutorizF   := U_GET_REC_JSON(oHead, "des_Autorizacao", "", "")
	nVlrTitulo  := U_GET_REC_JSON(oHead, "VLR", "", nVlrBrutV)

	/*cCnpjU  := U_PI_LIMPA_X(U_PI_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
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
					nQtdItm     := Max(U_PI_VAL_X(aPrd[nX], 'qtd_Produto'), 1)
					nVlrUniItm  := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoUnitario')

					// MULTIPLICANDO O DESCONTO PELA QUANTIDADE
					nDescItm    := Round(U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoDescontoUnitario') * nQtdItm, 2)

					nSomaMerc   += Round(nQtdItm * nVlrUniItm, 2)
					nSomaDesc   += nDescItm
				Next nX
			EndIf
		EndIf
	EndIf

	If nVlrMercV <= 0
		nVlrMercV := nSomaMerc
	EndIf
	If nDescTot <= 0
		nDescTot  := nSomaDesc
	EndIf
	If nVlrBrutV <= 0
		nVlrBrutV := Round(nVlrMercV - nDescTot + nFreteTot + nSegTot + nOutrTot, 2)
	EndIf

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
			If SF2->(FieldPos("F2_VALBRUT")) > 0
				SF2->F2_VALBRUT := nVlrBrutV
			EndIf
			If SF2->(FieldPos("F2_VALFAT")) > 0
				SF2->F2_VALFAT  := nVlrBrutV
			EndIf
			If SF2->(FieldPos("F2_VALMERC")) > 0
				SF2->F2_VALMERC := nVlrMercV
			EndIf
			If SF2->(FieldPos("F2_DESCONT")) > 0
				SF2->F2_DESCONT := nDescTot
			EndIf
			If SF2->(FieldPos("F2_VALICM")) > 0
				SF2->F2_VALICM  := nVlrIcmN
			EndIf
			If SF2->(FieldPos("F2_BASEICM")) > 0
				SF2->F2_BASEICM := nBasIcmN
			EndIf
			If SF2->(FieldPos("F2_VALIPI")) > 0
				SF2->F2_VALIPI  := nVlrIpiN
			EndIf
			If SF2->(FieldPos("F2_VALPIS")) > 0
				SF2->F2_VALPIS  := nVlrPisN
			EndIf
			If SF2->(FieldPos("F2_VALCOF")) > 0
				SF2->F2_VALCOF  := nVlrCofN
			EndIf
			If SF2->(FieldPos("F2_CHVNFE")) > 0
				SF2->F2_CHVNFE  := PadR(cChaveNFe, TamSx3("F2_CHVNFE")[1])
			EndIf
			If SF2->(FieldPos("F2_UFDEST")) > 0
				SF2->F2_UFDEST  := cEstCli
			EndIf
			If SF2->(FieldPos("F2_ESPECIE")) > 0
				SF2->F2_ESPECIE := PadR(cEspecie, TamSx3("F2_ESPECIE")[1])
			EndIf

			If cNatOp == "DEVOLUCAO DE COMPRA"
				If SF2->(FieldPos("F2_NFORI")) > 0
					SF2->F2_NFORI := PadR(U_PI_STR_X(oHead, 'num_NFOrigem'), TamSx3("F2_NFORI")[1])
				EndIf
				If SF2->(FieldPos("F2_CHVCLE")) > 0
					SF2->F2_CHVCLE := PadR(U_PI_STR_X(oHead, 'cod_ChaveNFeOrigem'), TamSx3("F2_CHVCLE")[1])
				EndIf
				If SF2->(FieldPos("F2_XVLDEV")) > 0
					SF2->F2_XVLDEV := U_PI_VAL_X(oHead, 'vlr_NotaFiscalDevCAASP')
				EndIf
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
					cCfopItm   := PadR(U_PI_LIMPA_X(U_PI_STR_X(aPrd[nX], 'cod_ProdutoCFOP', 'cfop')), TamSx3("D2_CF")[1])
					cItemSql   := PadL(cValToChar(nX), TamSx3("D2_ITEM")[1], "0")

					nQtdItm     := Max(U_PI_VAL_X(aPrd[nX], 'qtd_Produto'), 1)
					nVlrUniItm  := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoUnitario')
					nDescItm    := Round(U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoDescontoUnitario') * nQtdItm, 2)
					nVlrBrutItm := Round(nQtdItm * nVlrUniItm, 2)
					nVlrLiqItm  := Round(nVlrBrutItm - nDescItm, 2)

					// Extracao Fiscal
					nPicmItem   := U_PI_VAL_X(aPrd[nX], 'pct_ProdutoICMS')
					nBicmItem   := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMSBaseCalculo')
					nVicmItem   := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMS')
					nBicmStItem := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMSOutrosBaseCalculo')
					nBIcmsIsen  := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMSIsentoBaseCalculo')
					nVicmStItem := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMSST')
					nVicmDeson  := U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoICMSDesonerado')
					nPReducIcm  := U_PI_VAL_X(aPrd[nX], 'pct_ProdutoReducaoICMS')
					nPReducSt   := U_PI_VAL_X(aPrd[nX], 'pct_ProdutoReducaoICMSST')

					nAliqIcm    := nPicmItem
					nIcmItm     := nVicmItem

					nPercDesc := 0
					If nVlrBrutItm > 0
						nPercDesc := Round((nDescItm / nVlrBrutItm) * 100, 2)
					EndIf

					cCustoSD2  := U_PI_STR_X(aPrd[nX], 'cod_CentroCusto')
					If Empty(cCustoSD2)
						cCustoSD2 := cCustoHead
					EndIf

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
					If Len(TamSx3("D2_PICM")) > 0
						cQryRec += ", D2_PICM = " + StrTran(cValToChar(nPicmItem), ",", ".")
					EndIf
					If Len(TamSx3("D2_BASEICM")) > 0
						cQryRec += ", D2_BASEICM = " + StrTran(cValToChar(nBicmItem), ",", ".")
					EndIf
					If Len(TamSx3("D2_VALICM")) > 0
						cQryRec += ", D2_VALICM = " + StrTran(cValToChar(nVicmItem), ",", ".")
					EndIf
					If Len(TamSx3("D2_BASERET")) > 0
						cQryRec += ", D2_BASERET = " + StrTran(cValToChar(nBicmStItem), ",", ".")
					EndIf
					If Len(TamSx3("D2_VALRET")) > 0
						cQryRec += ", D2_VALRET = " + StrTran(cValToChar(nVicmStItem), ",", ".")
					EndIf
					If Len(TamSx3("D2_ICMDES")) > 0
						cQryRec += ", D2_ICMDES = " + StrTran(cValToChar(nVicmDeson), ",", ".")
					EndIf
					If Len(TamSx3("D2_PRDICM")) > 0
						cQryRec += ", D2_PRDICM = " + StrTran(cValToChar(nPReducIcm), ",", ".")
					EndIf
					If Len(TamSx3("D2_PRDRET")) > 0
						cQryRec += ", D2_PRDRET = " + StrTran(cValToChar(nPReducSt), ",", ".")
					EndIf

                    /*If cNatOp == "DEVOLUCAO DE COMPRA"
                        cQryRec += ", D2_OUTROS = " + StrTran(cValToChar(U_PI_VAL_X(aPrd[nX], 'vlr_ProdutoOutros')), ",", ".") 
                    EndIf*/

					cQryRec += " WHERE D2_DOC='" + cDocPad + "' AND D2_SERIE='" + cSerPad + "' AND D2_CLIENTE='" + cCliPad + "' AND D2_LOJA='" + cLojaPad + "' AND D2_ITEM='" + cItemSql + "' AND D_E_L_E_T_=' '"
					TCSqlExec(cQryRec)

					nPosGrp := AScan(aGrpSF3, {|x| x[1] == cCfopItm .And. x[2] == nAliqIcm})
					If nPosGrp == 0
						AAdd(aGrpSF3, {cCfopItm, nAliqIcm, nVlrLiqItm, nIcmItm,nBicmItem,nBicmStItem,nBIcmsIsen})
					Else
						aGrpSF3[nPosGrp][3] += nVlrLiqItm
						aGrpSF3[nPosGrp][4] += nIcmItm
						aGrpSF3[nPosGrp][5] += nBicmItem
						aGrpSF3[nPosGrp][6] += nBicmStItem
						aGrpSF3[nPosGrp][7] += nBIcmsIsen
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
			SF3->F3_ESTADO  := SF2->F2_EST
			SF3->F3_CHVNFE  := SF2->F2_CHVNFE
			SF3->F3_NFISCAL := cDocPad
			SF3->F3_SERIE   := cSerPad
			SF3->F3_CLIEFOR := cCliPad
			SF3->F3_LOJA    := cLojaPad
			SF3->F3_CFO     := aGrpSF3[nX][1]
			SF3->F3_ALIQICM := aGrpSF3[nX][2]
			SF3->F3_VALCONT := aGrpSF3[nX][3]
			SF3->F3_VALICM  := aGrpSF3[nX][4]
			SF3->F3_BASEICM := aGrpSF3[nX][5]
			SF3->F3_OUTRICM := aGrpSF3[nX][6]
			SF3->F3_ISENICM := aGrpSF3[nX][7]


			SF3->F3_ESPECIE := PadR(cEspecie, TamSx3("F3_ESPECIE")[1])
			SF3->(MsUnlock())
		Next nX
	EndIf

	// ATUALIZACAO DO FINANCEIRO (SE1)
	cHistPad := "API: Orig:" + cOrigem + " Aut:" + cAutoriz + " Trans:" + cTransacao

	If Empty(cNatItm)
		cNatItm := cNatJson
	EndIf
	If Empty(cCCItm)
		cCCItm  := cCustoHead
	EndIf
	If Empty(cFormaRec)
		cFormaRec := Upper(AllTrim(cFormaPag))
	EndIf

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
		If Empty(AllTrim(cParcela))
			// [FIX-E1-PARCELA] Jose Carlos - Artiq - 08/2026 - zero a
			// esquerda, mesmo padrao do FZ_GER_E1.
			cParcela := PadL("1", TamSx3("E1_PARCELA")[1], "0")
		EndIf

		cQrySE1 := "UPDATE " + RetSqlName("SE1") + " SET "
		cQrySE1 += "E1_TIPO = '" + PadR(cTipoE1, TamSx3("E1_TIPO")[1]) + "', "
		cQrySE1 += "E1_PARCELA = '" + PadR(cParcela, TamSx3("E1_PARCELA")[1]) + "', "
		cQrySE1 += "E1_NATUREZ = '" + PadR(cNatItm, TamSx3("E1_NATUREZ")[1]) + "', "
		cQrySE1 += "E1_CCUSTO = '" + PadR(cCCItm, TamSx3("E1_CCUSTO")[1]) + "', "
		cQrySE1 += "E1_XEVENTO = '" + PadR(cOrigem, TamSx3("E1_XEVENTO")[1]) + "', "
		// [FIX-SE1-CODFUNC] Jose Carlos - Artiq - 08/2026 - campo novo, sem
		// precedente no original - ver instrucoes_pendentes_pos_debug_transf.md,
		// C.1. Guarda Len(TamSx3(...)) por seguranca (ainda nao confirmado
		// no dicionario).
		If Len(TamSx3("E1_CODFUNC")) > 0
			cQrySE1 += "E1_CODFUNC = '" + PadR(Posicione('SA1', 1, FWxFilial('SA1') + cCliPad + cLojaPad, 'A1_XCODRH'), TamSx3("E1_CODFUNC")[1]) + "', "
		EndIf
		// [FIX-SE1-MOEDA] Jose Carlos - Artiq - 08/2026 - mesmo valor fixo
		// que E2_MOEDA ja usa do lado de compras - ver C.2. Campo padrao
		// do Protheus, sem guarda.
		cQrySE1 += "E1_MOEDA = 1, "

		cQrySE1 += "E1_VALOR = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
		cQrySE1 += "E1_SALDO = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
		cQrySE1 += "E1_VALLIQ = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "
		cQrySE1 += "E1_VLCRUZ = " + StrTran(cValToChar(nVlrTitulo), ",", ".") + ", "

		If !Empty(cFormaTrat)
			cQrySE1 += "E1_FORMAPG = '" + PadR(cFormaTrat, TamSx3("E1_FORMAPG")[1]) + "', "
		EndIf
		If !Empty(cBandeira)
			cQrySE1 += "E1_CARTAO = '" + PadR(cBandeira, TamSx3("E1_CARTAO")[1]) + "', "
		EndIf
		If !Empty(cTransac)
			cQrySE1 += "E1_NSUTEF = '" + PadR(cTransac, TamSx3("E1_NSUTEF")[1]) + "', "
		EndIf
		If !Empty(cAutorizF)
			cQrySE1 += "E1_CARTAUT = '" + PadR(cAutorizF, TamSx3("E1_CARTAUT")[1]) + "', "
		EndIf

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
User Function FATPI01NF(aPrd, oHead, cCnpjOrigem, cDoc, cSer, aEmpDest, lIsTransf)
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
	RpcClearEnv()
	RpcSetEnv(aEmpDest[1], aEmpDest[2], Nil, Nil, "FAT")

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
		cCondSafe := PadR(U_PI_COND_X("004"), 3)

		For nI := 1 To Len(aPrd)
			cAuxC := U_PI_LIMPA_X(U_PI_STR_X(aPrd[nI], 'cod_ProdutoCFOP', 'cfop'))

			// Inverte CFOP para a Otica de Entrada (Ex: 5409 vira 1409)
			cAuxC := U_PI_INVCFOP(cAuxC, "E")

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
			aRet := U_PI_GERANF_X(aPrd, oHead, cForn, cLoja, cDoc, cSer, "", "SA2", aEmpDest[2], 0, cCondSafe, lIsTransf)
		Else
			aRet := {.F., cMsgTes}
		EndIf
	EndIf

	PutMv("MV_PCNFE", cOldPcNfe)

	// 5. Retorna ao Ambiente Original da API
	RpcClearEnv()
	RpcSetEnv(cEmpAtu, cFilAtu, Nil, Nil, "FAT")

Return aRet

// ==========================================================================
// VENDAS (SAIDAS) - MOTOR DIRETO MANFS2NFS (SA1 E SA2 DINAMICOS E TRANSFERENCIA)
// ==========================================================================
User Function PI_SAIDA_X(aPrd, oHead, cCli, cLoja, cLeg, cSer, cFil, cTab, lIsTransf, cNF, cSerNF, cLegT, cCond)
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
	Local dEmissao   := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Emissao'))
	Local cDocPad    := PadL(AllTrim(cValToChar(cNF)), TamSx3("F2_DOC")[1], "0")
	Local cSerPad    := PadR(AllTrim(cValToChar(cSer)), TamSx3("F2_SERIE")[1], " ")
	Local cTipoOper  := ""
	Local cCustItm   := ""
	Local cEstCli    := U_PI_UF_X(cTab, cCli, cLoja)
	Local cUmDB      := ""
	Local cLocDB     := ""
	Local cModDoc    := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')
	Local cEspecie   := ""
	Local cNotaOri
	Local cSerieOri
	Local cItemOri
	Local lDevol := .T.
	// [FIX-TRANSF-CLIENTE] Jose Carlos - Artiq - 08/2026 - cCnpjCli usado
	// no bloco lIsTransf abaixo pra resolver cliente/loja via SA1 -
	// restaurado do original (FZ_PROS_X), nao existia aqui ainda. Ver
	// instrucoes_pendentes_pos_debug_transf.md, A.3.
	Local cCnpjCli   := U_PI_LIMPA_X(U_PI_STR_X(oHead, "des_DestDocumento", "des_DestDocumento"))

	Local bFiscalSF2 := {|| .T.}
	Local bFiscalSD2 := {|| .T.}

	// [FIX-FRETE] Jose Carlos - Artiq - 08/2026 - nFreteVlr/nF2FRETE
	// restaurados, sumiram na extracao pro PI_SAIDA_X atual - ver
	// instrucao_despesa_frete_debug_transferencia.md. Leitura propria (nao
	// reaproveita a variavel de JSON_VENDA - escopo de Static Function
	// separado, e JSON_VENDA roda so depois, tratamento pos-gravacao).
	Local nFreteVlr  := U_PI_VAL_X(oHead, 'vlr_Frete')
	Local nF2FILIAL, nF2TIPO, nF2DOC, nF2SERIE, nF2EMISSAO, nF2CLIENTE, nF2LOJA, nF2COND, nF2ESPECIE, nF2EST, nF2FRETE
	Local nD2FILIAL, nD2DOC, nD2SERIE, nD2CLIENTE, nD2LOJA, nD2TIPO, nD2COD, nD2QUANT, nD2PRCVEN, nD2TOTAL, nD2TES, nD2CF, nD2CC, nD2ITEM, nD2UM, nD2LOCAL, nD2DESCON, nD2FRETE
	// [FIX-FRETE-SAIDA] Jose Carlos - Artiq - 08/2026 - D2_VALFRE (item)
	// restaurado, sumiu na extracao pro PI_SAIDA_X atual - ver
	// instrucoes_pendentes_pos_debug_transf.md, Parte B.2. Compartilhado
	// por FATZZA01 (NFe) e FATZZD01 (NFCe).
	Local nFreteItem := 0

	Local nQtdCalc   := 0
	Local nPrcCalc   := 0
	Local nDescUnit  := 0
	Local nDescTotal := 0
	Local nTamItemOri:= TamSx3("D2_ITEMORI")[1]
	Local nTamSerie  := TamSx3("D2_SERIORI")[1]
	Local cCnpjU
	Local aEmpFil

	Private lMsErroAuto := .F.

	cCnpjU  := U_PI_LIMPA_X(U_PI_STR_X(oHead, "num_SubseccaoCNPJ", "num_SubseccaoCNPJ"))
	aEmpFil := U_FATPIEMP(cCnpjU)

	If Len(aEmpFil) > 0
		If aEmpFil[1] != cEmpAnt .Or. aEmpFil[2] != cFilAnt
			RPCClearEnv()
			RpcSetEnv(aEmpFil[1], aEmpFil[2])
		EndIf
	Endif

	If cModDoc == "55"
		cEspecie := "SPED"
	Else
		cEspecie := "NFE"
	EndIf

	cTipoOper := IIF(Alltrim(cTab) == 'SA2', 'D','N')

	If lIsTransf
		// [FIX-TRANSF-CLIENTE] resolve cliente/loja de destino via SA1
		// (des_DestDocumento) - sem isso, cCli/cLoja continuam com o valor
		// do chamador (pode estar errado/vazio pra CONVENIOS). Restaurado
		// do original, ver instrucoes_pendentes_pos_debug_transf.md, A.3.
		DbSelectArea("SA1")
		SA1->(DbSetOrder(3))
		If SA1->(DbSeek(xFilial("SA1") + cCnpjCli))
			cCli  := SA1->A1_COD
			cLoja := SA1->A1_LOJA
		EndIf
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
	nD2FRETE   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_VALFRE"})
	nD2NFORI   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_NFORI"})
	nD2SERORI  := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_SERIORI"})
	nD2ITORI   := Ascan(aStruSD2,{|x| AllTrim(x[1]) == "D2_ITEMORI"})

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

	If nF2FILIAL > 0
		aCabs[nF2FILIAL]  := xFilial("SF2")
	EndIf
	If nF2DOC > 0
		aCabs[nF2DOC]     := cDocPad
	EndIf
	If nF2SERIE > 0
		aCabs[nF2SERIE]   := cSerPad
	EndIf
	If nF2EMISSAO > 0
		aCabs[nF2EMISSAO] := dEmissao
	EndIf
	If nF2CLIENTE > 0
		aCabs[nF2CLIENTE] := cCli
	EndIf
	If nF2LOJA > 0
		aCabs[nF2LOJA]    := cLoja
	EndIf
	If nF2TIPO > 0
		aCabs[nF2TIPO]    := cTipoOper
	EndIf
	If nF2COND > 0
		aCabs[nF2COND]    := cCond
	EndIf
	If nF2ESPECIE > 0
		aCabs[nF2ESPECIE] := PadR(cEspecie, TamSx3("F2_ESPECIE")[1])
	EndIf
	If nF2EST > 0
		aCabs[nF2EST]     := PadR(cEstCli, TamSx3("F2_EST")[1])
	EndIf
	If nF2FRETE > 0
		aCabs[nF2FRETE]   := nFreteVlr
	EndIf

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

		cCustItm := U_PI_STR_X(aPrd[nI], 'cod_CentroCusto')
		If Empty(cCustItm)
			cCustItm := U_PI_CCUSTO_X(aPrd[nI]['cod_Produto'])
		EndIf

		cUmDB := Posicione("SB1", 1, xFilial("SB1") + PadR(aPrd[nI]['cod_Produto'], TamSx3("B1_COD")[1]), "B1_UM")
		cLocDB := Posicione("SB1", 1, xFilial("SB1") + PadR(aPrd[nI]['cod_Produto'], TamSx3("B1_COD")[1]), "B1_LOCPAD")
		If Empty(cUmDB)
			cUmDB := "UN"
		EndIf
		If Empty(cLocDB)
			cLocDB := "01"
		EndIf

		nQtdCalc   := Max(U_PI_VAL_X(aPrd[nI], 'qtd_Produto'), 1)
		nPrcCalc   := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario')
		nDescUnit  := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario')
		nDescTotal := Round(nQtdCalc * nDescUnit, 2)
		nFreteItem := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoFrete') // [FIX-FRETE-SAIDA] restaurado

		cNotaOri := PadL(ALLTRIM(U_PI_STR_X(aPrd[nI], 'num_NFOrigem')), 9, '0')
		cSerieOri := U_PI_STR_X(aPrd[nI], 'cod_SerieOrigem')
		cItemOri := U_PI_STR_X(aPrd[nI], 'num_ProdutoSequencialOrigem')
		cChaveOri := U_PI_STR_X(aPrd[nI], 'cod_ChaveNFeOrigem')

		// [FIX-D2FILIAL] Jose Carlos - Artiq - 08/2026
		// nD2FILIAL era calculado (Ascan) mas nunca usado pra preencher
		// aItens - diferente de nF2FILIAL, que ja preenchia aCabs[nF2FILIAL]
		// := xFilial("SF2") no cabecalho. Sem isso, todo item gerado por
		// U_PI_SAIDA_X ficava com D2_FILIAL em branco (o loop de
		// inicializacao do array so limpa pra "" - nunca reatribui).
		// Reproduzido em teste real: 1 de 20 NFCe quebrou por causa disso.
		If nD2FILIAL > 0
			aItens[nPos, nD2FILIAL] := xFilial("SD2")
		EndIf

		If nD2DOC > 0
			aItens[nPos, nD2DOC]    := cDocPad
		EndIf
		If nD2SERIE > 0
			aItens[nPos, nD2SERIE]  := cSerPad
		EndIf
		If nD2CLIENTE > 0
			aItens[nPos, nD2CLIENTE]:= cCli
		EndIf
		If nD2LOJA > 0
			aItens[nPos, nD2LOJA]   := cLoja
		EndIf
		If nD2TIPO > 0
			aItens[nPos, nD2TIPO]   := cTipoOper
		EndIf
		If nD2ITEM > 0
			aItens[nPos, nD2ITEM]   := PadL(cValToChar(nI), TamSx3("D2_ITEM")[1], "0")
		EndIf
		If nD2COD > 0
			aItens[nPos, nD2COD]    := PadR(aPrd[nI]['cod_Produto'], TamSx3("D2_COD")[1])
		EndIf

		IF !Empty(cNotaOri) .AND. cTipoOper == 'D'
			IF lDevol
				lDevol := U_FZ_VALID_DEV(cChaveOri,cNotaOri,'C')
			Endif
			If nD2NFORI > 0
				aItens[nPos, nD2NFORI]  := cNotaOri
			EndIf
			If nD2SERORI > 0
				aItens[nPos, nD2SERORI] := PADR(ALLTRIM(cSerieOri), nTamSerie, '')
			EndIf
			If nD2ITORI > 0
				aItens[nPos, nD2ITORI]  := PadL(ALLTRIM(cItemOri), nTamItemOri, '0')
			EndIf
		ENDIF

		If nD2QUANT > 0
			aItens[nPos, nD2QUANT]  := nQtdCalc
		EndIf
		If nD2PRCVEN > 0
			aItens[nPos, nD2PRCVEN] := nPrcCalc
		EndIf
		If nD2FRETE > 0
			aItens[nPos, nD2FRETE] := nFreteItem
		EndIf
		If nD2TOTAL > 0
			aItens[nPos, nD2TOTAL]  := Round(nQtdCalc * nPrcCalc, 2)
		EndIf
		If nD2DESCON > 0 .And. nDescTotal > 0
			aItens[nPos, nD2DESCON] := nDescTotal
		EndIf

		If nD2TES > 0
			aItens[nPos, nD2TES]    := PadR(aPrd[nI]['_TES_CACHE'], TamSx3("D2_TES")[1])
		EndIf
		If nD2CF > 0
			aItens[nPos, nD2CF]     := PadR(aPrd[nI]['cod_ProdutoCFOP'], TamSx3("D2_CF")[1])
		EndIf
		If nD2CC > 0
			aItens[nPos, nD2CC]     := PadR(cCustItm, TamSx3("D2_CCUSTO")[1])
		EndIf
		If nD2UM > 0
			aItens[nPos, nD2UM]     := PadR(cUmDB, TamSx3("D2_UM")[1])
		EndIf
		If nD2LOCAL > 0
			aItens[nPos, nD2LOCAL]  := PadR(cLocDB, TamSx3("D2_LOCAL")[1])
		EndIf

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

// [FIX-LOTE-COMPILACAO] Jose Carlos - Artiq - 08/2026
// Promovida de Static Function pra User Function - era so visivel dentro
// de FATPI01S.prw (lote de compilacao proprio), mas U_PI_GERANF_X
// (FATPI01E.prw) e o motor de devolucao (FATPI01D.prw) tambem chamam,
// erro reproduzido em teste real ("cannot find function RETOPERA in
// AppMap" em U_PI_GERANF_X). Mesmo motivo de sempre nesse codebase (ver
// BuscaCad/U_BUSCACAD, FZ_ROLLBACK_NF/U_PI_ROLLBACK_NF etc.) - Static
// Function nao atravessa lote de compilacao diferente. Chamadores
// (FATPI01D.prw/FATPI01E.prw) atualizados de RetOpera(...) pra
// U_RetOpera(...).
User Function RetOpera(cOper,cCST)

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
	Local cTipoTit

	DbSelectArea("SE1")
	SE1->(DbGoTo(nRecno))

	If !FWIsInCallStack("U_FATPI08NF")

		cNaturez := oHead['cod_NaturezaFinanceira']
		cCusto   := oHead['itens'][1]['cod_CentroCusto']
		cEvento  := SE1->E1_XEVENTO
		cHist    := SE1->E1_HIST

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
				cFormaPag   := U_PI_STR_X(oParcItem, "des_FormaRecebimento")
				cFormaRec   := U_PI_STR_X(oParcItem, 'des_FormaRecebimento')
				cBandeira   := U_PI_STR_X(oParcItem, "des_Bandeira")
				cTransac    := U_PI_STR_X(oParcItem, "num_Transacao")
				cAutorizF   := U_PI_STR_X(oParcItem, "des_Autorizacao")
				cTipoTit    := U_PI_STR_X(oParcItem, "des_FormaPag")

				cFormaRec := Upper(AllTrim(cFormaRec))

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
				cNumP := cValToChar(U_PI_VAL_X(oParcItem, 'num_Parcela'))
				dVencP := U_PI_DATA_X(U_PI_STR_X(oParcItem, 'dta_Vencimento'))
				nVlrP := U_PI_VAL_X(oParcItem, 'vlr_Recebimento')

				// [FIX-E1-PARCELA] Jose Carlos - Artiq - 08/2026 - se vier
				// vazio/zero, sempre 1 (nao a posicao no loop).
				If Empty(cNumP) .Or. cNumP == "0"
					cNumP := "1"
				EndIf

				RecLock("SE1", .T.)
				SE1->E1_FILIAL  := xFilial("SE1")
				SE1->E1_FILORIG := xFilial("SE1")
				SE1->E1_MSFIL   := xFilial("SE1")
				SE1->E1_PREFIXO := cSer
				SE1->E1_NUM     := cDoc
				// [FIX-E1-PARCELA] Jose Carlos - Artiq - 08/2026
				// Gravava cParce (contador alfabetico A/B/C via SOMA1) em vez
				// de cNumP (ja calculado corretamente logo acima a partir de
				// num_Parcela do JSON, com fallback sequencial 1/2/3 se vier
				// vazio/zero) - cNumP ficava computado e nunca usado. Mesmo
				// padrao que FZ_GER_E2 (FATPI01E.prw) ja usa do lado de
				// compras (E2_PARCELA := cNumP). Campo alfanumerico com zero
				// a esquerda (confirmado 08/2026 - "1" deve virar "01").
				SE1->E1_PARCELA := PadL(cNumP, TamSx3("E1_PARCELA")[1], "0")
				SE1->E1_TIPO    := IIF(!Empty(cTipoTit),cTipoTit,'NF')
				SE1->E1_XTIPO   := 'NF'
				SE1->E1_NATUREZ := cNaturez
				SE1->E1_CLIENTE := cCli
				SE1->E1_LOJA    := cLoja
				SE1->E1_NOMCLI  := Posicione('SA1', 1, FWxFilial('SA1') + SE1->E1_CLIENTE + SE1->E1_LOJA, 'A1_NOME')
				// [FIX-SE1-CODFUNC] Jose Carlos - Artiq - 08/2026 - campo
				// novo, sem precedente no original, confirmado com o Jose
				// Carlos - ver instrucoes_pendentes_pos_debug_transf.md,
				// C.1. Guarda FieldPos por seguranca (ainda nao confirmado
				// no dicionario).
				If SE1->(FieldPos("E1_CODFUNC")) > 0
					SE1->E1_CODFUNC := Posicione('SA1', 1, FWxFilial('SA1') + SE1->E1_CLIENTE + SE1->E1_LOJA, 'A1_XCODRH')
				EndIf
				// [FIX-SE1-MOEDA] Jose Carlos - Artiq - 08/2026 - mesmo
				// valor fixo que E2_MOEDA ja usa do lado de compras
				// (FZ_GER_E2) - ver C.2. Campo padrao do Protheus, sem
				// guarda (mesmo padrao ja usado em E2_MOEDA).
				SE1->E1_MOEDA   := 1
				SE1->E1_EMISSAO := SF2->F2_EMISSAO
				SE1->E1_EMIS1   := SF2->F2_EMISSAO
				SE1->E1_VENCTO  := dVencP
				SE1->E1_VENCREA := dVencP
				SE1->E1_VALOR   := nVlrP
				SE1->E1_VALLIQ  := nVlrP
				SE1->E1_SALDO   := nVlrP
				SE1->E1_VLCRUZ  := nVlrP
				SE1->E1_CCUSTO  := cCusto
//				SE1->E1_ORIGEM  := 'MATA460'
				SE1->E1_FLUXO   := 'S'
				SE1->E1_HIST    := cHist
				SE1->E1_STATUS  := 'A'
				SE1->E1_SERIE   := cSer
				SE1->E1_CARTAO  := cBandeira
				SE1->E1_SITUACA := '0'
				SE1->E1_CARTAUT := cAutorizF
				SE1->E1_NSUTEF  := cTransac
				SE1->E1_FORMAPG := cFormaTrat
				SE1->E1_XEVENTO := cEvento
				SE1->(MsUnlock())
			Next nX
		EndIf
	Endif
Return



// ==========================================================================
// PI_LOJA_X - Motor NFCe via ExecAuto LOJA701 (renomeada de FZ_PROS_LOJA)
// [FIX-10CHAR] Jose Carlos - Artiq - 07/2026
// U_FZ_PROS_LOJA colidia com U_PI_SAIDA_X — AdvPL so considera os primeiros
// 10 caracteres do nome (incluindo o U_) na resolucao de simbolo. Ambas
// comecavam identicas em "U_FZ_PROS_", o compilador barrava por conflito.
// Renomeada para PI_LOJA_X, que diverge do PI_SAIDA_X ja no 6o caractere.
// Inclusao de orcamento (parametro 3) via SL1/SLR/SL4 — NAO finaliza venda.
// ==========================================================================
User Function PI_LOJA_X(aPrd, oHead, cCli, cLoja, cSer, cTab, cCond)
//	Local aRet       := {.F., ""}
	Local aCab       := {}
	Local aItem      := {}
	Local aLin       := {}
	Local aParcelas  := {}
	Local nI         := 0
	Local nX         := 0
	Local cNumVen    := ""
	Local dEmissao   := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Emissao'))
	Local nVlrBrut   := U_PI_VAL_X(oHead, 'vlr_NotaFiscal', 'vlr_ReciboVendaTotal')
	Local nVlrMerc   := U_PI_VAL_X(oHead, 'vlr_TotalProduto', 'vlr_ReciboVendaTotal')
	Local nVlrDesc   := U_PI_VAL_X(oHead, 'vlr_Desconto', 'vlr_ReciboVendaDesconto')
	Local xRecVal    := Nil
	Local aParcJson  := {}
	Local oParcItem  := Nil
	Local cMsg       := ""

	Private lMsErroAuto    := .F.
	Private lAutoErrNoFile := .T.
	Private __cBatch       := "1"
	Private __cXEvento     := "LOJ"

	// Gera numero do orcamento/venda
	cNumVen := GetSxeNum("SL1", "L1_NUM")

	// --- CABECALHO (aCab) ---
	AAdd(aCab, {"L1_FILIAL",  xFilial("SL1"),                                  Nil})
	AAdd(aCab, {"L1_NUM",     PadR(cNumVen, TamSx3("L1_NUM")[1]),               Nil})
	AAdd(aCab, {"L1_CLIENTE", PadR(cCli, TamSx3("L1_CLIENTE")[1]),              Nil})
	AAdd(aCab, {"L1_LOJA",    PadR(cLoja, TamSx3("L1_LOJA")[1]),                Nil})
	AAdd(aCab, {"L1_EMISSAO", dEmissao,                                         Nil})
	AAdd(aCab, {"L1_SERIE",   PadR(cSer, TamSx3("L1_SERIE")[1]),                Nil})
	AAdd(aCab, {"L1_COND",    PadR(cCond, TamSx3("L1_COND")[1]),                Nil})
	AAdd(aCab, {"L1_SITUA",   "RX",                                             Nil})
	AAdd(aCab, {"L1_VALMERC", nVlrMerc,                                         Nil})
	AAdd(aCab, {"L1_VALBRUT", nVlrBrut,                                         Nil})
	AAdd(aCab, {"L1_DESCONT", nVlrDesc,                                         Nil})
	AAdd(aCab, {"L1_VEND",    PadR("000001", TamSx3("L1_VEND")[1]),             Nil})
	AAdd(aCab, {"L1_PDV",     PadR("001", TamSx3("L1_PDV")[1]),                 Nil})
	AAdd(aCab, {"L1_OPERADO", PadR(U_PI_STR_X(oHead, 'cod_LoginEmissao'), TamSx3("L1_OPERADO")[1]), Nil})

	// --- ITENS (aItem) ---
	For nI := 1 To Len(aPrd)
		aLin := {}
		AAdd(aLin, {"LR_FILIAL",  xFilial("SLR"),                                              Nil})
		AAdd(aLin, {"LR_NUM",     PadR(cNumVen, TamSx3("LR_NUM")[1]),                         Nil})
		AAdd(aLin, {"LR_ITEM",    PadL(cValToChar(nI), TamSx3("LR_ITEM")[1], "0"),            Nil})
		AAdd(aLin, {"LR_PRODUTO", PadR(AllTrim(aPrd[nI]['cod_Produto']), TamSx3("LR_PRODUTO")[1]), Nil})
		AAdd(aLin, {"LR_QUANT",   Max(U_PI_VAL_X(aPrd[nI], 'qtd_Produto'), 1),               Nil})
		AAdd(aLin, {"LR_PRECO",   U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'),               Nil})
		AAdd(aLin, {"LR_TOTAL",   Round(Max(U_PI_VAL_X(aPrd[nI], 'qtd_Produto'),1) * U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), 2), Nil})
		AAdd(aLin, {"LR_TES",     PadR(AllTrim(aPrd[nI]['_TES_CACHE']), TamSx3("LR_TES")[1]),Nil})
		AAdd(aLin, {"LR_CF",      PadR(AllTrim(aPrd[nI]['cod_ProdutoCFOP']), TamSx3("LR_CF")[1]), Nil})
		AAdd(aLin, {"LR_LOCAL",   PadR(U_PI_LOCAL_X(AllTrim(aPrd[nI]['cod_Produto'])), TamSx3("LR_LOCAL")[1]), Nil})
		AAdd(aLin, {"LR_UM",      PadR(Posicione("SB1",1,xFilial("SB1")+PadR(AllTrim(aPrd[nI]['cod_Produto']),TamSx3("B1_COD")[1]),"B1_UM"), TamSx3("LR_UM")[1]), Nil})
		AAdd(aItem, aLin)
	Next nI

	// --- PARCELAS (aParcelas) ---
	If oHead:HasProperty('recebimentos')
		xRecVal := oHead['recebimentos']
		If ValType(xRecVal) == "A"
			aParcJson := xRecVal
		EndIf
	EndIf

	For nX := 1 To Len(aParcJson)
		oParcItem := aParcJson[nX]
		AAdd(aParcelas, {;
			U_PI_DATA_X(U_PI_STR_X(oParcItem, 'dta_Vencimento')),;
			U_PI_VAL_X(oParcItem, 'vlr_Recebimento'),;
			PadR(U_PI_STR_X(oParcItem, 'des_FormaRecebimento'), TamSx3("L4_FORMA")[1]),;
			PadR(U_PI_STR_X(oParcItem, 'des_Bandeira'), TamSx3("L4_ADMINIS")[1]),;
			PadR(U_PI_STR_X(oParcItem, 'num_Transacao'), TamSx3("L4_NSUTEF")[1]),;
			PadR(U_PI_STR_X(oParcItem, 'des_Autorizacao'), TamSx3("L4_AUTORIZ")[1]);
		})
	Next nX

	// --- EXECUTA LOJA701 (parametro 3 = inclusao de orcamento — NAO finaliza venda) ---
	MSExecAuto({|a,b,c,d,e,f,g,h| LOJA701(a,b,c,d,e,f,g,h)}, .F., 3, aCab, aItem, aParcelas, Nil, Nil)

	If lMsErroAuto
		RollBackSx8()
		cMsg := U_PI_LOG_X("LOJA701")
		Return {.F., cMsg}
	EndIf

	ConfirmSx8()
Return {.T., cNumVen}

