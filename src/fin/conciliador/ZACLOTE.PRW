#INCLUDE "PROTHEUS.CH"
#INCLUDE "PARMTYPE.CH"
#INCLUDE "TOTVS.CH"
#INCLUDE "RPTDEF.CH"
#INCLUDE "TOPCONN.CH"

/*/
+==================================================================================================+
| Fun??o      | ZACLOTE                                                                            |
|-------------+------------------------------------------------------------------------------------|
| Descri??o   | Localiza, ainda n?o validadas, no contas a receber (SE1)                           |
|--------------------------------------------------------------------------------------------------|
| Ocorr?ncias                                                                                      |
|     JOL 25/04/2026 - Inicio da implementa??o                                                     |
+==================================================================================================+
/*/
USER FUNCTION ZACLOTE(aDados)

	Local nI            := 0
	Local nReg          := 0
	Local cTRB          := ''
	Local nQtde         := 0

	Local aMatch		:= {}

	Local nQtdTotal     := 0
	Local nValTotal     := 0

	Local nQtdMatch     := 0
	Local nValMatch     := 0

	Local nRegistros	:= 0

	Local cTipo     := ''
	Local cBandeira := ''
	Local cNumFil   := ''
	Local cEmissao  := ''
	Local nValor    := 0
	Local cNsu      := ''
	Local cAutoriza := ''

	If Len(aDados) == 0
		FWAlertInfo("Nenhuma venda está disponível para ser validada.", "Validação de Vendas")
		Return NIL
	EndIf
	If Len(aDados) == 1
		If aDados[1,3] == ""
			FWAlertInfo("Nenhuma venda está disponível para ser validada.", "Validação de Vendas")
			Return NIL
		EndIf
	EndIf

	//----- ESTRUTURA DO VETOR aDados
	// 01 - Chave - situacao da venda
	// 02 - selecao
	// 03 - Filial onde ocorreu a venda
	// 04 - PV
	// 05 - RV
	// 06 - ORIGEM (descricao)
	// 07 - BANDEIRA (nome)
	// 08 - Valor da venda
	// 09 - Tipo de registro no SE1
	// 10 - Numero do titulo no SE1
	// 11 - Numero da parcela no SE1
	// 12 - Data da venda
	// 13 - Data da importacao
	// 14 - Numero do registro no SE1
	// 15 - Numero do registro no SZV
	// 16 - Codigo da bandeira
	// 17 - Codigo da origem
	// 18 - NSU
	// 19 - AUTORIZACAO

	Begin Transaction

		nRegistros := Len(aDados)+1
		ProcRegua(nRegistros)

		For nI := 1 To Len(aDados)
			IncProc("Verficando vendas x contas a receber" + cValToChar(nI) + " de " + cValToChar(nRegistros))

			//----- Verifica a situação da venda
			If AllTrim(aDados[nI, 01]) == "01" .OR. AllTrim(aDados[nI, 01]) == ""
				cTipo     := ''
				nReg      := aDados[nI, 15]
				cNumFil   := aDados[nI, 03]
				nValor    := aDados[nI, 08]

				If ValType(aDados[nI, 12])=='C'
					cEmissao  := SubStr(aDados[nI, 12],7,4)+SubStr(aDados[nI, 12],4,2)+SubStr(aDados[nI, 12],1,2)
				Else
					cEmissao  := DtoS(aDados[nI, 12])
				EndIf

				nValTotal += aDados[nI][8]
				nQtdTotal ++

				//----- ESTRUTURA DO VETOR aMatch
				// 01 - Filial onde ocorreu a venda
				// 02 - PV
				// 03 - RV
				// 04 - Valor da venda
				// 05 - Prefixo SE1
				// 06 - Tipo SE1
				// 07 - N?mero SE1
				// 08 - Parcela SE1
				// 09 - Registro SE1
				// 10 - Registro SZV

				cTRB := GetNextAlias()

				//----- Pagamentos via PIX
				If 	aDados[nI, 17] == 'P00'
					cTipo     := 'PX'
					cAutoriza := aDados[nI, 19] + aDados[nI, 18]

					BeginSql Alias cTRB
						SELECT	E1_PREFIXO,
								E1_NUM,
								E1_PARCELA,
								E1_EMISSAO,
								E1_VENCREA,
								E1_VALOR,
								E1_FILIAL,
								E1_TIPO,
								R_E_C_N_O_
						FROM %table:SE1%
						WHERE	E1_TIPO=%exp:cTipo% AND
								E1_CARTAUT=%exp:cAutoriza% AND
								// E1_VALOR = %exp:nValor% AND
								// E1_EMISSAO = %exp:cEmissao% AND
								E1_SALDO > 0 AND
								%notDel%
						// WHERE	E1_FILIAL=%exp:cNumFil% AND
						// 		E1_TIPO=%exp:cTipo% AND
						//         E1_CARTAUT=%exp:cAutoriza% AND
						// 		E1_VALOR = %exp:nValor% AND
						// 		E1_EMISSAO = %exp:cEmissao% AND
						// 		E1_SALDO > 0 AND
						// 		%notDel%
					EndSql

					If Select(cTRB) > 0
						nQtde := 0

						(cTRB)->(DbGoTop())

						While !(cTRB)->(Eof())
							nQtde++
							(cTRB)->(DbSkip())
						EndDo

						(cTRB)->(DbGoTop())

						If nQtde == 1
							nQtdMatch ++
							nValMatch += (cTRB)->E1_VALOR

							AAdd(aMatch, {;
								aDados[nI, 03],;
								aDados[nI, 04],;
								aDados[nI, 05],;
								(cTRB)->E1_VALOR,;
								(cTRB)->E1_PREFIXO,;
								(cTRB)->E1_TIPO,;
								(cTRB)->E1_NUM,;
								(cTRB)->E1_PARCELA,;
								(cTRB)->R_E_C_N_O_,;
								nReg,;
								' '})
						EndIf
					EndIf

					(cTRB)->(DbCloseArea())
				EndIf

				//----- Pagamentos via POS CC
				If aDados[nI, 17] == 'P01'
					cTipo     := 'CC'
					cAutoriza := aDados[nI, 19]
					cNsu      := AllTrim(Str(Val(aDados[nI, 18])))

					BeginSql Alias cTRB
						SELECT	E1_PREFIXO,
								E1_NUM,
								E1_PARCELA,
								E1_EMISSAO,
								E1_VENCREA,
								E1_VALOR,
								E1_FILIAL,
								E1_TIPO,
								R_E_C_N_O_
            			FROM %table:SE1%
            			WHERE	E1_FILIAL=%exp:cNumFil% AND
               					E1_TIPO=%exp:cTipo% AND
                       			E1_EMISSAO=%exp:cEmissao% AND
								E1_SALDO > 0 AND
								E1_CARTAUT=%exp:cAutoriza% AND
								E1_NSUTEF=%exp:cNsu% AND
								E1_VALOR=%exp:nValor% AND
            				%notDel%
					EndSql

					If Select(cTRB) > 0
						nQtde := 0

						(cTRB)->(DbGoTop())

						While !(cTRB)->(Eof())
							nQtde++
							(cTRB)->(DbSkip())
						EndDo

						(cTRB)->(DbGoTop())

						If nQtde == 1
							nQtdMatch ++
							nValMatch += (cTRB)->E1_VALOR

							AAdd(aMatch, {;
								aDados[nI, 03],;
								aDados[nI, 04],;
								aDados[nI, 05],;
								(cTRB)->E1_VALOR,;
								(cTRB)->E1_PREFIXO,;
								(cTRB)->E1_TIPO,;
								(cTRB)->E1_NUM,;
								(cTRB)->E1_PARCELA,;
								(cTRB)->R_E_C_N_O_,;
								nReg,;
								' '})
						EndIf
					EndIf

					(cTRB)->(DbCloseArea())
				EndIf

				//----- Pagamentos via POS CD
				If aDados[nI, 17] == 'P02'
					cTipo     := 'CD'
					cAutoriza := aDados[nI, 19]

					// FWAlertInfo('cFilial: '+cNumFil+Chr(13)+Chr(10)+;
						// 	'cTipo: '+cTipo+Chr(13)+Chr(10)+;
						// 	'cEmissao: '+cEmissao+Chr(13)+Chr(10)+;
						// 	'cAutoriza: '+cAutoriza+Chr(13)+Chr(10),'Acha Venda')

					BeginSql Alias cTRB
						SELECT	E1_PREFIXO,
								E1_NUM,
								E1_PARCELA,
								E1_EMISSAO,
								E1_VENCREA,
								E1_VALOR,
								E1_FILIAL,
								E1_TIPO,
								R_E_C_N_O_
						FROM %table:SE1%
						WHERE	E1_FILIAL=%exp:cNumFil% AND
								E1_TIPO=%exp:cTipo% AND
								E1_EMISSAO=%exp:cEmissao% AND
								E1_SALDO > 0 AND
								// E1_CARTAO LIKE %exp:cBandeira% AND
								E1_CARTAUT=%exp:cAutoriza% AND
								E1_VALOR=%exp:nValor% AND
								%notDel%
					EndSql

					If Select(cTRB) > 0
						nQtde := 0

						(cTRB)->(DbGoTop())

						While !(cTRB)->(Eof())
							nQtde++
							(cTRB)->(DbSkip())
						EndDo

						(cTRB)->(DbGoTop())

						If nQtde == 1
							nQtdMatch ++
							nValMatch += (cTRB)->E1_VALOR

							AAdd(aMatch, {;
								aDados[nI, 03],;
								aDados[nI, 04],;
								aDados[nI, 05],;
								(cTRB)->E1_VALOR,;
								(cTRB)->E1_PREFIXO,;
								(cTRB)->E1_TIPO,;
								(cTRB)->E1_NUM,;
								(cTRB)->E1_PARCELA,;
								(cTRB)->R_E_C_N_O_,;
								nReg,;
								' '})
						EndIf

					EndIf

					(cTRB)->(DbCloseArea())
				EndIf

				//----- Pagamentos via TEF CC
				If aDados[nI, 17] == 'P03'
					cTipo     := 'CC'
					cAutoriza := aDados[nI, 19]
					cNsu      := Alltrim(Str(Val(aDados[nI, 18])))

					BeginSql Alias cTRB
						SELECT	E1_PREFIXO,
								E1_NUM,
								E1_PARCELA,
								E1_EMISSAO,
								E1_VENCREA,
								E1_VALOR,
								E1_FILIAL,
								E1_TIPO,
								R_E_C_N_O_
						FROM %table:SE1%
						WHERE	E1_FILIAL=%exp:cNumFil% AND
								E1_TIPO=%exp:cTipo% AND
								E1_EMISSAO=%exp:cEmissao% AND
								E1_SALDO > 0 AND
								(E1_DOCTEF=%exp:cNsu% OR E1_NSUTEF=%exp:cNsu%) AND
								E1_CARTAUT=%exp:cAutoriza% AND
								E1_VALOR=%exp:nValor% AND
								%notDel%
					EndSql

					If Select(cTRB) > 0
						nQtde := 0

						(cTRB)->(DbGoTop())

						While !(cTRB)->(Eof())
							nQtde++
							(cTRB)->(DbSkip())
						EndDo

						(cTRB)->(DbGoTop())

						If nQtde == 1
							nQtdMatch ++
							nValMatch += (cTRB)->E1_VALOR

							AAdd(aMatch, {;
								aDados[nI, 03],;
								aDados[nI, 04],;
								aDados[nI, 05],;
								(cTRB)->E1_VALOR,;
								(cTRB)->E1_PREFIXO,;
								(cTRB)->E1_TIPO,;
								(cTRB)->E1_NUM,;
								(cTRB)->E1_PARCELA,;
								(cTRB)->R_E_C_N_O_,;
								nReg,;
								' '})
						EndIf

					EndIf

					(cTRB)->(DbCloseArea())
				EndIf

				//----- Pagamentos via TEF CD
				If aDados[nI, 17] == 'P04'
					cTipo     := 'CD'
					cAutoriza := aDados[nI, 19]
					cNsu      := aDados[nI, 18]

					BeginSql Alias cTRB
						SELECT	E1_PREFIXO,
								E1_NUM,
								E1_PARCELA,
								E1_EMISSAO,
								E1_VENCREA,
								E1_VALOR,
								E1_FILIAL,
								E1_TIPO,
								R_E_C_N_O_
						FROM %table:SE1%
						WHERE	E1_FILIAL=%exp:cNumFil% AND
								E1_TIPO=%exp:cTipo% AND
								E1_EMISSAO=%exp:cEmissao% AND
								E1_SALDO > 0 AND
								(E1_DOCTEF=%exp:cNsu% OR E1_NSUTEF=%exp:cNsu%) AND
								E1_CARTAUT=%exp:cAutoriza% AND
								E1_VALOR=%exp:nValor% AND
								%notDel%
					EndSql

					If Select(cTRB) > 0
						nQtde := 0

						(cTRB)->(DbGoTop())

						While !(cTRB)->(Eof())
							nQtde++
							(cTRB)->(DbSkip())
						EndDo

						(cTRB)->(DbGoTop())

						If nQtde == 1
							(cTRB)->(DbGoTop())

							nQtdMatch ++
							nValMatch += (cTRB)->E1_VALOR

							AAdd(aMatch, {;
								aDados[nI, 03],;
								aDados[nI, 04],;
								aDados[nI, 05],;
								(cTRB)->E1_VALOR,;
								(cTRB)->E1_PREFIXO,;
								(cTRB)->E1_TIPO,;
								(cTRB)->E1_NUM,;
								(cTRB)->E1_PARCELA,;
								(cTRB)->R_E_C_N_O_,;
								nReg,;
								' '})
						EndIf

					EndIf

					(cTRB)->(DbCloseArea())
				EndIf

			EndIf
		Next nI
	End Transaction

	If nQtdMatch <= 0
		FWAlertInfo("Nenhuma venda foi encontrada no contas a receber.", "Valida??o de Vendas")
	Else
		brwLote(aMatch, nQtdTotal, nValTotal, nQtdMatch, nValMatch)
	EndIf

Return Nil

/*/
	+==================================================================================================+
	| Fun??o      | brwLote                                                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Descri??o   | Browse para exibir os matchs entre as vendas e contas a receber                   |
	+==================================================================================================+
/*/
STATIC FUNCTION brwLote(aDados, nQtdTotal, nValTotal, nQtdMatch, nValMatch)

	Local oDlg   := Nil
	Local oBrw   := Nil
	Local oFont  := TFont():New("Arial", , -12)
	Local oFontN := TFont():New("Arial", , -12, .T.)

	//----- Tamanho da janela (metade da tela)
	Local aSize      := MsAdvSize()
	Local nJanLarg   := aSize[5]
	Local nJanAltu   := Int(aSize[6] / 2)
	Local nMrg       := 25
	Local nTopArea   := 45
	Local nBrwH      := nJanAltu - nTopArea - 50
	Local nBtnLinha  := 4

	DEFINE MSDIALOG oDlg TITLE "Validação em Lote - Vendas x Contas a Receber" ;
		FROM 00, 00 TO 600, 800 PIXEL

	//----- Cabecalho: resumo
	@ nMrg+2, 010 SAY "Totais:" SIZE 40, 10 OF oDlg PIXEL FONT oFontN
	@ nMrg,   040 MSGET nQtdTotal PICTURE "9999999999"       SIZE 50, 12 OF oDlg PIXEL FONT oFont WHEN .F.
	@ nMrg,   090 MSGET nValTotal PICTURE "@E 99,999,999.99" SIZE 80, 12 OF oDlg PIXEL FONT oFont WHEN .F.

	@ nMrg+2, 200 SAY "Encontrados:" SIZE 60, 10 OF oDlg PIXEL FONT oFontN
	@ nMrg,   240 MSGET nQtdMatch PICTURE "9999999999"       SIZE 50, 12 OF oDlg PIXEL FONT oFont WHEN .F.
	@ nMrg,   300 MSGET nValMatch PICTURE "@E 99,999,999.99" SIZE 80, 12 OF oDlg PIXEL FONT oFont WHEN .F.

	//----- Browse principal
	oBrw := TWBrowse():New(nTopArea, nMrg, 400, 650, , , , oDlg, , , , , , , , , , , , , , .T.)
	oBrw:SetArray(aDados)
	oBrw:lAutoEdit  := .F.
	oBrw:oFont := oFont

	// oBrw:AddColumn(TCColumn():New(" ",          {|| Iif(aDados[oBrw:nAt, 11] == "X", "X", " ") }, , , , 'CENTER', 20, .T., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("Filial",     {|| aDados[oBrw:nAt, 01] }, , , , 'LEFT',  60, .F., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("PV",         {|| aDados[oBrw:nAt, 02] }, , , , 'LEFT',  60, .F., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("RV",         {|| aDados[oBrw:nAt, 03] }, , , , 'LEFT',  60, .F., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("Valor",      {|| aDados[oBrw:nAt, 04] }, "@E 999,999.99", , , 'RIGHT', 80, .F., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("Prefixo",    {|| aDados[oBrw:nAt, 05] }, , , , 'LEFT',  50, .F., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("Tipo",       {|| aDados[oBrw:nAt, 06] }, , , , 'LEFT',  40, .F., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("Numero",     {|| aDados[oBrw:nAt, 07] }, , , , 'LEFT',  80, .F., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("Parcela",    {|| aDados[oBrw:nAt, 08] }, , , , 'CENTER', 40, .F., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("Rec SE1",    {|| aDados[oBrw:nAt, 09] }, "9999999999999", , , 'RIGHT', 80, .F., .F., , , , .F., ))
	oBrw:AddColumn(TCColumn():New("Rec SZV",    {|| aDados[oBrw:nAt, 10] }, "9999999999999", , , 'RIGHT', 80, .F., .F., , , , .F., ))

	// oBrw:bLDblClick := {|| clkDuplo(oBrw, aDados) }

	//----- Botoes
	// nCol := 330
	// @ nBtnLinha, 010 BUTTON oMarcar PROMPT "Marcar Todos";
		// 	ACTION {|| Marcar('S', aDados, oBrw) };
		// 	SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	// @ nBtnLinha, 080 BUTTON oDesmarc PROMPT "Desmarcar Todos";
		// 	ACTION {|| Marcar('N', aDados, oBrw) };
		// 	SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	// @ nBtnLinha, 150 BUTTON oInverter PROMPT "Inverter";
		// 	ACTION {|| Marcar('I', aDados, oBrw) };
		// 	SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@ nBtnLinha, 220 BUTTON oGravar PROMPT "Gravação";
		ACTION {|| grvValida(aDados), oDlg:End() };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@ nBtnLinha, 290 BUTTON oSair PROMPT "Sair";
		ACTION {|| oDlg:End() };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	ACTIVATE MSDIALOG oDlg CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Fun??o      | clkDuplo                                                                           |
	|-------------+------------------------------------------------------------------------------------|
	| Descri??o   | Trata click duplo no browse - alterna marca??o                                    |
	+==================================================================================================+
/*/
STATIC FUNCTION clkDuplo(oBrw, aDados)

	Local nPos := oBrw:nAt

	If nPos < 1 .Or. nPos > Len(aDados)
		Return NIL
	EndIf

	aDados[nPos, 11] := Iif(aDados[nPos, 11] == "X", " ", "X")
	oBrw:Refresh()

Return NIL

/*/
	+==================================================================================================+
	| Fun??o      | Marcar                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descri??o   | Marca/Desmarca/Inverte a marca??o                                                  |
	+==================================================================================================+
/*/
STATIC FUNCTION Marcar(cAcao, aDados, oBrw)

	Local nI := 0

	For nI := 1 To Len(aDados)
		Do Case
		Case cAcao == 'S'
			aDados[nI, 11] := "X"
		Case cAcao == 'N'
			aDados[nI, 11] := " "
		Case cAcao == 'I'
			aDados[nI, 11] := Iif(aDados[nI, 11] == "X", " ", "X")
		EndCase
	Next nI

	oBrw:nAt := 1
	oBrw:Refresh()

Return NIL

/*/
	+==================================================================================================+
	| Função      | grvValida                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Gravacao da valida??o em lote                                                      |
	+==================================================================================================+
/*/
STATIC FUNCTION grvValida(aMatch)

	Local nI         := 0
	Local nRegSZV    := 0
	Local nRegistros := Len(aMatch)+1
	Local cFilVenda  := ''
	Local cPrefixo   := ''
	Local cTipo      := ''
	Local cTitulo    := ''
	Local cParcela   := ''

	ProcRegua(nRegistros)

	Begin Transaction
		For nI := 1 To Len(aMatch)
			IncProc("Gravando a valida??o da venda: "+Str(nI,6)+'/'+Str(nRegistros,6))

			// //----- Somente registros selecionados
			// If aMatch[nI, 11] != "X"
			// 	Loop
			// EndIf

			nRegSZV  := aMatch[nI,10]
			cPrefixo := aMatch[nI,05]
			cTipo    := aMatch[nI,06]
			cTitulo  := aMatch[nI,07]
			cParcela := aMatch[nI,08]

			DbSelectArea("SZV")
			DbSetOrder(1)
			DbGoto(nRegSZV)

			cFilVenda := SZV->ZV_E1_FIL

			RecLock("SZV", .F.)
			SZV->ZV_E1_PREF := cPrefixo
			SZV->ZV_E1_NUM  := cTitulo
			SZV->ZV_E1_PARC := cParcela
			SZV->ZV_E1_TIPO := cTipo
			SZV->ZV_CHAVE   := "02"
			SZV->ZV_VALDATA := dDataBase
			SZV->ZV_VALHORA := SubStr(Time(), 1, 5)
			SZV->ZV_VALUSER := RetCodUsr()
			MsUnLock()

			//----- Marca o titulo com "VENDA VALIDADA"
			DbSelectArea("SE1")
			DbSetOrder(1)
			If DbSeek(cFilVenda+cPrefixo+cTitulo+cParcela+cTipo)
				RecLock("SE1", .F.)
				SE1->E1_XVENDA   := 'S'
				SE1->E1_XREG     := nRegSZV
				MsUnLock()
			EndIf

			//----- Grava dados na tabela de LOG
			RecLock("SZL", .T.)
			ZL_FILIAL  := xFilial("SZL")
			ZL_USER    := RetCodUsr()
			ZL_DATA    := dDataBase
			ZL_HORA    := SubStr(Time(),1,5)
			ZL_TIPO    := 'VALM3'
			ZL_DESCRI  := 'Validação automática'
			ZL_RESUL1  := 'SZV Reg: '+Str(nRegSZV)
			ZL_RESUL2  := 'Título SE1: '+cPrefixo+'/'+cTitulo+'/'+cParcela+'/'+cTipo
			SZL->(MsUnlock())
		Next nI
	End Transaction

	FWAlertSuccess('Validação das vendas concluída com sucesso.','Validação das Vendas')

Return NIL
