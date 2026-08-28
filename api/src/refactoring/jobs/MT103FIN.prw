#include "ap5mail.ch"
#include "protheus.ch"
#INCLUDE "TOPCONN.CH"

/*
Funcao      : MT103FIN()
@type function
@author Luiz Alberto
@since 24.06.2026
*/

User Function MT103FIN()
Local aArea := GetArea()
Local aHeadSE2  := ParamIxb[1]
Local aCoolSE2  := ParamIxb[2]
Local i 
Local nPosHist		:= Ascan(aHeadSE2,{|x| Alltrim(x[2]) == 'E2_HIST'})
Local nPosForm		:= Ascan(aHeadSE2,{|x| Alltrim(x[2]) == 'E2_FORMPAG'})

If ! IsBlind()
	For i := 1 To Len(aCoolSE2)
		If Empty(aCoolSE2[i,nPosHist]) .Or. Empty(aCoolSE2[i,nPosForm])
			FWAlertError("Atenção, na Aba Duplicatas é Obrigatório o Preenchimento dos Campos Histórico e Forma de Pagamento nos Titulos !", "Erro")
			RestArea(aArea)
			Return .F.
		Endif
	Next
Endif
RestArea(aArea)
Return .T.
