#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

/*
+----------------------------------------------------------------------------+
| Autor: Antonio Nunes O Jr / Jose Carlos - Artiq                            |
| Data: 07/2026                                                              |
| Descritivo: FATPI01D - Motor de Devolucao                                 |
|             PI_DEVOL_X   - MATA103 tipo D/N (Devolucao de venda)          |
|             FZ_VALID_DEV - Valida nota de origem na SF2                   |
+----------------------------------------------------------------------------+
*/

User Function PI_DEVOL_X(aPrd, oHead, cCli, cLoja, cDoc, cSer, cTab, cFil, nAval, cCond)
	Local aRet       := {.F.,""}
	Local aCab       := {}
	Local aIt        := {}
	Local aLin       := {}
	Local nI         := 0
	Local cTE        := ""
//	Local nQtd       := 0
//	Local nPrc       := 0
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

	Local nVlrFrete  := U_PI_VAL_X(oHead, 'vlr_Frete')
	Local nVlrSeg    := U_PI_VAL_X(oHead, 'vlr_Seguro')
	Local nVlrDesc   := U_PI_VAL_X(oHead, 'vlr_Desconto')
	Local nVlrOutr   := U_PI_VAL_X(oHead, 'vlr_Outros')
	Local nVlrMerc   := U_PI_VAL_X(oHead, 'vlr_TotalProduto')
	Local nVlrBrut   := U_PI_VAL_X(oHead, 'vlr_NotaFiscal')

	Local cDocPad    := PadL(AllTrim(cValToChar(cDoc)), TamSx3("F1_DOC")[1], "0")
	Local cSerPad    := PadR(AllTrim(cValToChar(cSer)), TamSx3("F1_SERIE")[1], " ")
	Local cCliPad    := PadR(AllTrim(cValToChar(cCli)), TamSx3("F1_FORNECE")[1], " ")
//	Local cLojaPad   := PadR(AllTrim(cValToChar(cLoja)), TamSx3("F1_LOJA")[1], " ")
	Local cItemSeq   := ""

	// Financeiro/Banco JSON
	Local cEvtMod    := U_PI_STR_X(oHead, "cod_EventoModalidade", "cod_Evento")
	Local cNatJson   := U_PI_STR_X(oHead, "cod_NaturezaFinanceira")
	Local cTransacao := U_PI_STR_X(oHead, "num_Transacao")
	Local cCondReal  := PadR(U_PI_COND1_X(), 3)
	Local cHistPad   := ""
	Local cNatReal   := ""
	Local cNomeFin   := ""
	Local cNomeFor   := ""
	Local cAliSE2    := ""
	Local cQrySE2    := ""
	Local nRecSE2    := 0
	Local cUpdSF1    := ""
	Local cModDoc    := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')
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

	If Empty(cEvtMod)
		cEvtMod := "571"
	EndIf

	dEmissao := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Emissao'))
	dDataDigit := U_PI_DATA_X(U_PI_STR_X(oHead, 'dta_Conferencia'))
	cUFEntity := PadR(U_PI_UF_X(cTab, cCli, cLoja), 2)
	cCond := PadR(cValToChar(cCond), 3)

	dDataBase := dDataDigit

	cNomeFor := U_PI_STR_X(oHead, 'des_DestNome')
	If Empty(cNomeFor)
		cNomeFor := U_PI_STR_X(oHead, 'des_NomeCliente', 'nome')
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
		nTotNF += Round(U_PI_VAL_X(aPrd[nI], 'qtd_Produto') * U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario'), 2)
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
		cNatReal := PadR(U_PI_NAT_X(cFornSql, cLojaSql, oHead), TamSx3("E2_NATUREZ")[1])
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
	AAdd(aCab, {"F1_CHVNFE", U_PI_STR_X(oHead, 'cod_ChaveNFe'), Nil})
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

		nQtdItm     := Max(U_PI_VAL_X(aPrd[nI], 'qtd_Produto'), 1)
		nVlrUniItm  := U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoUnitario')

		// MULTIPLICANDO O DESCONTO PELA QUANTIDADE (CORRIGIDO PARA USO DE nI)
		nDescItm    := Round(U_PI_VAL_X(aPrd[nI], 'vlr_ProdutoDescontoUnitario') * nQtdItm, 2)

		nVlrBrutItm := Round(nQtdItm * nVlrUniItm, 2)
		nVlrLiqItm  := Round(nVlrBrutItm - nDescItm, 2)

		cItemSeq := PadL(cValToChar(nI), TamSx3("D1_ITEM")[1], "0")
		cCta := PadR(cValToChar(U_PI_CONTA_X(cProdKey)), 20)
		cCC  := U_PI_STR_X(aPrd[nI], 'cod_CentroCusto')

		If Empty(cCC)
			cCC := U_PI_CCUSTO_X(cProdKey)
		EndIf

        /*cNfOri   := PadR(U_PI_STR_X(aPrd[nI], '_NFORI', 'num_NFOri'), TamSx3("D1_NFORI")[1]) 
        cSerOri  := PadR(U_PI_STR_X(aPrd[nI], '_SERIORI', 'num_SerOri'), TamSx3("D1_SERIORI")[1]) 
        cItemOri := PadR(U_PI_STR_X(aPrd[nI], '_ITEMORI', 'num_ItemOri'), TamSx3("D1_ITEMORI")[1])*/

        cNotaOri := PadL(U_PI_STR_X(aPrd[nI], 'num_NFOrigem'), 9, '0')
        cSerieOri := U_PI_STR_X(aPrd[nI], 'cod_SerieOrigem')
        cItemOri := U_PI_STR_X(aPrd[nI], 'num_ProdutoSequencialOrigem')
		cChaveOri := U_PI_STR_X(aPrd[nI], 'cod_ChaveNFeOrigem')

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
        AAdd(aLin, {"D1_LOCAL", PadR(cValToChar(U_PI_LOCAL_X(cProdKey)), 2), Nil})
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
            cNumP := cValToChar(U_PI_VAL_X(oParcItem, 'num_Parcela')) 
            dVencP := U_PI_DATA_X(U_PI_STR_X(oParcItem, 'dta_ParcelaVencimento')) 
            nVlrP := U_PI_VAL_X(oParcItem, 'vlr_Parcela')
            
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
    aEx := U_PI_EXE103_X(aCab, aIt, cTipoDoc)


    // Restaura a trava de sistema
    PutMv("MV_PCNFE", cOldPcNfe)

    If aEx[1]
        aRet := {.T., cDoc,.T.}
        cUpdSF1 := "UPDATE " + RetSqlName("SF1") + " SET F1_COND = '" + cCondReal + "' WHERE F1_DOC = '" + cDocPad + "' AND F1_SERIE = '" + cSerPad + "' AND F1_FORNECE = '" + cCliPad + "' AND D_E_L_E_T_ = ' '"
        TCSqlExec(cUpdSF1)

        If !Empty(cNatJson)
            cNatReal := PadR(cNatJson, TamSx3("E2_NATUREZ")[1])
        Else
            cNatReal := PadR(U_PI_NAT_X(cCli, cLoja, oHead), TamSx3("E2_NATUREZ")[1])
        EndIf
        
        cHistPad := "API: Orig:" + U_PI_STR_X(oHead, "des_Origem") + " Aut:" + U_PI_STR_X(oHead, "des_Autorizacao") + " Trans:" + cTransacao

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
