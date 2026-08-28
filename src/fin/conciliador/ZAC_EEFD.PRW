#INCLUDE "TOTVS.CH"
#INCLUDE "FILEIO.CH"
#INCLUDE "PROTHEUS.CH"
#INCLUDE "FWMVCDEF.CH"
#INCLUDE "FINA914.CH"
#INCLUDE "TOPCONN.CH"

/*/
+==================================================================================================+
| Função      | ZAC_EEFD                                                                           |
|-------------+------------------------------------------------------------------------------------|
| Descrição   | Baixa de títulos via Cartão de Débito                                              |
|             |                                                                                    |
|             | REDECAR                                                                            |
|             | GETNET                                                                             |
|             |                                                                                    |
|-------------+------------------------------------------------------------------------------------|
| Ocorrências                                                                                      |
|                                                                                                  |
+==================================================================================================+
/*/
USER FUNCTION EEFD_DEB()

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
		FWAlertInfo("Nenhuma EC e sua respectiva filial n?o foi encontrada.", "Estabelecimento Comercial")
		Return(Nil)
	EndIf

	//----- Form principal
	DEFINE MSDIALOG oDlgProc TITLE "Recebimento de Pagamentos via DÉBITO" FROM 0, 0 TO 180, 720 PIXEL

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
		procE1_DEB(AllTrim(cFile), dDataEff, aEC) ) )

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
	| Ocorrências                                                                                      |
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
	| Função      | procE1_DEB                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Processamento do arquivo de vendas a Débito para usar o registros de crédito       |
	|             | em conta corrente                                                                  |
	|-------------+------------------------------------------------------------------------------------|
	| Ocorrências                                                                                      |
	|                                                                                                  |
	|                                                                                                  |
	+==================================================================================================+
/*/
STATIC FUNCTION procE1_DEB(cFile, dDataEff, aEC)

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
		FWAlertError("Arquivo não localizado: " + cFile,"Arquivo de Pagamentos")
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

	nQtde      := 0
	nTotal     := 0
	nLinha     := 0
	lValidaBco := .F.
	lTemConta  := .F.

	While !FT_FEOF()
		cLinha := FT_FReadLn()
		nLinha++

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


		//----- Validação se conta bancária a crédito está no Protheus
		If lValidaBco == .F.
			lValidaBco := .T.
			lTemConta  := .F.

			DbSelectArea("SA6")
			DbSetOrder(1)
			DbGoTop()

			While SA6->(!Eof())
				If SA6->A6_COD == cBanco
					If Val(SA6->A6_AGENCIA) == Val(cAgencia)
						If Val(SA6->A6_NUMCON) == Val(cConta)
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

		//----- Identifica os dados da venda para as linhas de detalhe do arquivo retorno
		If aLinha[01]=="05"
			__pv        := aLinha[02]
			__rv        := ''
			dVenda      := CtoD(SubStr(aLinha[4],1,2)+'/'+SubStr(aLinha[4],3,2)+'/'+SubStr(aLinha[4],5,4))
			nValor      := (Val(aLinha[5])/100)
			cAutoriza   := aLinha[20]
			cNSU        := AllTrim(Str(Val(aLinha[10])))
			__codFil    := U_achaFilial(__pv, aEC)

			nQtde  ++
			nTotal += nValor

			Aadd(aBaixa, {cNsu, __pv, __rv, dVenda, nValor, __codFil})
		EndIf

		FT_FSKIP()
	EndDo

	//----- Fecha o Arquivo
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
		cQuery := "SELECT SE1.E1_FILIAL, SE1.E1_NUM, SE1.E1_PREFIXO, SE1.E1_VALOR, "
		cQuery += "SE1.E1_EMISSAO, SE1.E1_PARCELA, SE1.R_E_C_N_O_ AS REC, "
		cQuery += "SE1.E1_TIPO, SE1.E1_CLIENTE, SE1.E1_LOJA "
		cQuery += "FROM " + RetSqlName("SE1") + " SE1 "
		cQuery += "INNER JOIN " + oTempTable:GetRealName() + " TMP "
		cQuery += "ON SE1.E1_NSUTEF = TMP.TMP_NSU "
		cQuery += "AND SE1.E1_FILIAL = TMP.TMP_FILIAL "
		cQuery += "WHERE SE1.D_E_L_E_T_ = ' '"

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
		"Baixas no EEFD: " + Str(nQtde,5) +' Total R$ '+Transform(nTotal, '@E 999,999,999.99') + Chr(13) + Chr(10) +;
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
			AADD(_aCabec, {"AUTBANCO",     _banco,          nil})
			AADD(_aCabec, {"AUTAGENCIA",   _agencia,        nil})
			AADD(_aCabec, {"AUTCONTA",     _conta,          nil})
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
