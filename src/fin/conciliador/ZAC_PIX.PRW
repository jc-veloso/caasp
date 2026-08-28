#INCLUDE "TOTVS.CH"
#INCLUDE "FILEIO.CH"
#INCLUDE "PARMTYPE.CH"
#INCLUDE "RPTDEF.CH"
#INCLUDE "TOPCONN.CH"

/*/
+==================================================================================================+
| Função      | LerArqPIX                                                                          |
|-------------+------------------------------------------------------------------------------------|
| Descrição   | Leitura do arquivo de pagamento via PIX                                            |
+==================================================================================================+
/*/
USER FUNCTION LerArqPIX(aPix, cFile)

	Local nHdlRet	:= 0
	Local nTamArq	:= 0
	Local nI        := 0

	Local cCodFil   := ''
	Local cBuffer	:= ''
	Local cLinha	:= ''
	Local nTamLin	:= 0
	Local nLidos	:= 0

	Local cIDTran   := ''
	Local cMotivo   := ''
	Local dMvto     := CtoD('//')
	Local nValOrig  := 0
	Local nValJuros := 0
	Local nValMulta := 0
	Local nValAbat  := 0
	Local nValDesc  := 0
	Local nValFinal := 0
	Local nValPago  := 0
	Local cCpfCnpj  := ''
	Local cCnpjRec  := ''
	Local cNome     := ''

	Local cNomeArq  := ''
	Local nNumLinha := 0

	Local aFilial   := getFilial()
	Local aMotivo   := {}

	Aadd(aMotivo,{02,'Emissão confirmada'})
	Aadd(aMotivo,{03,'Emissão rejeitada'})
	Aadd(aMotivo,{04,'Alteração confirmada'})
	Aadd(aMotivo,{05,'Alteração rejeitada'})
	Aadd(aMotivo,{06,'Recebimento'})
	Aadd(aMotivo,{07,'Cancelamento pelo recebedor confirmado'})
	Aadd(aMotivo,{08,'Cancelamento pelo PSP'})
	Aadd(aMotivo,{10,'Cancelamento rejeitado'})

	If Empty(AllTrim(cFile))
		FWAlertInfo("Selecione um arquivo retorno.", "Processamento de Pagamentos PIX")
		Return .F.
	EndIf

	If !File(cFile)
		FWAlertInfo("Arquivo de retorno não localizado.", "Processamento de Pagamentos PIX")
		Return .F.
	EndIf

	nHdlRet := FOPEN(cFile, 0 + 64)
	If nHdlRet == -1
		FWAlertInfo("Falha ao abrir o arquivo retorno: " + cFile, "Processamento de Pagamentos PIX")
		Return .F.
	EndIf

	//----- Nome do arquivo
	cNomeArq := SubStr(cFile, RAt("\", cFile)+1)

	//=========================================================================================//
	//	                                                                                       //
	//                       Leitura linha a linha do arquivo retorno                          //
	//	                                                                                       //
	//=========================================================================================//
	nTamArq := FSEEK(nHdlRet, 0, 2)
	FSEEK(nHdlRet, 0, 0)

	While nLidos < nTamArq
		cBuffer := ""
		cLinha  := ""
		nTamLin := 0

		//----- Leitura byte a byte até encontrar CR+LF ou fim do arquivo
		While nLidos < nTamArq
			FREAD(nHdlRet, @cBuffer, 1)
			nLidos++

			If cBuffer == Chr(13) .Or. cBuffer == Chr(10)
				Exit
			EndIf

			cLinha += cBuffer
			nTamLin++
		EndDo

		//----- Descarta linhas vazias
		If Empty(cLinha)
			Loop
		EndIf

		nNumLinha++

		//-------------------------------------------------------------------------------------------
		// Identifica o tipo de registro (posicao 1)
		//   1 = Confirmacao do Transmissor (Transmitter Response)
		//   4 = QR Code (EMV/Payload)
		//   5 = Confirmacao Final (Receiver Response)
		//-------------------------------------------------------------------------------------------
		cTipoReg := SubStr(cLinha, 1, 1)

		//-------------------------------------------------------------------------------------------
		// TIPO 1 ou TIPO 5: Dados comuns da transacao PIX
		//-------------------------------------------------------------------------------------------
		If cTipoReg == '5'
			cIDTran   := AllTrim(SubStr(cLinha, 002, 035))
			cMotivo   := SubStr(cLinha, 167, 002)
			dMvto     := CtoD(SubStr(cLinha, 175, 002)+'/'+SubStr(cLinha, 173, 002)+'/'+SubStr(cLinha, 169, 004))
			nValOrig  := Val(SubStr(cLinha, 199, 17)) / 100
			nValJuros := Val(SubStr(cLinha, 216, 17)) / 100
			nValMulta := Val(SubStr(cLinha, 233, 17)) / 100
			nValAbat  := Val(SubStr(cLinha, 250, 17)) / 100
			nValDesc  := Val(SubStr(cLinha, 267, 17)) / 100
			nValFinal := Val(SubStr(cLinha, 284, 17)) / 100
			nValPago  := Val(SubStr(cLinha, 301, 17)) / 100
			cCpfCnpj  := SubStr(cLinha, 336, 014)
			cCnpjRec  := SubStr(cLinha, 047, 014)
			cNome     := SubStr(cLinha, 350, 100)
			cCodFil   := ''
			cNumAgc   := SubStr(cLinha, 061, 004)
			cNumCta   := SubStr(cLinha, 065, 019)

			For nI:=1 To Len(aMotivo)
				If Val(cMotivo) == aMotivo[nI][1]
					cMotivo := aMotivo[nI][2]
					Exit
				EndIf
			Next nI

			For nI:=1 To Len(aFilial)
				If cCnpjRec == aFilial[nI][3]
					cCodFil := aFilial[nI][1]
					Exit
				EndIf
			Next nI

			AAdd(aPix, {;
				cCodFil,;
				cIDTran,;
				cMotivo,;
				dMvto,;
				nValOrig,;
				nValJuros,;
				nValMulta,;
				nValAbat,;
				nValDesc,;
				nValFinal,;
				nValPago,;
				cCpfCnpj,;
				cNome,;
				cNomeArq,;
				nNumLinha,;
				cNumAgc,;
				cNumCta })
		EndIf
	EndDo

	FCLOSE(nHdlRet)

Return NIL

/*/
	+==================================================================================================+
	| Função      | getFilial                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Busca a lista de filiais                                                           |
	+==================================================================================================+
/*/
STATIC FUNCTION getFilial()

	Local aFilial	:= {}

	DbSelectArea( 'SM0' )
	DbGoTop()

	While !SM0->(EOF())
		aAdd(aFilial, {SM0->M0_CODFIL, SM0->M0_FILIAL, SM0->M0_CGC})

		DbSkip()
	EndDo

Return aFilial

/*/
	+==================================================================================================+
	| Função      | ShowPIX                                                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Mostra os pagamentos via PIX                                                       |
	+==================================================================================================+
/*/
USER FUNCTION ShowPix(aPIX)

	Local oDlg
	Local oBrw

	//----- Tamanho da janela
	Local aSize     := MsAdvSize()
	Local nJanLarg  := aSize[5]
	Local nJanAltu  := aSize[6]
	Local nBtnLinha := 370

	Local oFont     := TFont():New("Arial",, -12,, .F.)
	Local oFont13   := TFont():New("Arial",, -13,, .F.)
	Local oFont14   := TFont():New("Arial",, -14,, .F.)
	Local oFont14n  := TFont():New("Arial",, -14,, .T.)
	Local oFont16n  := TFont():New("Arial",, -16,, .T.)

	Local aHeader	:= {}
	Local aSizeAut	:= MsAdvSize()

	If Len(aPIX) <= 0
		FWAlertInfo('Nenhuma informação das vendas via PIX está disponível.','Importação de Pagamentos PIX')
		Return NIL
	EndIf

	//==================================================================================================================
	// Formulario
	//==================================================================================================================
	DEFINE MSDIALOG oDlg TITLE "Importação das Vendas [ PIX ]" FROM aSizeAut[7],000 TO aSizeAut[6],aSizeAut[5] FONT oFont PIXEL

	@ 006, 010 SAY "LISTA DE PAGAMENTOS VIA PIX" SIZE 150,10 OF oDlg PIXEL FONT oFont16n COLORS(RGB(0,34,51))

	//------------------------------------------------------------------------------------------------------------------
	// Browse dos pagamentos via PIX
	//------------------------------------------------------------------------------------------------------------------
	aHeader := {"Filial", "ID", "Data", "R$ Valor", "CPF/CNPJ", "Nome", "Arquivo", "Linha"}
	aSize   := {30, 130, 60, 60, 60, 120, 120, 40}

	oBrw := TWBrowse():New(015, 010, 800, 350,,aHeader,aSize, oDlg,,,,,,,,,,,,.T.,,.T.,,.T.,,,)

	oBrw:SetArray(aPIX)

	oBrw:bLine := {||{;
		aPIX[oBrw:nAt, 1],;
		aPIX[oBrw:nAt, 2],;
		aPIX[oBrw:nAt, 4],;
		Transform(aPIX[oBrw:nAt, 11], "@E 999,999,999.99"),;
		aPIX[oBrw:nAt, 12],;
		aPIX[oBrw:nAt, 13],;
		aPIX[oBrw:nAt, 14],;
		aPIX[oBrw:nAt, 15],;
		}}

	oBrw:oFont := oFont13
	oBrw:Refresh()

	@ nBtnLinha, 050 BUTTON "Gravar" SIZE 50, 16 ACTION {|| grvVendPIX(aPIX), oDlg:End()} OF oDlg FONT oFont14n PIXEL
	@ nBtnLinha, 200 BUTTON "Sair"   SIZE 50, 16 ACTION oDlg:End() OF oDlg FONT oFont14n PIXEL

	ACTIVATE MSDIALOG oDlg CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Função      | grvVendPIX                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Grava as vendas lidas do arquivo PIX                                               |
	+==================================================================================================+
/*/
STATIC FUNCTION grvVendPIX(aVendas)

	Local nI		:= 0
	Local nQtde		:= 0
	Local nValor	:= 0
	Local cMsg   	:= ''

	If Len(aVendas) <= 0
		FWAlertInfo("Nenhuma venda via PIX a ser gravada.", "Importação de vendas [PIX]")
		Return NIL
	EndIf

	If Len(aVendas) == 1
		cMsg := "Gravar esta única venda?"
	Else
		cMsg := "Gravar as " + AllTrim(Str(Len(aVendas))) + " vendas?"
	EndIf

	If !FWAlertYesNo(cMsg, "Gravar as vendas via PIX ?")
		Return NIL
	EndIf

	ProcRegua(Len(aVendas))

	Begin Transaction
		For nI := 1 To Len(aVendas)
			IncProc("Gravando registro: " + AllTrim(Str(nI)) + "/" + AllTrim(Str(Len(aVendas))))

			RecLock("SZV", .T.)
			ZV_FILIAL  := xFilial("SZV")
			ZV_ARQUIVO := aVendas[nI][14]
			ZV_DTVENDA := aVendas[nI][04]
			ZV_AUTORIZ := SubStr(aVendas[nI][02],01,30)
			ZV_NUNICO  := SubStr(aVendas[nI][02],31,05)
			ZV_E1_FIL  := aVendas[nI][01]
			ZV_E1_NUM  := ''
			ZV_E1_PARC := ''
			ZV_E1_PREF := ''
			ZV_E1_TIPO := ''
			ZV_IMPDATA := dDataBase
			ZV_IMPHORA := SubStr(Time(),1,5)
			ZV_IMPUSER := cUserName
			ZV_LINHA   := Iif(ValType(aVendas[nI][15]) == "N", Str(aVendas[nI][15]), aVendas[nI][15])
			ZV_PV      := ''
			ZV_RV      := ''
			ZV_ORIGEM  := 'P00'
			ZV_VALVEND := aVendas[nI][10]
			ZV_BAND    := ''
			ZV_CHAVE   := '01'
			ZV_CARTAO  := ''
			SZV->(MsUnlock())

			nQtde  ++
			nValor += aVendas[nI][10]
		Next nX

		//----- Grava dados na tabela de LOG
		RecLock("SZL", .T.)
		ZL_FILIAL  := xFilial("SZL")
		ZL_USER    := RetCodUsr()
		ZL_DATA    := dDataBase
		ZL_HORA    := SubStr(Time(),1,5)
		ZL_TIPO    := 'I-VEN'
		ZL_DESCRI  := 'Importação de Vendas [PIX]'
		ZL_RESUL1  := 'Qtde de vendas: '+AllTrim(Str(Len(aVendas)))+' R$ : '+AllTrim(Str(nValor,15,2))
		// ZL_RESUL2  := 'Qtde de RVs: '+AllTrim(Str(Len(aRVs)))+' Soma RVs: '+AllTrim(Str(nSomaRVs,15,2))
		SZL->(MsUnlock())
	End Transaction

	FWAlertInfo("Gravação finalizada! " + CRLF + CRLF + AllTrim(Str(nQtde)) + " registros com valor total de R$ " + AllTrim(Str(nValor,15,2)) + " em vendas.", "importação de Vendas")

Return NIL

/*/
	+==================================================================================================+
	| Funcao      | BX_PIX                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descricao   | Baixa das vendas com pagamentos via PIX                                            |
	+==================================================================================================+
/*/
USER FUNCTION BX_PIX()

	Local oDlgProc
	Local oBrwFiles

	Local oFont12  := TFont():New("Arial", , -12)
	Local oFont14  := TFont():New("Arial", , -14)
	Local oFont14b := TFont():New("Arial", , -14, .T.)

	Local cTxtForm  := 'Baixa de vendas [PIX]'
	Local cTxtLabel := 'Selecione os arquivos de PIX'
	Local cMask     := "RET (*.ret) |*.ret| CSV (*.csv) |*.csv| TXT (*.txt) |*.txt| TODOS (*.*) |*.*|"

	Local cFile     := ''
	Local aFiles    := {}
	Local aPix      := {}

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

	@ 190, 080 BUTTON "Remover" SIZE 60, 16 ;
		ACTION (Iif(Len(aFiles)>0,;
		(ADel(aFiles, oBrwFiles:nAt), ASize(aFiles, Len(aFiles)-1),;
		oBrwFiles:SetArray(aFiles),;
		Iif(oBrwFiles:nAt > Len(aFiles) .AND. Len(aFiles) > 0, oBrwFiles:nAt := Len(aFiles), NIL),;
		oBrwFiles:Refresh()), NIL)) ;
		OF oDlgProc FONT oFont14 PIXEL

	@ 190, 150 BUTTON "Processar" SIZE 60, 16 ;
		ACTION {|| BaixaPIX(aFiles)};
		SIZE 65, 18 OF oDlgProc FONT oFont14 PIXEL

	@ 190, 225 BUTTON "Sair" SIZE 60, 16 ;
		ACTION oDlgProc:End() ;
		OF oDlgProc FONT oFont14 PIXEL

	ACTIVATE MsDialog oDlgProc CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Funcao      | getArqRet                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descricao   | Selecao do arquivo retorno de pagamentos via PIX                                   |
	+==================================================================================================+
/*/
STATIC FUNCTION getArqRet()

	Local cFile := ""
	Local cMask := "RET (*.ret) |*.ret| CSV (*.csv) |*.csv| TXT (*.txt) |*.txt| TODOS (*.*) |*.*|"

	cFile := tFileDialog(cMask, "Selecione o arquivo de retorno", , , , .F.)

Return cFile

/*/
	+==================================================================================================+
	| Funcao      | BaixaPIX                                                                           |
	|-------------+------------------------------------------------------------------------------------|
	| Descricao   | Processamento dos arquivos de retorno PIX                                          |
	+==================================================================================================+
/*/
STATIC FUNCTION BaixaPIX(aFiles)

	If Len(aFiles) <= 0
		FWAlertInfo("Nenhum arquivo selecionado foi selecionado.", "Conciliar vendas via PIX")
		Return NIL
	EndIf

	If FWAlertYesNo("Processar os arquivos selecionados?","Conciliar vendas via PIX") == .F.
		Return NIL
	EndIf

	Processa({|| procBxPix(aFiles) }, "Processando a baixa dos pagamentos via PIX")
Return NIL

/*/
	+==================================================================================================+
	| Funcao      | procBxPix                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descricao   | Processamento dos arquivos de retorno PIX                                          |
	+==================================================================================================+
/*/
STATIC FUNCTION procBxPix(aFiles)

	Local nI        := 0
	Local aPIX      := {}

	Local nQtde     := 0
	Local nAchou    := 0
	Local nNaoAchou := 0

	Local cAlias    := ''
	Local aBaixas   := {}

	Local cBco := ''
	Local cAgc := ''
	Local cCta := ''

	For nI:=1 To Len(aFiles)
		U_LerArqPIX(@aPIX, aFiles[nI])
	Next nI

	nQtde   := Len(aPix)
	lTemCta := .F.

	//----- Validação da conta bancaria
	For nI:=1 To Len(aPIX)
		__agc := aPIX[nI][16]
		__cta := aPIX[nI][17]
		Exit
	Next nI

	DbSelectArea("SA6")
	DbSetOrder(1)
	DbGoTop()

	While SA6->(!Eof())
		If Val(SA6->A6_AGENCIA) == Val(__agc)
			If Val(SA6->A6_NUMCON) == Val(__cta)
				cBco := SA6->A6_COD
				cAgc := AllTrim(SA6->A6_AGENCIA)
				cCta := AllTrim(SA6->A6_NUMCON)

				lTemCta := .T.

				Exit
			EndIf
		EndIf

		SA6->(DbSkip(1))
	EndDo

	If lTemCta == .F.
		FWAlertInfo("Conta bancária não cadastrada no Protheus.", "Processamento Cancelado")
		Return NIL
	EndIf

	For nI:=1 To Len(aPIX)
		__fil   := aPIX[nI][1]
		__id    := aPIX[nI][2]

		cAlias  := GetNextAlias()

		// --- Consulta SQL filtrada por periodo
		BeginSQL Alias cAlias
		SELECT ZV_E1_FIL,
               ZV_E1_NUM,
			   ZV_E1_PARC,
			   ZV_E1_PREF,
			   ZV_E1_TIPO,
			   R_E_C_N_O_ AS REC,
			   ZV_VALVEND
		 FROM %table:SZV% ZV
		 WHERE ZV.ZV_E1_FIL = %exp:__fil% AND
		       RTRIM(ZV.ZV_AUTORIZ) || RTRIM(ZV.ZV_NUNICO) = %exp:__id% AND
		       ZV.ZV_CHAVE = '02' AND
		       %notDel%
		EndSQL

		If (cAlias)->(!Eof())
			nAchou++

			aAdd(aBaixas,;
				{(cAlias)->ZV_E1_FIL,;
				(cAlias)->ZV_E1_NUM,;
				(cAlias)->ZV_E1_PARC,;
				(cAlias)->ZV_E1_PREF,;
				(cAlias)->ZV_E1_TIPO,;
				(cAlias)->REC,;
				(cAlias)->ZV_VALVEND})
		Else
			nNaoAchou++
		EndIf
	Next nI

	//----- Validação dos dados da conta destino
	If Val(cBco) <= 0 .OR. Val(cAgc) <= 0 .OR. Val(cCta) <= 0
		FWAlertInfo("Conta bancária inválida.", "Processamento Cancelado")
		Return NIL
	Else
		DbSelectArea("SA6")
		DbSetOrder(1)
		If DbSeek(xFilial('SA6') + cBco + cAgc + cCta) == .F.
			FWAlertInfo("Conta bancária inválida.", "Processamento Cancelado")
			Return NIL
		EndIf
	EndIf

	//----- Confirmação do usuário
	If FWAlertYesNao(;
			"Análise dos pagamentos foi concluída com sucesso."+CRLF+CRLF+;
			"Quantidade de pagamentos: "+AllTrim(Str(nQtde))+CRLF+;
			"Qtde de pagamentos COM vendas validadas: "+AllTrim(Str(nAchou))+CRLF+;
			"Qtde de pagamentos SEM vendas validadas: "+AllTrim(Str(nNaoAchou))+CRLF+CRLF+;
			"Baixar os pagamentos com vendas validadas?",;
			"Análise dos pagamentos [ PIX ]")

		__bxPIX(aBaixas, cBco, cAgc, cCta)
	EndIf

Return NIL

/*/
	+==================================================================================================+
	| Funcao      | __bxPIX                                                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Descricao   | Efetiva a baixa do contas a receber                                                |
	+==================================================================================================+
/*/
STATIC FUNCTION __bxPIX(aBaixas, cBco, cAgc, cCta)

	Local aTit      := {}
	Local aErro     := {}
	Local cMsg      := ""
	Local nI        := 0
	Local nX        := 0
	Local lOk       := .T.
	Local dBaixa    := dDataBase

	Local cPref
	Local cTipo
	Local cNum
	Local cParc
	Local cFil
	Local cCli
	Local cLoja

	Private lMsErroAuto    := .F.
	Private lMsHelpAuto    := .T.
	Private lAutoErrNoFile := .T.

	For nI:=1 To Len(aBaixas)
		aTit	:= {}
		aErro   := {}
		cMsg    := ''
		nReg    := aBaixas[nI][6]
		cPref	:= aBaixas[nI][4]
		cTipo   := aBaixas[nI][5]
		cNum    := aBaixas[nI][2]
		cParc   := aBaixas[nI][3]
		cFil    := aBaixas[nI][1]
		nVal    := aBaixas[nI][7]
		cCli	:= ''
		cLoja	:= ''

		DbSelectArea("SE1")
		DbSetOrder(1)
		If DbSeek(cFil+cPref+cNum+cParc+cTipo)
			cCli  := SE1->E1_CLIENTE
			cLoja := SE1->E1_LOJA
		EndIf

		DbSelectArea('SZV')
		DbGoTo(nReg)

		Begin Transaction
			RecLock("SZV", .F.)
			SZV->ZV_E1_TIPO := ''
			SZV->ZV_CHAVE   := "04"
			SZV->ZV_CONDATA := dDataBase
			SZV->ZV_VALHORA := SubStr(Time(),1,5)
			SZV->ZV_VALUSER := RetCodUsr()
			SZV->ZV_BXDATA  := dDataBase
			SZV->ZV_BXHORA  := SubStr(Time(),1,5)
			SZV->ZV_BXUSER  := RetCodUsr()
			MsUnLock()

			//----- Grava dados na tabela de LOG
			RecLock("SZL", .T.)
			ZL_FILIAL  := xFilial("SZL")
			ZL_USER    := RetCodUsr()
			ZL_DATA    := dDataBase
			ZL_HORA    := SubStr(Time(),1,5)
			ZL_TIPO    := 'CONC1'
			ZL_DESCRI  := 'Consolidação pagamento PIX'
			ZL_RESUL1  := 'SZV Reg: '+Str(nReg)
			ZL_RESUL2  := 'Título SE1: '+cFil+'/'+cPref+'/'+cNum+'/'+cParc+'/'+cTipo
			SZL->(MsUnlock())

			RecLock("SZL", .T.)
			ZL_FILIAL  := xFilial("SZL")
			ZL_USER    := RetCodUsr()
			ZL_DATA    := dDataBase
			ZL_HORA    := SubStr(Time(),1,5)
			ZL_TIPO    := 'BXPIX'
			ZL_DESCRI  := 'Baixa CR - pgto via PIX'
			ZL_RESUL1  := 'SZV Reg: '+Str(nReg)
			ZL_RESUL2  := 'Título SE1: '+cFil+'/'+cPref+'/'+cNum+'/'+cParc+'/'+cTipo
			SZL->(MsUnlock())

			cBco := StrZero(Val(cBco),3)
			cAgc := Alltrim(Str(Val(cAgc)))
			cCta := Alltrim(Str(Val(cCta)))

			aAdd(aTit, {"E1_FILIAL", SE1->E1_FILIAL, Nil})
			aAdd(aTit, {"E1_PREFIXO", SE1->E1_PREFIXO, Nil})
			aAdd(aTit, {"E1_NUM", SE1->E1_NUM, Nil})
			aAdd(aTit, {"E1_PARCELA", SE1->E1_PARCELA, Nil})
			aAdd(aTit, {"E1_TIPO", SE1->E1_TIPO, Nil})
			aAdd(aTit, {"E1_CLIENTE", SE1->E1_CLIENTE, Nil})
			aAdd(aTit, {"E1_LOJA", SE1->E1_LOJA, Nil})

			Aadd(atit, {"AUTMOTBX",     "NOR",  Nil})
			Aadd(aTit, {"AUTDTCREDITO", dBaixa, Nil})
			aAdd(aTit, {"AUTDTBAIXA",   dBaixa, Nil})               // Data do lancamento da baixa
			aAdd(aTit, {"AUTVALREC",    nVal,   Nil})               // Valor efetivamente recebido
			aAdd(aTit, {"AUTBANCO",     cBco,   Nil})               // Portador (opcional)
			aAdd(aTit, {"AUTAGENCIA",   cAgc,   Nil})               // Agencia (opcional)
			aAdd(aTit, {"AUTCONTA",     cCta,   Nil})               // Conta corrente (opcional)
			aAdd(aTit, {"AUTHIST", "Baixa via PIX", Nil})           // Historico

			MsExecAuto({|x, y, z| FINA070(x, y, z)}, aTit, 3)

			If lMsErroAuto
				aErro := GetAutoGRLog()

				For nX := 1 To Len(aErro)
					cMsg += AllTrim(aErro[nX]) + " "
				Next nX

				lOk := .F.

				DisarmTransaction()
			EndIf

		End Transaction
	Next nI

	If !lOk
		FWLogMsg("Bx Contas a Receber [PIX] com erro: " + cMsg)
	Else
		FWAlertSuccess('Baixas [PIX] executados com sucesso.','Baixas Contas a Receber')
	EndIf

Return NIL

/*/
	+==================================================================================================+
	| Funcao      | procArqRet                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descricao   | Processamento do arquivo retorno PIX com 3 niveis de conciliacao:                 |
	|             |   1) NSU direto no SE1                                                            |
	|             |   2) CPF/CNPJ (via SA1) + Valor + Data de Pagamento                               |
	|             |   3) Valor + Data de Pagamento (contingencia)                                     |
	+==================================================================================================+
/*/
STATIC FUNCTION procArqRet(cFile, dDataEff)

	Local oDlgProc
	Local oFont12  := TFont():New("Arial", , -12)
	Local oFont14  := TFont():New("Arial", , -14)

	//----- Arquivo
	Local nHdlRet  := 0
	Local nTamArq  := 0
	Local nLidos   := 0
	Local cBuffer  := ""
	Local cLinha   := ""
	Local cTipoReg := ""

	//----- Totais por tipo
	Local nQtdTP1  := 0
	Local nValTP1  := 0
	Local nQtdTP4  := 0
	Local nQtdTP5  := 0
	Local nValTP5  := 0
	Local nQtdTot  := 0

	//----- Contadores
	Local nI       := 0

	//----- Dados do registro
	Local cIDTran     := ""
	Local cChavePix   := ""
	Local cNsNum      := ""
	Local cOcorr      := ""
	Local cLinkPix    := ""
	Local cLinkPay    := ""
	Local cQrCode     := ""
	Local cMotBan     := ""
	Local nVlrOrig    := 0
	Local nValRec     := 0
	Local nJuros      := 0
	Local nMulta      := 0
	Local nDescont    := 0

	//----- Recebedor (Type 5)
	Local recCNPJCPF  := ""
	Local recAgencia  := ""
	Local recConta    := ""
	Local recChave    := ""

	//----- Pagador (Type 5)
	Local pagCNPJCPF  := ""
	Local pagNome     := ""

	//----- Datas
	Local datMvto     := Ctod("//")
	Local datVcto     := Ctod("//")

	//----- Arrays de processamento
	Local aPixInfo    := {}
	Local aPixTipo1   := {}
	Local aPixTipo4   := {}
	Local aPixTipo5   := {}
	Local aPixConc    := {}
	Local aPixNConc   := {}
	Local nConcNSU    := 0
	Local nConcCPF    := 0
	Local nConcVD     := 0

	//----- Filial corrente do SE1
	Local cFilSE1     := xFilial("SE1")

	If Empty(AllTrim(cFile))
		FWAlertInfo("Selecione um arquivo retorno.", "Processamento de Pagamentos PIX")
		Return .F.
	EndIf

	If !File(cFile)
		FWAlertInfo("Arquivo de retorno nao localizado.", "Processamento de Pagamentos PIX")
		Return .F.
	EndIf

	nHdlRet := FOPEN(cFile, 0 + 64)
	If nHdlRet == -1
		FWAlertInfo("Falha ao abrir o arquivo retorno: " + cFile, "Processamento de Pagamentos PIX")
		Return .F.
	EndIf


	//=========================================================================================//
	//	                                                                                       //
	//                       Leitura linha a linha do arquivo retorno                          //
	//	                                                                                       //
	//=========================================================================================//

	nTamArq := FSEEK(nHdlRet, 0, 2)
	FSEEK(nHdlRet, 0, 0)

	While nLidos < nTamArq
		cBuffer := ""
		cLinha  := ""
		nTamLin := 0

		//----- Leitura byte a byte até encontrar CR+LF ou fim do arquivo
		While nLidos < nTamArq
			FREAD(nHdlRet, @cBuffer, 1)
			nLidos++

			If cBuffer == Chr(13) .Or. cBuffer == Chr(10)
				Exit
			EndIf

			cLinha += cBuffer
			nTamLin++
		EndDo

		//----- Descarta linhas vazias
		If Empty(cLinha)
			Loop
		EndIf

		//-------------------------------------------------------------------------------------------
		// Descarta header (posicao 1 = "0") e trailer (posicao 1 = "9")
		//-------------------------------------------------------------------------------------------
		If SubStr(cLinha, 1, 1) == "0" .Or. SubStr(cLinha, 1, 1) == "9"
			Loop
		EndIf

		//-------------------------------------------------------------------------------------------
		// Inicializa variaveis do registro
		//-------------------------------------------------------------------------------------------
		cIDTran     := ""
		cChavePix   := ""
		cNsNum      := ""
		cOcorr      := ""
		cLinkPix    := ""
		cLinkPay    := ""
		cQrCode     := ""
		cMotBan     := ""
		nVlrOrig    := 0
		nValRec     := 0
		nJuros      := 0
		nMulta      := 0
		nDescont    := 0
		datMvto     := Ctod("//")
		datVcto     := Ctod("//")
		recCNPJCPF  := ""
		recAgencia  := ""
		recConta    := ""
		recChave    := ""
		pagCNPJCPF  := ""
		pagNome     := ""

		//-------------------------------------------------------------------------------------------
		// Identifica o tipo de registro (posicao 1)
		//   1 = Confirmacao do Transmissor (Transmitter Response)
		//   4 = QR Code (EMV/Payload)
		//   5 = Confirmacao Final (Receiver Response)
		//-------------------------------------------------------------------------------------------
		cTipoReg := SubStr(cLinha, 1, 1)

		//-------------------------------------------------------------------------------------------
		// TIPO 1 ou TIPO 5: Dados comuns da transacao PIX
		//-------------------------------------------------------------------------------------------
		If cTipoReg $ "1|5"

			//----- ID Transacao (posicao 25-52, 28 caracteres)
			cIDTran := AllTrim(SubStr(cLinha, 25, 28))

			//----- Chave PIX (posicao 57-98, 42 caracteres)
			cChavePix := AllTrim(SubStr(cLinha, 57, 42))

			//----- NSU (posicao 99-108, 10 caracteres numericos)
			cNsNum := AllTrim(SubStr(cLinha, 99, 10))

			//----- Codigo de Ocorrencia (posicao 109, 1 caractere)
			cOcorr := PadR(AllTrim(SubStr(cLinha, 109, 1)), 3)

			//----- Valor Original (posicao 137-151, 15 caracteres, centavos)
			nVlrOrig := Round(Val(SubStr(cLinha, 137, 15)) / 100, 2)
		EndIf

		//-------------------------------------------------------------------------------------------
		// TIPO 5: Confirmacao Final (Receiver Response) â€” campos adicionais
		//-------------------------------------------------------------------------------------------
		If cTipoReg == "5"

			//----- Dados do Recebedor
			recCNPJCPF := SubStr(cLinha, 047, 014)
			recAgencia := SubStr(cLinha, 061, 004)
			recConta   := SubStr(cLinha, 065, 020)
			recChave   := SubStr(cLinha, 089, 077)

			//----- Dados do Pagador
			pagCNPJCPF := SubStr(cLinha, 336, 014)
			pagNome    := SubStr(cLinha, 350, 140)

			// --- Data da movimentacao (posicao 169-176, YYYYMMDD)
			cString := SubStr(cLinha, 169, 008)
			If !Empty(AllTrim(cString)) .And. cString != "00000000"
				datMvto := CtoD(SubStr(cString, 7, 2) + "/" + SubStr(cString, 5, 2) + "/" + SubStr(cString, 1, 4))
			EndIf

			// --- Data de vencimento (posicao 177-184, YYYYMMDD)
			cString := SubStr(cLinha, 177, 008)
			If !Empty(AllTrim(cString)) .And. cString != "00000000"
				datVcto := CtoD(SubStr(cString, 7, 2) + "/" + SubStr(cString, 5, 2) + "/" + SubStr(cString, 1, 4))
			EndIf

			// --- Juros (posicao 216-230, 15 caracteres, centavos)
			nJuros := Val(SubStr(cLinha, 216, 015)) / 100

			// --- Multa (posicao 233-247, 15 caracteres, centavos)
			nMulta := Val(SubStr(cLinha, 233, 015)) / 100

			// --- Desconto (posicao 267-281, 15 caracteres, centavos)
			nDescont := Val(SubStr(cLinha, 267, 015)) / 100

			// --- Valor de Pagamento (posicao 301-315, 15 caracteres, centavos)
			nValRec := Val(SubStr(cLinha, 301, 015)) / 100
		EndIf

		//-------------------------------------------------------------------------------------------
		// TIPO 1: Confirmacao do Transmissor (Transmitter Response) â€” campos adicionais
		//-------------------------------------------------------------------------------------------
		If cTipoReg == "1"
			//----- Vencimento/Validade QR Code (posicao 110-117, YYYYMMDD)
			cString := SubStr(cLinha, 110, 8)
			If !Empty(AllTrim(cString)) .And. cString != "00000000"
				dDtVldQrCod := CtoD(SubStr(cString, 7, 2) + "/" + SubStr(cString, 5, 2) + "/" + SubStr(cString, 1, 4))
			EndIf

			//----- Data de Aplicacao (posicao 121-128, YYYYMMDD)
			cString := SubStr(cLinha, 121, 8)
			If !Empty(AllTrim(cString)) .And. cString != "00000000"
				dBaixa := CtoD(SubStr(cString, 7, 2) + "/" + SubStr(cString, 5, 2) + "/" + SubStr(cString, 1, 4))
			EndIf

			//----- Data Vencimento (posicao 129-136, YYYYMMDD)
			cString := SubStr(cLinha, 129, 8)
			If !Empty(AllTrim(cString)) .And. cString != "00000000"
				dDtVc := CtoD(SubStr(cString, 7, 2) + "/" + SubStr(cString, 5, 2) + "/" + SubStr(cString, 1, 4))
			EndIf

			//----- Motivo Banco (posicao 227-241, 15 caracteres)
			cMotBan := AllTrim(SubStr(cLinha, 227, 15))

			//----- Link PIX (posicao 501-550, 50 caracteres)
			cLinkPix := SubStr(cLinha, 501, 50)

			//----- Link Pay (posicao 551-600, 50 caracteres)
			cLinkPay := SubStr(cLinha, 551, 50)

			//----- Descarta ocorrencia "02" (rejeitada)
			If AllTrim(cOcorr) == "02"
				Loop
			EndIf
		EndIf

		//-------------------------------------------------------------------------------------------
		// TIPO 4: QR Code (EMV/Payload)
		//-------------------------------------------------------------------------------------------
		If cTipoReg == "4"
			//----- ID Transacao (posicao 2-29, 28 caracteres)
			cIDTran := AllTrim(SubStr(cLinha, 2, 28))

			//----- NSU (posicao 30-40, 11 caracteres)
			cNsNum := AllTrim(SubStr(cLinha, 30, 11))

			//----- Codigo de Ocorrencia (posicao 41, 1 caractere)
			cOcorr := AllTrim(SubStr(cLinha, 41, 1))

			//----- QR Code EMV (posicao 42-251, 210 caracteres)
			cQrCode := AllTrim(SubStr(cLinha, 42, 210))

			If Empty(cQrCode) .Or. Empty(cIDTran)
				Loop
			EndIf
		EndIf

		//-------------------------------------------------------------------------------------------
		// Agrupa na matriz geral de retorno
		//-------------------------------------------------------------------------------------------
		AAdd(aPixInfo, { cTipoReg, cIDTran, cChavePix, cNsNum, datMvto, nValRec, nJuros, nMulta, nDescont, cOcorr, cMotBan, cLinkPix, cLinkPay, cQrCode })

		//-------------------------------------------------------------------------------------------
		// Classifica por tipo de registro
		//-------------------------------------------------------------------------------------------
		If cTipoReg == "1"
			AAdd(aPixTipo1, { cIDTran, cChavePix, cNsNum, nValRec, cOcorr, cMotBan, cLinkPix, cLinkPay, dBaixa, dDtVc, dDtVldQrCod })
		ElseIf cTipoReg == "4"
			AAdd(aPixTipo4, { cIDTran, cChavePix, cQrCode, cOcorr })
		ElseIf cTipoReg == "5"
			AAdd(aPixTipo5, { cIDTran, cChavePix, cNsNum, nValRec, cOcorr, datMvto, datVcto, nJuros, nMulta, nDescont, recCNPJCPF, pagCNPJCPF, pagNome })
		EndIf

		//-------------------------------------------------------------------------------------------
		// Conciliacao SE1 â€” 3 niveis de busca
		//-------------------------------------------------------------------------------------------
		If !Empty(AllTrim(cNsNum)) .And. cTipoReg == "5"

			// --- Nivel 1: Busca direta por NSU no SE1
			If getPorNSU(cFilSE1, cNsNum, nValRec)
				nConcNSU++
				AAdd(aPixConc, { cNsNum, "NSU", cIDTran, cChavePix, nValRec, cOcorr })
			Else
				// --- Nivel 2: CPF/CNPJ do pagador via SA1 + Valor + Data
				If !Empty(AllTrim(pagCNPJCPF))
					If getPorCPF(cFilSE1, pagCNPJCPF, nValRec, datMvto)
						nConcCPF++
						AAdd(aPixConc, { cNsNum, "CPF", cIDTran, cChavePix, nValRec, cOcorr })
					Else
						// --- Nivel 3: Valor + Data de Pagamento (contingencia)
						If matchPorValorData(cFilSE1, nValRec, datMvto)
							nConcVD++
							AAdd(aPixConc, { cNsNum, "VD", cIDTran, cChavePix, nValRec, cOcorr })
						Else
							AAdd(aPixNConc, { cNsNum, cIDTran, cChavePix, nValRec, cOcorr, pagCNPJCPF, pagNome })
						EndIf
					EndIf
				Else
					// --- Nivel 3: Somente Valor + Data (sem CPF/CNPJ)
					If getPorVal(cFilSE1, nValRec, datMvto)
						nConcVD++
						AAdd(aPixConc, { cNsNum, "VD", cIDTran, cChavePix, nValRec, cOcorr })
					Else
						AAdd(aPixNConc, { cNsNum, cIDTran, cChavePix, nValRec, cOcorr, "", "" })
					EndIf
				EndIf
			EndIf
		EndIf

	EndDo

	FCLOSE(nHdlRet)

	//-------------------------------------------------------------------------------------------
	// Totalizacao por tipo
	//-------------------------------------------------------------------------------------------
	nQtdTP1 := Len(aPixTipo1)
	For nI := 1 To nQtdTP1
		nValTP1 += aPixTipo1[nI, 4]
	Next nI

	nQtdTP4 := Len(aPixTipo4)
	nQtdTP5 := Len(aPixTipo5)

	For nI := 1 To nQtdTP5
		nValTP5 += aPixTipo5[nI, 4]
	Next nI

	nQtdTot := Len(aPixInfo)

	//-------------------------------------------------------------------------------------------
	// Form com o resultado do processamento
	//-------------------------------------------------------------------------------------------
	DEFINE MSDIALOG oDlgProc TITLE "Resultado do Processamento dos Pagamentos via PIX" FROM 0, 0 TO 280, 700 PIXEL

	//----- Cabecalho
	@ 010, 200 SAY "Quantidade"                          SIZE 100, 010 Of oDlgProc FONT oFont12 Pixel
	@ 010, 320 SAY "R$ Total"                            SIZE 100, 010 Of oDlgProc FONT oFont12 Pixel

	//--- Registros por tipo
	@ 025, 010 SAY "Registros Tipo 1 (Transmissor)"     SIZE 150, 010 Of oDlgProc FONT oFont12 Pixel
	@ 037, 010 SAY "Registros Tipo 4 (QR Code)"         SIZE 150, 010 Of oDlgProc FONT oFont12 Pixel
	@ 049, 010 SAY "Registros Tipo 5 (Recebedor)"       SIZE 150, 010 Of oDlgProc FONT oFont12 Pixel
	@ 061, 010 SAY "Total de Registros"                  SIZE 150, 010 Of oDlgProc FONT oFont12 Pixel

	//----- Quantidades
	@ 025, 225 MSGET nQtdTP1 PICTURE "999,999,999"      SIZE 55, 12 Of oDlgProc PIXEL FONT oFont14
	@ 025, 325 MSGET nValTP1 PICTURE "@E 9,999,999.99"  SIZE 75, 12 Of oDlgProc PIXEL FONT oFont14

	@ 037, 225 MSGET nQtdTP4 PICTURE "999,999,999"      SIZE 55, 12 Of oDlgProc PIXEL FONT oFont14

	@ 049, 225 MSGET nQtdTP5 PICTURE "999,999,999"      SIZE 55, 12 Of oDlgProc PIXEL FONT oFont14
	@ 049, 325 MSGET nValTP5 PICTURE "@E 9,999,999.99"  SIZE 75, 12 Of oDlgProc PIXEL FONT oFont14

	@ 061, 225 MSGET nQtdTot PICTURE "999,999,999"      SIZE 55, 12 Of oDlgProc PIXEL FONT oFont14

	//----- Separador
	@ 075, 010 SAY Replicate("_", 90) SIZE 300, 010 Of oDlgProc PIXEL

	//----- Conciliacao
	@ 085, 010 SAY "Registros Conciliados (NSU)"         SIZE 150, 010 Of oDlgProc FONT oFont12 Pixel
	@ 085, 225 MSGET nConcNSU PICTURE "999,999,999"     SIZE 55, 12 Of oDlgProc PIXEL FONT oFont14

	@ 097, 010 SAY "Registros Conciliados (CPF/CNPJ)"   SIZE 150, 010 Of oDlgProc FONT oFont12 Pixel
	@ 097, 225 MSGET nConcCPF PICTURE "999,999,999"     SIZE 55, 12 Of oDlgProc PIXEL FONT oFont14

	@ 109, 010 SAY "Registros Conciliados (Valor+Data)" SIZE 150, 010 Of oDlgProc FONT oFont12 Pixel
	@ 109, 225 MSGET nConcVD  PICTURE "999,999,999"     SIZE 55, 12 Of oDlgProc PIXEL FONT oFont14

	@ 121, 010 SAY "Registros Nao Conciliados"           SIZE 150, 010 Of oDlgProc FONT oFont12 Pixel
	@ 121, 225 MSGET Len(aPixNConc) PICTURE "999,999,999" SIZE 55, 12 Of oDlgProc PIXEL FONT oFont14

	@ 133, 010 SAY Replicate("_", 90) SIZE 300, 010 Of oDlgProc PIXEL

	//----- Botao sair
	@ 140, 300 Button oBtnSair;
		Prompt "Sair";
		Size 040, 015 OF oDlgProc;
		FONT oFont14 Pixel ;
		Action oDlgProc:End()

	ACTIVATE MsDialog oDlgProc CENTERED

	FWAlertInfo("Processamento concluido." + Chr(13) + Chr(10) + ;
		"Registros lidos: " + Str(nQtdTot) + Chr(13) + Chr(10) + ;
		"Conciliados (NSU): " + Str(nConcNSU) + Chr(13) + Chr(10) + ;
		"Conciliados (CPF): " + Str(nConcCPF) + Chr(13) + Chr(10) + ;
		"Conciliados (V+D): " + Str(nConcVD) + Chr(13) + Chr(10) + ;
		"Nao conciliados: " + Str(Len(aPixNConc)), ;
		"Registros processados: " + Str(nQtdTot))

Return .T.

/*/
	+==================================================================================================+
	| Funcao      | getPorNSU                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descricao   | Busca direta do título no SE1 pelo NSU                                             |
	+==================================================================================================+
/*/
STATIC FUNCTION getPorNSU(cFilSE1, cNsNum, nValor)

	Local lRet     := .F.
	Local aAreaSE1 := SE1->(GetArea())
	Local cNumAux  := ""

	Begin Sequence

		cNumAux := PadR(cNsNum, TamSX3("E1_NUM")[1])

		DbSelectArea("SE1")
		SE1->(DbSetOrder(1))
		If SE1->(DbSeek(cFilSE1 + cNumAux))

			While !SE1->(Eof()) .And. SE1->E1_FILIAL == cFilSE1 .And. AllTrim(SE1->E1_NUM) == AllTrim(cNsNum)

				If Empty(SE1->E1_BAIXA) .And. SE1->E1_SALDO == nValor
					lRet := .T.
					Exit
				EndIf

				SE1->(DbSkip())
			EndDo
		EndIf

		Recover
		lRet := .F.

	End Sequence

	RestArea(aAreaSE1)

Return lRet

/*/
	+==================================================================================================+
	| Funcao      | getPorCPF                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descricao   | Busca o cliente por CPF/CNPJ, depois procura título em aberto                      |
	+==================================================================================================+
/*/
STATIC FUNCTION getPorCPF(cFilSE1, cCpfCnpj, nValor, dDataPag)

	Local lRet      := .F.
	Local aAreaSA1  := SA1->(GetArea())
	Local aAreaSE1  := SE1->(GetArea())
	Local cCodCli   := ""
	Local cLojaCli  := ""

	Begin Sequence

		//----- Busca cliente por CPF/CNPJ no SA1
		DbSelectArea("SA1")
		SA1->(DbSetOrder(3)) // A1_CGC
		If SA1->(DbSeek(xFilial("SA1") + AllTrim(cCpfCnpj)))
			cCodCli  := SA1->A1_COD
			cLojaCli := SA1->A1_LOJA
		Else
			//----- Tenta com zeros a esquerda (CNPJ 14 digitos, CPF 11 digitos)
			If Len(AllTrim(cCpfCnpj)) == 11
				SA1->(DbSeek(xFilial("SA1") + PadL(AllTrim(cCpfCnpj), 14, "0")))
			ElseIf Len(AllTrim(cCpfCnpj)) == 14
				SA1->(DbSeek(xFilial("SA1") + SubStr(AllTrim(cCpfCnpj), 2)))
			EndIf
			If Found()
				cCodCli  := SA1->A1_COD
				cLojaCli := SA1->A1_LOJA
			EndIf
		EndIf

		//----- Se encontrou o cliente, busca titulos dele
		If !Empty(cCodCli)
			DbSelectArea("SE1")
			SE1->(DbSetOrder(2)) // E1_FILIAL + E1_CLIENTE + E1_LOJA
			If SE1->(DbSeek(cFilSE1 + cCodCli + cLojaCli))
				While !SE1->(Eof()) .And. SE1->E1_FILIAL == cFilSE1 .And. ;
						SE1->E1_CLIENTE == cCodCli .And. SE1->E1_LOJA == cLojaCli

					If Empty(SE1->E1_BAIXA) .And. SE1->E1_SALDO == nValor .And. ;
							(SE1->E1_VENCTO == dDataPag .Or. SE1->E1_VENCREA == dDataPag)
						lRet := .T.
						Exit
					EndIf

					SE1->(DbSkip())
				EndDo
			EndIf
		EndIf

		Recover
		lRet := .F.

	End Sequence

	RestArea(aAreaSA1)
	RestArea(aAreaSE1)

Return lRet

/*/
	+==================================================================================================+
	| Funcao      | getPorVal                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descricao   | Busca o título na SE1 por PJ, depois procura título em aberto                      |
	+==================================================================================================+
/*/
/*/{Protheus.doc} matchPorValorData
Ultimo recurso: busca qualquer titulo em aberto com mesmo valor e data.
@param cFilSE1, Caracter, Filial do SE1
@param nValor, Numerico, Valor do pagamento
@param dDataPag, Date, Data de pagamento
@return Logico, .T. se encontrou
/*/
Static Function getPorVal(cFilSE1, nValor, dDataPag)

	Local lRet     := .F.
	Local aAreaSE1 := SE1->(GetArea())

	Begin Sequence

		DbSelectArea("SE1")
		SE1->(DbSetOrder(4)) // E1_FILIAL + E1_VENCTO
		If SE1->(DbSeek(cFilSE1 + DtoS(dDataPag)))
			While !SE1->(Eof()) .And. SE1->E1_FILIAL == cFilSE1 .And. SE1->E1_VENCTO == dDataPag
				If Empty(SE1->E1_BAIXA) .And. SE1->E1_SALDO == nValor
					lRet := .T.
					Exit
				EndIf
				SE1->(DbSkip())
			EndDo
		EndIf

		Recover
		lRet := .F.

	End Sequence

	RestArea(aAreaSE1)

Return lRet
