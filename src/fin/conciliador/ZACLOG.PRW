#INCLUDE "PROTHEUS.CH"
#INCLUDE "PARMTYPE.CH"
#INCLUDE "TOTVS.CH"
#INCLUDE "RPTDEF.CH"
#INCLUDE "TOPCONN.CH"

/*/
+==================================================================================================+
| Função      | ZACLOG                                                                             |
|-------------+------------------------------------------------------------------------------------|
| Descrição   | Validação dos logs                                                                 |
|-------------+------------------------------------------------------------------------------------|
| OBSERVAÇÕES                                                                                      |
|                                                                                                  |
|                                                                                                  |
|                                                                                                  |
|--------------------------------------------------------------------------------------------------|
| Ocorrências                                                                                      |
|     JOL 22/07/2026 - Início da criação das funções                                               |
+==================================================================================================+
/*/
USER FUNCTION ZACLOG()

	Local aArea      := GetArea()
	Local aAreaSZL   := SZL->(GetArea())

	//----- Tela
	Local oDlg       := Nil
	Local oBrowse    := Nil
	Local oPanel     := Nil

	//----- Fonts
	Local oFont12    := Nil
	Local oFont13    := Nil

	//----- Campos de filtro
	Local dDeData    := FirstDate(dDatabase)
	Local dAteData   := dDatabase

	//----- Botoes
	Local oSair      := Nil
	Local oVisualizar:= Nil
	Local oFiltrar   := Nil

	//----- Browse
	Local aDados     := {}
	Private cCadastro := "Consulta LOG"

	// --- Define fontes
	DEFINE FONT oFont12 NAME "Arial" SIZE 0, -12
	DEFINE FONT oFont13 NAME "Arial" SIZE 0, -13 BOLD

	// --- Carrega dados
	SZL->(DbSetOrder(1))
	SZL->(DbGoTop())

	While !SZL->(Eof())
		aAdd(aDados, {;
			SZL->ZL_USER,;
			SZL->ZL_DATA,;
			SZL->ZL_HORA,;
			SZL->ZL_TIPO,;
			SZL->ZL_DESCRI;
			})
		SZL->(DbSkip())
	EndDo

	//=============================================================
	// FORMULÁRIO
	//=============================================================
	Define MSDialog oDlg Title "Consulta LOG" From 0, 0 To 550, 900 Pixel

	//----- Painel superior para filtros e botoes
	oPanel := TPanel():New(0, 0, "", oDlg,, .T.,,,, 900, 90, .T.)

	//----- Campos de Data
	@ 12, 010 Say "De Data:" Of oPanel Pixel
	@ 12, 060 MsGet dDeData Size 60, 10 Of oPanel Pixel

	@ 12, 140 Say "Até Data:" Of oPanel Pixel
	@ 12, 200 MsGet dAteData Size 60, 10 Of oPanel Pixel

	//----- Botoes
	@ 45, 010 Button oSair        Prompt "Sair"        Action {|| oDlg:End() }                           size 60, 18 Of oPanel Pixel
	@ 45, 080 Button oVisualizar  Prompt "Visualizar"  Action {|| SZLVISU(oBrowse) }                     size 60, 18 Of oPanel Pixel
	@ 45, 150 Button oFiltrar     Prompt "Filtrar"     Action {|| SZLFILT(@oBrowse, dDeData, dAteData) } size 60, 18 Of oPanel Pixel

	//----- Browse
	oBrowse := TCBrowse():New(065,010,870,440,,,,oDlg,,,,,,,,,,,,,,.T.)

	oBrowse:SetArray(aDados)
	oBrowse:bLine := {|| {;
		aDados[oBrowse:nAt, 01],;
		aDados[oBrowse:nAt, 02],;
		aDados[oBrowse:nAt, 03],;
		aDados[oBrowse:nAt, 04],;
		aDados[oBrowse:nAt, 05];
		}}

	oBrowse:oFont := oFont13

	oBrowse:AddColumn(TCColumn():New("Usuário",   {|| UsrRetName(aDados[oBrowse:nAt, 01]) },"", Nil, Nil, "LEFT",   Nil, .F., .F.))
	oBrowse:AddColumn(TCColumn():New("Data",      {|| aDados[oBrowse:nAt, 02] },"", Nil, Nil, "CENTER", Nil, .F., .F.))
	oBrowse:AddColumn(TCColumn():New("Hora",      {|| aDados[oBrowse:nAt, 03] },"", Nil, Nil, "CENTER", Nil, .F., .F.))
	oBrowse:AddColumn(TCColumn():New("Tipo",      {|| aDados[oBrowse:nAt, 04] },"", Nil, Nil, "LEFT",   Nil, .F., .F.))
	oBrowse:AddColumn(TCColumn():New("Descrição", {|| aDados[oBrowse:nAt, 05] },"", Nil, Nil, "LEFT",   Nil, .F., .F.))

	oBrowse:lAutoEdit := .F.
	oBrowse:Refresh()

	Activate MSDialog oDlg Centered

	RestArea(aAreaSZL)
	RestArea(aArea)

Return NIL

/*/
	+==================================================================================================+
	| Função      | SZLFILT                                                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Filtrar log por data                                                               |
	+==================================================================================================+
/*/
STATIC FUNCTION SZLFILT(oBrowse, dDeData, dAteData)

	Local aArea   := GetArea()
	Local aDados  := {}
	Local cAlias  := GetNextAlias()

	If Empty(dDeData)
		dDeData := FirstDate(dDatabase)
	EndIf

	If Empty(dAteData)
		dAteData := dDatabase
	EndIf

	// --- Consulta SQL filtrada por periodo
	BeginSQL Alias cAlias
		SELECT ZL_USER,
		       ZL_DATA,
		       ZL_HORA,
		       ZL_TIPO,
		       ZL_DESCRI
		  FROM %table:SZL% SZL
		 WHERE SZL.ZL_FILIAL = %xFilial:SZL%
		   AND SZL.ZL_DATA >= %exp:DTOS(dDeData)%
		   AND SZL.ZL_DATA <= %exp:DTOS(dAteData)%
		   AND %notDel%
		 ORDER BY ZL_DATA, ZL_HORA
	EndSQL

	While !(cAlias)->(Eof())
		aAdd(aDados, {;
			UsrRetName((cAlias)->ZL_USER),;
			StoD((cAlias)->ZL_DATA),;
			(cAlias)->ZL_HORA,;
			(cAlias)->ZL_TIPO,;
			(cAlias)->ZL_DESCRI;
			})
		(cAlias)->(DbSkip())
	EndDo

	(cAlias)->(DbCloseArea())

	// --- Atualiza browse
	oBrowse:SetArray(aDados)
	oBrowse:bLine := {|| {;
		SZLBmpStatus(aDados[oBrowse:nAt, 04]),;
		aDados[oBrowse:nAt, 01],;
		aDados[oBrowse:nAt, 02],;
		aDados[oBrowse:nAt, 03],;
		aDados[oBrowse:nAt, 04],;
		aDados[oBrowse:nAt, 05];
		}}
	oBrowse:Refresh()

	RestArea(aArea)

Return NIL

/*/
	+==================================================================================================+
	| Função      | SZLVISU                                                                            |
	|-------------+------------------------------------------------------------------------------------|
	| Descrição   | Visualização dos dados do registro                                                 |
	+==================================================================================================+
/*/
STATIC FUNCTION SZLVISU(oBrowse)

	Local aArea := GetArea()
	Local nRec  := 0

	DbSelectArea("SZL")
	DbSetOrder(1)

	nRec := oBrowse:nAt

	If nRec > 0 .And. nRec <= Len(oBrowse:aArray)
		// --- Busca o registro pela combinação de dados
		DbGoTop()
		While !Eof()
			If SZL->ZL_USER == oBrowse:aArray[nRec, 1] .And. ;
					SZL->ZL_DATA == oBrowse:aArray[nRec, 2] .And. ;
					SZL->ZL_HORA == oBrowse:aArray[nRec, 3]
				RecLock("SZL", .F.)
				MsUnlock()
				AxVisual("SZL", RecNo(), 2)
				Exit
			EndIf
			DbSkip()
		EndDo
	Else
		MsgStop("Nenhum registro selecionado para visualização.", "Consulta LOG")
	EndIf

	RestArea(aArea)

Return NIL
