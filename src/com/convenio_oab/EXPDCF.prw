#include "protheus.ch"
#include "topconn.ch"


/*/{Protheus.doc} User Function MEDCSV
    Exporta a planilha de medição em CSV para ser preenchida manualmente no Excel.
    Feito com base na "MIT044 - IMTEP - Relatorio para Medicao"

    @type  Function
    @author Leandro Favero
    @since 15/01/2020
    @version 1.0
    /*/
User Function EXPDCF()

    Local cArquivo
	Local targetDir	:=''
    Local cPerg		:= PadR('EXPTX1',10)
    Local cFile
    Private LF		:=Chr(13)+Chr(10)

    AjustaSX1(cPerg)
	If !Pergunte(cPerg,.T.)
		Return
	Endif

	If MV_PAR01 == 2 .And. MV_PAR02 == 3
		alert('Atenção, Para a Opção Caasp, Não é Permitido a Escolha de Ambos em Tipo de Enventos !')
		Return
	Endif

	cSeqOAB := SuperGetMV("MV_XSEQOAB",.F.,'000001')
	cSeqCas := SuperGetMV("MV_XSEQCAS",.F.,'000001')

	cArq := ''
	if MV_PAR01 == 1
		cSeqOab := Soma1(cSeqOAB,6)
		If MV_PAR02 == 1
			cArq := 'DoF'+StrZero(Day(dDataBase),2)+StrZero(Month(dDataBase),2)+cSeqOAB
		ElseIf MV_PAR02 == 2
			cArq := 'DoL'+StrZero(Day(dDataBase),2)+StrZero(Month(dDataBase),2)+cSeqOAB
		ElseIf MV_PAR02 == 3
			cArq := 'DofDol'+StrZero(Day(dDataBase),2)+StrZero(Month(dDataBase),2)+cSeqOAB
		Endif
	elseIf MV_PAR01 == 2
		cSeqCas := Soma1(cSeqCas,6)
		cArq := 'DCF'+StrZero(Day(dDataBase),2)+StrZero(Month(dDataBase),2)+cSeqCas
	Endif

	cArquivo := cArq

	FWMsgRun(, {|oSay| cArquivo := GeraCSV()}, "Processando", "Gerando Arquivo...")   

	if EMPTY(cArquivo)
		alert('Nenhum registro encontrado, verifique os parâmetros informados.')
	else
		cDiretorio := 'C:\TEMP\'
		If !ExistDir("C:\temp\")
			MontaDir("C:\temp\")
		EndIf

		cFile := cDiretorio + cArq + '.TXT'			
		MemoWrite(cFile,cArquivo)
		alert('Gerado arquivo '+cFile+'.')

		PutMV("MV_XSEQOAB",cSeqOAB)
		PutMV("MV_XSEQCAS",cSeqCas)
	endif

Return 


/*---------------------------------------------------------------------------------------------------+
|  DETALHE - Montagem do Detalhe do arquivo                                                          |
-----------------------------------------------------------------------------------------------------*/
Static function GeraCSV()
	Local aArea	:= GetArea()
	Local cRet  := ''
    
	cQryAux := "    SELECT * "		+ CRLF
	cQryAux += "    FROM " + RetSqlName("SE1") + " E1, " + RetSqlName("SA1") + " SA1 "		+ CRLF
	cQryAux += "    WHERE E1.D_E_L_E_T_ = ' ' "		+ CRLF
	cQryAux += "    AND E1.E1_TIPO    = 'CO' " + CRLF
	cQryAux += "    AND E1.E1_SALDO > 0 " + CRLF
	cQryAux += "    AND E1.E1_CLIENTE = SA1.A1_COD " + CRLF
	cQryAux += "    AND E1.E1_LOJA = SA1.A1_LOJA " + CRLF
	cQryAux += "    AND E1.E1_VENCREA BETWEEN '" +DTOS(MV_PAR04)+ "' AND '" +DTOS(MV_PAR05)+ "' " + CRLF
	If MV_PAR01 == 1
		//Se for OAB
		cQryAux += "    AND RTRIM(E1.E1_CARTAO) = 'CONVENIO - OAB' " + CRLF
	ElseIf MV_PAR01 == 2
		//Se for CAASP
		cQryAux += "    AND RTRIM(E1.E1_CARTAO) = 'CONVENIO - CAASP' " + CRLF
	ElseIf MV_PAR01 == 3	
		//Se for OAB PREV
		cQryAux += "    AND RTRIM(E1.E1_CARTAO) = 'CONVENIO - OABPR' " + CRLF
	ElseIf MV_PAR01 == 4
		//Se for DIRET
		cQryAux += "    AND RTRIM(E1.E1_CARTAO) = 'CONVENIO - DIRET' " + CRLF
	Endif
	If MV_PAR02 == 1
		//Se for Farmacia
		cQryAux += "    AND E1.E1_XEVENTO = 'FAR' " + CRLF
	ElseIf MV_PAR02 == 2
		//Se for Livraria
		cQryAux += "    AND E1.E1_XEVENTO = 'LIV' " + CRLF
	ElseIf MV_PAR02 == 3
		//Se for Livraria
		cQryAux += "    AND E1.E1_XEVENTO IN('LIV','FAR') " + CRLF
	Endif
	If !Empty(MV_PAR03)
		cQryAux += "    AND E1.E1_NUMBOR = '" + MV_PAR03 + "' " + CRLF
	Endif
	cQryAux += "    ORDER BY E1.E1_FILIAL, E1.E1_PREFIXO, E1.E1_NUM, E1.E1_PARCELA "		+ CRLF

	cQryAux := ChangeQuery(cQryAux)
	
	//Executando consulta e setando o total da régua
	TCQuery cQryAux New Alias "CHK1"

	Count to nTotal

	CHK1->(dbGoTop())

	If nTotal > 0
	    while !CHK1->(EOF())
			SA1->(dbSetOrder(1), dbSeek(xFilial("SA1")+ CHK1->E1_CLIENTE + CHK1->E1_LOJA))

			cRet += Left(SA1->A1_XCODRH,9)       //Codigo RH
			If MV_PAR01 == 2 .And. MV_PAR02 == 1 // CAASP - Farmacia
				cRet += '447'
			ElseIf MV_PAR01 == 2 .And. MV_PAR02 == 2 // CAASP - Livraria
				cRet += '571'
			ElseIf MV_PAR01 == 1 // OAB
				cRet += '314'
			Endif
			cRet += StrZero(CHK1->E1_SALDO*100,16)       //Valor Unitário
	        cRet+= CRLF //Pula Linha
	        
	        CHK1->(DBSkip())
	    enddo
	Endif

    CHK1->(DBCLoseArea())

RestArea(aArea)
Return cRet

/*---------------------------------------------------------------------------------------------------+
|  Num - Ajusta o tamanho do campo numerico, remove pontos e virgulas                                |
-----------------------------------------------------------------------------------------------------*/
Static function Num(xValor)
    Local cRet:=''
    Local cIdx:='0123456789,.'
    Local nI
    Local cVlr:=cValToChar(xValor)

    //somente numeros, virgula e ponto
    for nI:=1 to Len(cVlr)
        if Substr(cVlr,nI,1) $ cIdx
            cRet+=Substr(cVlr,nI,1)
        endif
    next

    cRet:='*'+cRet+'*' 

return cRet

/*
ÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜ
±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±
±±ÉÍÍÍÍÍÍÍÍÍÍÑÍÍÍÍÍÍÍÍÍÍËÍÍÍÍÍÍÑÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍËÍÍÍÍÍÍÑÍÍÍÍÍÍÍÍÍÍÍÍÍ»±±
±±ºPrograma  ³ AjustaSX1ºAutor ³Luiz Alberto V Alvesº Data ³  22/05/06   º±±
±±ÌÍÍÍÍÍÍÍÍÍÍØÍÍÍÍÍÍÍÍÍÍÊÍÍÍÍÍÍÏÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÊÍÍÍÍÍÍÏÍÍÍÍÍÍÍÍÍÍÍÍÍ¹±±
±±ºDesc.     ³ Ajusta o SX1 - Arquivo de Perguntas..                      º±±
±±ÌÍÍÍÍÍÍÍÍÍÍØÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¹±±
±±ºUso       ³ Funcao Principal                                           º±±
±±ÌÍÍÍÍÍÍÍÍÍÍØÍÍÍÍÍÍÍÍÍÍÑÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¹±±
±±ºDATA      ³ ANALISTA ³ MOTIVO                                          º±±
±±ÌÍÍÍÍÍÍÍÍÍÍØÍÍÍÍÍÍÍÍÍÍØÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¹±±
±±º          ³          ³                                                 º±±
±±ÈÍÍÍÍÍÍÍÍÍÍÏÍÍÍÍÍÍÍÍÍÍÏÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼±±
±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±±
ßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßß
*/

Static Function AjustaSX1(cPerg)
Local	aRegs   := {},;
		_sAlias := Alias(),;
		nX

		//ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
		//³Campos a serem grav. no SX1³
		//³aRegs[nx][01] - X1_GRUPO   ³
		//³aRegs[nx][02] - X1_ORDEM   ³
		//³aRegs[nx][03] - X1_PERGUNTE³
		//³aRegs[nx][04] - X1_PERSPA  ³
		//³aRegs[nx][05] - X1_PERENG  ³
		//³aRegs[nx][06] - X1_VARIAVL ³
		//³aRegs[nx][07] - X1_TIPO    ³
		//³aRegs[nx][08] - X1_TAMANHO ³
		//³aRegs[nx][09] - X1_DECIMAL ³
		//³aRegs[nx][10] - X1_PRESEL  ³
		//³aRegs[nx][11] - X1_GSC     ³
		//³aRegs[nx][12] - X1_VALID   ³
		//³aRegs[nx][13] - X1_VAR01   ³
		//³aRegs[nx][14] - X1_DEF01   ³
		//³aRegs[nx][15] - X1_DEF02   ³
		//³aRegs[nx][16] - X1_DEF03   ³
		//³aRegs[nx][17] - X1_DEF04   ³
		//³aRegs[nx][18] - X1_DEF05   ³
		//³aRegs[nx][19] - X1_F3      ³
		//ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ

		//ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
		//³Cria uma array, contendo todos os valores...³
		//ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ

        aAdd(aRegs,{cPerg,'01','Convenio           ?','','','mv_ch1','N', 01,0,0,'C',''                     ,'mv_par01','Oab','Caasp','Oab Prev','Diret','','',''})
        aAdd(aRegs,{cPerg,'02','Tipo Evento        ?','','','mv_ch2','N', 01,0,0,'C',''                     ,'mv_par02','Farmacia','Livraria','Ambos','','','',''})
        aAdd(aRegs,{cPerg,'03','Numero Bordero     ?','','','mv_ch3','C', 06,0,0,'G',''                     ,'mv_par03','','','','','','',''})
        aAdd(aRegs,{cPerg,'04','Vencimento De      ?','','','mv_ch4','D', 08,0,0,'G',''                     ,'mv_par04','','','','','','',''})
        aAdd(aRegs,{cPerg,'05','Vencimento Ate     ?','','','mv_ch5','D', 08,0,0,'G',''                     ,'mv_par05','','','','','','',''})

		DbSelectArea('SX1')
		SX1->(DbSetOrder(1))

		For nX:=1 to Len(aRegs)
			If	( ! SX1->(DbSeek(aRegs[nx][01]+aRegs[nx][02])) )
				If	RecLock('SX1',.T.)
					Replace SX1->X1_GRUPO  		With aRegs[nx][01]
					Replace SX1->X1_ORDEM   	With aRegs[nx][02]
					Replace SX1->X1_PERGUNTE	With aRegs[nx][03]
					Replace SX1->X1_PERSPA		With aRegs[nx][04]
					Replace SX1->X1_PERENG		With aRegs[nx][05]
					Replace SX1->X1_VARIAVL		With aRegs[nx][06]
					Replace SX1->X1_TIPO		With aRegs[nx][07]
					Replace SX1->X1_TAMANHO		With aRegs[nx][08]
					Replace SX1->X1_DECIMAL		With aRegs[nx][09]
					Replace SX1->X1_PRESEL		With aRegs[nx][10]
					Replace SX1->X1_GSC			With aRegs[nx][11]
					Replace SX1->X1_VALID		With aRegs[nx][12]
					Replace SX1->X1_VAR01		With aRegs[nx][13]
					Replace SX1->X1_DEF01		With aRegs[nx][14]
					Replace SX1->X1_DEF02		With aRegs[nx][15]
					Replace SX1->X1_DEF03		With aRegs[nx][16]
					Replace SX1->X1_DEF04		With aRegs[nx][17]
					Replace SX1->X1_DEF05		With aRegs[nx][18]
					Replace SX1->X1_F3   		With aRegs[nx][19]
					Replace SX1->X1_PICTURE		With aRegs[nx][20]
					SX1->(MsUnlock())
				Else
					Help('',1,'REGNOIS')
				EndIf	
			Endif
		Next nX

Return

