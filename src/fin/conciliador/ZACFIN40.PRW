#INCLUDE "totvs.ch"

/*/
+==================================================================================================+
| Função      | zacFin40                                                                           |
|-------------+------------------------------------------------------------------------------------|
| Descrição   | Mudança de cor para o semáfaro da transação VENDAS x TITULOS                       |
|-------------+------------------------------------------------------------------------------------|
| Ocorrência  | JOL     21/08/2026 - Desenvolvimento do programa                                   |
|             |                                                                                    |
+==================================================================================================+
/*/
USER FUNCTION zacFin40()

	Local aArea   := GetArea()
	Local cImagem := ""

	If SE1->E1_XVENDA == 'S'
		cImagem := "BR_AZUL"
	Else
		cImagem := ""
	EndIf

	RestArea(aArea)

Return cImagem
