#INCLUDE "PARMTYPE.CH"
#INCLUDE "TOTVS.CH"
#INCLUDE "RPTDEF.CH"
#INCLUDE "TOPCONN.CH"

/*/
+==================================================================================================+
| Função      | ZACVALID                                                                           |
|-------------+------------------------------------------------------------------------------------|
| Descrição   | Validação das vendas                                                               |
|-------------+------------------------------------------------------------------------------------|
| Ocorr?ncias                                                                                      |
|     JOL 22/07/2026 - In?cio da criação das funções                                               |
+==================================================================================================+
/*/
USER FUNCTION ZACVALID()

	Local dDeData   := dDataBase - 1
	Local dAteData  := dDatabase
	Local cTipo     := "Todas"
	Local aTipos    := {"Todas", "Importadas", "Validadas","Conciliadas"}

	Local cPeriodo  := "Data Importação"
	Local aPeriodo  := {"Data Importação", "Data Venda"}

	Local cOrigem   := 'Todas'
	Local aOrigem   := {"Todas","Crédito","Débito","PIX"}

	Local cFilSel   := "Todas"
	Local aFiliais  := getFilial()

	Local oFont     := TFont():New("Arial",, -13, .F.)
	Local oFontN    := TFont():New("Arial",, -13, .T.)

	//----- Tamanho da janela
	Local aSize     := MsAdvSize()
	Local nJanLarg  := aSize[5]
	Local nJanAltu  := aSize[6]
	Local nBtnLinha := (nJanAltu/2)+10

	Local aDados    := {{ "", "", "", "", "", "", "", 0, "", "", "", CtoD("//"),CtoD('//'), 0, 0 }}

	Local nQtdReg   := 0
	Local nValVendas:= 0
	Local oQtdReg   := Nil
	Local oValVendas:= Nil

	Private oSem01  := LoadBitmap(GetResources(),"BR_BRANCO")
	Private oSem02  := LoadBitmap(GetResources(),"BR_AZUL")
	Private oSem03  := LoadBitmap(GetResources(),"BR_LARANJA")
	Private oSem04  := LoadBitmap(GetResources(),"BR_PRETO")
	Private oSem05	:= LoadBitmap(GetResources(),"BR_VERDE")
	Private oSem00	:= LoadBitmap(GetResources(),"ENABLE")

	Private oS_OK	:= LoadBitmap(GetResources(),"LBOK")
	Private oN_OK   := LoadBitmap(GetResources(),"LBNO")

	Private aRotina := {}

	//---------------------------------------------------------------------------------------------
	// Formulario
	//---------------------------------------------------------------------------------------------
	DEFINE MSDIALOG oDlg TITLE "Validação das Vendas" FROM 00,00 TO aSize[6],aSize[5] PIXEL FONT oFont

	@ 13, 005 SAY "Período:" OF oDlg PIXEL FONT oFont
	@ 10, 035 COMBOBOX cPeriodo ITEMS aPeriodo SIZE 65, 12 OF oDlg PIXEL FONT oFont

	@ 13, 105 SAY "Da Data:" OF oDlg PIXEL FONT oFont
	@ 10, 135 MSGET dDeData SIZE 50, 12 OF oDlg PIXEL FONT oFont

	@ 13, 190 SAY "Até Data:" OF oDlg PIXEL FONT oFont
	@ 10, 220 MSGET dAteData SIZE 50, 12 OF oDlg PIXEL FONT oFont

	@ 13, 270 SAY "Filial:" OF oDlg PIXEL FONT oFont
	@ 10, 290 COMBOBOX cFilSel ITEMS aFiliais SIZE 150, 12 OF oDlg PIXEL FONT oFont

	@ 13, 445 SAY "Situação:" OF oDlg PIXEL FONT oFont
	@ 10, 475 COMBOBOX cTipo ITEMS aTipos SIZE 40, 12 OF oDlg PIXEL FONT oFont

	@ 13, 535 SAY "Origem:" OF oDlg PIXEL FONT oFont
	@ 10, 560 COMBOBOX cOrigem ITEMS aOrigem SIZE 40, 12 OF oDlg PIXEL FONT oFont

	@ 12, 610 BUTTON oFiltrar PROMPT "Filtrar";
		ACTION MsAguarde({|| aDados := FilVendas(dDeData, dAteData, cFilSel, cTipo, cOrigem, cPeriodo), ;
		updTotais(aDados, @nQtdReg, @nValVendas, oQtdReg, oValVendas), ;
		oBrw:SetArray(aDados), ;
		oBrw:nLen := Len(aDados), ;
		oBrw:nAt  := 1, ;
		oBrw:GoTop(), ;
		oBrw:Refresh(), ;
		SysRefresh()}, "Aguarde...", "Filtrando registros de vendas", .T.);
		SIZE 45, 18 OF oDlg PIXEL FONT oFontN

	@nBtnLinha - 35, 010 BUTTON oValidar PROMPT "Validação em Lote";
		ACTION MsAguarde({|| U_ZACLOTE(aDados), ;
		aDados := FilVendas(dDeData, dAteData, cFilSel, cTipo, cOrigem, cPeriodo),;
		updTotais(aDados, @nQtdReg, @nValVendas, oQtdReg, oValVendas), ;
		oBrw:SetArray(aDados), ;
		oBrw:nLen := Len(aDados), ;
		oBrw:nAt  := 1, ;
		oBrw:GoTop(), ;
		oBrw:Refresh(), ;
		SysRefresh()}, "Aguarde...", "Analisando vendas e contas a receber.", .T.);
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@nBtnLinha - 35, 080 BUTTON oEstLote PROMPT "Estorno em Lote";
		ACTION MsAguarde({|| grvEstAll(aDados), ;
		aDados := FilVendas(dDeData, dAteData, cFilSel, cTipo, cOrigem, cPeriodo),;
		updTotais(aDados, @nQtdReg, @nValVendas, oQtdReg, oValVendas), ;
		oBrw:SetArray(aDados), ;
		oBrw:nLen := Len(aDados), ;
		oBrw:nAt  := 1, ;
		oBrw:GoTop(), ;
		oBrw:Refresh(), ;
		SysRefresh()}, "Aguarde...", "Estornando em lote.", .T.);
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@nBtnLinha - 35, 150 BUTTON oMarcar PROMPT "Marcar";
		ACTION {|| Marcar(oBrw, aDados) };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@nBtnLinha - 35, 220 BUTTON oValUnico PROMPT "Validação Manual";
		ACTION {|| validaUm(aDados),;
		aDados := FilVendas(dDeData, dAteData, cFilSel, cTipo, cOrigem, cPeriodo),;
		updTotais(aDados, @nQtdReg, @nValVendas, oQtdReg, oValVendas), ;
		oBrw:SetArray(aDados), ;
		oBrw:nLen := Len(aDados), ;
		oBrw:nAt  := 1, ;
		oBrw:GoTop(), ;
		oBrw:Refresh()};
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@nBtnLinha - 35, 290 BUTTON oEstUnico PROMPT "Estorno Manual";
		ACTION {|| estornaUm(aDados),;
		aDados := FilVendas(dDeData, dAteData, cFilSel, cTipo, cOrigem, cPeriodo),;
		updTotais(aDados, @nQtdReg, @nValVendas, oQtdReg, oValVendas), ;
		oBrw:SetArray(aDados), ;
		oBrw:nLen := Len(aDados), ;
		oBrw:nAt  := 1, ;
		oBrw:GoTop(), ;
		oBrw:Refresh()};
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@nBtnLinha - 35, 360 BUTTON oInverter PROMPT "Inverter";
		ACTION {|| Inverter(oBrw, aDados) };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@nBtnLinha - 35, 430 BUTTON oLegenda PROMPT "Legenda";
		ACTION {|| ExibeLegenda() };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@nBtnLinha - 35, 500 BUTTON oSair PROMPT "Sair";
		ACTION {|| oDlg:End() };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	//----- Browse de dados
	oBrw := TWBrowse():New(2,1, (nJanLarg/2)-100, (nJanAltu/2)-80)

	oBrw:AddColumn(TCColumn():New("Vendas",;
		{|| Iif(AllTrim(aDados[oBrw:nAt,01]) == "01", oSem01,;
		Iif(AllTrim(aDados[oBrw:nAt,01]) == "02", oSem02,;
		Iif(AllTrim(aDados[oBrw:nAt,01]) == "03", oSem03,;
		Iif(AllTrim(aDados[oBrw:nAt,01]) == "04", oSem04, oSem00)) ))},,,,'LEFT', 40, .T.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New(" ",;
		{|| If(aDados[oBrw:nAt,02] == "X", oS_OK, oN_OK)},,,,'LEFT', 30, .T.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Filial",        {|| aDados[oBrw:nAt,03] },,,,'LEFT', 80, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("PV",            {|| aDados[oBrw:nAt,04] },,,,'LEFT', 90, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("RV",            {|| aDados[oBrw:nAt,05] },,,,'LEFT', 90, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Origem",        {|| aDados[oBrw:nAt,06] },,,,'LEFT', 90, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Bandeira",      {|| aDados[oBrw:nAt,07] },,,,'LEFT', 90, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("R$ Venda",      {|| aDados[oBrw:nAt,08] },"@E 999,999.99",,,'RIGHT', 120,.F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Tipo",          {|| aDados[oBrw:nAt,09] },,,,'LEFT', 90, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Título",        {|| aDados[oBrw:nAt,10] },,,,'LEFT', 90, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Parcela",       {|| aDados[oBrw:nAt,11] },,,,'LEFT', 90, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Dt Venda",      {|| aDados[oBrw:nAt,12] },,,,'LEFT', 90, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Dt Importação", {|| aDados[oBrw:nAt,13] },,,,'LEFT', 90, .F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Nº Reg SE1",    {|| aDados[oBrw:nAt,14] },"999999999999999",,,'RIGHT', 120,.F.,.F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Nº Reg SZV",    {|| aDados[oBrw:nAt,15] },"999999999999999",,,'RIGHT', 120,.F.,.F.,,,,.F.,))

	oBrw:SetArray(aDados)
	oBrw:nLen  := Len(aDados)
	oBrw:oFONT := oFont

	oBrw:bLDblClick := {|| If(Len(aDados) > 0, (aDados[oBrw:nAt, 02] := If(aDados[oBrw:nAt, 02] == "X", "", "X"), oBrw:Refresh()), Nil) }

	oBrw:Refresh()

	//----- Totalizadores
	@ nBtnLinha - 50, 010 SAY "Registros:" OF oDlg PIXEL FONT oFontN
	@ nBtnLinha - 53, 065 MSGET oQtdReg VAR nQtdReg PICTURE "9999999999" SIZE 60, 12 OF oDlg PIXEL FONT oFont WHEN .F.

	@ nBtnLinha - 50, 200 SAY "Total Vendas:" OF oDlg PIXEL FONT oFontN
	@ nBtnLinha - 53, 275 MSGET oValVendas VAR nValVendas PICTURE "@E 999,999,999.99" SIZE 100, 12 OF oDlg PIXEL FONT oFont WHEN .F.

	ACTIVATE MSDIALOG oDlg CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Função      | ExibeLegenda                                                                       |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Exibe a legenda das cores do browse                                                |
	+==================================================================================================+
/*/
STATIC FUNCTION ExibeLegenda()

	Local aLegenda :=;
		{{"BR_BRANCO", "Venda importada"  },;
		{"BR_AZUL",    "Venda validada"   },;
		{"BR_LARANJA", "Venda baixada"    }}

	BrwLegenda("Validação das Vendas", "Legenda", aLegenda)

Return .T.

/*/
	+==================================================================================================+
	| Função      | FilVendas                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Filtro das vendas                                                                  |
	+==================================================================================================+
/*/
STATIC FUNCTION FilVendas(_de, _ate, _fil, _tipo, _ori, _periodo)

	Local aRet     := {}
	Local cQuery   := ""
	Local cAlias   := GetNextAlias()
	Local aArea    := GetArea()
	Local cCodFil  := ""
	Local cCodTipo := ""
	Local cCodOri  := ""
	Local cCampoDt := ""

	//----- Mapeia filial do combo para c?digo
	If _fil != "Todas"
		cCodFil := AllTrim(SubStr(_fil, 1, At(" - ", _fil) - 1))
	EndIf

	//----- Mapeia situação do combo para chave
	Do Case
	Case _tipo == "Importadas"
		cCodTipo := "01"
	Case _tipo == "Validadas"
		cCodTipo := "02"
	Case _tipo == "Conciliadas"
		cCodTipo := "03"
	OtherWise
		cCodTipo := ""
	EndCase

	//----- Mapeia origem do combo para c?digo
	Do Case
	Case _ori == "Crédito"
		cCodOri := "P01,P03"
	Case _ori == "Débito"
		cCodOri := "P02,P04"
	Case _ori == "PIX"
		cCodOri := "P00"
	OtherWise
		cCodOri := ""
	EndCase

	//----- Mapeia tipo de per?odo para campo de data
	If _periodo == "Data Venda"
		cCampoDt := "ZV_DTVENDA"
	Else
		cCampoDt := "ZV_IMPDATA"
	EndIf

	cQuery := "SELECT ZV_CHAVE,"
	cQuery += "       ZV_E1_FIL,"
	cQuery += "       ZV_PV,"
	cQuery += "       ZV_RV,"
	cQuery += "       CASE ZV_ORIGEM"
	cQuery += "           WHEN 'P00' THEN 'PIX'"
	cQuery += "           WHEN 'P01' THEN 'POS CC'"
	cQuery += "           WHEN 'P02' THEN 'POS CD'"
	cQuery += "           WHEN 'P03' THEN 'TEF CC'"
	cQuery += "           WHEN 'P04' THEN 'TEF CD'"
	cQuery += "           ELSE ' '"
	cQuery += "       END AS ZV_ORIGEM,"
	cQuery += "       CASE ZV_BAND"
	cQuery += "           WHEN '0' THEN 'OUTRAS'"
	cQuery += "           WHEN '1' THEN 'MASTERCARD'"
	cQuery += "           WHEN '2' THEN 'DINERS CLUB'"
	cQuery += "           WHEN '3' THEN 'VISA'"
	cQuery += "           WHEN '4' THEN 'CABAL'"
	cQuery += "           WHEN '5' THEN 'HIPERCARD'"
	cQuery += "           WHEN '6' THEN 'SOROCARD'"
	cQuery += "           WHEN '7' THEN 'CUP'"
	cQuery += "           WHEN '8' THEN 'CREDSYSTEM'"
	cQuery += "           WHEN '9' THEN 'SICRED'"
	cQuery += "           WHEN 'A' THEN 'AVISTA'"
	cQuery += "           WHEN 'B' THEN 'BANESCARD'"
	cQuery += "           WHEN 'E' THEN 'ELO'"
	cQuery += "           WHEN 'J' THEN 'JCB'"
	cQuery += "           WHEN 'X' THEN 'AMEX'"
	cQuery += "           WHEN 'Z' THEN 'CREDZ'"
	cQuery += "           ELSE ' '"
	cQuery += "       END AS ZV_BAND,"
	cQuery += "       ZV_VALVEND, "
	cQuery += "       ZV_E1_TIPO, "
	cQuery += "       ZV_E1_NUM,"
	cQuery += "       ZV_E1_PARC,"
	cQuery += "       ZV_IMPDATA,"
	cQuery += "       ZV_IMPHORA,"
	cQuery += "       ZV_DTVENDA,"
	cQuery += "       R_E_C_N_O_ AS ZV_REC,"
	cQuery += "       ZV_BAND AS ZV_CODBAND,"
	cQuery += "       ZV_ORIGEM AS ZV_CODORI,"
	cQuery += "       ZV_NUNICO AS ZV_NSU,"
	cQuery += "       ZV_AUTORIZ AS ZV_AUTORIZ"
	cQuery += "  FROM " + RetSqlName("SZV") + " SZV "
	cQuery += "  WHERE SZV.D_E_L_E_T_ = ' ' AND"
	cQuery += "        SZV." + cCampoDt + " >= '" + DToS(_de)  + "' AND"
	cQuery += "        SZV." + cCampoDt + " <= '" + DToS(_ate) + "' "

	//----- Filtro por filial
	If !Empty(cCodFil)
		cQuery += "  AND SZV.ZV_E1_FIL = '" + cCodFil + "' "
	EndIf

	//----- Filtro por situação (chave)
	If !Empty(cCodTipo)
		cQuery += "  AND SUBSTR(SZV.ZV_CHAVE, 1, 2) = '" + cCodTipo + "' "
	EndIf

	//----- Filtro por origem
	If !Empty(cCodOri)
		cQuery += "  AND SZV.ZV_ORIGEM IN (" + fParsedIN(cCodOri) + ") "
	EndIf

	cQuery += "ORDER BY ZV_FILIAL, " + cCampoDt + ", ZV_IMPHORA"

	DbUseArea(.T., "TOPCONN", TcGenQry(, , cQuery), cAlias, .F., .T.)

	//----- ESTRUTURA DO VETOR aDados
	// 01 - Chave - situação da venda
	// 02 - seleção
	// 03 - Filial onde ocorreu a venda
	// 04 - PV
	// 05 - RV
	// 06 - ORIGEM (Descrição)
	// 07 - BANDEIRA (nome)
	// 08 - Valor da venda
	// 09 - Tipo de registro no SE1
	// 10 - Numero do titulo no SE1
	// 11 - Numero da parcela no SE1
	// 12 - Data da venda
	// 13 - Data da importação
	// 14 - Numero do registro no SE1
	// 15 - Numero do registro no SZV
	// 16 - Codigo da bandeira
	// 17 - Codigo da origem
	// 18 - NSU
	// 19 - AUTORIZAÇÃO

	While !(cAlias)->(EoF())
		aAdd(aRet,;
			{SubStr((cAlias)->ZV_CHAVE,1,2),;
			" ",;
			(cAlias)->ZV_E1_FIL,;
			(cAlias)->ZV_PV,;
			(cAlias)->ZV_RV,;
			(cAlias)->ZV_ORIGEM,;
			(cAlias)->ZV_BAND,;
			(cAlias)->ZV_VALVEND,;
			(cAlias)->ZV_E1_TIPO,;
			(cAlias)->ZV_E1_NUM,;
			(cAlias)->ZV_E1_PARC,;
			DtoC(SToD((cAlias)->ZV_DTVENDA)),;
			DtoC(SToD((cAlias)->ZV_IMPDATA)),;
			0,;
			(cAlias)->ZV_REC,;
			(cAlias)->ZV_CODBAND,;
			(cAlias)->ZV_CODORI,;
			(cAlias)->ZV_NSU,;
			(cAlias)->ZV_AUTORIZ})

		(cAlias)->(DbSkip())
	EndDo

	(cAlias)->(DbCloseArea())
	RestArea(aArea)

Return aRet

/*/
	+==================================================================================================+
	| Função      | validaUM                                                                           |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Valida apenas o registro corrente do browse                                        |
	+==================================================================================================+
/*/
STATIC FUNCTION validaUm(aDados)

	Local nSel      := 0
	Local nI        := 0
	Local nPos      := 0
	Local nReg      := 0

	Local oDlg

	Local oFont     := TFont():New("Arial",, -13, .F.)
	Local oFontN    := TFont():New("Arial",, -13, .T.)

	Local cPrefixo  := Space(TamSX3('E1_PREFIXO')[1])
	Local cTitulo   := Space(TamSX3('E1_NUM')[1])
	Local cParcela  := Space(TamSX3('E1_PARCELA')[1])
	Local cTipo     := Space(TamSX3('E1_TIPO')[1])

	For nI := 1 To Len(aDados)
		If aDados[nI, 02] == "X"
			nSel++
			nPos := nI
		EndIf
	Next nI

	If nSel == 0
		FWAlertInfo("Nenhum registro foi selecionado.", "Validação de Vendas")
		Return NIL
	EndIf

	If nSel > 1
		FWAlertInfo("Selecione apenas UM registro de venda.", "Validação de Vendas")
		Return NIL
	EndIf

	If (AllTrim(aDados[nPos, 01]) == "01" .OR. AllTrim(aDados[nPos, 01]) == "") == .F.
		FWAlertInfo("O registro selecionado não pode ser validado porque a situação atual não permite.", "Validação de Vendas")
		Return NIL
	EndIf

	nReg := aDados[nPos, 15]

	//----- Formul?rio
	DEFINE MSDIALOG oDlg TITLE "Validação da Venda" FROM 0,0 TO 300, 650 PIXEL FONT oFont

	@ 005, 005 TO 095, 320 OF oDlg PIXEL

	@ 018,020 SAY "Prefixo:" SIZE 090,010 OF oDlg PIXEL FONT oFont
	@ 015,060 MSGET cPrefixo PICTURE "@!" F3 'SE1' OF oDlg PIXEL SIZE 040,012

	@ 038,020 SAY "Título:" SIZE 090,010 OF oDlg PIXEL FONT oFont
	@ 035,060 GET cTitulo PICTURE "@!" SIZE 070,012 OF oDlg PIXEL FONT oFont

	@ 058,020 SAY "Parcela:" SIZE 090,010 OF oDlg PIXEL FONT oFont
	@ 055,060 GET cParcela PICTURE "@!" SIZE 030,012 OF oDlg PIXEL FONT oFont

	@ 078,020 SAY "Tipo:" SIZE 090,010 OF oDlg PIXEL FONT oFont
	@ 075,060 GET cTipo PICTURE "@!" SIZE 030,012 OF oDlg PIXEL FONT oFont

	@ 120, 080 BUTTON "VALIDAR" SIZE 70, 18 OF oDlg PIXEL FONT oFontN ;
		ACTION (grvValidUm(nReg, cPrefixo, cTitulo, cParcela, cTipo), oDlg:End())

	@ 120, 180 BUTTON "SAIR" SIZE 70, 18 OF oDlg PIXEL FONT oFontN ;
		ACTION oDlg:End()

	ACTIVATE MSDIALOG oDlg CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Função      | grvValidUm                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Gravação da validação unitária                                                     |
	+==================================================================================================+
/*/
STATIC FUNCTION grvValidUm(nReg, cPrefixo, cTitulo, cParcela, cTipo)

	Local cFilVenda := ''

	If FWAlertYesNo("Confirma a validação desta venda?", "Validação de Vendas") == .T.
		DbSelectArea("SZV")
		DbGoTo(nReg)

		Begin Transaction
			RecLock("SZV", .F.)
			SZV->ZV_E1_PREF := cPrefixo
			SZV->ZV_E1_NUM  := cTitulo
			SZV->ZV_E1_PARC := cParcela
			SZV->ZV_E1_TIPO := cTipo
			SZV->ZV_CHAVE   := "02"
			SZV->ZV_VALDATA := dDatabase
			SZV->ZV_VALHORA := SubStr(Time(), 1, 5)
			SZV->ZV_VALUSER := RetCodUsr()
			MsUnLock()

			cFilVenda := SZV->ZV_E1_FIL

			//----- Gração da amarração com o título do SE1
			DbSelectArea("SE1")
			DbSetOrder(1)
			If DbSeek(cFilVenda+cPrefixo+cTitulo+cParcela+cTipo)
				RecLock("SE1", .F.)
				SE1->SE1_XREG    := nReg
				SE1->SE1_XVENDA  := 'S'
				MsUnLock()
			EndIf

			//----- Grava dados na tabela de LOG
			RecLock("SZL", .T.)
			ZL_FILIAL  := xFilial("SZL")
			ZL_USER    := RetCodUsr()
			ZL_DATA    := dDataBase
			ZL_HORA    := SubStr(Time(),1,5)
			ZL_TIPO    := 'VALM1'
			ZL_DESCRI  := 'Validação manual'
			ZL_RESUL1  := 'SZV Reg: '+Str(nReg)
			ZL_RESUL2  := 'Título SE1: '+cPrefixo+'/'+cTitulo+'/'+cParcela+'/'+cTipo
			SZL->(MsUnlock())
		End Transaction
	EndIf

Return NIL

/*/
	+==================================================================================================+
	| Função      | grvEstorUm                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Estorno da validação da venda                                                      |
	+==================================================================================================+
/*/
STATIC FUNCTION grvEstorUm(nReg, cPrefixo, cTitulo, cParcela, cTipo)

	Local cFilVenda  := ''

	If FWAlertYesNo("Confirma o estorno da validação desta venda?", "Validação de Vendas") == .T.
		DbSelectArea("SZV")
		DbGoTo(nReg)

		cFilVenda := SZV->ZV_E1_FIL

		RecLock("SZV", .F.)
		SZV->ZV_E1_PREF := ''
		SZV->ZV_E1_NUM  := ''
		SZV->ZV_E1_PARC := ''
		SZV->ZV_E1_TIPO := ''
		SZV->ZV_CHAVE   := "01"
		SZV->ZV_VALDATA := CtoD('//')
		SZV->ZV_VALHORA := ''
		SZV->ZV_VALUSER := ''
		MsUnLock()

		//----- Desmarca o t?tulo com "VENDA VALIDADA"
		DbSelectArea("SE1")
		DbSetOrder(1)
		If DbSeek(cFilVenda+cPrefixo+cTitulo+cParcela+cTipo)
			RecLock("SE1", .F.)
			SE1->E1_XVENDA   := ' '
			SE1->E1_XREG     := 0
			MsUnLock()
		EndIf

		//----- Grava dados na tabela de LOG
		RecLock("SZL", .T.)
		ZL_FILIAL  := xFilial("SZL")
		ZL_USER    := RetCodUsr()
		ZL_DATA    := dDataBase
		ZL_HORA    := SubStr(Time(),1,5)
		ZL_TIPO    := 'VALM2'
		ZL_DESCRI  := 'Estorno da validação manual'
		ZL_RESUL1  := 'SZV Reg: '+Str(nReg)
		ZL_RESUL2  := 'T?tulo SE1: '+cPrefixo+'/'+cTitulo+'/'+cParcela+'/'+cTipo
		SZL->(MsUnlock())
	EndIf

Return NIL

/*/
	+==================================================================================================+
	| Função      | estornaUm                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Estono da validação de uma venda                                                   |
	+==================================================================================================+
/*/
STATIC FUNCTION estornaUm(aDados)

	Local nSel      := 0
	Local nI        := 0
	Local nPos      := 0
	Local nReg      := 0

	Local oDlg

	Local oFont     := TFont():New("Arial",, -13, .F.)
	Local oFontN    := TFont():New("Arial",, -13, .T.)

	Local cPrefixo  := ''
	Local cTitulo   := ''
	Local cParcela  := ''
	Local cTipo     := ''

	For nI := 1 To Len(aDados)
		If aDados[nI, 02] == "X"
			nSel++
			nPos := nI
		EndIf
	Next nI

	If nSel == 0
		FWAlertInfo("Nenhum registro foi selecionado.", "Estorno da Validação de Vendas")
		Return NIL
	EndIf

	If nSel > 1
		FWAlertInfo("Selecione apenas UM registro de venda.", "Estorno da Validação de Vendas")
		Return NIL
	EndIf

	If (AllTrim(aDados[nPos, 01]) == "02") == .F.
		FWAlertInfo("O registro selecionado n?o pode receber o estorno da validação da venda.", "Estorno da Validação de Vendas")
		Return NIL
	EndIf

	nReg := aDados[nPos, 15]

	DbSelectArea("SZV")
	DbSetOrder(1)
	DbGoTo(nReg)

	cPrefixo  := AllTrim(SZV->ZV_E1_PREF)
	cTitulo   := AllTrim(SZV->ZV_E1_NUM)
	cParcela  := AllTrim(SZV->ZV_E1_PARC)
	cTipo     := AllTrim(SZV->ZV_E1_TIPO)

	//----- Formul?rio
	DEFINE MSDIALOG oDlg TITLE "Estornar Validação" FROM 0,0 TO 300, 650 PIXEL FONT oFont

	@ 005, 005 TO 095, 320 OF oDlg PIXEL

	@ 018,020 SAY "Prefixo:" SIZE 090,010 OF oDlg PIXEL FONT oFont
	@ 015,060 MSGET cPrefixo PICTURE "@!" OF oDlg PIXEL SIZE 040,012 READONLY

	@ 038,020 SAY "T?tulo:" SIZE 090,010 OF oDlg PIXEL FONT oFont
	@ 035,060 GET cTitulo PICTURE "@!" SIZE 070,012 OF oDlg PIXEL FONT oFont READONLY

	@ 058,020 SAY "Parcela:" SIZE 090,010 OF oDlg PIXEL FONT oFont
	@ 055,060 GET cParcela PICTURE "@!" SIZE 030,012 OF oDlg PIXEL FONT oFont READONLY

	@ 078,020 SAY "Tipo:" SIZE 090,010 OF oDlg PIXEL FONT oFont
	@ 075,060 GET cTipo PICTURE "@!" SIZE 030,012 OF oDlg PIXEL FONT oFont READONLY

	@ 125, 080 BUTTON "ESTORNAR" SIZE 70, 18 OF oDlg PIXEL FONT oFontN ;
		ACTION (grvEstorUm(nReg, cPrefixo, cTitulo, cParcela, cTipo), oDlg:End())

	@ 125, 180 BUTTON "SAIR" SIZE 70, 18 OF oDlg PIXEL FONT oFontN ;
		ACTION oDlg:End()

	ACTIVATE MSDIALOG oDlg CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Função      | allEstorno                                                                         |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | confirmação do processamento do estorno                                            |
	+==================================================================================================+
/*/
STATIC FUNCTION allEstorno(aDados)

	Local nTotal     := 0
	Local nI         := 0
	Local nReg       := 0
	Local lContinua  := .F.
	Local nRegistros := 0

	Local cPrefixo  := ''
	Local cTitulo   := ''
	Local cParcela  := ''
	Local cTipo     := ''

	lContinua := FWAlertYesNo("Deseja estornar a validação das vendas de TODOS os registros filtrados?", "Estornar Lote")

	If !lContinua
		Return NIL
	EndIf

	MsAguarde({|| grvEstAll(aDados), "Aguarde...", "Estornando validações de vendas.", .T.})


/*/
	+==================================================================================================+
	| Função      | grvEstAll                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Gravação do estorno da validação da venda                                          |
	+==================================================================================================+
/*/
STATIC FUNCTION grvEstAll(aDados)

	Local nI := 0

	Begin Transaction
		For nI := 1 To Len(aDados)
			If AllTrim(aDados[nI, 01]) == "02"
				nTotal ++
				nReg   := aDados[nI, 15]

				DbSelectArea("SZV")
				DbGoTo(nReg)

				cPrefixo  := AllTrim(SZV->ZV_E1_PREF)
				cTitulo   := AllTrim(SZV->ZV_E1_NUM)
				cParcela  := AllTrim(SZV->ZV_E1_PARC)
				cTipo     := AllTrim(SZV->ZV_E1_TIPO)

				RecLock("SZV", .F.)
				SZV->ZV_E1_PREF := ''
				SZV->ZV_E1_NUM  := ''
				SZV->ZV_E1_PARC := ''
				SZV->ZV_E1_TIPO := ''
				SZV->ZV_CHAVE   := "01"
				SZV->ZV_VALDATA := CtoD('//')
				SZV->ZV_VALHORA := ''
				SZV->ZV_VALUSER := ''
				MsUnLock()

				//----- Grava dados na tabela de LOG
				RecLock("SZL", .T.)
				ZL_FILIAL  := xFilial("SZL")
				ZL_USER    := RetCodUsr()
				ZL_DATA    := dDataBase
				ZL_HORA    := SubStr(Time(),1,5)
				ZL_TIPO    := 'VALM2'
				ZL_DESCRI  := 'Estorno autom?tico'
				ZL_RESUL1  := 'SZV Reg: '+Str(nReg)
				ZL_RESUL2  := 'T?tulo SE1: '+cPrefixo+'/'+cTitulo+'/'+cParcela+'/'+cTipo
				SZL->(MsUnlock())
			EndIf
		Next nI
	End Transaction

Return NIL

/*/
	+==================================================================================================+
	| Função      | estUnico                                                                           |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Estorna validação do registro corrente do browse                                   |
	+==================================================================================================+
/*/
STATIC FUNCTION estUnico(oBrw, aDados)

	Local nPos  := oBrw:nAt
	Local aArea := GetArea()

	If nPos < 1 .Or. nPos > Len(aDados)
		FWAlertInfo("Nenhum registro selecionado.", "Estornar ?nico")
		Return NIL
	EndIf

	If aDados[nPos, 02] != "X"
		FWAlertInfo("Selecione um registro marcado (OK = X).", "Estornar ?nico")
		Return NIL
	EndIf

	If Empty(AllTrim(aDados[nPos, 01]))
		FWAlertInfo("Registro j? est? sem validação.", "Estornar ?nico")
		Return NIL
	EndIf

	If !FWAlertYesNo("Deseja estornar a validação do registro selecionado?" + Chr(13) + Chr(10) +;
			"Filial: " + aDados[nPos, 03] + Chr(13) + Chr(10) +;
			"PV: " + aDados[nPos, 04] + Chr(13) + Chr(10) +;
			"T?tulo: " + aDados[nPos, 08], "Estornar ?nico")
		Return NIL
	EndIf

	DbSelectArea("SZV")
	DbSetOrder(1)
	If DbSeek(aDados[nPos, 03] + aDados[nPos, 04] + aDados[nPos, 05] + aDados[nPos, 08])
		RecLock("SZV", .F.)
		SZV->ZV_CHAVE   := ' '
		SZV->ZV_IMPDATA := Ctod("")
		SZV->ZV_IMPHORA := ""
		SZV->ZV_IMPUSER := ""
		MsUnLock()
	EndIf

	aDados[nPos, 01] := ""
	aDados[nPos, 02] := ""

	RestArea(aArea)
	oBrw:Refresh()

	FWAlertInfo("Validação estornada com sucesso.", "Estornar ?nico")

Return NIL

/*/
	+==================================================================================================+
	| Função      | Marcar                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Marca todos os registros do browse                                                |
	+==================================================================================================+
/*/
Static Function Marcar(oBrw, aDados)

	Local nI := 0

	For nI := 1 To Len(aDados)
		aDados[nI, 02] := If(aDados[nI, 02] == "X", "", "X")
	Next nI

	oBrw:Refresh()

Return NIL

/*/
	+==================================================================================================+
	| Função      | Inverter                                                                           |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Inverte a marcação de todos os registros do browse                                 |
	+==================================================================================================+
/*/
Static Function Inverter(oBrw, aDados)

	Local nI := 0

	For nI := 1 To Len(aDados)
		aDados[nI, 02] := If(aDados[nI, 02] == "X", "", "X")
	Next nI

	oBrw:Refresh()

Return NIL

/*/
	+==================================================================================================+
	| Função      | getFilial                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Monta array de filiais                                                             |
	+==================================================================================================+
/*/
STATIC FUNCTION getFilial()

	Local aRet  := {"Todas"}
	Local aArea := SM0->(GetArea())

	DbSelectArea("SM0")
	DbSetOrder(1)
	DbGoTop()

	While SM0->(!Eof())
		Aadd(aRet, SM0->M0_CODFIL + " - " + SM0->M0_FILIAL)
		SM0->(DbSkip())
	EndDo

	RestArea(aArea)

Return aRet

/*/
	+==================================================================================================+
	| Função      | updTotais                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Atualiza totalizadores do browse                                                  |
	+==================================================================================================+
/*/
STATIC FUNCTION updTotais(aDados, nQtdReg, nValVendas, oQtdReg, oValVendas)

	Local nI := 0

	nQtdReg    := Len(aDados)
	nValVendas := 0

	For nI := 1 To Len(aDados)
		nValVendas += aDados[nI, 08]
	Next nI

	oQtdReg:Refresh()
	oValVendas:Refresh()

Return NIL

/*/
	+==================================================================================================+
	| Função      | fParsedIN                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Converte string separada por v?rgulas em cl?usula IN para SQL                      |
	+==================================================================================================+
/*/
STATIC FUNCTION fParsedIN(cLista)

	Local cRet    := ""
	Local aItems  := {}
	Local nI      := 0

	aItems := StrTokArr(cLista, ",")

	For nI := 1 To Len(aItems)
		If !Empty(cRet)
			cRet += ","
		EndIf
		cRet += "'" + AllTrim(aItems[nI]) + "'"
	Next nI

Return cRet
