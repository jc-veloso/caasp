#INCLUDE "TOTVS.CH"
#INCLUDE "FILEIO.CH"
#INCLUDE "PROTHEUS.CH"
#INCLUDE "FWMVCDEF.CH"
#INCLUDE "FINA914.CH"
#INCLUDE "TOPCONN.CH"

/*/
+==================================================================================================+
| Função      | ZAC_EEFI                                                                           |
|-------------+------------------------------------------------------------------------------------|
| Descrição   | Importação dos arquivos de pagamentos                                              |
|             |                                                                                    |
|             | REDECAR                                                                            |
|             | GETNET                                                                             |
|             |                                                                                    |
|-------------+------------------------------------------------------------------------------------|
| Ocorr?ncias                                                                                      |
|     JOL - 22/06/2026 - Criação da rotina a partir da derivação do fonte padr?o FINA914           |
|                                                                                                  |
+==================================================================================================+
/*/
USER FUNCTION EEFI_CRE()

	Local oDlgProc
	Local oBtnProc
	Local oBtnSair
	Local oSayFile

	Local oFont12  := TFont():New("Arial", , -12)
	Local oFont14  := TFont():New("Arial", , -14)

	Local cFile    := Space(100)
	Local dDataEff := dDataBase

	Local aEC := U_BuscaECFil()

	If Len(aEC) <= 0
		FWAlertInfo("Nenhuma EC e sua respectiva filial não foi encontrada.", "Estabelecimento Comercial")
		Return(Nil)
	EndIf

	//----- Form principal
	DEFINE MSDIALOG oDlgProc TITLE "Recebimento de Pagamentos via CRÉDITO" FROM 0, 0 TO 180, 720 PIXEL

	//----- Seleção do arquivo retorno
	@ 015, 010 SAY oSayFile PROMPT "Arquivo Retorno:" SIZE 100, 010 OF oDlgProc FONT oFont12 PIXEL

	@ 012, 110 GET oArq ;
		VAR cFile ;
		MULTILINE READONLY ;
		SIZE 250, 045 ;
		OF oDlgProc ;
		FONT oFont14 ;
		PIXEL

	@ 013, 060 BUTTON oBtnSel PROMPT "Buscar" ;
		ACTION (cFile := getArqRet(oArq), oArq:Refresh()) ;
		SIZE 040, 015 ;
		OF oDlgProc FONT oFont14 PIXEL

	//----- Data da baixa
	@ 068, 010 SAY "Data Baixa: " SIZE 55, 10 OF oDlgProc PIXEL FONT oFont12
	@ 065, 055 MSGET dDataEff PICTURE "@D" ;
		SIZE 055, 012 ;
		OF oDlgProc PIXEL FONT oFont14

	//----- Bot?o para o processamento
	@ 065, 235 BUTTON oBtnProc PROMPT "Processar" ;
		SIZE 040, 015 ;
		OF oDlgProc FONT oFont14 PIXEL ;
		ACTION ( If( Empty(AllTrim(cFile)), ;
		FWAlertInfo("Selecione um arquivo retorno.","Processamento Cancelado"), ;
		procE1_CRE(AllTrim(cFile), dDataEff, aEC) ) )

	//----- Bot?o para encerramento da rotina
	@ 065, 305 BUTTON oBtnSair PROMPT "Sair" ;
		SIZE 040, 015 ;
		OF oDlgProc FONT oFont14 PIXEL ;
		ACTION oDlgProc:End()

	ACTIVATE MsDialog oDlgProc CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Função      | getArqRet                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Seleção do arquivo retorno de pagmentos                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Ocorr?ncias                                                                                      |
	|                                                                                                  |
	|                                                                                                  |
	+==================================================================================================+
/*/
STATIC FUNCTION getArqRet(oGet)
	Local cFile := ""
	Local cMask := "RET (*.ret) |*.ret| CSV (*.csv) |*.csv| TXT (*.txt) |*.txt| TODOS (*.*) |*.*|"

	cFile := tFileDialog(cMask,"Selecione o arquivo de retorno",,,.F.)

Return cFile

/*/
	+==================================================================================================+
	| Função      | procE1_CRE                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Processamento do arquivo EEFI                                                      |
	| Descrição   | Processamento do arquivo EEFI                                                      |
	|-------------+------------------------------------------------------------------------------------|
	| Ocorr?ncias                                                                                      |
	|                                                                                                  |
	|                                                                                                  |
	+==================================================================================================+
/*/
STATIC FUNCTION procE1_CRE(cFile, dDataEff, aEC)

	Local nHandle	:= 0
	Local cCurrLine	:= ""
	Local nLinha	:= 0
	Local aBaixa    := {}
	Local nQtde     := 0
	Local nTotal    := 0
	Local nI        := 0
	Local cAliasQ   := GetNextAlias()
	Local oTempTable
	Local aFields   := {}

	//----- Verifica se o arquivo est? armazenado no disco
	If File(cFile) == .F.
		FWAlertError("Arquivo n?o localizado: " + cFile,"Arquivo de Pagamentos")
		Return NIL
	EndIf

	//----- Abertura do arquivo
	nHandle := FT_FUse(cFile)

	//----- Se houver erro de abertura abandona processamento
	If nHandle = -1
		FWAlertError("Erro ao abrir arquivo retorno: " + __arquivo,"Arquivo Retorno")
		Return {}
	EndIf

	//----- Leitura do arquivo
	FT_FGoTop()

	nLinha     := 0
	lValidaBco := .F.

	While !FT_FEOF()
		nLinha++

		cCurrLine := FT_FREADLN()

		If SubStr(cCurrLine,1,3) == '034'
			__ec     := SubStr(cCurrLine,004,009)
			__bco    := SubStr(cCurrLine,048,003)
			__agc    := Alltrim(Str(Val(SubStr(cCurrLine,051,006))))
			__cta    := Alltrim(Str(Val(SubStr(cCurrLine,057,010))))

			__filial := U_achaFilial(__ec, aEC)

			//----- Validação se conta bancária a crédito está no Protheus
			If lValidaBco == .F.
				lValidaBco := .T.
				lTemConta  := .F.

				DbSelectArea("SA6")
				DbSetOrder(1)
				DbGoTop()

				While SA6->(!Eof())
					If SA6->A6_COD == __bco
						If Val(SA6->A6_AGENCIA) == Val(__agc)
							If Val(SA6->A6_NUMCON) == Val(__cta)
								lTemConta := .T.
								Exit
							EndIf
						EndIf
					EndIf

					SA6->(DbSkip(1))
				EndDo

				If lTemConta == .F.
					FWAlertInfo("Conta bancária não cadastrada no Protheus.", "Processamento Cancelado")
					Return NIL
				EndIf
			EndIf

			__nsu    := SubStr(cCurrLine,013,011)
			__pv     := SubStr(cCurrLine,004,009)
			__rv     := SubStr(cCurrLine,076,009)
			__dtMvto := CtoD(SubStr(cCurrLine,068,002)+'/'+SubStr(cCurrLine,070,002)+'/'+SubStr(cCurrLine,072,004))
			__valor  := Val(SubStr(cCurrLine,095,015))/100

			nQtde  ++
			nTotal += __valor

			Aadd(aBaixa, {__nsu, __pv, __rv, __dtMvto, __valor, __filial})
		EndIf

		FT_FSKIP()
	EndDo

	FT_FUSE()

	If FWAlertYesNo("Iniciar o processamento dos recebimento?","Processamento de Recebimentos") == .F.
		Return NIL
	EndIf

	nQtdE1    := 0
	nValE1    := 0
	lProc     := .F.

	//----- Cria tabela temporária com NSU e Filial do vetor aBaixa
	AAdd(aFields, {"TMP_NSU",    "C", TamSX3("E1_NSUTEF")[1], 0})
	AAdd(aFields, {"TMP_FILIAL", "C", TamSX3("E1_FILIAL")[1], 0})

	oTempTable := FWTemporaryTable():New("TMP_BAIXA")
	oTempTable:SetFields(aFields)
	oTempTable:Create()

	//----- Insere dados do vetor na temporária
	For nI := 1 To Len(aBaixa)
		If !Empty(aBaixa[nI][1]) .And. !Empty(aBaixa[nI][6])
			RecLock("TMP_BAIXA", .T.)
			TMP_BAIXA->TMP_NSU    := aBaixa[nI][1]
			TMP_BAIXA->TMP_FILIAL := aBaixa[nI][6]
			MsUnlock()
		EndIf
	Next nI

	//----- Query com JOIN na tabela temporária — sem risco de limite de caracteres
	aBaixa := {}

	If TMP_BAIXA->(LastRec()) > 0
		cQuery := "SELECT SE1.E1_FILIAL,"
		cQuery += "       SE1.E1_NUM,"
		cQuery += "       SE1.E1_PREFIXO,"
		cQuery += "       SE1.E1_VALOR, "
		cQuery += "       SE1.E1_EMISSAO,"
		cQuery += "       SE1.E1_PARCELA,"
		cQuery += "       SE1.R_E_C_N_O_ AS REC, "
		cQuery += "       SE1.E1_TIPO,"
		cQuery += "       SE1.E1_CLIENTE,"
		cQuery += "       SE1.E1_LOJA "
		cQuery += "   FROM " + RetSqlName("SE1") + " SE1 "
		cQuery += "   INNER JOIN " + oTempTable:GetRealName() + " TMP ON SE1.E1_NSUTEF = TMP.TMP_NSU AND SE1.E1_FILIAL = TMP.TMP_FILIAL "
		cQuery += "   INNER JOIN " + RetSqlName("SZV") + " SZV ON SE1.E1_FILIAL = SZV.ZV_E1_FIL AND "
		cQuery += "                                            SE1.E1_NUM = SZV.ZV_E1_NUM AND "
		cQuery += "                                            SE1.E1_PREFIXO = SZV.ZV_E1_PREF AND "
		cQuery += "                                            SE1.E1_PARCELA = SZV.ZV_E1_PARC AND"
		cQuery += "                                            SE1.E1_TIPO = SZV.ZV_E1_TIPO  AND"
		cQuery += "                                            SZV.D_E_L_E_T_ = ' '"
		cQuery += "   WHERE SE1.D_E_L_E_T_ = ' '"

		cQuery := ChangeQuery(cQuery)

		dbUseArea(.T., "TOPCONN", TCGenQry(,, cQuery), cAliasQ, .T., .T.)

		While (cAliasQ)->(!Eof())
			nQtdE1++
			nValE1 += (cAliasQ)->E1_VALOR

			Aadd(aBaixa,;
				{(cAliasQ)->E1_FILIAL,;
				(cAliasQ)->E1_NUM,;
				(cAliasQ)->E1_PREFIXO,;
				(cAliasQ)->E1_VALOR,;
				(cAliasQ)->E1_EMISSAO,;
				(cAliasQ)->E1_PARCELA,;
				(cAliasQ)->E1_TIPO,;
				(cAliasQ)->E1_CLIENTE,;
				(cAliasQ)->E1_LOJA,;
				(cAliasQ)->REC})

			(cAliasQ)->(DbSkip())
		EndDo

		(cAliasQ)->(DbCloseArea())
	EndIf

	//----- Remove tabela temporária
	oTempTable:Delete()

	lProc := FWAlertYesNo("Baixas a serem processadas: " + Chr(13) + Chr(10) +;
		"Baixas no EEFI: " + Str(nQtde,5) +' Total R$ '+Transform(nTotal, '@E 999,999,999.99') + Chr(13) + Chr(10) +;
		"Baixas no SE1: " + Str(nQtdE1,5) +' Total R$ '+Transform(nValE1, '@E 999,999,999.99') + Chr(13) + Chr(10) +;
		"Diferenças: " + Str(nQtde-nQtdE1,5) +' Total R$ '+Transform(nTotal-nValE1, '@E 999,999,999.99') + Chr(13) + Chr(10), +;
		"Processamento dos Recebimentos")

	If lProc
		//----- marcar a venda como concluida
		//----- baixar o titulo SE1
		For nI := 1 To Len(aBaixa)
			DbSelectArea("SE1")
			DbSetOrder(1)
			DbGoTo(aBaixa[nI][10])

			_aCabec := {}

			Aadd(_aCabec, {"E1_FILIAL",    aBaixa[nI][1],   nil})
			Aadd(_aCabec, {"E1_PREFIXO",   aBaixa[nI][3],   nil})
			Aadd(_aCabec, {"E1_NUM",       aBaixa[nI][2],   nil})
			Aadd(_aCabec, {"E1_PARCELA",   aBaixa[nI][6],   nil})
			Aadd(_aCabec, {"E1_TIPO",      aBaixa[nI][7],   nil})
			Aadd(_aCabec, {"E1_CLIENTE",   aBaixa[nI][8],   nil})
			Aadd(_aCabec, {"E1_LOJA",      aBaixa[nI][9],   nil})
			AADD(_aCabec, {"AUTBANCO",     __bco,           nil})
			AADD(_aCabec, {"AUTAGENCIA",   __agc,           nil})
			AADD(_aCabec, {"AUTCONTA",     __cta,           nil})
			Aadd(_aCabec, {"AUTMOTBX",     "NOR",           nil})
			Aadd(_aCabec, {"AUTDTBAIXA",   dDataEff,        nil})
			Aadd(_aCabec, {"AUTDTCREDITO", dDataEff,        nil})
			Aadd(_aCabec, {"AUTHIST",      "BXEEFI " + aBaixa[nI][3] + "/" + aBaixa[nI][2], nil})
			Aadd(_aCabec, {"AUTVALREC",    aBaixa[nI][4],   nil})

			lMsErroAuto := .F.

			Begin Transaction
				MSExecAuto({|x,y| fina070(x,y)},_aCabec,3) //3-Inclusao
				IF lMsErroAuto
					DisarmTransaction()
					Break
				ELSE
					// sucesso
				ENDIF

				//----- Marca a venda com a baixa do título

				__update := "UPDATE "+RetSqlName('SZV')+" SET ZV_CHAVE = '04'"
				__update += "   WHERE ZV_E1_FIL = '"+aBaixa[nI][1]+"' AND"
				__update += "         ZV_E1_NUM = '"+aBaixa[nI][2]+"' AND"
				__update += "         ZV_E1_PREF = '"+aBaixa[nI][3]+"' AND"
				__update += "         ZV_E1_PARC = '"+aBaixa[nI][6]+"' AND"
				__update += "         ZV_E1_TIPO = '"+aBaixa[nI][7]+"'"
				TcSqlExec(__update)

				//----- Grava dados na tabela de LOG
				RecLock("SZL", .T.)
				ZL_FILIAL  := xFilial("SZL")
				ZL_USER    := RetCodUsr()
				ZL_DATA    := dDataBase
				ZL_HORA    := SubStr(Time(),1,5)
				ZL_TIPO    := 'BXCC'
				ZL_DESCRI  := 'Baixa via arquivo EEFI'
				ZL_RESUL1  := 'SZV'
				ZL_RESUL2  := 'Título SE1: '+aBaixa[nI][3]+'/'+aBaixa[nI][2]+'/'+aBaixa[nI][6]+'/'+aBaixa[nI][7]
				SZL->(MsUnlock())
			End Transaction

			IF lMsErroAuto
				MostraErro()
			ENDIF
		Next nI

		FWAlertSuccess('Baixas executados com sucesso','Baixas Contas a Receber')
	EndIf

Return NIL

// /*/
// 	+==================================================================================================+
// 	| Função      | procArqRet                                                                         |
// 	|-------------+------------------------------------------------------------------------------------|
// 	| Descrição   | Processamento do arquivo de pagamentos                                             |
// 	|-------------+------------------------------------------------------------------------------------|
// 	| Ocorr?ncias                                                                                      |
// 	|                                                                                                  |
// 	|                                                                                                  |
// 	+==================================================================================================+
// /*/
// STATIC FUNCTION procArqRet(cFile, dDataEff)

// 	Local lTem035		:= .F.
// 	Local nQtd035		:= 0
// 	Local nQtdSerasa	:= 0
// 	Local lFilEmp		:= .F.
// 	Local nLinTotal 	:= 0
// 	Local nQtdLida 		:= 0
// 	Local lLinOk		:= .F.
// 	Local nHandle		:= 0
// 	Local cCurrLine		:= ""
// 	Local cArqEEFI		:= ''
// 	Local aFields		:= {}
// 	Local aRegNProc		:= {}
// 	Local nLinha		:= 0

// 	//----- Verifica se o arquivo est? armazenado no disco
// 	If File(cFile) == .F.
// 		FWAlertError("Arquivo n?o localizado: " + cFile,"Arquivo de Pagamentos")
// 		Return NIL
// 	EndIf

// 	//----- Abertura do arquivo
// 	nHandle := FT_FUse(cFile)

// 	//----- Se houver erro de abertura abandona processamento
// 	If nHandle = -1
// 		FWAlertError("Erro ao abrir arquivo retorno: " + __arquivo,"Arquivo Retorno")
// 		Return {}
// 	EndIf

// 	//----- ARQUIVO TEMPORARIO PARA ARMAZENAMENTO DOS REGISTROS DO TIPO 035 (AJUSTES DE PAGAMENTOS)
// 	//----- Cria tabela tempor?ria no banco de dados
// 	cArqEEFI := GetNextAlias()
// 	aFields  := {}

// 	AAdd( aFields, { "CODEST",   "C", 9, 0 } )
// 	AAdd( aFields, { "FILIAL",   "C", 20, 0 } )
// 	AAdd( aFields, { "NURESU",   "C", 9, 0 } )
// 	AAdd( aFields, { "DTTEF",    "D", 8, 0 } )
// 	AAdd( aFields, { "NSUTEF",   "C", 12, 0 } )
// 	AAdd( aFields, { "NSUARQ",   "C", 12, 0 } )
// 	AAdd( aFields, { "NUCART",   "C", 16, 0 } )
// 	AAdd( aFields, { "CAPTUR",   "C", 1, 0 } )
// 	AAdd( aFields, { "VLR",      "C", TamSX3('FIF_VLBRUT')[1], TamSX3('FIF_VLBRUT')[2] } )
// 	AAdd( aFields, { "PARC"	,    "C", 3, 0 } )
// 	AAdd( aFields, { "NUMPV",    "C", 9, 0 } )
// 	AAdd( aFields, { "MOTAJUST", "C", 2, 0 } )
// 	AAdd( aFields, { "VLBRUT",   "C", TamSX3('FIF_VLBRUT')[1], TamSX3('FIF_VLBRUT')[2] } )
// 	AAdd( aFields, { "VLAJUST",  "C", TamSX3('FIF_VLBRUT')[1], TamSX3('FIF_VLBRUT')[2] } )
// 	AAdd( aFields, { "VLRTX",    "C", TamSX3('FIF_VLBRUT')[1], TamSX3('FIF_VLBRUT')[2] } )
// 	AAdd( aFields, { "VLRPARC",  "C", TamSX3('FIF_VLBRUT')[1], TamSX3('FIF_VLBRUT')[2] } )
// 	AAdd( aFields, { "VLRORIG",  "C", TamSX3('FIF_VLBRUT')[1], TamSX3('FIF_VLBRUT')[2] } )
// 	AAdd( aFields, { "STDCRED",  "C", 1, 0 } )

// 	__oFINA914 := FwTemporaryTable():New(cArqEEFI)
// 	__oFINA914:SetFields(aFields)
// 	__oFINA914:AddIndex("1", {"CODEST","DTTEF","NURESU"})
// 	__oFINA914:Create()

// 	//----- ARMAZENAMENTO DOS REGISTROS TIPO 035
// 	//----- Posiciona no topo do arquivo de pagamentos
// 	FT_FGoTop()

// 	While !FT_FEOF()
// 		lLinOk	:= !Empty(cCurrLine)

// 		If lLinOk .AND. SubStr(cCurrLine,1,3) == '035'
// 			nQtd035++

// 			(cArqEEFI)->(DbAppend())
// 			(cArqEEFI)->Filial	 := xFilial("FIF")
// 			(cArqEEFI)->CODEST	 := SubStr( cCurrLine, 4, 9 )

// 			//----- Chave entre registros 034 e 035
// 			(cArqEEFI)->NUMPV 	 := SubStr( cCurrLine, 04, 9 )
// 			(cArqEEFI)->NURESU	 := SubStr( cCurrLine, 13, 9 )
// 			(cArqEEFI)->DTTEF	 := CToD( SubStr( cCurrLine, 147, 2 ) + '/' + SubStr( cCurrLine, 149, 2 ) + '/' + SubStr( cCurrLine, 151, 04 ) )
// 			(cArqEEFI)->NSUTEF	 := PADR("", nTamNsu-len(Alltrim(SubStr(cCurrLine,093,006))),"0") + Alltrim(SubStr(cCurrLine,093,006))
// 			(cArqEEFI)->NSUARQ	 := SubStr(cCurrLine,093,006)
// 			(cArqEEFI)->NUCART	 := SubStr( cCurrLine, 76, 16 )
// 			(cArqEEFI)->CAPTUR	 := SubStr( cCurrLine, 257, 16 )

// 			//----- Motivo do ajuste
// 			(cArqEEFI)->MOTAJUST := SubStr( cCurrLine, 46, 2 )

// 			//----- Valores referente ao ajuste
// 			(cArqEEFI)->VLAJUST	 := SubStr(cCurrLine,30,15 )
// 			(cArqEEFI)->VLRTX	 := SubStr(cCurrLine,100,15 )
// 			(cArqEEFI)->VLRPARC	 := SubStr(cCurrLine,179,15 )
// 			(cArqEEFI)->VLRORIG	 := SubStr(cCurrLine,194,15 )
// 			(cArqEEFI)->VLBRUT	 := SubStr(cCurrLine,209,15 )
// 			(cArqEEFI)->VLRPARC	 := SubStr(cCurrLine,224,15 )
// 		EndIf

// 		FT_FSKIP()

// 		cCurrLine := FT_FREADLN()
// 	Enddo

// 	//----- Posiciona o arquivo no top para iniciar a leitura dos pagamentos
// 	FT_FGOTOP()

// 	While !FT_FEOF()
// 		nLinha++

// 		cCurrLine := FT_FREADLN()
// 		lLinOk    := !Empty(cCurrLine)
// 		cLinLog   := StrZero( nLinha, nTamLinha )

// 		If lLinOk  .AND. SubStr(cCurrLine,1,3) == '032'
// 			lLinOk := .F.
// 			nQtdLida++
// 		EndIf

// 		If lLinOk
// 			If SubStr(cCurrLine,1,3) == '030' .OR. SubStr(cCurrLine,1,3) == '052'
// 				nQtdLida++
// 			EndIf

// 			If SubStr(cCurrLine,1,3) <> '030' .and. SubStr(cCurrLine,1,3) <> '052'
// 				cCodEst := SubStr(cCurrLine,004,009)
// 				cCodFil := EC_Filial(cCodEst)

// 				If Empty(cCodEst)
// 					nQtdNProc++
// 					cCodEstab 	:= SubStr(cCurrLine,004,009)
// 					cNuComp 	:= SubStr(cCurrLine,013,11)
// 					cDescLeg    := 'Sem a informação do Estabelecimento Comercial'

// 					F914GrvLog('2',cIdProc,cLinLog,cNomArq,dDataIni,cHoraIni,cCodEstab,cNuComp,cDescLeg,"REDE",,,,@aCodEst,.T.,cCodFil)
// 				ElseIf Empty(cCodFil)
// 					nQtdNProc++
// 					cCodEstab 	:= SubStr(cCurrLine,004,009)
// 					cNuComp 	:= SubStr(cCurrLine,013,11)
// 					cDescLeg    := 'N?mero da filial n?o encontrado com base no Estabelecimento Comercial'

// 					F914GrvLog('2',cIdProc,cLinLog,cNomArq,dDataIni,cHoraIni,cCodEstab,cNuComp,cDescLeg,"REDE",,,,@aCodEst,.T.,cCodFil)
// 				Else
// 					//----- Ordem de Cr?dito
// 					If SubStr(cCurrLine,1,3) == '034'
// 						lTem035    := .F.
// 						cCodEst	   := SubStr(cCurrLine,04,9)
// 						dDtCredito := CtoD( SubStr( cCurrLine, 24, 2 ) + '/' + SubStr( cCurrLine, 26, 2 ) + '/' + SubStr( cCurrLine, 28, 04 ) )
// 						cNuresu	   := SubStr(cCurrLine,76,9)
// 						cParc 	   := StrZero(Val(SubStr(cCurrLine,125,2)),nTParc)

// 						//----- Verifica se o registro 034 possui algum ajuste 035
// 						(cArqEEFI)->( DbGoTop() )

// 						If (cArqEEFI)->(DbSeek(cCodEst + Dtos(dDtCredito) + cNuresu))
// 							lTem035 := .T.
// 						EndIf

// 						//---- Encontra o t?tulo na FIF referente ao registro 034
// 						cQuery := "SELECT FIF_FILIAL, FIF_CODEST, FIF_DTCRED, FIF_PARCEL, FIF_NURESU, FIF_NSUTEF "
// 						cQuery += "FROM " + AllTrim(RetSqlName("FIF")) + " FIF "
// 						cQuery += "WHERE FIF_FILIAL = '" + FWxFilial("FIF") + "'"

// 						cQuery += "AND FIF_CODEST = '" + cCodEst + "' "
// 						cQuery += "AND FIF_DTCRED = '" + Dtos(dDtCredito) + "' "
// 						cQuery += "AND FIF_NURESU = '" + cNuresu + "' "
// 						cQuery += "AND FIF_PARCEL = '" + cParc + "' "
// 						cQuery += "AND FIF_STATUS = ' ' "
// 						cQuery += "AND FIF_STVEND = '1' "
// 						cQuery += "AND FIF.D_E_L_E_T_ <> '*' "

// 						cQuery := ChangeQuery( cQuery )

// 						cAliasQry := GetNextAlias()
// 						dbUseArea( .T., "TOPCONN", TcGenQry(,,cQuery), cAliasQry, .F., .T. )

// 						// Valida atualização da FIF referente ao registro 034
// 						DbSelectArea("FIF")
// 						FIF->(DbSetOrder(6)) //FIF_CODFIL, FIF_DTCRED, FIF_NSUTEF, FIF_PARCEL
// 						If DbSeek(cCodFil + (cAliasQry)->FIF_DTCRED + (cAliasQry)->FIF_NSUTEF + (cAliasQry)->FIF_PARCEL )
// 							nQtdAlt++
// 							nQtdLida++
// 							RecLock( 'FIF', .F. )
// 							If lTem035
// 								FIF->FIF_STATUS	:= '1'
// 								FIF->FIF_TPREG	:= '3'
// 								FIF->FIF_CODMAJ := (cArqEEFI)->MOTAJUST
// 							Else
// 								FIF->FIF_STATUS	:= '1'
// 							Endif
// 							FIF->FIF_ARQPAG := aRede[nX][01]
// 							FIF->( MsUnlock() )

// 							cCodEstab 	:= cCodEst
// 							cNuComp 	:= SubStr(cCurrLine,013,11)
// 							cDescLeg 	:= "Registro alterado por motivo de ajuste"
// 							F914GrvLog('2',cIdProc,cLinLog,cNomArq,dDataIni,cHoraIni,cCodEstab,cNuComp,cDescLeg)
// 						Else
// 							nQtdNProc++
// 							cCodEstab 	:= cCodEst
// 							cNuComp 	:= SubStr(cCurrLine,013,11)
// 							cDescLeg 	:= 'Arquivo de pagamento/antecipação sem vendas localizadas - NuResu '+ cNuresu
// 							F914GrvLog('2',cIdProc,cLinLog,cNomArq,dDataIni,cHoraIni,cCodEstab,cNuComp,cDescLeg)
// 						EndIf
// 						(cAliasQry)->( dbCloseArea() )

// 						//Resumo Antecipado RAV
// 					ElseIf SubStr(cCurrLine,1,3) == '036'
// 						lTem035  := .F.
// 						cCodEst	 := SubStr(cCurrLine,04,9)
// 						dDataTef := CtoD( SubStr( cCurrLine, 24, 2 ) + '/' + SubStr( cCurrLine, 26, 2 ) + '/' + SubStr( cCurrLine, 28, 04 ) )
// 						dDataDeb := CtoD( SubStr( cCurrLine, 243, 2 ) + '/' + SubStr( cCurrLine, 245, 2 ) + '/' + SubStr( cCurrLine, 247, 04 ) )
// 						cNuresu	 := SubStr(cCurrLine,68,9)
// 						cNuComp  := PADR("", nTamNUCOMP - len(Alltrim(SubStr(cCurrLine,013,11))),'0') + Alltrim(SubStr(cCurrLine,013,11))

// 						aAdd( aBanco, SubStr(cCurrLine,048,003) ) // Banco
// 						aAdd( aBanco, SubStr(cCurrLine,051,006) ) // Ag?ncia
// 						aAdd( aBanco, SubStr(cCurrLine,057,011) ) // Conta

// 						cParcela := IiF(Val(SubStr(cCurrLine,108,2)) > 0, SubStr(cCurrLine,108,2), '1')
// 						cParcela := Padl(Val(cParcela),nTamParc,'0')

// 						//----- Verifica se o registro 036 possui algum ajuste 035
// 						(cArqEEFI)->( DbGoTop() )

// 						If (cArqEEFI)->(DbSeek(cCodEst + Dtos(dDataTef) + cNuresu))
// 							cNumCV  := (cArqEEFI)->NSUTEF
// 							cNSUARQ := (cArqEEFI)->NSUARQ
// 							lTem035 := .T.
// 						Else
// 							cNumCV  := ''
// 							cNSUARQ := ''
// 						Endif

// 						//----- Valida inclusao
// 						DbSelectArea("FIF")
// 						FIF->(DbSetOrder(6)) //FIF_CODFIL, FIF_DTCRED, FIF_NSUTEF, FIF_PARCEL
// 						If FIF->(DbSeek(cCodFil + DtoS(dDataDeb) + cNumCV  + cParcela))
// 							lContinua := .F.
// 						EndIf

// 						//----- Validação para verificar caracter especial na composição dos campos FIF_NSUTEF e FIF_NUCOMP
// 						lCarEsp := FINCARCESP(cNumCV,cNuComp,@lNsuTef,@lNuComp)

// 						If lContinua .And. !lCarEsp

// 							nQtdReg++
// 							nQtdLida++
// 							RecLock( 'FIF', .T. )
// 							FIF->FIF_FILIAL	:= xFilial("FIF")
// 							FIF->FIF_TPREG	:= '3'
// 							FIF->FIF_INTRAN := '0'
// 							FIF->FIF_CODEST := cCodEst
// 							FIF->FIF_DTTEF	:= dDataTef
// 							FIF->FIF_NURESU	:= cNuresu
// 							FIF->FIF_NUCOMP := cNuComp
// 							FIF->FIF_NSUTEF := cNumCV
// 							FIF->FIF_NUCART := If(lTem035,(cArqEEFI)->NUCART,'')
// 							FIF->FIF_CODBCO := aBanco[1]
// 							FIF->FIF_CODAGE := aBanco[2]
// 							FIF->FIF_NUMCC	:= aBanco[3]
// 							FIF->FIF_CODFIL := cCodFil
// 							FIF->FIF_CODBAN := SubStr(cCurrLine,152,1)
// 							FIF->FIF_SEQREG := PadL( Str( nQtdReg ), 6, '0' )
// 							FIF->FIF_DTIMP	:= dDataBase
// 							FIF->FIF_MSIMP	:= DtoS( dDataBase )
// 							FIF->FIF_SEQFIF	:= cSeqFIF
// 							FIF->FIF_STATUS	:= '1' // Ser? apresentado tanto na venda quanto no pagamento
// 							FIF->FIF_STVEND	:= '1'
// 							FIF->FIF_CODADM	:= cCodRede
// 							FIF->FIF_CODMAJ := If(lTem035,(cArqEEFI)->MOTAJUST,'')
// 							FIF->FIF_CODLOJ := cCodEst
// 							FIF->FIF_VLBRUT := IF(lTem035,Round( Val((cArqEEFI)->VLBRUT ) / 100, nTamVLBRUT ),Round( Val( SubStr(cCurrLine,113,15) ) / 100, nTamVLBRUT ))
// 							FIF->FIF_VLCOM 	:= Round( Val( SubStr(cCurrLine,128,15) ) / 100, nTamVLCOM )
// 							FIF->FIF_VLLIQ	:= IF(lTem035,Round( Val((cArqEEFI)->VLRORIG ) / 100, nTamVLBRUT ), FIF->FIF_VLBRUT - FIF->FIF_VLCOM)
// 							FIF->FIF_TXSERV	:= Round(( FIF->FIF_VLCOM / FIF->FIF_VLBRUT )  * 100, nTamTXSERV)
// 							FIF->FIF_TOTPAR := ""
// 							FIF->FIF_DTCRED := dDataDeb
// 							FIF->FIF_PARCEL := cParcela
// 							FIF->FIF_TPPROD := SubStr(cCurrLine,47,1)
// 							FIF->FIF_CAPTUR := ""
// 							FIF->FIF_CODRED := SubStr(cCurrLine,152,1)
// 							FIF->FIF_ARQPAG := aRede[nX][01]
// 							FIF->FIF_NSUARQ := cNSUARQ
// 							If __lAPixTpd
// 								FIF->FIF_MODPAG	:= '1' // 1-TEF / 2-Carteiras Digitais
// 							Endif

// 							FIF->( MsUnlock() )

// 							cSeqFIF := Soma1( cSeqFIF )
// 						Else

// 							If !lCarEsp
// 								cDescLeg := STR0052 +"036"+ STR0054 // "Registro "  //" J? importado anteriormente."
// 							else
// 								cDescLeg := STR0066
// 								lCarEsp  := .F.
// 							Endif

// 							F914GrvLog('2',cIdProc,cLinLog,cNomArq,dDataIni,cHoraIni,cCodEstab,Iif(lNsutef,cNumCV,cNuComp),cDescLeg,STR0012) // Grava detalhes do Log

// 							nQtdNProc++
// 							nQdtImp++
// 							lNsuTef  := .F.
// 							lNuComp  := .F.
// 						Endif

// 						aBanco := {}
// 						//Ajuste a D?bito
// 					ElseIf SubStr(cCurrLine,1,3) == '038'
// 						cCodEst	 := SubStr(cCurrLine,04,9)
// 						dDataTef := CtoD( SubStr( cCurrLine, 24, 2 ) + '/' + SubStr( cCurrLine, 26, 2 ) + '/' + SubStr( cCurrLine, 28, 04 ) )
// 						dDataDeb := CtoD( SubStr( cCurrLine, 243, 2 ) + '/' + SubStr( cCurrLine, 245, 2 ) + '/' + SubStr( cCurrLine, 247, 04 ) )
// 						cNumCV   := PADR("", nTamNsu - len(Alltrim(SubStr(cCurrLine,222,12))),"0") + Alltrim(SubStr(cCurrLine,222,12))
// 						cNSUARQ  := SubStr(cCurrLine,222,12)
// 						cParcela := PadL( '1', nTamParc, '0' )
// 						cNuComp  := PADR("", nTamNUCOMP - len(Alltrim(SubStr(cCurrLine,013,11))),'0') + Alltrim(SubStr(cCurrLine,013,11))

// 						aAdd( aBanco, SubStr(cCurrLine,048,003) ) // Banco
// 						aAdd( aBanco, SubStr(cCurrLine,051,006) ) // Ag?ncia
// 						aAdd( aBanco, SubStr(cCurrLine,057,011) ) // Conta

// 						// Valida inclusao
// 						DbSelectArea("FIF")
// 						FIF->(DbSetOrder(6)) //FIF_CODFIL, FIF_DTCRED, FIF_NSUTEF, FIF_PARCEL
// 						If FIF->(DbSeek(cCodFil + DtoS(dDataDeb) + cNumCV  + cParcela))
// 							lContinua := .F.
// 						EndIf

// 						// Validação para verificar caracter especial na composição dos campos FIF_NSUTEF e FIF_NUCOMP
// 						lCarEsp := FINCARCESP(cNumCV,cNuComp,@lNsuTef,@lNuComp)

// 						If lContinua .and. !lCarEsp

// 							nQtdReg++
// 							nQtdLida++
// 							RecLock( 'FIF', .T. )
// 							FIF->FIF_FILIAL	:= xFilial("FIF")
// 							FIF->FIF_TPREG	:= '3'
// 							FIF->FIF_INTRAN := '0'
// 							FIF->FIF_CODEST := cCodEst
// 							FIF->FIF_DTTEF	:= dDataTef
// 							FIF->FIF_NURESU	:= SubStr(cCurrLine,234,9)
// 							FIF->FIF_NUCOMP := cNuComp
// 							FIF->FIF_NSUTEF := cNumCV
// 							FIF->FIF_NUCART := SubStr(cCurrLine,130,16)
// 							FIF->FIF_VLBRUT := Round( Val( SubStr(cCurrLine,251,15) ) / 100, nTamVLBRUT )
// 							FIF->FIF_TOTPAR := ""
// 							FIF->FIF_VLLIQ	:= Round( Val( SubStr(cCurrLine,32,15) ) / 100, nTamVLBRUT )
// 							FIF->FIF_VLCOM 	:= FIF->FIF_VLBRUT - FIF->FIF_VLLIQ
// 							FIF->FIF_TXSERV	:= Round(( FIF->FIF_VLCOM / FIF->FIF_VLBRUT )  * 100, nTamTXSERV)
// 							FIF->FIF_DTCRED := dDataDeb
// 							FIF->FIF_PARCEL := cParcela
// 							FIF->FIF_TPPROD := "D"
// 							FIF->FIF_CAPTUR := ""
// 							FIF->FIF_CODRED := SubStr(cCurrLine,303,1)
// 							FIF->FIF_CODBCO := aBanco[1]
// 							FIF->FIF_CODAGE := aBanco[2]
// 							FIF->FIF_NUMCC	:= aBanco[3]
// 							FIF->FIF_SEQREG := PadL( Str( nQtdReg ), 6, '0' )
// 							FIF->FIF_DTIMP	:= dDataBase
// 							FIF->FIF_MSIMP	:= DtoS( dDataBase )
// 							FIF->FIF_CODFIL := cCodFil
// 							FIF->FIF_CODBAN := SubStr(cCurrLine,303,1)
// 							FIF->FIF_SEQFIF	:= cSeqFIF
// 							FIF->FIF_STATUS	:= '1' // Ser? apresentado tanto na venda quanto no pagamento
// 							FIF->FIF_STVEND	:= '1'
// 							FIF->FIF_CODADM	:= cCodRede
// 							FIF->FIF_CODMAJ := SubStr(cCurrLine,100,2)
// 							FIF->FIF_CODLOJ := cCodEst
// 							FIF->FIF_ARQPAG := aRede[nX][01]
// 							FIF->FIF_NSUARQ := cNSUARQ
// 							If __lAPixTpd
// 								FIF->FIF_MODPAG	:= '1' // 1-TEF / 2-Carteiras Digitais
// 							Endif

// 							FIF->( MsUnlock() )

// 							cSeqFIF := Soma1( cSeqFIF )
// 						Else

// 							If !lCarEsp
// 								cDescLeg := STR0052 +"038"+ STR0054 // "Registro "  //" J? importado anteriormente."
// 							else
// 								cDescLeg := STR0066
// 								lCarEsp  := .F.
// 							Endif

// 							F914GrvLog('2',cIdProc,cLinLog,cNomArq,dDataIni,cHoraIni,cCodEstab,Iif(lNsutef,cNumCV,cNuComp),cDescLeg,STR0012) // Grava detalhes do Log

// 							nQtdNProc++
// 							nQdtImp++
// 							lNsuTef  := .F.
// 							lNuComp  := .F.
// 						Endif

// 						aBanco := {}
// 						//Ajuste a Cr?dito
// 					ElseIf SubStr(cCurrLine,1,3) == '043'
// 						lTem035  := .F.
// 						cCodEst	 := SubStr(cCurrLine,04,9)
// 						dDataTef := CtoD( SubStr( cCurrLine, 33, 2 ) + '/' + SubStr( cCurrLine, 35, 2 ) + '/' + SubStr( cCurrLine, 37, 04 ) )
// 						dDataCre := CtoD( SubStr( cCurrLine, 41, 2 ) + '/' + SubStr( cCurrLine, 43, 2 ) + '/' + SubStr( cCurrLine, 45, 04 ) )
// 						cNuresu	 := SubStr(cCurrLine,13,9)
// 						cParcela := PadL( '1', nTamParc, '0' )
// 						cNuComp  := PADR("", nTamNUCOMP - len(Alltrim(SubStr(cCurrLine,022,11))),'0') + Alltrim(SubStr(cCurrLine,022,11))

// 						aAdd( aBanco, SubStr(cCurrLine,065,003) ) // Banco
// 						aAdd( aBanco, SubStr(cCurrLine,068,006) ) // Ag?ncia
// 						aAdd( aBanco, SubStr(cCurrLine,074,011) ) // Conta

// 						//Verifica se o registro 043 possui algum ajuste 035
// 						(cArqEEFI)->( DbGoTop() )

// 						If (cArqEEFI)->(DbSeek(cCodEst + Dtos(dDataCre) + cNuresu))
// 							lTem035 := .T.
// 							cNumCV  := (cArqEEFI)->NSUTEF
// 							cNSUARQ := (cArqEEFI)->NSUARQ
// 						Else
// 							cNumCV  := ''
// 							cNSUARQ := ''
// 						EndIf

// 						// Valida inclusao
// 						DbSelectArea("FIF")
// 						FIF->(DbSetOrder(6)) //FIF_CODFIL, FIF_DTCRED, FIF_NSUTEF, FIF_PARCEL
// 						If FIF->(DbSeek(cCodFil + DtoS(dDataDeb) + cNumCV  + cParcela))
// 							lContinua := .F.
// 						EndIf

// 						// Validação para verificar caracter especial na composição dos campos FIF_NSUTEF e FIF_NUCOMP
// 						lCarEsp := FINCARCESP(cNumCV,cNuComp,@lNsuTef,@lNuComp)

// 						If lContinua .And. !lCarEsp

// 							nQtdReg++
// 							nQtdLida++
// 							RecLock( 'FIF', .T. )
// 							FIF->FIF_FILIAL	:= xFilial("FIF")
// 							FIF->FIF_TPREG	:= '3'
// 							FIF->FIF_INTRAN := '0'
// 							FIF->FIF_CODEST := cCodEst
// 							FIF->FIF_DTTEF	:= dDataTef
// 							FIF->FIF_NURESU	:= SubStr(cCurrLine,13,9)
// 							FIF->FIF_NUCOMP := cNuComp
// 							FIF->FIF_NSUTEF := cNumCV
// 							FIF->FIF_NUCART := If(lTem035,(cArqEEFI)->NUCART,'')
// 							FIF->FIF_VLBRUT := IF(lTem035,Round( Val((cArqEEFI)->VLBRUT ) / 100, nTamVLBRUT ),Round( Val( SubStr(cCurrLine,49,15) ) / 100, nTamVLBRUT ))
// 							FIF->FIF_TOTPAR := ""
// 							FIF->FIF_VLLIQ	:= Round( Val((cArqEEFI)->VLRORIG ) / 100, nTamVLBRUT )
// 							FIF->FIF_VLCOM 	:= FIF->FIF_VLBRUT - FIF->FIF_VLLIQ
// 							FIF->FIF_TXSERV	:= Round(( FIF->FIF_VLCOM / FIF->FIF_VLBRUT )  * 100, nTamTXSERV)
// 							FIF->FIF_DTCRED := dDataCre
// 							FIF->FIF_PARCEL := cParcela
// 							FIF->FIF_TPPROD := "C"
// 							FIF->FIF_CAPTUR := ""
// 							FIF->FIF_CODRED := SubStr(cCurrLine,115,1)
// 							FIF->FIF_CODBCO := aBanco[1]
// 							FIF->FIF_CODAGE := aBanco[2]
// 							FIF->FIF_NUMCC	:= aBanco[3]
// 							FIF->FIF_SEQREG := PadL( Str( nQtdReg ), 6, '0' )
// 							FIF->FIF_DTIMP	:= dDataBase
// 							FIF->FIF_MSIMP	:= DtoS( dDataBase )
// 							FIF->FIF_CODFIL := cCodFil
// 							FIF->FIF_CODBAN := SubStr(cCurrLine,115,1)
// 							FIF->FIF_SEQFIF	:= cSeqFIF
// 							FIF->FIF_STATUS	:= '1' // Ser? apresentado tanto na venda quanto no pagamento
// 							FIF->FIF_STVEND	:= '1'
// 							FIF->FIF_CODADM	:= cCodRede
// 							FIF->FIF_CODMAJ := If(lTem035,(cArqEEFI)->MOTAJUST,'')
// 							FIF->FIF_CODLOJ := cCodEst
// 							FIF->FIF_ARQPAG := aRede[nX][01]
// 							FIF->FIF_NSUARQ := cNSUARQ
// 							If __lAPixTpd
// 								FIF->FIF_MODPAG	:= '1' // 1-TEF / 2-Carteiras Digitais
// 							Endif

// 							FIF->( MsUnlock() )

// 							cSeqFIF := Soma1( cSeqFIF )
// 						Else

// 							If !lCarEsp
// 								cDescLeg := STR0052 +"043"+ STR0054 // "Registro "  //" J? importado anteriormente."
// 							else
// 								cDescLeg := STR0066
// 								lCarEsp  := .F.
// 							Endif

// 							F914GrvLog('2',cIdProc,cLinLog,cNomArq,dDataIni,cHoraIni,cCodEstab,Iif(lNsutef,cNumCV,cNuComp),cDescLeg,STR0012) // Grava detalhes do Log

// 							nQtdNProc++
// 							nQdtImp++
// 							lNsuTef  := .F.
// 							lNuComp  := .F.
// 						Endif

// 						aBanco := {}
// 						//Consulta Serasa
// 					ElseIf SubStr(cCurrLine,1,3) == '040' .OR.  SubStr(cCurrLine,1,3) == '019'  // Consulta Serasa
// 						nRegNProc := AScan(aRegNProc, { |x| Upper(x[1]) == "REDE" .AND. x[2] == SubStr(cCurrLine,1,3) })

// 						If nRegNProc == 0
// 							cDescLeg  := STR0052 + SubStr(cCurrLine,1,3) + STR0053 // "Registro "  //" n?o ? processado pelo conciliador."
// 							cCodEstab := ""
// 							cNuComp   := ""
// 						Else
// 							cDescLeg  := STR0052 + SubStr(cCurrLine,1,3) + " - "+Alltrim(aRegNProc[nRegNProc][5]) + STR0053 // "Registro "  //" n?o ? processado pelo conciliador."
// 							cCodEstab := iIf(aRegNProc[nRegNProc][3] > 0,SubStr(cCurrLine,aRegNProc[nRegNProc][3],aRegNProc[nRegNProc][4]),"")
// 							cNuComp   := ""
// 						EndIf

// 						F914GrvLog('2',cIdProc,cLinLog,cNomArq,dDataIni,cHoraIni,cCodEstab,cNuComp,cDescLeg)

// 						nQtdNProc++
// 						nQtdSerasa++
// 					ElseIf !(SubStr(cCurrLine,1,3) $ "037/050")
// 						nRegNProc := AScan(aRegNProc, { |x| Upper(x[1]) == "REDE" .AND. x[2] == SubStr(cCurrLine,1,3) })

// 						If nRegNProc == 0
// 							cDescLeg  :=  STR0052 + SubStr(cCurrLine,1,3)+ STR0053 // "Registro "  //" n?o ? processado pelo conciliador."
// 							cCodEstab := ""
// 							cNuComp   := ""
// 						Else
// 							cDescLeg  := STR0052 + SubStr(cCurrLine,1,3)+" - "+Alltrim(aRegNProc[nRegNProc][5])+ STR0053 // "Registro "  //" n?o ? processado pelo conciliador."
// 							cCodEstab := iIf(aRegNProc[nRegNProc][3] > 0,SubStr(cCurrLine,aRegNProc[nRegNProc][3],aRegNProc[nRegNProc][4]),"")
// 							cNuComp   := ""
// 						EndIf

// 						F914GrvLog('2',cIdProc,cLinLog,cNomArq,dDataIni,cHoraIni,cCodEstab,cNuComp,cDescLeg)

// 						nQtdNProc++
// 					Else
// 						nQtdLida++
// 					EndIf
// 				EndIf
// 			EndIf
// 		EndIf
// 		FT_FSKIP()
// 		cCurrLine	:= FT_FREADLN()
// 	EndDo

// END TRANSACTION

// Else // Rever correto ? tipo de arquivo n?o importado
// 	//Erro na abertura do arquivo
// 	lErro 	 := .T.
// 	cStatus	 := "6" // 6="Arquivo n?o importado"
// 	cDescLeg :=  STR0049  //"Arquivo n?o importado"
// EndIf
// If cStatus <> "2"
// 	A914Status(@lErro, @cStatus, @cDescLeg, nQtdReg, nQtdNProc, nLinha, nQtdLida, nQdtImp, nQtdSerasa,nQtdAlt)
// EndIf
// Else
// 	//Erro na abertura do arquivo
// 	lErro    := .T.
// 	cStatus	 := "3" // 3="Falha na abertura do arquivo"
// 	cDescLeg := STR0029 //"Falha na abertura do arquivo"
// EndIf

// FT_FUSE()
// EndIf

/*/
	+==================================================================================================+
	| Função      | EC_Filial                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Busca o c?digo da filial que est? atrelado ao pagamento, utilizando o c?digo do    |
	|             | do estabelecimento e o par?metro MV_EMPTRED                                        |
	|-------------+------------------------------------------------------------------------------------|
	| Ocorr?ncias                                                                                      |
	|                                                                                                  |
	|                                                                                           ''     |
	+==================================================================================================+
/*/
STATIC FUNCTION EC_Filial(__codEst)

	Local __numFil  := ''
	Local cQuery	:= ''
	Local cAlias	:= GetNextAlias()

	cQuery := " SELECT X6_FIL"
	cQuery += " FROM " + RetSqlName("SX6")
	cQuery += " WHERE X6_VAR = 'MV_EMPTRED' AND"
	cQuery += "       X6_CONTEUD = '" + __codEst + "' AND"
	cQuery += "       D_E_L_E_T_ = ' ' "

	TcQuery cQuery NEW ALIAS (cAlias)

	While !(cAlias)->(Eof())
		__numFil := (cAlias)->X6_FIL

		(cAlias)->(DbSkip())
	EndDo

	(cAlias)->(DbCloseArea())

Return __numFil
