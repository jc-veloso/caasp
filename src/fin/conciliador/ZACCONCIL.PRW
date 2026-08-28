#INCLUDE "PROTHEUS.CH"
#INCLUDE "PARMTYPE.CH"
#INCLUDE "TOTVS.CH"
#INCLUDE "RPTDEF.CH"
#INCLUDE "TOPCONN.CH"

/*/
+==================================================================================================+
| Função      | ZACCONCIL                                                                          |
|-------------+------------------------------------------------------------------------------------|
| Descrição   | Motor de Conciliação POS ( sem NSU )                                               |
|             | Projeto CAASP                                                                      |
|             |                                                                                    |
|-------------+------------------------------------------------------------------------------------|
| OBSERVAÇÕES                                                                                      |
|                                                                                                  |
|                                                                                                  |
|                                                                                                  |
|--------------------------------------------------------------------------------------------------|
| Ocorrências                                                                                      |
|     JOL 25/04/2026 - Início da criação das funções                                               |
|     JOL 30/04/2026 - Baixa dos títulos do contas a receber                                       |
|     JOL 03/06/2026 - Revisão da leitura do arquivo de pagamentos com cartão de crédito           |
|                      No arquivo de pagamentos vem o parcelamento e precisa:                      |
|                      1) achar os títulos envolvidos no parcelamento                              |
|                      2) marcar os títulos com a informação do agendamento                        |
|                      3) no dia do crédito em conta corrente realizar a baixa do título           |
|                      4) não esquecer de ler o arquivo e verificar se houve cancelamento          |
|     JOL 04/07/2026 - Implementação da conciliação das vendas a crédito e depois a conciliação    |
|                      dos pagamentos                                                              |
+==================================================================================================+
/*/
USER FUNCTION ZACCONCIL()

	Local oDlg          := NIL
	Local oBtn1         := NIL
	Local oBtn2         := NIL
	Local oBtn3         := NIL
	Local oBtn4         := NIL
	Local oBtn5         := NIL
	Local oBtnSair      := NIL

	Local oFont13b   := TFont():New("Arial", , -13, .T.)
	Local oFont14b   := TFont():New("Arial", , -14, .T.)

	//----- Formulário
	DEFINE MSDIALOG oDlg TITLE "Conciliação das Vendas [POS]" FROM 000, 000 TO 590, 800 OF oMainWnd PIXEL

	@ 010, 130 SAY "SELEÇÃO DAS AÇÕES DA CONCILIAÇÃO" SIZE 380, 012 OF oDlg PIXEL FONT oFont13b

	//----- Separador
	@ 025, 010 TO 026, 390 OF oDlg PIXEL

	//----- Botões

	@ 050, 030 BUTTON oBtn1 PROMPT "Importar Vendas [Crédito]" SIZE 100, 30 OF oDlg ;
		ACTION {||impAdquire(1)};
		PIXEL FONT oFont14b

	@ 085, 030 BUTTON oBtn8 PROMPT "Baixar via Crédito" SIZE 100, 30 OF oDlg ;
		ACTION {|| U_EEFI_CRE() };
		PIXEL FONT oFont14b

	@ 050, 160 BUTTON oBtn2 PROMPT "Importar Vendas [Débito]" SIZE 100, 30 OF oDlg ;
		ACTION {||impAdquire(2)};
		PIXEL FONT oFont14b

	@ 085, 160 BUTTON oBtn7 PROMPT "Baixar via Débito" SIZE 100, 30 OF oDlg ;
		ACTION {|| U_EEFD_DEB() };
		PIXEL FONT oFont14b

	@ 050, 290 BUTTON oBtn3 PROMPT "Importar Vendas [PIX]" SIZE 100, 30 OF oDlg ;
		ACTION {||impAdquire(3)};
		PIXEL FONT oFont14b

	@ 085, 290 BUTTON oBtn9 PROMPT "Baixar via PIX" SIZE 100, 30 OF oDlg ;
		ACTION {|| U_BX_PIX() };
		PIXEL FONT oFont14b

	@ 155, 030 BUTTON oBtn4 PROMPT "Validar Vendas" SIZE 100, 30 OF oDlg ;
		ACTION {||U_ZACVALID()};
		PIXEL FONT oFont14b

	@ 155, 160 BUTTON oBtn5 PROMPT "Prestação de Contas" SIZE 100, 30 OF oDlg ;
		ACTION {|| U_ZACContas()};
		PIXEL FONT oFont14b

	@ 155, 290 BUTTON oBtn9 PROMPT "Visualização LOG" SIZE 100, 30 OF oDlg ;
		ACTION {|| U_ZACLOG()};
		PIXEL FONT oFont14b

	@ 200, 290 BUTTON oBtnSair PROMPT "Sair" SIZE 100, 30 OF oDlg ;
		ACTION { || oDlg:End() };
		PIXEL FONT oFont14b

	ACTIVATE MSDIALOG oDlg CENTERED

Return NIl

/*/
	+==================================================================================================+
	| Função      | impAdquire                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Importação dos movimentos existentes nos arquivos da RedeCar                       |
	|             |                                                                                    |
	|-------------+------------------------------------------------------------------------------------|
	| Parâmetros  | 1) acao: 1-Importação das vendas a Crédito                                         |
	|             |          2-Importação das vendas a Débito                                          |
	|             |          3-Importação das vendas via PIX                                           |
	|-------------+------------------------------------------------------------------------------------|
	| Ocorrências                                                                                      |
	|                                                                                                  |
	+==================================================================================================+
/*/
STATIC FUNCTION impAdquire(acao)

	Local oDlgProc
	Local oBrwFiles

	Local oFont12  := TFont():New("Arial", , -12)
	Local oFont14  := TFont():New("Arial", , -14)
	Local oFont14b := TFont():New("Arial", , -14, .T.)

	Local cTxtForm  := ''
	Local cTxtLabel := ''
	Local cMask     := "RET (*.ret) |*.ret| CSV (*.csv) |*.csv| TXT (*.txt) |*.txt| TODOS (*.*) |*.*|"
	Local cFile     := ''

	Local aFiles    := {}

	If acao==1
		cTxtForm  := 'Importação de Vendas [Crédito]'
		cTxtLabel := 'Selecione os arquivos de vendas a Crédito'
	ElseIf acao==2
		cTxtForm  := 'Importação de Vendas [Débito]'
		cTxtLabel := 'Selecione o arquivo de vendas a Débito'
	ElseIf acao==3
		cTxtForm  := 'Importação de Vendas [PIX]'
		cTxtLabel := 'Selecione os arquivos de PIX'
	EndIf

	//----- Form principal
	DEFINE MSDIALOG oDlgProc TITLE cTxtForm FROM 0, 0 TO 450, 920 PIXEL

	@ 006, 010 SAY cTxtLabel SIZE 400, 010 Of oDlgProc FONT oFont14b Pixel

	//----- Browse de arquivos selecionados
	oBrwFiles := TWBrowse():New(022, 010, 450, 150,, {"Arquivo"}, {480}, oDlgProc,,,,,,,,,,,,.T.,,.T.,,.T.,,,)
	oBrwFiles:SetArray(aFiles)
	oBrwFiles:bLine := {|| If(Len(aFiles)>0, {aFiles[oBrwFiles:nAt, 1]}, {""}) }
	oBrwFiles:oFont := oFont12

	//----- Botões
	@ 190, 010 BUTTON "Buscar" SIZE 50, 16 ;
		ACTION (cFile := tFileDialog(cMask, "Selecione o arquivo",,,.F.),;
		Iif(!Empty(cFile), (AAdd(aFiles, cFile), oBrwFiles:SetArray(aFiles),;
		oBrwFiles:GoBottom(), oBrwFiles:Refresh()), NIL)) ;
		OF oDlgProc FONT oFont14 PIXEL

	@ 190, 080 BUTTON "Remover" SIZE 50, 16 ;
		ACTION (Iif(Len(aFiles)>0,;
		(ADel(aFiles, oBrwFiles:nAt), ASize(aFiles, Len(aFiles)-1),;
		oBrwFiles:SetArray(aFiles),;
		Iif(oBrwFiles:nAt > Len(aFiles) .AND. Len(aFiles) > 0, oBrwFiles:nAt := Len(aFiles), NIL),;
		oBrwFiles:Refresh()), NIL)) ;
		OF oDlgProc FONT oFont14 PIXEL

	@ 190, 150 BUTTON "Processar" SIZE 60, 16 ;
		ACTION (Iif(Len(aFiles)<=0,;
		FWAlertInfo("Selecione ao menos um arquivo.","Processamento Cancelado"),;
		procFiles(aFiles, acao, oDlgProc))) ;
		OF oDlgProc FONT oFont14 PIXEL

	@ 190, 225 BUTTON "Sair" SIZE 50, 16 ;
		ACTION oDlgProc:End() ;
		OF oDlgProc FONT oFont14 PIXEL

	ACTIVATE MsDialog oDlgProc CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Função      | procFiles                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Processa os arquivos selecionados e acumula resultados                             |
	+==================================================================================================+
/*/
STATIC FUNCTION procFiles(aFiles, acao, oDlgProc)

	Local nI       := 0
	Local cFile    := ''
	Local cNomeArq := ''
	Local cTipoArq := ''

	Local aVendas  := {}
	Local aPIX     := {}

	Local aEC := U_BuscaECFil()

	If Len(aEC) <= 0
		FWAlertInfo("Nenhuma EC e sua respectiva filial não foi encontrada.", "Estabelecimento Comercial")
		Return(Nil)
	EndIf

	ProcRegua(Len(aFiles))

	For nI := 1 To Len(aFiles)
		IncProc("Processando o arquivo " + AllTrim(Str(nI)) + "/" + AllTrim(Str(Len(aFiles))))

		cFile    := aFiles[nI]
		cNomeArq := SubStr(cFile, RAt("\", cFile)+1)
		cTipoArq := SubStr(cNomeArq, 4, 1)

		If acao == 1
			//----- Valida o tipo do arquivo
			If cTipoArq <> "C"
				FWAlertError("Arquivo " + cNomeArq + " não é  compatível com vendas (Crédito).", "Arquivo Retorno")
				Loop
			EndIf

			//----- Leitura do arquivo de vendas
			LerArqCred(@aVendas, cFile, aEC)

		ElseIf acao == 2
			//----- Valida o tipo do arquivo
			If cTipoArq <> "D"
				FWAlertError("Arquivo " + cNomeArq + " não é  compatível com vendas (Débito).", "Arquivo Retorno")
				Loop
			EndIf

			//----- Leitura do arquivo de vendas
			LerArqDeb(@aVendas, cFile, aEC)

		ElseIf acao == 3
			//----- Valida o tipo do arquivo
			If SubStr(cNomeArq, 1, 3) <> 'PPI'
				FWAlertError("Arquivo " + cNomeArq + " não é  compatível com PIX.", "Pagamentos via PIX")
				Loop
			EndIf

			//----- Leitura do arquivo de PIX
			U_LerArqPIX(@aPIX, cFile)

		EndIf
	Next nI

	//----- Apresenta as vendas após leitura do arquido da adquirente
	If acao==1 .OR. acao==2
		If Len(aVendas) > 0
			ShowVendas(aVendas, acao)
		EndIf
	Else
		If Len(aPIX) > 0
			U_ShowPIX(aPIX)
		EndIf
	EndIf


Return NIL

/*/
	+==================================================================================================+
	| Função      | getArqRet                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Seleção do arquivo o retorno das vendas                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Ocorrências                                                                                      |
	|     JOL - 30/04/2026 - Início da criação das funções                                             |
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
	| Função      | procArqRet                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descriação  | Processamento do arquivo retorno                                                   |
	|-------------+------------------------------------------------------------------------------------|
	| Parâmetro   | 1) - arquivo a ser processado                                                      |
	|             | 2) - data da efetivação da venda                                                   |
	|             | 3) - acao: 1-importação de vendas                                                  |
	|             |            2-importação dos pagamentos e conciliação com as vendas validadas       |
	|             |            3-importação de PIX                                                     |
	|-------------+------------------------------------------------------------------------------------|
	| Ocorrências                                                                                      |
	|     JOL - 25/04/2026 - Início da criação das funções                                             |
	|                                                                                                  |
	+==================================================================================================+
/*/
STATIC FUNCTION procArqRet(cFile, dDataEff, acao)

	Local aArquivo  := {}
	Local cTipoArq  := ''
	Local cNomeArq	:= ''

	Local nI		:= 0
	Local nJ		:= 0
	Local nK	    := 0
	Local nRegs		:= 0
	Local lProc		:= .F.
	Local lAchou	:= .F.

	Local aEC		:= {}
	Local aPgtos	:= {}
	Local aContas	:= {}
	Local cComercio := ''

	Local aTitulos  := {}
	Local aRetorno  := {}

	Local dCredito  := CtoD('//')
	Local dPgto     := CtoD('//')
	Local dVenda    := CtoD('//')
	Local nValPDV   := 0
	Local nValTaxa	:= 0
	Local nValLiq	:= 0
	Local cIdPdv    := ''
	Local cAutoriza := ''

	Local nBanco	:= 0
	Local nAgencia	:= 0
	Local nConta	:= 0
	Local nDigito	:= 0

	Local cMsgAlerta := ''

	If acao == 1
		cMsgAlerta := "Importação de Vendas [Crédito]
	ElseIf acao == 2
		cMsgAlerta := "Importação de Vendas [Débito]
	ElseIf acao == 3
		cMsgAlerta := "Importação de Vendas [PIX]
	Else
		cMsgAlerta := ''
	EndIf

	//--------------------------------------------------------------------------------------------
	// Estrutura do vetor aPgtos
	//--------------------------------------------------------------------------------------------
	// 01 - numero da filial
	// 02 - nome da filial
	// 03 - data da venda
	// 04 - data do pagamento
	// 05 - valor do pagamento
	// 06 - EC
	// 07 - Autorização
	// 08 - PDV
	// 09 - Tipo de arquivo = C (crédito) ou D (débito)
	// 10 - Banco
	// 11 - Agência
	// 12 - conta corrente
	// 13 - digito da conta corrente
	// 14 - prefixo do titulo do E1
	// 15 - numero do titulo do E1
	// 16 - parcela do titulo do E1
	// 17 - codigo da pessoa do titulo do E1
	// 18 - codigo da loja do cliente no titulo do E1
	// 19 - número do registro no E1
	// 20 - numero da linha no arquivo de retorno
	// 21 - valor da taxa
	// 22 - valor liquido
	// 23 - data do credito em conta corrente
	// 24 -
	// 25 -
	// 26 -
	//--------------------------------------------------------------------------------------------
	//----- Guarda as filiais e os ECs existentes nos parâmetros
	aEC := U_BuscaECFil()

	If Len(aEC) <= 0
		FWAlertInfo("Nenhuma EC e sua respectiva filial não foi encontrada.", cMsgAlerta)
		Return(Nil)
	EndIf

	// //----- Guarda as contas bancárias para validação dos dados bancários existentes no arquivo retorno
	// aContas := BuscaCC()

	// If Len(aContas) <= 0
	// 	FWAlertInfo("Nenhuma conta bancária foi encontrada.", cMsgAlerta)
	// 	Return(Nil)
	// EndIf

	//----- Verifica o tipo de arquivo => "C" ou "R"
	aArquivo := StrTokArr2(cFile, "\", .T.)
	cNomeArq := aArquivo[Len(aArquivo)]
	cTipoArq := SubStr(cNomeArq, 4, 1)

	//----- Validação da ação solicitada pelo usuário com o arquivo selecionado
	//----- IMPORTAçãO DAS VENDAS
	If acao==1
		If cTipoArq=="D"
			FWAlertError("Ação solicitada e arquivo indicado não são compatíveis.", cMsgAlerta)
			Return NIL
		EndIf

		//----- leitura do arquivo de crédito
		If cTipoArq=="C"
			aPgtos := LerArqVend(cFile, acao, aEC)
		EndIf

		If Len(aPgtos) <= 0
			FWAlertInfo("Nenhuma venda foi encontrada no arquivo retorno.", cMsgAlerta)
			Return(Nil)
		EndIf

	ElseIf acao == 2
		// //----- CONCILIAçãO FINANCEIRA
		// //----- leitura do arquivo de débito
		// If cTipoArq== "D"
		// 	aPgtos := LerArqDeb(cFile)
		// EndIf
		// //----- leitura do arquivo de crédito
		// If cTipoArq=="C"
		// 	aPgtos := LerArqCred(cFile)
		// EndIf

		// If Len(aPgtos) <= 0
		// 	FWAlertInfo("Nenhum pagamento via POS foi encontrado no arquivo retorno.","Conciliação Vendas POS")
		// 	Return(Nil)
		// EndIf
	ElseIf acao == 3
		//----- IMPORTAçãO DE PAGAMENTOS PIX
		If SubStr(cNomeArq,1,3) <> 'PPI'
			FWAlertError("Ação solicitada e arquivo indicado não são compatíveis.","Pagamentos via PIX")
			Return NIL
		EndIf

		//----- leitura do arquivo de crédito
		If SubStr(cNomeArq,1,3) == 'PPI'
			aPgtos := LerArqPIX(cFile)
		EndIf

		If Len(aPgtos) <= 0
			FWAlertInfo("Nenhum pagamento via PIX foi encontrada no arquivo retorno.","Pagamentos via PIX")
			Return(Nil)
		EndIf

		ShowPIX(aPgtos)
	EndIf

	If acao==1
		//----- PROCESSAMENTO DAS VENDAS ENCONTRADAS

	ElseIf acao==2
		//----- PROCESSAMENTO DOS PAGAMENTOS ENCONTRADOS

		For nI := 1 To Len(aPgtos)
			cComercio := aPgtos[nI][6]

			For nJ := 1 To Len(aEC)
				If AllTrim(aEC[nJ][5]) == AllTrim(cComercio)
					//----- Marca a EC como utilizada na conciliação durante o processo da baixa
					aEC[nJ][01] := 'X'

					//----- Guarda o EC e a filial no controle de pagamentos
					aPgtos[nI][01] := aEC[nJ][03] // Filial
					aPgtos[nI][02] := aEC[nJ][04] // Nome da filial

					Exit
				EndIf
			Next nJ
		Next nI

		//--------------------------------------------------------------------------------------------
		// Valida se algum pagamento não tem EC, filial ou conta bancaria válida
		//--------------------------------------------------------------------------------------------
		lProc := .T.

		For nI := 1 To Len(aPgtos)
			If Val(aPgtos[nI][1]) == 0
				FWAlertError("Filial não identificada para o pagamento na linha: " + AllTrim(Str(aPgtos[nI][20])) + ".","Conciliação Vendas POS")
				lProc := .F.
			EndIf
			If Val(aPgtos[nI][6]) == 0
				FWAlertError("EC (estabelecimento comercial) não identificado para o pagamento na linha: " + AllTrim(Str(aPgtos[nI][20])) + ".","Conciliação Vendas POS")
				lProc := .F.
			EndIf
			If Val(aPgtos[nI][10]) == 0 .OR. Val(aPgtos[nI][11]) == 0 .OR. Val(aPgtos[nI][12]) == 0
				FWAlertError("Dados bancários não identificados para o pagamento na linha: " + AllTrim(Str(aPgtos[nI][20])) + ".","Conciliação Vendas POS")
				lProc := .F.
			EndIf

			nBanco   := Val(aPgtos[nI][10])
			nAgencia := Val(aPgtos[nI][11])
			nConta   := Val(aPgtos[nI][12])
			nDigito  := Val(aPgtos[nI][13])
			lAchou   := .F.

			For nJ:=1 To Len(aContas)
				If Val(aContas[nJ][2])==nBanco .AND. Val(aContas[nJ][3])==nAgencia .AND. Val(aContas[nJ][4])==nConta .AND. Val(aContas[nJ][5])==nDigito
					lAchou := .T.
					Exit
				EndIf
			Next nJ

			If lAchou == .F.
				FWAlertError("Os dados bancários existente na linha: " + AllTrim(Str(aPgtos[nI][20])) + " não foi localizada no cadastro de contas bancárias.","Conciliação Vendas POS")
				lProc := .F.
			EndIf
		Next nI

		If lProc == .F.
			Return(Nil)
		EndIf

		//--------------------------------------------------------------------------------------------
		// Cruza os pagamentos do aquivo retorno com os registros no contas a receber (E1)
		//--------------------------------------------------------------------------------------------
		aRetorno := BuscaSE1(aPgtos)

		For nI := 1 To Len(aPgtos)
			cNumFilial	:= aPgtos[nI][01]

			dCredito    := aPgtos[nI][23]
			dPgto       := aPgtos[nI][04]
			dVenda   	:= aPgtos[nI][03]
			cIdPdv		:= aPgtos[nI][08]

			nValPDV		:= aPgtos[nI][05]
			nValTaxa	:= aPgtos[nI][21]
			nValLiq		:= aPgtos[nI][22]

			cAutoriza	:= aPgtos[nI][07]
			cComercio	:= aPgtos[nI][06]

			cBanco   	:= aPgtos[nI][10]
			cAgencia 	:= aPgtos[nI][11]
			cConta   	:= aPgtos[nI][12]

			lAchou      := .F.

			For nJ:=1 To Len(aRetorno)
				If ValType(aRetorno[nJ][10])=='C'
					cCompData := Ctod(SubStr(aRetorno[nJ][10],7,2)+'/'+SubStr(aRetorno[nJ][10],5,2)+'/'+SubStr(aRetorno[nJ][10],1,4))
				Else
					cCompData := aRetorno[nJ][10]
				EndIf

				aRetorno[nJ][10] := cCompData

				If AllTrim(cNumFilial)==AllTrim(aRetorno[nJ][1]) .AND. dVenda==aRetorno[nJ][10] .AND. nValPDV==aRetorno[nJ][4]
					lAchou := .T.

					Aadd(aTitulos,;
						{'X',;
						cIdPdv,;
						dVenda,;
						nValPDV,;
						cAutoriza,;
						cComercio,;
						aPgtos[nI][01]+'-'+aPgtos[nI][02],;
						aRetorno[nJ][2],;
						aRetorno[nJ][3],;
						aRetorno[nJ][4],;
						aRetorno[nJ][5],;
						aRetorno[nJ][6],;
						aRetorno[nJ][7],;
						aRetorno[nJ][8],;
						aRetorno[nJ][9],;
						'BX ARQ RET DEB: '+Dtoc(dVenda),;
						dPgto,;
						dCredito,;
						nValTaxa,;
						nValLiq,;
						cBanco,;
						cAgencia,;
						cConta})
				EndIf
			Next nJ

			If lAchou == .F.
				Aadd(aTitulos,;
					{' ',;
					cIdPdv,;
					dVenda,;
					nValPDV,;
					cAutoriza,;
					cComercio,;
					aPgtos[nI][01]+'-'+aPgtos[nI][02],;
					'',;
					'',;
					0,;
					0,;
					'',;
					'',;
					'',;
					0,;
					'Não localizado ou já baixado',;
					dPgto,;
					dCredito,;
					nValTaxa,;
					nValLiq,;
					cBanco,;
					cAgencia,;
					cConta})
			EndIf
		Next nI

		//--------------------------------------------------------------------------------------------
		// Análise dos registros para verificar se há dupla/tripla seleção
		//--------------------------------------------------------------------------------------------
		nChave := 0

		For nI:=1 To Len(aTitulos)
			nChave := aTitulos[nI][15]
			nRegs  := 0

			For nJ:=1 To Len(aTitulos)
				If aTitulos[nJ][01]=='X'
					If nChave == aTitulos[nJ][15]
						nRegs++
					EndIf
				EndIf
			Next nJ

			If nRegs >= 2
				For nK := 1 To Len(aTitulos)
					If aTitulos[nK][01] == "X"
						If aTitulos[nK][15] == nChave
							aTitulos[nK][01] := " "
							aTitulos[nK][16] := "Registros com múltiplas seleções"
						EndIf
					EndIf
				Next nK
			EndIf
		Next nI

		ShowParcs(aTitulos, dDataEff, cNomeArq)
	EndIf

Return NIL

/*/
	+==================================================================================================+
	| Função      | ShowParcs                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Mostra os pagamentos encontrados no arquivo retorno e na tabela dos contas a       |
	|             | a receber (SE1)                                                                    |
	+==================================================================================================+
/*/
STATIC FUNCTION ShowParcs(aDados, dDataEff, cNomeArq)
	Local oDlg
	Local oBrw

	Local oFont     := TFont():New("Arial",, -12,, .F.)
	Local oFont14   := TFont():New("Arial",, -14,, .F.)
	Local oFont14n  := TFont():New("Arial",, -14,, .T.)
	Local oFont16n  := TFont():New("Arial",, -16,, .T.)

	Local aHeader	:= {}
	Local aSizeAut	:= MsAdvSize()

	Local nPos      := 0
	Local nI		:= 0
	Local aRodape	:= {}
	Local lSel 		:= .F.

	Local nTotPgtos := 0
	Local nValPgtos := 0
	Local nTotEncon := 0
	Local nValEncon := 0

	For nI:=1 To Len(aDados)
		cNumFil := aDados[nI][7]
		nValPDV := aDados[nI][4]
		cMarca  := aDados[nI][1]

		nTotPgtos ++
		nValPgtos += nValPDV

		If cMarca == 'X'
			nTotEncon ++
			nValEncon += nValPDV
		EndIf

		nPos := aScan(aRodape,{|x| x[2]==cNumFil})

		If nPos == 0
			lSel := Iif(If(cMarca=='X',1,0) > 0, .T., .F.)

			AAdd(aRodape,{lSel, cNumFil, nValPDV, 1, Iif(cMarca=='X', nValPDV, 0), Iif(cMarca=='X', 1, 0)})
		Else
			// indices: 1=Sel, 2=Filial, 3=R$ Pgtos, 4=Qtde Pgtos, 5=R$ Encontrados, 6=Qtde Encontrados
			aRodape[nPos][3] += nValPDV
			aRodape[nPos][4] ++
			If cMarca == 'X'
				aRodape[nPos][5] += nValPDV
				aRodape[nPos][6] ++
				// marca como selecionada se houver encontrados
				aRodape[nPos][1] := .T.
			EndIf
		EndIf
	Next nI

	If Len(aDados) >= 1
		//==================================================================================================================
		//
		// Formulario do totalizador
		//
		//==================================================================================================================
		DEFINE MSDIALOG oDlg TITLE "Conciliação dos Pagamentos POS - Efetivação: " + DtoC(dDataEff);
			FROM aSizeAut[7],000 TO aSizeAut[6],aSizeAut[5] FONT oFont PIXEL

		@ 006, 010 SAY "LISTA DE PAGAMENTOS:" SIZE 100,10 OF oDlg PIXEL FONT oFont16n COLORS(RGB(0,34,51))
		@ 006, 550 SAY "TOTAL POR FILIAL:" SIZE 100,10 OF oDlg PIXEL FONT oFont16n COLORS(RGB(0,34,51))

		//------------------------------------------------------------------------------------------------------------------
		// Browse dos pagamentos
		//------------------------------------------------------------------------------------------------------------------
		aHeader := {"Sel", "Filial","Dt Venda", "R$ Venda", "EC", "PDV", "Autorização", "Cliente", "Registro CR","Observações"}
		aSize   := {15, 40, 60, 60, 60, 50, 50, 60,80}

		oBrw := TWBrowse():New(015, 010, 500, 350,,;
			aHeader,;
			aSize, oDlg,,,,,,,,,,,,.T.,,.T.,,.T.,,,)

		oBrw:SetArray(aDados)

		oBrw:bLine := {||{;
			aDados[oBrw:nAt, 1],;
			aDados[oBrw:nAt, 7],;
			DtoC(aDados[oBrw:nAt, 3]),;
			Transform(aDados[oBrw:nAt, 4], "@E 999,999,999.99"),;
			aDados[oBrw:nAt, 6],;
			aDados[oBrw:nAt, 2],;
			aDados[oBrw:nAt, 5],;
			aDados[oBrw:nAt, 14],;
			Transform(aDados[oBrw:nAt,15], "9999999999"),;
			aDados[oBrw:nAt,16],;
			}}

		oBrw:oFont := oFont
		oBrw:Refresh()

		//------------------------------------------------------------------------------------------------------------------
		// Browse da totalização por filial
		//------------------------------------------------------------------------------------------------------------------
		aHeader := {"Sel","Filial","R$ Pgtos", "Qtde Pgtos", "R$ Encontrados", "Qtde Encontrados"}
		aSize   := {10,50, 60, 60, 60, 60}

		oBrwQt := TWBrowse():New(020, 575, 300, 350,,;
			aHeader,;
			aSize, oDlg,,,,,,,,,,,,.T.,,.T.,,.T.,,,)

		oBrwQt:SetArray(aRodape)

		oBrwQt:bLine := {|| If(Len(aRodape)>0,;
			{Iif(aRodape[oBrwQt:nAt,1], "[X]", "[ ]"),;
			aRodape[oBrwQt:nAt,2],;
			Transform(aRodape[oBrwQt:nAt,3], "@E 999,999,999.99"),;
			Transform(aRodape[oBrwQt:nAt,4], "999999"),;
			Transform(aRodape[oBrwQt:nAt,5], "@E 999,999,999.99"),;
			Transform(aRodape[oBrwQt:nAt,6], "999999")},;
			{"","","","","",""}) }

		oBrwQt:bLDblClick := {|| (aRodape[oBrwQt:nAt,1] := !aRodape[oBrwQt:nAt,1], oBrwQt:Refresh())}
		oBrwQt:bKeyDown   := {|nKey| If(nKey == 32, aRodape[oBrwQt:nAt,1] := !aRodape[oBrwQt:nAt,1], oBrwQt:Refresh())}

		oBrwQt:oFont := oFont
		oBrwQt:Refresh()

		//----- Totalizadores
		@ 380, 055 SAY "Qtd Pagamentos:" SIZE 55, 10 OF oDlg PIXEL FONT oFont14
		@ 375, 110 MSGET nTotPgtos PICTURE "999999 " SIZE 65, 12 OF oDlg PIXEL FONT oFont14n When .F.

		@ 380, 250 SAY "R$ Pagamentos:" SIZE 55, 10 OF oDlg PIXEL FONT oFont14
		@ 375, 305 MSGET nValPgtos PICTURE "@E 999,999,999.99" SIZE 65, 12 OF oDlg PIXEL FONT oFont14n When .F.

		@ 395, 055 SAY "Qtd Conciliados: " SIZE 55, 10 OF oDlg PIXEL FONT oFont14
		@ 390, 110 MSGET nTotEncon PICTURE "999999 " SIZE 65, 12 OF oDlg PIXEL FONT oFont14n When .F.

		@ 395, 250 SAY "R$ Conciliados:" SIZE 55, 10 OF oDlg PIXEL FONT oFont14
		@ 390, 305 MSGET nValEncon PICTURE "@E 999,999,999.99" SIZE 65, 12 OF oDlg PIXEL FONT oFont14n When .F.

		//----- Botoes
		@ 020, 520 BUTTON "Trocar"  SIZE 50, 16 ACTION {|| MudaSel(1, aRodape, oBrwQt), oBrwQt:Refresh()} OF oDlg FONT oFont14n PIXEL
		@ 050, 520 BUTTON "Todas"   SIZE 50, 16 ACTION {|| MudaSel(2, aRodape, oBrwQt), oBrwQt:Refresh()} OF oDlg FONT oFont14n PIXEL
		@ 080, 520 BUTTON "Nenhuma" SIZE 50, 16 ACTION {|| MudaSel(3, aRodape, oBrwQt), oBrwQt:Refresh()} OF oDlg FONT oFont14n PIXEL
		@ 300, 520 BUTTON "Baixar"  SIZE 50, 16 ACTION {|| Baixar(aDados, aRodape, dDataEff, cNomeArq), oDlg:End()}          OF oDlg FONT oFont14n PIXEL
		@ 330, 520 BUTTON "Sair"    SIZE 50, 16 ACTION oDlg:End() OF oDlg FONT oFont14n PIXEL

		ACTIVATE MSDIALOG oDlg CENTERED
	Else
		FWAlertInfo("Nenhum pagamento encontrado no arquivo retorno.", "Conciliação")
	EndIf

Return NIL


/*/
	+==================================================================================================+
	| Função      | MudaSel                                                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Muda seleção do da totalização por filial a receber                                |
	|-------------+------------------------------------------------------------------------------------|
	| Parâmetro   | nTipo: Tipo de mudança (1 para selecionar todas, 2 para desselecionar todas)       |
	|             |        1 trocar a seleção das filiais que tem pagamento encontrado                 |
	|             |        2 marcar todas as filiais que tem pagamento encontrado                      |
	|             |        3 remover a seleção de todas as filiais que tem pagamento encontrado        |
	|             | aRodape: Array com os dados da totalização por filial                              |
	|             | oBrwQt: Objeto do browse da totalização por filial                                 |
	+==================================================================================================+
/*/
STATIC FUNCTION MudaSel(nTipo, aRodape, oBrwQt)

	Local nI := 0

	For nI := 1 To Len(aRodape)

		//----- inverter a seleção da filial que tem pagamento encontrado
		If nTipo == 1
			If aRodape[nI][6] > 0
				aRodape[nI][1] := Iif(aRodape[nI][1], .F., .T.)
			Else
				aRodape[nI][1] := .F.
			EndIf
		EndIf

		//----- marcar todas as filiais que tem pagamento encontrado
		If nTipo == 2
			If aRodape[nI][6] > 0
				aRodape[nI][1] := .T.
			Else
				aRodape[nI][1] := .F.
			EndIf
		EndIf

		//----- desmarcar todas as filiais que tem pagamento encontrado
		If nTipo == 3
			aRodape[nI][1] := .F.
		EndIf
	Next
Return NIL

/*/
	+==================================================================================================+
	| Função      | BuscaE1                                                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Procura no SE1 parcelas em aberto que atendam os dados obtidos no arquivo retorno  |
	|             | e que sejam vendas pagar via POS                                                   |
	+==================================================================================================+
/*/
STATIC FUNCTION BuscaSE1(aPagtos)

	Local cAlias     := GetNextAlias()
	Local cQueryBase := ""
	Local cQuery     := ""
	Local cWhere     := ""
	Local aDados     := {}
	Local nI         := 0
	Local nConta     := 0
	Local lPrimeiro  := .T.

	Local cNumFilial := ""
	Local cEmissao   := ""
	Local cValor     := ""

	//----- Base da instrução SQL
	cQueryBase := " SELECT "
	cQueryBase += "     SE1.E1_FILIAL  FIL, "
	cQueryBase += "     SE1.E1_NUM     TIT, "
	cQueryBase += "     SE1.E1_PARCELA PAR, "
	cQueryBase += "     SE1.E1_VALOR   VAL, "
	cQueryBase += "     SE1.E1_SALDO   SAL, "
	cQueryBase += "     SE1.E1_CLIENTE CLI, "
	cQueryBase += "     SE1.E1_LOJA    LOJ, "
	cQueryBase += "     SA1.A1_NOME    NOM, "
	cQueryBase += "     SE1.R_E_C_N_O_ REC, "
	cQueryBase += "     SE1.E1_EMISSAO EMI "

	cQueryBase += " FROM " + RetSqlName("SE1") + " SE1 "

	cQueryBase += " LEFT JOIN " + RetSqlName("SA1") + " SA1 ON "
	cQueryBase += "     SA1.A1_FILIAL = '" + xFilial("SA1") + "' "
	cQueryBase += "     AND SA1.D_E_L_E_T_ = ' ' "
	cQueryBase += "     AND SA1.A1_COD = SE1.E1_CLIENTE "
	cQueryBase += "     AND SA1.A1_LOJA = SE1.E1_LOJA "

	//----- Monta instruções de 12 em 12 pagamentos
	For nI := 1 To Len(aPagtos)
		//----- Inicia novo bloco
		If nConta == 0
			cWhere    := " WHERE ( "
			lPrimeiro := .T.
		EndIf

		nConta++

		cNumFilial := AllTrim(aPagtos[nI][1])
		cEmissao   := DtoS(aPagtos[nI][3])
		cValor     := StrTran(AllTrim(Str(aPagtos[nI][5],15,2)), ",", ".")

		//----- OR entre as condições
		If !lPrimeiro
			cWhere += " OR "
		EndIf

		cWhere += " ( "
		cWhere += " SE1.E1_FILIAL = '" + cNumFilial + "' "
		cWhere += " AND SE1.E1_EMISSAO = '" + cEmissao + "' "
		cWhere += " AND SE1.E1_VALOR = " + cValor + " "
		cWhere += " ) "

		lPrimeiro := .F.

		//----- Finaliza a instrução a cada 12 pagamentos ou se chegar ao final do vetor aPagtos
		If nConta == 12 .Or. nI == Len(aPagtos)
			cWhere += " ) "
			cWhere += " AND SE1.E1_SALDO > 0 "
			cWhere += " AND SE1.D_E_L_E_T_ = ' ' "
			cWhere += " ORDER BY SE1.R_E_C_N_O_ "

			cQuery := cQueryBase + cWhere

			TcQuery cQuery NEW ALIAS (cAlias)

			While !(cAlias)->(Eof())
				AAdd(aDados,{;
					(cAlias)->FIL,;
					(cAlias)->TIT,;
					(cAlias)->PAR,;
					(cAlias)->VAL,;
					(cAlias)->SAL,;
					(cAlias)->CLI,;
					(cAlias)->LOJ,;
					(cAlias)->NOM,;
					(cAlias)->REC,;
					(cAlias)->EMI})

				(cAlias)->(DbSkip())
			EndDo

			(cAlias)->(DbCloseArea())

			nConta := 0
		EndIf

	Next nI

Return aDados

/*/
	+==================================================================================================+
	| Função      | achaFilial                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | acha a filial a partir do EC                                                       |
	+==================================================================================================+
/*/
USER FUNCTION achaFilial(__ec, aEC)

	Local nI      := 0
	Local _numFil := ''

	For nI:=1 To Len(aEC)
		If AllTrim(aEC[nI][5]) == AllTrim(__ec)
			_numFil := aEC[nI][3]
		EndIf
	Next nI

Return _numFil

/*/
	+==================================================================================================+
	| Função      | BuscaECFil                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Busca os ECs (estabelcimento comercial) a filial a ele atrelada                    |
	+==================================================================================================+
/*/
USER FUNCTION BuscaECFil()

	Local aFilial	:= {}
	Local cQuery	:= ''
	Local cAlias	:= GetNextAlias()
	Local aAreaSM0  := SM0->(GetArea())

	cQuery := " SELECT X6_FIL, X6_CONTEUD "
	cQuery += " FROM " + RetSqlName("SX6")
	cQuery += " WHERE X6_VAR = 'MV_EMPTRED' "
	cQuery += "   AND D_E_L_E_T_ = ' ' "
	cQuery += "   AND X6_CONTEUD <> ' ' "
	cQuery += " ORDER BY X6_FIL "

	TcQuery cQuery NEW ALIAS (cAlias)

	While !(cAlias)->(Eof())
		//----- busca nome da filial
		SM0->(DbSetOrder(1))
		If SM0->(DbSeek(cEmpAnt + (cAlias)->X6_FIL))
			AAdd(aFilial, {' ', SM0->M0_CODIGO, SM0->M0_CODFIL, SM0->M0_NOMECOM, (cAlias)->X6_CONTEUD})
		Else
			AAdd(aFilial, {' ', cEmpAnt, (cAlias)->X6_FIL, "FILIAL DESCONHECIDA", (cAlias)->X6_CONTEUD})
		EndIf

		DbSkip()
	EndDo

	(cAlias)->(DbCloseArea())
	RestArea(aAreaSM0)

Return aFilial

/*/
	+==================================================================================================+
	| Função      | BuscaCC                                                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Busca as contas bancárias cadastradas                                              |
	+==================================================================================================+
/*/
STATIC FUNCTION BuscaCC()

	Local cAlias	:= GetNextAlias()
	Local cQuery	:= ''
	Local aDados	:= {}

	cQuery := "SELECT A6_FILIAL, A6_COD, A6_AGENCIA, A6_NUMCON, A6_DVCTA, A6_NOMEAGE"
	cQuery += "   FROM " + RetSqlName("SA6")
	cQuery += "   WHERE D_E_L_E_T_ = ' '"

	TcQuery cQuery NEW ALIAS (cAlias)

	While (cAlias)->(!Eof())
		AAdd(aDados, {(cAlias)->A6_FILIAL,;
			(cAlias)->A6_COD,;
			(cAlias)->A6_AGENCIA,;
			(cAlias)->A6_NUMCON,;
			(cAlias)->A6_DVCTA,;
			(cAlias)->A6_NOMEAGE})

		(cAlias)->(DbSkip(1))
	EndDo

Return aDados

/*/
	+==================================================================================================+
	| Função      | baixar                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Chama a rotina para baixar as parcelas com origem no arquivo retorno e que foram   |
	|             | encontradas no SE1                                                                 |
	+==================================================================================================+
/*/
STATIC FUNCTION baixar(aDados, aRodape, dDataEff, cNomeArq)
	Processa({|| procBaixar(aDados, aRodape, dDataEff), cNomeArq}, "Baixando conta a receber...")
Return NIL

/*/
	+==================================================================================================+
	| Função      | getSeqFIF                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Chama rotina FINA070 através do AutoExec                                           |
	+==================================================================================================+
/*/
STATIC FUNCTION getSeqFIF()

	Local cAlias	:= GetNextAlias()

	Local nSeq      := 1
	Local cNum		:= ''

	Local cQuery	:= ''

	cQuery := " SELECT MAX(FIF_SEQFIF) AS SEQ FROM " + RetSqlName("FIF")
	cQuery += " WHERE D_E_L_E_T_ = ' ' AND FIF_FILIAL = '" + xFilial("FIF") + "'"

	TcQuery cQuery NEW ALIAS (cAlias)

	If (cAlias)->(!Eof())
		nSeq := Val((cAlias)->SEQ)
	EndIf

	cNum := StrZero(nSeq + 1, TamSX3("FIF_SEQFIF")[1])

Return cNum

/*/
	+==================================================================================================+
	| Função      | procBaixa                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Executa baixa                                                                      |
	+==================================================================================================+
/*/
STATIC FUNCTION procBaixar(aDados, aRodape, dDataEff, cNomeArq)

	Local nI       := 0
	Local nJ       := 0
	Local nReg     := 0
	Local idPgto   := ''
	Local cTpPgto  := SubStr(cNomeArq, 4, 1)

	Local __numCia := cEmpAnt
	Local __numFil := cFilAnt

	Local ciaAtual := ''
	Local filAtual := ''

	ProcRegua(Len(aDados))

	For nI := 1 To Len(aRodape)
		//----- verifica se a filial está marcada para o processamento
		If aRodape[nI][1] == .F.
			Loop
		EndIf





		If AllTrim(cFilAnt) <> AllTrim(aRodape[nI][2])
			RpcClearEnv()
			RpcSetEnv( "01",AllTrim(aRodape[nI][2]))

			ciaAtual := "01"
			filAtual := aRodape[nI][2]
		EndIf

		//----- Processamento dos pagamentos da filial selecionada
		For nJ := 1 To Len(aDados)
			IncProc("Processando Registro: "+AllTrim(Str(nJ,10))+'/'+AllTrim(Str(Len(aDados),10)))

			//----- Verifica se o pagamento está sem a indicação de encontrado no SE1, grava no controle de não conciliados
			If AllTrim(aDados[nI][1]) == ''
				cSeqFIF  := getSeqFif()
				cNumComp := '/POS/FIL/'+filAtual+'/EC/'+aDados[nI][6]+'/PDV/'+aDados[nI][2]+'/AUT/'+aDados[nI][5]

				RecLock('FIF', .T.)
				FIF->FIF_FILIAL	:= xFilial("FIF")
				FIF->FIF_TPREG	:= '08'					// Tipo de registro 08 - sem conciliação do título
				FIF->FIF_CODEST := aDados[nI][6]		// EC - estabelecimento comercial
				FIF->FIF_DTTEF  := DToS(aDados[nI][3])	// Data da venda
				FIF->FIF_NUCOMP := Alltrim(cNumComp)	// Dados para rastreio do pagamento
				FIF->FIF_NSUTEF := ''
				FIF->FIF_VLBRUT := aDados[nI][4]
				FIF->FIF_VLLIQ	:= aDados[nI][20]
				FIF->FIF_DTCRED := DtoS(aDados[nI][18])	// Data de crédito em conta corrente
				FIF->FIF_TXSERV	:= aDados[nI][19]		// valor da taxa do serviço
				FIF->FIF_DTIMP	:= DToS(dDataBase)
				FIF->FIF_MSIMP	:= DtoS(dDataBase)
				FIF->FIF_CODFIL := filAtual
				FIF->FIF_SEQFIF	:= cSeqFIF
				FIF->FIF_ARQPAG := cNomeArq
				FIF->FIF_PARALF := ''
				FIF->FIF_PARCEL := ''
				FIF->FIF_MODPAG := '2'
				FIF->FIF_TPPROD := cTpPgto
				FIF->FIF_VLCOM	:= 0
				FIF->FIF_STATUS	:= '3'
				FIF->FIF_STVEND := ''
				FIF->FIF_CODBCO := aDados[nI][21]		// Codigo do banco
				FIF->FIF_CODAGE := aDados[nI][22]		// Codigo da agencia
				FIF->FIF_NUMCC  := aDados[nI][23]		// Numero da conta corrente
				FIF->FIF_INTRAN := ''
				FIF->FIF_CODLOJ := ''
				FIF->FIF_NURESU	:= ''
				FIF->FIF_NUCART := ''
				FIF->FIF_TOTPAR := ''
				FIF->FIF_CAPTUR := ''
				FIF->FIF_CODRED := ''
				FIF->FIF_CODBAN := ''
				FIF->FIF_CODADM := ''
				FIF->FIF_ARQVEN := ''
				FIF->FIF_NSUARQ := ''
				FIF->FIF_SEQREG := ''
				FIF->FIF_CODAUT := aDados[nI][5]		// Codigo de autorização da transação
				MsUnlock()
			Else
				If SubStr(aDados[nJ][2],1,4) == AllTrim(aRodape[nI][2])
					//----- IdPgto: EC / Autorizacao / PDV
					idPgto := AllTrim(aDados[nI][6])+'/'+AllTrim(aDados[nI][2])+'/'+AllTrim(aDados[nI][5])
					nReg   := aDados[nI][15]

					DbSelectArea("SE1")
					DbSetOrder(1)
					DbGoTo(nReg)

					_aCabec := {}

					Aadd(_aCabec, {"E1_PREFIXO"      , SE1->E1_PREFIXO          , nil})
					Aadd(_aCabec, {"E1_NUM"          , SE1->E1_NUM              , nil})
					Aadd(_aCabec, {"E1_PARCELA"      , SE1->E1_PARCELA          , nil})
					Aadd(_aCabec, {"E1_TIPO"         , SE1->E1_TIPO             , nil})
					Aadd(_aCabec, {"E1_CLIENTE"      , SE1->E1_CLIENTE          , nil})
					Aadd(_aCabec, {"E1_LOJA"         , SE1->E1_LOJA             , nil})
					AADD(_aCabec, {"AUTBANCO"        , cBanco                   , Nil})
					AADD(_aCabec, {"AUTAGENCIA"      , cAgencia                 , Nil})
					AADD(_aCabec, {"AUTCONTA"        , cConta                   , Nil})
					Aadd(_aCabec, {"AUTMOTBX"        , "NOR"                    , nil})
					Aadd(_aCabec, {"AUTDTBAIXA"      , dDataEff                 , nil})
					Aadd(_aCabec, {"AUTDTCREDITO"    , dDataEff                 , nil})
					Aadd(_aCabec, {"AUTHIST"         , aDados[nI][16]           , nil})
					Aadd(_aCabec, {"AUTVALREC"       , aDados[nI][04]           , nil})

					lMsErroAuto := .F.

					Begin Transaction
						MSExecAuto({|x,y| fina070(x,y)},_aCabec,3) //3-Inclusao
						IF lMsErroAuto
							DisarmTransaction()
							Break
						Else
							// sucesso
						EndIf

						DbSelectArea("SE1")
						DbSetOrder(1)
						DbGoTo(nReg)

						Reclock("SE1",.F.)
						SE1->E1_NRDOC := idPgto
						MsUnlock()
					End Transaction

					IF lMsErroAuto
						MostraErro()
					EndIf

				EndIf
			EndIf
		Next nJ
	Next nI

	//----- Volta o acesso a base de dados da filial original
	RpcClearEnv()
	RpcSetEnv( __numCia, __NumFil)

	FWAlertInfo("Processamento finalizado!", "Conciliação de Pagamentos POS")
Return NIL

/*/
	+==================================================================================================+
	| Função      | getSE1                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Busca dados do E1 conforme informações capturadas no arquivo retorn                |
	+==================================================================================================+
/*/
STATIC FUNCTION getSE1(cNumFil, cxTipo, cFormaPgto, cCartao, nValor, dEmissao, dVcto, cTipoTit, cParcela)

	Local cAlias := GetNextAlias()
	Local cQuery := ""

	cQuery := "SELECT SE1.E1_PREFIXO PRE, "
	cQuery += "       SE1.E1_NUM     TIT, "
	cQuery += "       SE1.R_E_C_N_O_ REC "
	cQuery += " FROM " + RetSqlName("SE1") + " SE1 "
	cQuery += " WHERE SE1.E1_FILIAL = '" + cNumFil + "' AND"
	cQuery += "       SE1.E1_XTIPO = '" + cxTipo + "' AND"
	cQuery += "       SE1.E1_FORMAPG = '" + cFormaPgto + "' AND"
	cQuery += "       SE1.E1_CARTAO = '" + cCartao + "' AND"
	cQuery += "       SE1.E1_VALOR = " + cValToChar(nValor) + " AND"
	cQuery += "       SE1.E1_VCTO = '" + DtoS(dVcto) + "' AND"
	cQuery += "       SE1.E1_EMISSAO = '" + DtoS(dEmissao) + "' "
	cQuery += "       SE1.E1_TIPO = '" + cTipoTit + "' AND"
	cQuery += "       SE1.E1_PARCELA = '" + cParcela + "' "

	TcQuery cQuery NEW ALIAS (cAlias)

	While !(cAlias)->(Eof())
		nQtde++

		AAdd(aDados,{;
			(cAlias)->PRE,;
			(cAlias)->TIT,;
			(cAlias)->REC})

		(cAlias)->(DbSkip())
	EndDo

	(cAlias)->(DbCloseArea())

	If nQtde >= 2
		aDados := {}
	EndIf

Return aDados

/*/
	+==================================================================================================+
	| Função      | grvVendas                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Grava o vetor aVendas na tabela SZV                                                |
	+==================================================================================================+
/*/
STATIC FUNCTION grvVendas(aVendas, acao)

	Local nI		:= 0
	Local nQtde		:= 0
	Local nValor	:= 0
	Local cMsg   	:= ''
	Local cOrigem	:= ''

	If Len(aVendas) <= 0
		FWAlertInfo("Nenhuma venda para gravar.", "Gravar Vendas")
		Return NIL
	EndIf

	If Len(aVendas) == 1
		cMsg := "Gravar esta única venda?"
	Else
		cMsg := "Gravar as " + AllTrim(Str(Len(aVendas))) + " vendas?"
	EndIf

	If !FWAlertYesNo(cMsg, "Gravação das Vendas")
		Return NIL
	EndIf

	If acao == 1
		cOrigem := '[ CRÉDITO ]'
	ElseIf acao == 2
		cOrigem := '[ DÉBITO ]'
	Else
		cOrigem := '[ PIX ]'
	EndIf

	ProcRegua(Len(aVendas))

	Begin Transaction

		For nI := 1 To Len(aVendas)
			IncProc("Gravando registro: " + AllTrim(Str(nI)) + "/" + AllTrim(Str(Len(aVendas))))

			RecLock("SZV", .T.)
			ZV_FILIAL  := xFilial("SZV")
			ZV_ARQUIVO := aVendas[nI][12]
			ZV_AUTORIZ := aVendas[nI][08]
			ZV_E1_FIL  := aVendas[nI][01]
			ZV_E1_NUM  := ''
			ZV_E1_PARC := ''
			ZV_E1_PREF := ''
			ZV_E1_TIPO := ''
			ZV_IMPDATA := dDataBase
			ZV_IMPHORA := SubStr(Time(),1,5)
			ZV_IMPUSER := cUserName
			ZV_LINHA   := aVendas[nI][11]
			ZV_NUNICO  := aVendas[nI][14]
			ZV_ORIGEM  := aVendas[nI][09]
			ZV_PV      := aVendas[nI][02]
			ZV_RV      := aVendas[nI][03]
			ZV_VALVEND := aVendas[nI][05]
			ZV_BAND    := aVendas[nI][13]
			ZV_CHAVE   := '01'
			ZV_DTVENDA := aVendas[nI][15]
			SZV->(MsUnlock())

			nQtde  ++
			nValor += aVendas[nI][05]
		Next nI

		//----- Grava dados na tabela de LOG
		RecLock("SZL", .T.)
		ZL_FILIAL  := xFilial("SZL")
		ZL_USER    := RetCodUsr()
		ZL_DATA    := dDataBase
		ZL_HORA    := SubStr(Time(),1,5)
		ZL_TIPO    := 'I-VEN'
		ZL_DESCRI  := 'Importação de Vendas ' + cOrigem
		ZL_RESUL1  := 'Qtde de vendas: '+AllTrim(Str(Len(aVendas)))+' R$ : '+AllTrim(Str(nValor,15,2))
		// ZL_RESUL2  := 'Qtde de RVs: '+AllTrim(Str(Len(aRVs)))+' Soma RVs: '+AllTrim(Str(nSomaRVs,15,2))
		SZL->(MsUnlock())
	End Transaction

	FWAlertInfo("Gravação finalizada! " + CRLF + CRLF + AllTrim(Str(nQtde)) +;
		" registros com valor total de R$ " + AllTrim(Transform(nValor,"@E 999,999,999.99")) +;
		" em vendas.", "Importação de Vendas")

Return NIL

/*/
	+==================================================================================================+
	| Função      | grvLog                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Grava log de importação na tabela SZD                                              |
	|-------------+------------------------------------------------------------------------------------|
	| Parâmetros  | cArquivo  - nome do arquivo importado                                              |
	|             | nQtde     - quantidade de registros (RVs ou transações)                            |
	|             | nValor    - valor total dos registros                                              |
	|             | cTipo     - tipo: V=Vendas, P=PIX, D=Débito, C=Crédito                            |
	+==================================================================================================+
/*/
STATIC FUNCTION grvLog(cArquivo, nQtde, nValor, cTipo)

	// RecLock("SZD", .T.)
	// SZD->ZD_FILIAL := xFilial("SZD")
	// SZD->ZD_USER   := RetCodUsr()
	// SZD->ZD_DATA   := dDataBase
	// SZD->ZD_HORA   := Time()
	// SZD->ZD_ARQUIV := cArquivo
	// SZD->ZD_QTDE   := nQtde
	// SZD->ZD_VLRTOT := nValor
	// SZD->ZD_TIPO   := cTipo
	// MsUnlock()

Return NIL

/*/
	+==================================================================================================+
	| Função      | ShowVendas                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Mostra as vendas                                                                   |
	+==================================================================================================+
/*/
STATIC FUNCTION ShowVendas(aVendas, acao)
	Local oDlg
	Local oBrw

	Local oFont     := TFont():New("Arial",, -12,, .F.)
	Local oFont13   := TFont():New("Arial",, -13,, .F.)
	Local oFont14   := TFont():New("Arial",, -14,, .F.)
	Local oFont14n  := TFont():New("Arial",, -14,, .T.)
	Local oFont16n  := TFont():New("Arial",, -16,, .T.)

	Local nQtdeRV   := 0
	Local nValRV    := 0
	Local nLaco     := 0

	//----- Tamanho da janela
	Local aTamanho  := MsAdvSize()
	Local nJanLarg  := aTamanho[5]
	Local nJanAltu  := aTamanho[6]

	nQtdeVenda	:= 0
	nValVenda   := 0

	For nLaco:=1 To Len(aVendas)
		nQtdeVenda++
		nValVenda += aVendas[nLaco,5]
	Next

	//==================================================================================================================
	// Formulario
	//==================================================================================================================
	cTitulo := "Importação das Vendas"

	If acao==1
		cTitulo += " [ CRÉDITO ]"
	ElseIf acao==2
		cTitulo += " [ DÉBITO ]"
	ElseIf acao==3
		cTitulo += " [ PIX ]"
	EndIf

	DEFINE MSDIALOG oDlg TITLE cTitulo FROM 000, 000 TO nJanAltu, nJanLarg COLORS RGB(239,83,80) PIXEL FONT oFont

	//------------------------------------------------------------------------------------------------------------------
	// Titulos dos browses
	//------------------------------------------------------------------------------------------------------------------
	@ 001, 010 SAY "LISTA DAS VENDAS" SIZE 200,10 OF oDlg PIXEL FONT oFont16n COLORS(RGB(0,34,51))
	// @ 001, 530 SAY "TOTAIS POR RV"    SIZE 200,10 OF oDlg PIXEL FONT oFont16n COLORS(RGB(0,34,51))

	//------------------------------------------------------------------------------------------------------------------
	// Browse das vendas
	//------------------------------------------------------------------------------------------------------------------
	oBrw := TWBrowse():New(001, 001, 520, 400)
	oBrw:SetArray(aVendas)
	oBrw:AddColumn(TCColumn():New("Filial",       {|| aVendas[oBrw:nAt,01] }))
	oBrw:AddColumn(TCColumn():New("PV",           {|| aVendas[oBrw:nAt,02] }))
	oBrw:AddColumn(TCColumn():New("RV",           {|| aVendas[oBrw:nAt,03] }))
	oBrw:AddColumn(TCColumn():New("Data RV",      {|| aVendas[oBrw:nAt,04] }))
	oBrw:AddColumn(TCColumn():New("Valor",        {|| aVendas[oBrw:nAt,05] },"@E 999,999.99",,,'RIGHT',,.F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Bandeira",     {|| _bandeira(aVendas[oBrw:nAt,13]) }))
	oBrw:AddColumn(TCColumn():New("Pagamento",    {|| _Pagamento(aVendas[oBrw:nAt,09]) }))
	oBrw:AddColumn(TCColumn():New("Parcela",      {|| aVendas[oBrw:nAt,10] }))
	oBrw:AddColumn(TCColumn():New("Data Venda",   {|| aVendas[oBrw:nAt,15] }))
	oBrw:AddColumn(TCColumn():New("Data Crédito", {|| aVendas[oBrw:nAt,16] }))
	oBrw:AddColumn(TCColumn():New("Linha",        {|| aVendas[oBrw:nAt,11] }))
	oBrw:AddColumn(TCColumn():New("Arquivo",      {|| aVendas[oBrw:nAt,12] }))

	oBrw:lAutoEdit := .F.
	oBrw:oFont := oFont13
	oBrw:Refresh()

	//------------------------------------------------------------------------------------------------------------------
	// Browse resumo de vendas - RV ( direita )
	//------------------------------------------------------------------------------------------------------------------
	// oBrwRV := TWBrowse():New(001, 600, 300, 400)
	// oBrwRV:SetArray(aResumo)
	// oBrwRV:AddColumn(TCColumn():New("PV",          {|| aResumo[oBrwRV:nAt,01] }))
	// oBrwRV:AddColumn(TCColumn():New("RV",          {|| aResumo[oBrwRV:nAt,02] }))
	// oBrwRV:AddColumn(TCColumn():New("Data",        {|| aResumo[oBrwRV:nAt,03] }))
	// oBrwRV:AddColumn(TCColumn():New("Valor",       {|| aResumo[oBrwRV:nAt,04] },"999999",,,'RIGHT',,.F.,.F.,,,,.F.,))
	// oBrwRV:AddColumn(TCColumn():New("Qtde Vendas", {|| aResumo[oBrwRV:nAt,05] },"@E 999,999.99",,,'RIGHT',,.F.,.F.,,,,.F.,))

	// oBrwRV:lAutoEdit := .F.
	// oBrwRV:oFont := oFont13
	// oBrwRV:Refresh()

	//------------------------------------------------------------------------------------------------------------------
	// Botoes e totalizadores ( abaixo dos browses )
	//------------------------------------------------------------------------------------------------------------------
	@ 430, 050 BUTTON "Gravar" SIZE 50, 16 ACTION {|| grvVendas(aVendas, acao), oDlg:End()} OF oDlg FONT oFont14n PIXEL
	@ 430, 200 BUTTON "Sair"   SIZE 50, 16 ACTION oDlg:End() OF oDlg FONT oFont14n PIXEL

	@ 428, 350 SAY "QTDE VENDAS:"  SIZE 70, 10 OF oDlg PIXEL FONT oFont13 COLORS(RGB(0,34,51))
	@ 425, 400 MSGET oQtde2 VAR Str(nQtdeVenda,6) SIZE 70, 012 OF oDlg FONT oFont14n WHEN .F. PIXEL

	@ 443, 350 SAY "R$l TOTAL: " SIZE 70, 10 OF oDlg PIXEL FONT oFont13 COLORS(RGB(0,34,51))
	@ 440, 400 MSGET oValor VAR Transform(nValVenda, '@E 9,999,999.99') SIZE 70, 012 OF oDlg FONT oFont14n WHEN .F. PIXEL

	ACTIVATE MSDIALOG oDlg CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Função      | LerArqCred                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Leitura do arquivo de vendas a CREDITO                                             |
	+==================================================================================================+
/*/
STATIC FUNCTION LerArqCred(aVendas, __arquivo, aECFilial)

	Local nHandle	:= 0
	Local nI        := 0

	Local cTipo		:= ''
	Local cParcela	:= ''
	Local cLinArq	:= ''
	Local cLinha	:= ''
	Local cPV		:= ''
	Local cRV		:= ''
	Local cSit		:= ''
	Local cNSU		:= ''
	Local cRef		:= ''
	Local cAutoriza	:= ''
	Local nValor	:= 0
	Local dDataCred := CtoD('//')
	Local cNsu      := ''
	Local cBandeira := ''
	Local cCartao   := ''

	Local aResumo	:= {}
	Local aVendas	:= {}
	Local dataRV    := CtoD('//')

	Local nNumLinha := 0
	Local cCodFil   := Space(4)
	Local cNomeArq  := ''
	Local aStatus   := {}

	Local __pv		:= ''
	Local __rv		:= ''
	Local __dia		:= ''
	Local __mes     := ''
	Local __ano     := ''

	//----- Abertura do arquivo
	nHandle := FT_FUse(__arquivo)

	//----- Se houver erro de abertura abandona processamento
	If nHandle = -1
		FWAlertError("Erro ao abrir arquivo retorno: " + __arquivo,"Arquivo Retorno")
		Return {}
	EndIf

	//----- Nome do arquivo
	cNomeArq := SubStr(__arquivo, RAt("\", __arquivo)+1)

	Aadd(aStatus,{000, 'CV/NSU OK'})
	Aadd(aStatus,{001, 'VENDA JA PROCESSADA'})
	Aadd(aStatus,{002, 'MOEDA INVALIDA'})
	Aadd(aStatus,{003, 'TT PREST DIF VR VD'})
	Aadd(aStatus,{004, 'CV/NSU SEM VR PREST'})
	Aadd(aStatus,{005, 'CP ACIMA LIM REDE SHOP'})
	Aadd(aStatus,{007, 'CV/NSU IRREGULAR'})
	Aadd(aStatus,{008, 'ESTAB BORDERO INVALI'})
	Aadd(aStatus,{010, 'CARTAO EM BP'})
	Aadd(aStatus,{011, 'CV/NSU SEM ASSINATURA'})
	Aadd(aStatus,{012, 'CV/NSU ILEGIVEL'})
	Aadd(aStatus,{013, 'CV/NSU SEM AUTORIZAçãO'})
	Aadd(aStatus,{014, 'CARTAO N CRED/DINERS'})
	Aadd(aStatus,{015, 'FALTA 2A VIA PROCESS'})
	Aadd(aStatus,{016, 'ESTAB S/ IATA N AUTO'})
	Aadd(aStatus,{017, 'CV/NSU IRREGULAR'})
	Aadd(aStatus,{018, 'CARTAO EM BP'})
	Aadd(aStatus,{019, 'TX EMBARQUE VLR EXCD'})
	Aadd(aStatus,{020, 'CARTAO VENCIDO'})
	Aadd(aStatus,{021, 'CV/NSU PARA CARTAO JURID'})
	Aadd(aStatus,{022, 'ACIMA LIMITE C/AUTOR'})
	Aadd(aStatus,{023, 'DATA CV/NSU POSTERIOR RV'})
	Aadd(aStatus,{025, 'CARTAO N CRED/DINERS'})
	Aadd(aStatus,{027, 'CV/NSU PARA CARTAO INTER'})
	Aadd(aStatus,{028, 'CARTAO EM BP'})
	Aadd(aStatus,{029, 'PROMOCAO MASTERCARD'})
	Aadd(aStatus,{030, 'TR INV P/TIPO CARTAO'})
	Aadd(aStatus,{031, 'PLAN PAGTO BIG TICKE'})
	Aadd(aStatus,{032, 'COD AUT N ENCONTRADO'})
	Aadd(aStatus,{034, 'DATA CV/NSU POSTERIOR RV'})
	Aadd(aStatus,{035, 'CV/NSU COM VR INCORRETO'})
	Aadd(aStatus,{036, 'CV/NSU SEM AUTORIZACAO'})
	Aadd(aStatus,{037, 'APRES. TARDIA CV/NSU'})
	Aadd(aStatus,{041, 'PARC. INVAL. VIAC. AERE'})
	Aadd(aStatus,{042, 'NAC.INVAL. - DUTY FRE'})
	Aadd(aStatus,{043, 'MQ INVA/NAO TR VISTA'})
	Aadd(aStatus,{044, 'CV/NSU S/JRS EM RV ROTAT'})
	Aadd(aStatus,{045, 'CV/NSU ROT EM RV S/JUROS'})
	Aadd(aStatus,{047, 'CARTAO N PODE PARCEL'})
	Aadd(aStatus,{048, 'ESTAB.NAO AUTORIZADO'})
	Aadd(aStatus,{049, 'DESCUMPRIM DE PROCED'})
	Aadd(aStatus,{102, 'COD AUT N ENCONTRADO'})
	Aadd(aStatus,{106, 'VR CV/NSU MAIOR QUE AUT'})
	Aadd(aStatus,{108, 'AUT CARTAO DIFERENTE'})
	Aadd(aStatus,{109, 'ESTAB BORDERO INVALI'})
	Aadd(aStatus,{110, 'TIPO TRANS DF DA AUT'})
	Aadd(aStatus,{111, 'CV/NSU SEM ASSINATURA'})
	Aadd(aStatus,{112, 'CV/NSU ILEGIVEL'})
	Aadd(aStatus,{114, 'CARTAO N CRED/DINERS'})
	Aadd(aStatus,{115, 'FALTA 2A VIA PROCESS'})
	Aadd(aStatus,{117, 'CV/NSU IRREGULAR'})
	Aadd(aStatus,{125, 'CARTAO N CRED/DINERS'})
	Aadd(aStatus,{137, 'APRES. TARDIA CV/NSU'})
	Aadd(aStatus,{141, 'PARC. INVAL. VIAC. AERE'})
	Aadd(aStatus,{142, 'NAC. INVAL. - DUTYFRE'})
	Aadd(aStatus,{143, 'MQ INVA/Não TR VISTA'})
	Aadd(aStatus,{144, 'CV/NSU S/ JRS EM RV ROTAT'})
	Aadd(aStatus,{145, 'CV/NSU ROT EM RV S/ JUROS'})
	Aadd(aStatus,{147, 'CARTAO N PODE PARCEL'})
	Aadd(aStatus,{148, 'ESTAB.NAO AUTORIZADO'})
	Aadd(aStatus,{149, 'DESCUMPRIM DE PROCED'})
	Aadd(aStatus,{194, 'CV/NSU SEM AUTORIZAçãO'})
	Aadd(aStatus,{198, 'COD AUT REUTILIZADO'})

	//=====================================================================================
	//                                  ESTRUTURA DOS VETORES
	//=====================================================================================
	// aResumo
	//    01 - PV
	//    02 - RV
	//    03 - DATA DE RV
	//    04 - VALOR TOTAL DAS VENDAS
	//    05 - QTDE TOTAL DAS VENDAS
	//
	// aVendas
	//    01 - FILIAL VENDA
	//    02 - PV
	//    03 - RV
	//    04 - DATA DO RV
	//    05 - VALOR
	//    06 - SITUAÇÃO
	//    07 - REFERENCIA
	//    08 - AUTORIZAÇÃO
	//    09 - TIPO: POS CD, POS CC, PIX, NSU CD, NSU CC
	//    10 - NUM DA PARCELA
	//    11 - NUM LINHA NO ARQUIVO
	//    12 - NOME DO ARQUIVO
	//    13 - BANDEIRA
	//    14 - NSU
	//    15 - DATA DA VENDA
	//    16 - DATA DO CREDITO
	//=====================================================================================

	FT_FGoTop()

	While !FT_FEOF()
		cLinha := FT_FReadLn()
		nNumLinha++

		//----- Descarta linhas
		If SubStr(cLinha, 1, 3) == "040" .OR.;
				SubStr(cLinha, 1, 3) == "002" .OR.;
				SubStr(cLinha, 1, 3) == "003" .OR.;
				SubStr(cLinha, 1, 3) == "004"

			FT_FSkip()
			Loop
		EndIf

		//----- Cabecalho da venda PARCELA ÚNICA
		If SubStr(cLinha, 1, 3) == "006"
			// //----- Descarta quem não é captura POS
			// If SubStr(cLinha, 137,1) <> "3"
			// 	FT_FSkip()
			// 	Loop
			// EndIf

			__pv	:= SubStr(cLinha,004, 009)
			__rv	:= SubStr(cLinha,013, 009)

			__dia   := SubStr(cLinha,041, 002)
			__mes   := SubStr(cLinha,043, 002)
			__ano	:= SubStr(cLinha,045, 004)
			dataRV	:= CtoD(__dia+'/'+__mes+'/'+__ano)

			__dia   := SubStr(cLinha,129, 002)
			__mes   := SubStr(cLinha,131, 002)
			__ano	:= SubStr(cLinha,133, 004)
			dataCrd := CtoD(__dia+'/'+__mes+'/'+__ano)

			nValNSU := Val(SubStr(cLinha,054, 015))/100
			nQtdNSU := Val(SubStr(cLinha,049, 005))
			cBand   := SubStr(cLinha,137, 001)

			// If cBand $ '0123456789'
			// 	cBand := _Bandeira(Val(cBand))
			// Else
			// 	cBand := _Bandeira(cBand)
			// EndIf

			//----- Resumo
			Aadd(aResumo,{__pv, __rv, dataRV, nValNSU, nQtdNSU})

			While !FT_FEOF() .AND. SubStr(cLinha,004, 009) == __pv .AND. SubStr(cLinha,013, 009) == __rv
				cLinha := FT_FReadLn()

				If SubStr(cLinha, 1, 3) == "008"
					If SubStr(cLinha,203, 001) == "3"
						cTipo := 'P01'   // POS CC
					Else
						cTipo := 'P03'   // TEF CC
					EndIf

					nValor		:= Val(SubStr(cLinha, 038, 015))/100
					cSit		:= ''
					cRef		:= SubStr(cLinha,099, 013)
					cAutoriza	:= SubStr(cLinha,127, 006)
					cParcela	:= '01'
					cLinArq		:= StrZero(nNumLinha,6)
					cNSU		:= SubStr(cLinha,087, 012)

					__codFil	:= ''
					__dia       := SubStr(cLinha,022, 002)
					__mes       := SubStr(cLinha,024, 002)
					__ano	    := SubStr(cLinha,026, 004)
					dataVenda   := CtoD(__dia+'/'+__mes+'/'+__ano)

					//----- Busca filial com base no __pv
					For nI := 1 To Len(aECFilial)
						If AllTrim(aECFilial[nI][5]) == AllTrim(__pv)
							__codFil := aECFilial[nI][3]
							Exit
						EndIf
					Next nI

					//----- Armazena venda
					aAdd(aVendas, {;
						__codFil,;
						__pv,;
						__rv,;
						dataRV,;
						nValor,;
						cSit,;
						cRef,;
						cAutoriza,;
						cTipo,;
						cParcela,;
						cLinArq,;
						cNomeArq,;
						cBand,;
						cNSU,;
						dataVenda,;
						dataCrd})
				EndIf

				FT_FSkip()
				Loop
			EndDo
		ElseIf SubStr(cLinha, 1, 3) == "010"
			//----- Cabecalho da venda PARCELADO
			//----- Se for diferente de 3, não venda com pagamento via POS
			// If SubStr(cLinha, 137,1) <> "3"
			// 	FT_FSkip()
			// 	Loop
			// EndIf

			__pv	  := SubStr(cLinha,004, 009)
			__rv  	  := SubStr(cLinha,013, 009)
			__dia     := SubStr(cLinha,041, 002)
			__mes     := SubStr(cLinha,043, 002)
			__ano	  := SubStr(cLinha,045, 004)
			dataRV	  := CtoD(__dia+'/'+__mes+'/'+__ano)
			dataVenda := CtoD('//')
			processar := 'S'
			__codFil  := ''

			//----- Busca filial com base no __pv
			For nI := 1 To Len(aECFilial)
				If AllTrim(aECFilial[nI][5]) == AllTrim(__pv)
					__codFil := aECFilial[nI][3]
					Exit
				EndIf
			Next nI

			nValNSU := Val(SubStr(cLinha,054, 015))/100
			nQtdNSU := Val(SubStr(cLinha,049, 005))
			cBand   := SubStr(cLinha,137, 001)

			// If cBand $ '0123456789'
			// 	cBand := _Bandeira(Val(cBand))
			// Else
			// 	cBand := _Bandeira(cBand)
			// EndIf

			//----- Resumo
			Aadd(aResumo,{__pv, __rv, dataRV, nValNSU, nQtdNSU})

			While !FT_FEOF() .AND. SubStr(cLinha,004, 009) == __pv .AND. SubStr(cLinha,013, 009) == __rv
				cLinha := FT_FReadLn()

				If SubStr(cLinha, 1, 3) == "012"
					dataVenda   := CtoD(SubStr(cLinha,022, 002)+'/'+SubStr(cLinha,024, 002)+'/'+SubStr(cLinha,026, 004))
					cNSU		:= SubStr(cLinha,089, 012)
					cAutoriza	:= SubStr(cLinha,129, 006)

					// //----- Só processar quem for captura == '3'
					// If SubStr(cLinha, 205, 001) <> "3"
					// 	processar := 'N'
					// EndIf

					If SubStr(cLinha,205, 001) == "3"
						cTipo := 'P01'   // POS CC
					Else
						cTipo := 'P03'   // TEF CC
					EndIf
				EndIf

				If SubStr(cLinha, 1, 3) == "014" .AND. processar == 'S'
					nValor		:= Val(SubStr(cLinha, 040, 015))/100
					cSit		:= ''
					cRef		:= ''
					cParcela	:= SubStr(cLinha,038, 002)
					cLinArq		:= StrZero(nNumLinha,6)
					dataCred    := CtoD(SubStr(cLinha,085, 002)+'/'+SubStr(cLinha,087, 002)+'/'+SubStr(cLinha,089, 004))

					//----- Venda
					aAdd(aVendas, {;
						__codFil,;
						__pv,;
						__rv,;
						dataRV,;
						nValor,;
						cSit,;
						cRef,;
						cAutoriza,;
						cTipo,;
						cParcela,;
						cLinArq,;
						cNomeArq,;
						cBand,;
						cNsu,;
						dataVenda,;
						dataCred})
				EndIf

				FT_FSkip()
				Loop
			EndDo
		Else
			FT_FSkip()
			Loop
		EndIf
	EndDo

	//----- Fecha o Arquivo
	FT_FUSE()

Return({aResumo, aVendas})

/*/
	+==================================================================================================+
	| Função      | LerArqDeb                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Leitura do arquivo dos pagamentos ( Débito )                                       |
	+==================================================================================================+
/*/
STATIC FUNCTION LerArqDeb(aVendas, __arquivo, aECFilial)

	Local nHandle	:= 0
	Local aLinha	:= {}
	Local cLinha	:= ''
	Local nNumLinha := 0
	Local cNomeArq  := SubStr(__arquivo, RAt("\", __arquivo)+1)

	Local cBanco	:= ''
	Local cAgencia	:= ''
	Local cConta	:= ''
	Local cDigito	:= ''

	Local _banco	:= ''
	Local _agencia	:= ''
	Local _conta	:= ''
	Local _digito	:= ''

	Local cCredito  := ''
	Local dCredito  := CtoD('//')
	Local dVenda	:= CtoD('//')
	Local cAutoriza	:= ''
	Local nI        := 0

	//----- Abertura do arquivo
	nHandle := FT_FUse(__arquivo)

	//----- Se houver erro de abertura abandona processamento
	If nHandle = -1
		FWAlertError("Erro ao abrir arquivo retorno: " + __arquivo,"Arquivo Retorno")
		Return {}
	EndIf

	FT_FGoTop()

	While !FT_FEOF()
		cLinha := FT_FReadLn()
		nNumLinha++

		//--------------------------------------------------------------------------------------------
		// Análise de cada uma das linhas do arquivo retorno
		//--------------------------------------------------------------------------------------------
		aLinha := StrTokArr2(cLinha, ",", .T.)

		If aLinha[01]=="00" .OR. aLinha[01]=="02"
			FT_FSkip()
			Loop
		EndIf

		//----- Identifica os dados bancários para as linhas de header do arquivo retorno
		If aLinha[01]=="01"
			cBanco    := SubStr(cLinha, 99, 3)
			cAgencia  := SubStr(cLinha, 103, 6)
			cConta    := SubStr(cLinha, 110, 10)
			cDigito   := SubStr(cLinha, 120, 1)
			cCredito  := SubStr(cLinha, 014, 8)
			dCredito  := CtoD(SubStr(cCredito,1,2)+'/'+SubStr(cCredito,3,2)+'/'+SubStr(cCredito,5,4))

			_banco	  := StrZero(Val(cBanco), 3)
			_agencia  := AllTrim(Str(Val(cAgencia)))
			_conta    := AllTrim(Str(Val(cConta)))
			_digito   := cDigito

			FT_FSkip()
			Loop
		EndIf

		//----- Identifica os dados da venda para as linhas de detalhe do arquivo retorno
		If aLinha[01]=="05"
			If Val(aLinha[15])==3
				cTipo := 'P02'
			Else
				cTipo := 'P04'
			EndIf

			__codFil    := ''
			__pv        := aLinha[02]
			__rv        := ''
			dVenda      := CtoD(SubStr(aLinha[4],1,2)+'/'+SubStr(aLinha[4],3,2)+'/'+SubStr(aLinha[4],5,4))
			nValor      := (Val(aLinha[5])/100)
			cSit        := aLinha[12]
			cRef        := ''
			cAutoriza   := aLinha[20]
			cParcela    := ''
			cBandeira   := aLinha[19]
			cNSU        := aLinha[10]
			dCred       := CtoD(SubStr(aLinha[11],1,2)+'/'+SubStr(aLinha[11],3,2)+'/'+SubStr(aLinha[11],5,4))

			//----- Busca filial com base no __pv
			For nI := 1 To Len(aECFilial)
				If AllTrim(aECFilial[nI][5]) == AllTrim(__pv)
					__codFil := aECFilial[nI][3]
					Exit
				EndIf
			Next nI

			//----- Armazena venda
			aAdd(aVendas, {;
				__codFil,;
				__pv,;
				__rv,;
				dVenda,;
				nValor,;
				cSit,;
				cRef,;
				cAutoriza,;
				cTipo,;
				cParcela,;
				StrZero(nNumLinha,4),;
				cNomeArq,;
				cBandeira,;
				cNSU,;
				dVenda,;
				dCred})
		EndIf

		FT_FSkip()
	EndDo

	//----- Fecha o Arquivo
	FT_FUSE()

Return aVendas

/*/
	+==================================================================================================+
	| Função      | _Bandeira                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Busca a descricao da bandeira                                                      |
	+==================================================================================================+
/*/
STATIC FUNCTION _Bandeira(codigo)

	Local cBandeira := ''

	If codigo == "0"
		cBandeira := "OUTRAS"
	ElseIf codigo == "1"
		cBandeira := "MASTERCARD"
	ElseIf codigo == "2"
		cBandeira := "DINERS CLUB"
	Elseif codigo == "3"
		cBandeira := "VISA"
	ElseIf codigo == "4"
		cBandeira := "CABAL"
	ElseIf codigo == "5"
		cBandeira := "HIPERCARD"
	ElseIf codigo == "6"
		cBandeira := "SOROCARD"
	ElseIf codigo == "7"
		cBandeira := "CUP"
	ElseIf codigo == "8"
		cBandeira := "CREDSYSTEM"
	ElseIf codigo == "9"
		cBandeira := "SICRED"
	ElseIf codigo == "A"
		cBandeira := "AVISTA"
	ElseIf codigo == "B"
		cBandeira := "BANESCARD"
	ElseIf codigo == "E"
		cBandeira := "ELO"
	ElseIf codigo == "J"
		cBandeira := "JCB"
	ElseIf codigo == "X"
		cBandeira := "AMEX"
	ElseIf codigo == "Z"
		cBandeira := "CREDZ"
	Else
		cBandeira := ""
	EndIf

Return cBandeira

/*/
	+==================================================================================================+
	| Função      | _Pagamento                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Busca a descricao dos tipos de pagamentos                                          |
	+==================================================================================================+
/*/
STATIC FUNCTION _Pagamento(cOrigem)

	Local cDescricao := ''

	If cOrigem == "P00"
		cDescricao := "PIX"
	ElseIf cOrigem == "P01"
		cDescricao := "POS CC"
	ElseIf cOrigem == "P02"
		cDescricao := "POS CD"
	ElseIf cOrigem == "P03"
		cDescricao := "TEF CC"
	ElseIf cOrigem == "P04"
		cDescricao := "TEF CD"
	Else
		cDescricao := ""
	EndIf

Return cDescricao
