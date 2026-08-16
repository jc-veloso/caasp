#INCLUDE "TOTVS.CH"

/*/{Protheus.doc} F150SUM 
Sera utilizado para agregar valores especificos nas variaveis nSomaValor e nSomaVlLote
@type   function
@author Jose Carlos Veloso
@since  17/07/2026
/*/

User function F150SUM()

Local nSaldo  := 0

nSaldo := SE2->E2_SALDO + SE2->E2_SDACRES - SE2->E2_SDDECRE - SE2->E2_XDESCON

Return( nSaldo )