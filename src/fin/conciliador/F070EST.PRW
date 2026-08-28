#INCLUDE "TOTVS.CH"
#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/
+==================================================================================================+
| Função      | F070EST                                                                            |
|-------------+------------------------------------------------------------------------------------|
| Descrição   | Ponto de Entrada para integração do estorno do contas a receber com a validação    |
|             | das vendas no conciliados customizado.                                             |
|-------------+------------------------------------------------------------------------------------|
| Ocorrências                                                                                      |
| JOL     24/08/2026 - Início do desenvolvimento                                                   |
+==================================================================================================+
/*/
USER FUNCTION F070EST()

	Local aArea := GetArea()
	Local nReg  := SE1->SE1_XREG

	Begin Transaction
		If nReg >= 1
			dbSelectArea("SZV")
			DbGoto(nReg)

			//----- Grava dados na tabela de VENDAS -> estorno da baixa
			RecLock("SZV", .F.)
			SZV->ZV_E1_PREF := SE1->E1_PREFIXO
			SZV->ZV_E1_NUM  := SE1->E1_NUM
			SZV->ZV_E1_PARC := SE1->E1_PARCELA
			SZV->ZV_E1_TIPO := SE1->E1_TIPO
			SZV->ZV_E1_FIL  := SE1->E1_FILIAL
			SZV->ZV_CHAVE   := "02"
			SZV->ZV_VALDATA := dDatabase
			SZV->ZV_VALHORA := SubStr(Time(), 1, 5)
			SZV->ZV_VALUSER := RetCodUsr()
			MsUnLock()

			//----- Grava dados na tabela de LOG
			RecLock("SZL", .T.)
			ZL_FILIAL  := xFilial("SZL")
			ZL_USER    := RetCodUsr()
			ZL_DATA    := dDataBase
			ZL_HORA    := SubStr(Time(),1,5)
			ZL_TIPO    := 'ESTE1'
			ZL_DESCRI  := 'Estono da baixa via contas a receber'
			ZL_RESUL1  := 'SZV Reg: '+Str(nReg)
			ZL_RESUL2  := 'Título SE1: '+SE1->E1_FILIAL+'/'+SE1->E1_PREFIXO+'/'+SE1->E1_NUM+'/'+SE1->E1_PARCELA+'/'+SE1->E1_TIPO
			SZL->(MsUnlock())
		EndIf
	END Transaction

	RestArea(aArea)
Return Nil
