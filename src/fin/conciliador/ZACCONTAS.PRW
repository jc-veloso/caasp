#INCLUDE "TOTVS.CH"
#INCLUDE "PARMTYPE.CH"
#INCLUDE "RPTDEF.CH"
#INCLUDE "TOPCONN.CH"

/*/
+==================================================================================================+
| Função      | ZACCONTAS                                                                          |
|-------------+------------------------------------------------------------------------------------|
| Descrição   | Browse de dados contendo os semafaros da vendas x financeiro                       |
|--------------------------------------------------------------------------------------------------|
| Ocorrencias                                                                                      |
|     JOL 17/08/2026 - Criacao da Função                                                           |
+==================================================================================================+
/*/
USER FUNCTION ZACCONTAS()

	Local dDeData   := dDataBase - 1
	Local dAteData  := dDataBase
	Local cFilSel   := "Todas"
	Local aFiliais  := getFilial()
	Local cSituac   := "Sem validação da venda"
	Local aSituac   := {"Todas", "Sem validação da venda", "Com venda validada", "Título Baixado"}

	Local oFont     := TFont():New("Arial",, -13, .F.)
	Local oFontN    := TFont():New("Arial",, -13, .T.)

	Local aSize     := MsAdvSize()
	Local nJanLarg  := aSize[5]
	Local nJanAltu  := aSize[6]

	Local aDados    := {{ " ", "", "", "", "", 0, "", "", "", "", "", "", "P" }}
	Local nQtdeReg  := 0
	Local nValTotal := 0

	//--- Semaforo SE1: titulo em aberto a vencer
	Local oSemSE1Aberto := LoadBitmap(GetResources(), "BR_VERDE")
	//--- Semaforo SE1: titulo liquidado
	Local oSemSE1Liq    := LoadBitmap(GetResources(), "BR_AZUL")
	//--- Semaforo SE1: titulo em aberto vencido
	Local oSemSE1Ven    := LoadBitmap(GetResources(), "BR_VERMELHO")
	//--- Semaforo SE1: campos SE1 vazios (sem titulo vinculado)
	Local oSemSE1Preto  := LoadBitmap(GetResources(), "BR_PRETO")
	//--- Semaforo SE1: titulo nao encontrado no SE1
	Local oSemSE1Nao    := LoadBitmap(GetResources(), "BR_CINZA")
	//--- Semaforo SZV: sem validacao da venda
	Local oSemSZV01     := LoadBitmap(GetResources(), "BR_BRANCO")
	//--- Semaforo SZV: venda validada
	Local oSemSZV02     := LoadBitmap(GetResources(), "BR_AZUL")
	//--- Semaforo SZV: titulo baixado
	Local oSemSZV04     := LoadBitmap(GetResources(), "BR_PRETO")
	//--- Semaforo SZV: chave vazia
	Local oSemSZVVazio  := LoadBitmap(GetResources(), "BR_LARANJA")

	DEFINE MSDIALOG oDlg TITLE "Vendas - Contas a Receber" FROM 00, 00 TO aSize[6], aSize[5] PIXEL FONT oFont

	@ 13, 010 SAY "De Data:" OF oDlg PIXEL FONT oFont
	@ 10, 040 MSGET dDeData SIZE 50, 12 OF oDlg PIXEL FONT oFont

	@ 13, 110 SAY "Até Data:" OF oDlg PIXEL FONT oFont
	@ 10, 140 MSGET dAteData SIZE 60, 12 OF oDlg PIXEL FONT oFont

	@ 13, 220 SAY "Filial:" OF oDlg PIXEL FONT oFont
	@ 10, 250 COMBOBOX cFilSel ITEMS aFiliais SIZE 200, 12 OF oDlg PIXEL FONT oFont

	@ 13, 470 SAY "Situação:" OF oDlg PIXEL FONT oFont
	@ 10, 510 COMBOBOX cSituac ITEMS aSituac SIZE 140, 12 OF oDlg PIXEL FONT oFont

	//--- Browse
	oBrw := TWBrowse():New(002, 001, (nJanLarg / 2) - 10, (nJanAltu / 2) - 80)

	oBrw:SetArray(aDados)

	//--- Semaforo SZV (ZV_CHAVE)
	oBrw:AddColumn(TCColumn():New("Venda",;
		{|| Iif(AllTrim(aDados[oBrw:nAt, 12]) == "01" .OR. AllTrim(aDados[oBrw:nAt, 12]) == '' , oSemSZV01,;
		Iif(AllTrim(aDados[oBrw:nAt, 12]) == "02", oSemSZV02,;
		Iif(AllTrim(aDados[oBrw:nAt, 12]) == "04", oSemSZV04,;
		oSemSZVVazio)))},,,,'LEFT', 30, .T., .F.,,,,.F.,))

	//--- Semaforo SE1 (titulo a receber)
	oBrw:AddColumn(TCColumn():New("Título",;
		{|| Iif(aDados[oBrw:nAt, 13] == "P", oSemSE1Preto,;
		Iif(aDados[oBrw:nAt, 13] == "A", oSemSE1Aberto,;
		Iif(aDados[oBrw:nAt, 13] == "L", oSemSE1Liq,;
		Iif(aDados[oBrw:nAt, 13] == "V", oSemSE1Ven,;
		oSemSE1Nao))))},,,,'LEFT', 30, .T., .F.,,,,.F.,))

	oBrw:AddColumn(TCColumn():New("Filial",    {|| aDados[oBrw:nAt, 02] },,,,'LEFT',  80, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("PV",        {|| aDados[oBrw:nAt, 03] },,,,'LEFT',  90, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("RV",        {|| aDados[oBrw:nAt, 04] },,,,'LEFT',  90, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Origem",    {|| aDados[oBrw:nAt, 05] },,,,'LEFT',  80, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Valor",     {|| aDados[oBrw:nAt, 06] },"@E 999,999.99",,,'RIGHT', 120, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Prefixo",   {|| aDados[oBrw:nAt, 07] },,,,'LEFT',  90, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Tipo",      {|| aDados[oBrw:nAt, 08] },,,,'LEFT',  90, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Número",    {|| aDados[oBrw:nAt, 09] },,,,'LEFT',  90, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Parcela",   {|| aDados[oBrw:nAt, 10] },,,,'LEFT',  90, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Cliente",   {|| aDados[oBrw:nAt, 11] },,,,'LEFT', 200, .F., .F.,,,,.F.,))
	oBrw:AddColumn(TCColumn():New("Reg SZV",   {|| aDados[oBrw:nAt, 12] },,,,'LEFT',  90, .F., .F.,,,,.F.,))

	oBrw:nLen   := Len(aDados)
	oBrw:oFont  := oFont
	oBrw:lAutoEdit := .F.

	oBrw:Refresh()

	//--- Totalizadores acima dos botoes
	@ (nJanAltu / 2) - 50, 010 SAY "Registros:" OF oDlg PIXEL FONT oFont
	@ (nJanAltu / 2) - 53, 070 MSGET nQtdeReg Picture "999999999" SIZE 50, 12 OF oDlg PIXEL FONT oFont WHEN .F.

	@ (nJanAltu / 2) - 50, 150 SAY "Valor Total:" OF oDlg PIXEL FONT oFont
	@ (nJanAltu / 2) - 53, 210 MSGET nValTotal Picture "@E 99,999,999.99" SIZE 80, 12 OF oDlg PIXEL FONT oFont WHEN .F.

	//--- Botoes abaixo do browse
	@ (nJanAltu / 2) - 25, 010 BUTTON oFiltrar PROMPT "Filtrar";
		ACTION MsAguarde({|| aDados := filSZV(dDeData, dAteData, cFilSel, cSituac), ;
		nQtdeReg := Len(aDados), ;
		nValTotal := 0, ;
		aEval(aDados, {|x| nValTotal += x[06]}), ;
		oBrw:SetArray(aDados), ;
		oBrw:nLen := Len(aDados), ;
		oBrw:nAt  := 1, ;
		oBrw:GoTop(), ;
		oBrw:Refresh(), ;
		SysRefresh()}, "Aguarde...", "Filtrando registros da SZV", .T.);
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@ (nJanAltu / 2) - 25, 090 BUTTON oTitReceber PROMPT "Título";
		ACTION {|| visSE1(aDados, oBrw) };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@ (nJanAltu / 2) - 25, 170 BUTTON oVisVenda PROMPT "Venda";
		ACTION {|| visSZV(aDados, oBrw) };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@ (nJanAltu / 2) - 25, 250 BUTTON oLegenda PROMPT "Legenda";
		ACTION {|| legenda() };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	@ (nJanAltu / 2) - 25, 330 BUTTON oSair PROMPT "Sair";
		ACTION {|| oDlg:End() };
		SIZE 65, 18 OF oDlg PIXEL FONT oFontN

	ACTIVATE MSDIALOG oDlg CENTERED

Return NIL

/*/
	+==================================================================================================+
	| Função      | filSZV                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Filtra registros da SZV com LEFT JOIN no SE1 e SA1                               |
	+==================================================================================================+
/*/
STATIC FUNCTION filSZV(_de, _ate, _fil, _situac)

	Local aRet     := {}
	Local cQuery   := ""
	Local cAlias   := GetNextAlias()
	Local aArea    := GetArea()
	Local cCodFil  := ""

	//--- Extrai codigo da filial do combo ("01 - Loja SP" -> "01")
	If Left(_fil, 4) == "Toda"
		cCodFil := ""
	Else
		cCodFil := SubStr(_fil, 1, At(" ", _fil) - 1)
	EndIf

	cQuery := "SELECT SZV.ZV_CHAVE,"
	cQuery += "       SZV.ZV_E1_FIL,"
	cQuery += "       SZV.ZV_PV,"
	cQuery += "       SZV.ZV_RV,"
	cQuery += "       CASE SZV.ZV_ORIGEM"
	cQuery += "           WHEN 'P00' THEN 'PIX'"
	cQuery += "           WHEN 'P01' THEN 'POS CC'"
	cQuery += "           WHEN 'P02' THEN 'POS CD'"
	cQuery += "           WHEN 'P03' THEN 'TEF CC'"
	cQuery += "           WHEN 'P04' THEN 'TEF CD'"
	cQuery += "           ELSE ' '"
	cQuery += "       END AS ZV_ORIGEM,"
	cQuery += "       SZV.ZV_VALVEND,"
	cQuery += "       SZV.ZV_E1_PREF,"
	cQuery += "       SZV.ZV_E1_TIPO,"
	cQuery += "       SZV.ZV_E1_NUM,"
	cQuery += "       SZV.ZV_E1_PARC,"
	cQuery += "       SE1.E1_SALDO,"
	cQuery += "       SE1.E1_VENCREA,"
	cQuery += "       SA1.A1_NOME,"
	cQuery += "       SZV.R_E_C_N_O_ AS REC"
	cQuery += "  FROM " + RetSqlName("SZV") + " SZV"
	cQuery += "  LEFT JOIN " + RetSqlName("SE1") + " SE1"
	cQuery += "    ON SE1.D_E_L_E_T_ = ' '"
	cQuery += "   AND SE1.E1_FILIAL  = SZV.ZV_E1_FIL"
	cQuery += "   AND SE1.E1_PREFIXO = SZV.ZV_E1_PREF"
	cQuery += "   AND SE1.E1_NUM     = SZV.ZV_E1_NUM"
	cQuery += "   AND SE1.E1_PARCELA = SZV.ZV_E1_PARC"
	cQuery += "   AND SE1.E1_TIPO    = SZV.ZV_E1_TIPO"
	cQuery += "  LEFT JOIN " + RetSqlName("SA1") + " SA1"
	cQuery += "    ON SA1.D_E_L_E_T_ = ' '"
	cQuery += "   AND SA1.A1_FILIAL  = '" + xFilial("SA1") + "'"
	cQuery += "   AND SA1.A1_COD     = SE1.E1_CLIENTE"
	cQuery += "   AND SA1.A1_LOJA    = SE1.E1_LOJA"
	cQuery += " WHERE SZV.D_E_L_E_T_ = ' '"
	cQuery += "   AND SZV.ZV_IMPDATA >= '" + DToS(_de)  + "'"
	cQuery += "   AND SZV.ZV_IMPDATA <= '" + DToS(_ate) + "'"

	//----- Filtro por filial
	If !Empty(cCodFil)
		cQuery += "   AND SZV.ZV_E1_FIL = '" + cCodFil + "'"
	EndIf

	//----- Filtro por situacao (ZV_CHAVE)
	If _situac == "Sem validação da venda"
		cQuery += "   AND (SUBSTR(SZV.ZV_CHAVE, 1, 2) = '01' OR SUBSTR(SZV.ZV_CHAVE, 1, 2) = '  ')"
	ElseIf _situac == "Com venda validada"
		cQuery += "   AND SUBSTR(SZV.ZV_CHAVE, 1, 2) = '02'"
	ElseIf _situac == "Título Baixado"
		cQuery += "   AND SUBSTR(SZV.ZV_CHAVE, 1, 2) = '04'"
	EndIf

	cQuery += " ORDER BY SZV.ZV_FILIAL, SZV.ZV_IMPDATA, SZV.ZV_IMPHORA"

	DbUseArea(.T., "TOPCONN", TcGenQry(,, cQuery), cAlias, .F., .T.)

	//--- Estrutura do array aDados
	// 01 - selecao
	// 02 - Filial
	// 03 - PV
	// 04 - RV
	// 05 - Origem (traduzida)
	// 06 - Valor da venda
	// 07 - Prefixo SE1
	// 08 - Tipo SE1
	// 09 - Numero SE1
	// 10 - Parcela SE1
	// 11 - Nome do cliente (SA1)
	// 12 - Chave SZV (para semaforo)
	// 13 - Semaforo SE1 ("A"=aberto, "L"=liquidado, "V"=vencido, "N"=nao encontrado)

	While !(cAlias)->(EoF())
		aAdd(aRet,;														//
		{" ",;                                                          // 01 - semafaro vendas
		(cAlias)->ZV_E1_FIL,;                                           // 02 - Filial
		(cAlias)->ZV_PV,;                                               // 03 - PV
		(cAlias)->ZV_RV,;                                               // 04 - RV
		(cAlias)->ZV_ORIGEM,;                                           // 05 - Origem
		(cAlias)->ZV_VALVEND,;                                          // 06 - Valor
		(cAlias)->ZV_E1_PREF,;                                          // 07 - Prefixo
		(cAlias)->ZV_E1_TIPO,;                                          // 08 - Tipo
		(cAlias)->ZV_E1_NUM,;                                           // 09 - Numero
		(cAlias)->ZV_E1_PARC,;                                          // 10 - Parcela
		(cAlias)->A1_NOME,;                                             // 11 - Cliente
		SubStr((cAlias)->ZV_CHAVE, 1, 2),;                              // 12 - Chave SZV
		semSe1((cAlias)->E1_SALDO,(cAlias)->E1_VENCREA,(cAlias)->ZV_E1_PREF,(cAlias)->ZV_E1_TIPO,(cAlias)->ZV_E1_NUM,(cAlias)->ZV_E1_PARC),;                                         //
		(cAlias)->REC})                                                 // 13

		(cAlias)->(DbSkip())
	EndDo

	//----- Se nao encontrou registros, retorna array vazio com linha em branco
	If Len(aRet) == 0
		aAdd(aRet, {" ", "", "", "", "", 0, "", "", "", "", "", "", "P"})
	EndIf

	(cAlias)->(DbCloseArea())
	RestArea(aArea)

Return aRet

/*/
	+==================================================================================================+
	| Função      | semSe1                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Retorna semaforo do titulo a receber                                               |
	|             |   "P" = campos SE1 vazios, sem titulo vinculado (BR_PRETO)                         |
	|             |   "A" = em aberto a vencer (BR_VERDE)                                              |
	|             |   "V" = em aberto vencido (BR_VERMELHO)                                            |
	|             |   "L" = liquidado (BR_AZUL)                                                        |
	|             |   "N" = titulo nao encontrado no SE1 (BR_CINZA)                                    |
	+==================================================================================================+
/*/
STATIC FUNCTION semSe1(nSaldo, dVencrea, cPref, cTipo, cNum, cParc)

	Local cRet := "N"

	//--- Se os campos de vinculo SE1 estiverem vazios, retorna preto
	If Empty(cPref) .And. Empty(cTipo) .And. Empty(cNum) .And. Empty(cParc)
		Return "P"
	EndIf

	If nSaldo == Nil .Or. dVencrea == Nil
		Return cRet
	EndIf

	If nSaldo > 0
		If dVencrea >= DtoS(dDataBase)
			cRet := "A"  //--- em aberto a vencer
		Else
			cRet := "V"  //--- em aberto vencido
		EndIf
	Else
		cRet := "L"      //--- liquidado
	EndIf

Return cRet

/*/
	+==================================================================================================+
	| Função      | visSE1                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Visualiza titulo no SE1 usando rotina padrao AxVisual                             |
	+==================================================================================================+
/*/
STATIC FUNCTION visSE1(aDados, oBrw)

	Local nPos    := oBrw:nAt
	Local aArea   := GetArea()
	Local aAreaSE1:= SE1->(GetArea())

	Local cFil    := ''
	Local cPref   := ''
	Local cTipo   := ''
	Local cNum    := ''
	Local cParc   := ''
	Local nReg    := 0

	If Len(aDados) == 0
		FWAlertInfo("Nenhum registro para visualizar.", "Título a Receber")
		Return NIL
	EndIf

	//--- Verifica se os campos SE1 estao preenchidos
	cFil  := AllTrim(aDados[nPos, 02])
	cPref := AllTrim(aDados[nPos, 07])
	cTipo := AllTrim(aDados[nPos, 08])
	cNum  := AllTrim(aDados[nPos, 09])
	cParc := AllTrim(aDados[nPos, 10])

	If Empty(cPref) .AND. Empty(cTipo) .AND. Empty(cNum) .AND. Empty(cParc)
		FWAlertInfo("Os campos do Contas a Receber estão vazios. Não há Título vinculado.", "Título a Receber")
		Return NIL
	EndIf

	//--- Busca o titulo no SE1
	DbSelectArea("SE1")
	DbSetOrder(1)
	If DbSeek(cFil + cPref + cNum + cParc + cTipo)
		nReg := SE1->(RecNo())
		AxVisual("SE1", nReg, 2)
	Else
		FWAlertInfo("Título não encontrado no Contas a Receber." + Chr(13) + Chr(10) +;
			"Filial:  " + cFil + Chr(13) + Chr(10) +;
			"Prefixo: " + cPref + Chr(13) + Chr(10) +;
			"Número: " + cNum + Chr(13) + Chr(10) +;
			"Parcela: " + cParc + Chr(13) + Chr(10) +;
			"Tipo: " + cTipo, "Título a Receber")
	EndIf

	RestArea(aAreaSE1)
	RestArea(aArea)

Return NIL

/*/
	+==================================================================================================+
	| Função      | visSZV                                                                             |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Visualiza dados da venda no SZV usando AxVisual                                   |
	+==================================================================================================+
/*/
STATIC FUNCTION visSZV(aDados, oBrw)

	Local nPos    := oBrw:nAt
	Local aArea   := GetArea()
	Local aAreaSZV:= SZV->(GetArea())
	Local nReg    := 0

	cCadastro := 'Vendas'

	If Len(aDados) == 0
		FWAlertInfo("Nenhum registro para visualizar.", "Venda")
		Return NIL
	EndIf

	nReg := aDados[nPos, 13]
	If nReg == 0
		FWAlertInfo("Registro da venda inválido.", "Venda")
		Return NIL
	EndIf

	DbSelectArea("SZV")
	SZV->(DbGoTo(nReg))

	If SZV->(EoF())
		FWAlertInfo("Registro da venda não encontrado na SZV.", "Venda")
	Else
		AxVisual("SZV", nReg, 2)
	EndIf

	RestArea(aAreaSZV)
	RestArea(aArea)

Return NIL

/*/
	+==================================================================================================+
	| Função      | legenda                                                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Exibe legenda das cores do browse, separando Vendas e Titulos                      |
	+==================================================================================================+
/*/
STATIC FUNCTION legenda()

	Local oDlgLeg   := Nil
	Local oFont     := TFont():New("Arial",, -12, .F.)
	Local oFontN    := TFont():New("Arial",, -13, .T.)

	Local oBmp1, oBmp2, oBmp3, oBmp4
	Local oBmp5, oBmp6, oBmp7, oBmp8

	DEFINE MSDIALOG oDlgLeg TITLE "Legenda" FROM 0,0 TO 440, 420 PIXEL FONT oFont

	//----- Titulo Vendas
	@ 010, 010 SAY "VENDAS" OF oDlgLeg PIXEL FONT oFontN

	@ 030, 010 BITMAP oBmp1 RESOURCE "BR_BRANCO" SIZE 09,09 OF oDlgLeg PIXEL
	@ 030, 035 SAY "Sem validação da venda" OF oDlgLeg PIXEL FONT oFont

	@ 045, 010 BITMAP oBmp2 RESOURCE "BR_AZUL" SIZE 09,09 OF oDlgLeg PIXEL
	@ 045, 035 SAY "Venda validada" OF oDlgLeg PIXEL FONT oFont

	@ 060, 010 BITMAP oBmp3 RESOURCE "BR_PRETO" SIZE 09,09 OF oDlgLeg PIXEL
	@ 060, 035 SAY "Título baixado" OF oDlgLeg PIXEL FONT oFont

	@ 075, 010 BITMAP oBmp4 RESOURCE "BR_LARANJA" SIZE 09,09 OF oDlgLeg PIXEL
	@ 075, 035 SAY "Chave vazia" OF oDlgLeg PIXEL FONT oFont

	//----- Titulo Titulos a Receber
	@ 105, 010 SAY "TITULOS A RECEBER" OF oDlgLeg PIXEL FONT oFontN

	@ 125, 010 BITMAP oBmp5 RESOURCE "BR_PRETO" SIZE 09,09 OF oDlgLeg PIXEL
	@ 125, 035 SAY "Campos SE1 vazios (sem título vinculado)" OF oDlgLeg PIXEL FONT oFont

	@ 140, 010 BITMAP oBmp6 RESOURCE "BR_VERDE" SIZE 09,09 OF oDlgLeg PIXEL
	@ 140, 035 SAY "Em aberto a vencer" OF oDlgLeg PIXEL FONT oFont

	@ 155, 010 BITMAP oBmp7 RESOURCE "BR_AZUL" SIZE 09,09 OF oDlgLeg PIXEL
	@ 155, 035 SAY "Liquidado" OF oDlgLeg PIXEL FONT oFont

	@ 170, 010 BITMAP oBmp8 RESOURCE "BR_VERMELHO" SIZE 09,09 OF oDlgLeg PIXEL
	@ 170, 035 SAY "Em aberto vencido" OF oDlgLeg PIXEL FONT oFont

	@ 185, 150 BUTTON "Fechar" SIZE 50, 18 OF oDlgLeg PIXEL FONT oFontN ;
		ACTION {|| oDlgLeg:End() }

	ACTIVATE MSDIALOG oDlgLeg CENTERED

Return .T.

/*/
	+==================================================================================================+
	| Função      | getFilial                                                                          |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Monta array de filiais para o combo                                                |
	+==================================================================================================+
/*/
STATIC FUNCTION getFilial()

	Local aRet  := {"Todas"}
	Local aArea := SM0->(GetArea())

	DbSelectArea("SM0")
	DbSetOrder(1)
	DbGoTop()

	While SM0->(!Eof())
		AAdd(aRet, SM0->M0_CODFIL + " - " + SM0->M0_FILIAL)
		SM0->(DbSkip())
	EndDo

	RestArea(aArea)

Return aRet
