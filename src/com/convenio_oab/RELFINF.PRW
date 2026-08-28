//Bibliotecas
#INCLUDE "TOTVS.CH"
#INCLUDE "TOPCONN.CH"
	
//Constantes
#Define STR_PULA		Chr(13)+Chr(10)
	

/*/{Protheus.doc} xTitVenc
Relatorio de Registros de 
@type function
@version  
@author Luiz Alberto
@since 10/01/2023
@return variant, return_description

/*/	
User FunctioN RelFinF()
	
	Local oPergSX1	As Object	
	Private aPergunte	As Array
    Private cPerg := PadR("RELFN4",10)

    AjustaSX1(cPerg)

	oPergSX1 := FWSX1Util():New()
	oPergSX1:AddGroup('RELFN4')
	oPergSX1:SearchGroup()

	aPergunte := oPergSX1:GetGroup('RELFN4')

	IF !Empty(aPergunte)
		IF !Pergunte(aPergunte[1])
			Return
		ELSE
			oReport := fReportDef()
			oReport:PrintDialog()
		EndIF
	ELSE
		FWAlertWarning('O grupo de perguntas nใo foi localizado no dicionแrio de dados, perguntas criadas, feche a tela e acesse novamente.','Sem Pergunta')
	EndIF

	aSize(aPergunte,0)
	oPergSX1:Destroy()

	FreeObj(oPergSX1)

Return
	
/*-------------------------------------------------------------------------------*
 | Func:  fReportDef                                                             |
 | Desc:  Fun็ใo que monta a defini็ใo do relat๓rio                              |
 *-------------------------------------------------------------------------------*/
	
Static Function fReportDef()
	Local oReport
	Local oSectDad := Nil
	Local oBreak := Nil
	
	//Cria็ใo do componente de impressใo
	oReport := TReport():New(	"RelFinF",;		//Nome do Relat๓rio
								"Relatorio de Financeiro",;		//Tํtulo
								cPerg,;		//Pergunte ... Se eu defino a pergunta aqui, serแ impresso uma pแgina com os parโmetros, conforme privil้gio 101
								{|oReport| fRepPrint(oReport)},;		//Bloco de c๓digo que serแ executado na confirma็ใo da impressใo
								)		//Descri็ใo
	oReport:SetTotalInLine(.T.)
	oReport:lParamPage := .T.
	oReport:oPage:SetPaperSize(9) //Folha A4
	oReport:SetLandscape()
	
	//Criando a se็ใo de dados
	oSectDad := TRSection():New(	oReport,;		//Objeto TReport que a se็ใo pertence
									"Dados",;		//Descri็ใo da se็ใo
									{"SE1"})		//Tabelas utilizadas, a primeira serแ considerada como principal da se็ใo

	//Colunas do relat๓rio

	TRCell():New(oSectDad,"E1_FILIAL"		   	,"CHK1",GetSx3Cache("E1_FILIAL"   	,"X3_TITULO"),PesqPict("SE1","E1_FILIAL")	    , 20)
	TRCell():New(oSectDad,"A1_COD"				,"CHK1",'Codigo Cliente',PesqPict("SA1","A1_COD")	    , TamSX3("A1_COD")[1])
	TRCell():New(oSectDad,"A1_NOME"  		   	,"CHK1",'Nome do Cliente',PesqPict("SA1","A1_NOME")	        , TamSX3("A1_NOME")[1])
	TRCell():New(oSectDad,"E1_XEVENTO" 		   	,"CHK1",'Servi็o','', 15)
	TRCell():New(oSectDad,"A1_XCODRH"		   	,"CHK1",'Codigo RH',PesqPict("SA1","A1_XCODRH")	    , TamSX3("A1_XCODRH")[1])
	TRCell():New(oSectDad,"E1_TIPO"  		   	,"CHK1",GetSx3Cache("E1_TIPO"   	,"X3_TITULO"),PesqPict("SE1","E1_TIPO")	    	, TamSX3("E1_TIPO")[1])
	TRCell():New(oSectDad,"E1_CARTAO"  		   	,"CHK1",GetSx3Cache("E1_CARTAO"   	,"X3_TITULO"),'', 20)
	TRCell():New(oSectDad,"E1_SALDO"		   	,"CHK1",GetSx3Cache("E1_SALDO"   	,"X3_TITULO"),PesqPict("SE1","E1_SALDO")	    , TamSX3("E1_SALDO")[1])

	TRFunction():New(oSectDad:Cell("E1_SALDO"), ,"SUM",/*oBreak*/,"Total Geral ",/*cPicture*/,/*cF๓rmula*/,.F.,.T.,.F.,oSectDad)

Return oReport
	

/*-------------------------------------------------------------------------------*
 | Func:  fRepPrint                                                              |
 | Desc:  Fun็ใo que imprime o relat๓rio                                         |
 *-------------------------------------------------------------------------------*/
	
Static Function fRepPrint(oReport)
	Local aArea    := GetArea()
	Local cQryAux  := ""
	Local oSectDad := Nil
	Local nAtual   := 0
	Local nTotal   := 0
    Local nPedido

	cQryAux := ""
	
	//Pegando as se็๕es do relat๓rio
	oSectDad := oReport:Section(1)

	dInicio  := MV_PAR01
	dFinal   := MV_PAR02

	//Montando consulta de dados

	cQryAux += "    SELECT E1.E1_FILIAL, SA1.A1_NOME, SA1.A1_COD, SA1.A1_LOJA, SA1.A1_XCODRH, E1.E1_XEVENTO, E1.E1_TIPO, E1.E1_CARTAO, SUM(E1.E1_SALDO) E1_SALDO "		+ STR_PULA
	cQryAux += "    FROM " + RetSqlName("SE1") + " E1, " + RetSqlName("SA1") + " SA1 "		+ STR_PULA
	cQryAux += "    WHERE E1.D_E_L_E_T_ = ' ' "		+ STR_PULA
	cQryAux += "    AND E1.E1_VENCREA BETWEEN '" +DTOS(MV_PAR03)+ "' AND '" +DTOS(MV_PAR04)+ "' " + STR_PULA
	cQryAux += "    AND E1.E1_EMISSAO BETWEEN '" +DTOS(MV_PAR09)+ "' AND '" +DTOS(MV_PAR10)+ "' " + STR_PULA
	cQryAux += "    AND E1.E1_TIPO    = 'CO' " + STR_PULA
	cQryAux += "    AND E1.E1_SALDO > 0 " + STR_PULA
	cQryAux += "    AND E1.E1_CLIENTE = SA1.A1_COD " + STR_PULA
	cQryAux += "    AND E1.E1_LOJA = SA1.A1_LOJA " + STR_PULA
	cQryAux += "    AND SA1.A1_COD BETWEEN '" + MV_PAR05+ "' AND '" +MV_PAR07+ "' " + STR_PULA
	cQryAux += "    AND SA1.A1_LOJA BETWEEN '" + MV_PAR06+ "' AND '" +MV_PAR08+ "' " + STR_PULA
	If MV_PAR01 == 1
		//Se for OAB
		cQryAux += "    AND RTRIM(E1.E1_CARTAO) = 'CONVENIO - OAB' " + STR_PULA
	ElseIf MV_PAR01 == 2
		//Se for CAASP
		cQryAux += "    AND RTRIM(E1.E1_CARTAO) = 'CONVENIO - CAASP' " + STR_PULA
	ElseIf MV_PAR01 == 3	
		//Se for OAB PREV
		cQryAux += "    AND RTRIM(E1.E1_CARTAO) = 'CONVENIO - OABPR' " + STR_PULA
	ElseIf MV_PAR01 == 4
		//Se for DIRET
		cQryAux += "    AND RTRIM(E1.E1_CARTAO) = 'CONVENIO - DIRET' " + STR_PULA
	Endif
	If MV_PAR02 == 1
		//Se for Farmacia
		cQryAux += "    AND E1.E1_XEVENTO = 'FAR' " + STR_PULA
	ElseIf MV_PAR02 == 2
		//Se for Livraria
		cQryAux += "    AND E1.E1_XEVENTO = 'LIV' " + STR_PULA
	ElseIf MV_PAR02 == 3
		//Se for Ambos
		cQryAux += "    AND E1.E1_XEVENTO IN ('FAR', 'LIV') " + STR_PULA
	Endif
	cQryAux += "    GROUP BY E1.E1_FILIAL, SA1.A1_NOME, SA1.A1_COD, SA1.A1_LOJA, SA1.A1_XCODRH, E1.E1_XEVENTO, E1.E1_TIPO, E1.E1_CARTAO "		+ STR_PULA
	cQryAux += "    ORDER BY SA1.A1_NOME, E1.E1_XEVENTO "		+ STR_PULA

	cQryAux := ChangeQuery(cQryAux)
	
	//Executando consulta e setando o total da r้gua
	TCQuery cQryAux New Alias "CHK1"

    TcSetField('CHK1','E1_EMISSAO','D')
    TcSetField('CHK1','E1_VENCTO','D')
    TcSetField('CHK1','E1_VENCREA','D')

	Count to nTotal
	oReport:SetMeter(nTotal)

    xFilAnt := cFilAnt

	//Enquanto houver dados
	oSectDad:Init()
	CHK1->(DbGoTop())
	While ! CHK1->(Eof())
		//Incrementando a r้gua
		nAtual++
		oReport:SetMsgPrint("Imprimindo registro "+cValToChar(nAtual)+" de "+cValToChar(nTotal)+"...")
		oReport:IncMeter()

        nRegSm0 := SM0->(Recno())
        SM0->(DbSeek(cEmpAnt+CHK1->E1_FILIAL))
        _cNomFil := CHK1->E1_FILIAL + ' - ' + AllTrim(SM0->M0_NOMECOM)
        SM0->(dbGoTo(nRegSm0))

        cFilAnt := CHK1->E1_FILIAL

        SA1->(dbSetOrder(1), dbSeek(xFilial("SA1")+CHK1->A1_COD+CHK1->A1_LOJA))

		cEvento := ''
		If AllTrim(CHK1->E1_XEVENTO) == 'FAR'
			cEvento := 'Farmแcia'
		ElseIf AllTrim(CHK1->E1_XEVENTO) == 'LIV'
			cEvento := 'Livraria'
		Endif

		oSectDad:Cell("E1_FILIAL"):SetValue(_cNomFil)
		oSectDad:Cell("E1_XEVENTO"):SetValue(cEvento)
		oSectDad:Cell("A1_COD"):SetValue(SA1->A1_COD)
		oSectDad:Cell("A1_XCODRH"):SetValue(SA1->A1_XCODRH)
		oSectDad:Cell("E1_TIPO"):SetValue(Tabela('05',CHK1->E1_TIPO))
		oSectDad:Cell("E1_CARTAO"):SetValue(CHK1->E1_CARTAO)
		oSectDad:Cell("A1_NOME"):SetValue(SA1->A1_NOME)
		oSectDad:Cell("E1_SALDO"):SetValue(CHK1->E1_SALDO)

		//Imprimindo a linha atual
		oSectDad:PrintLine()
		
		CHK1->(DbSkip())
	EndDo
	oSectDad:Finish()
	CHK1->(DbCloseArea())

    cFilAnt := xFilAnt


	RestArea(aArea)
Return




/*
ÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜ
ฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑ
ฑฑษออออออออออัออออออออออหออออออัอออออออออออออออออออออหออออออัอออออออออออออปฑฑ
ฑฑบPrograma  ณ AjustaSX1บAutor ณLuiz Alberto V Alvesบ Data ณ  22/05/06   บฑฑ
ฑฑฬออออออออออุออออออออออสออออออฯอออออออออออออออออออออสออออออฯอออออออออออออนฑฑ
ฑฑบDesc.     ณ Ajusta o SX1 - Arquivo de Perguntas..                      บฑฑ
ฑฑฬออออออออออุออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออนฑฑ
ฑฑบUso       ณ Funcao Principal                                           บฑฑ
ฑฑฬออออออออออุออออออออออัอออออออออออออออออออออออออออออออออออออออออออออออออนฑฑ
ฑฑบDATA      ณ ANALISTA ณ MOTIVO                                          บฑฑ
ฑฑฬออออออออออุออออออออออุอออออออออออออออออออออออออออออออออออออออออออออออออนฑฑ
ฑฑบ          ณ          ณ                                                 บฑฑ
ฑฑศออออออออออฯออออออออออฯอออออออออออออออออออออออออออออออออออออออออออออออออผฑฑ
ฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑ
฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿
*/

Static Function AjustaSX1(cPerg)
Local	aRegs   := {},;
		_sAlias := Alias(),;
		nX

		//ฺฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฟ
		//ณCampos a serem grav. no SX1ณ
		//ณaRegs[nx][01] - X1_GRUPO   ณ
		//ณaRegs[nx][02] - X1_ORDEM   ณ
		//ณaRegs[nx][03] - X1_PERGUNTEณ
		//ณaRegs[nx][04] - X1_PERSPA  ณ
		//ณaRegs[nx][05] - X1_PERENG  ณ
		//ณaRegs[nx][06] - X1_VARIAVL ณ
		//ณaRegs[nx][07] - X1_TIPO    ณ
		//ณaRegs[nx][08] - X1_TAMANHO ณ
		//ณaRegs[nx][09] - X1_DECIMAL ณ
		//ณaRegs[nx][10] - X1_PRESEL  ณ
		//ณaRegs[nx][11] - X1_GSC     ณ
		//ณaRegs[nx][12] - X1_VALID   ณ
		//ณaRegs[nx][13] - X1_VAR01   ณ
		//ณaRegs[nx][14] - X1_DEF01   ณ
		//ณaRegs[nx][15] - X1_DEF02   ณ
		//ณaRegs[nx][16] - X1_DEF03   ณ
		//ณaRegs[nx][17] - X1_DEF04   ณ
		//ณaRegs[nx][18] - X1_DEF05   ณ
		//ณaRegs[nx][19] - X1_F3      ณ
		//ภฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤู

		//ฺฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฟ
		//ณCria uma array, contendo todos os valores...ณ
		//ภฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤฤู

        aAdd(aRegs,{cPerg,'01','Convenio           ?','','','mv_ch1','N', 01,0,0,'C',''                     ,'mv_par01','Oab','Caasp','Oab Prev','Diret','','',''})
        aAdd(aRegs,{cPerg,'02','Tipo Evento        ?','','','mv_ch2','N', 01,0,0,'C',''                     ,'mv_par02','Farmacia','Livraria','Ambos','','','',''})
        aAdd(aRegs,{cPerg,'03','Vencimento De      ?','','','mv_ch3','D', 08,0,0,'G',''                     ,'mv_par03','','','','','','',''})
        aAdd(aRegs,{cPerg,'04','Vencimento Ate     ?','','','mv_ch4','D', 08,0,0,'G',''                     ,'mv_par04','','','','','','',''})
        aAdd(aRegs,{cPerg,'05','Codigo Cliente De  ?','','','mv_ch5','C', 06,0,0,'G',''                     ,'mv_par05','','','','','','SA1',''})
        aAdd(aRegs,{cPerg,'06','Loja Cliente De    ?','','','mv_ch6','C', 02,0,0,'G',''                     ,'mv_par06','','','','','','',''})
        aAdd(aRegs,{cPerg,'07','Codigo Cliente Ate ?','','','mv_ch7','C', 06,0,0,'G',''                     ,'mv_par07','','','','','','SA1',''})
        aAdd(aRegs,{cPerg,'08','Loja Cliente Ate   ?','','','mv_ch8','C', 02,0,0,'G',''                     ,'mv_par08','','','','','','',''})
        aAdd(aRegs,{cPerg,'09','Emissao De         ?','','','mv_ch9','D', 08,0,0,'G',''                     ,'mv_par09','','','','','','',''})
        aAdd(aRegs,{cPerg,'10','Emissao Ate        ?','','','mv_chA','D', 08,0,0,'G',''                     ,'mv_par10','','','','','','',''})

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


#include "protheus.ch"

/*
ÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜ
ฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑ
ฑฑษออออออออออัออออออออออหอออออออัออออออออออออออออออออหออออออัอออออออออออออปฑฑ
ฑฑบPrograma  ณ EmbarNew บAutor  ณ Felipe Melo        บ Data ณ  18/01/2012 บฑฑ
ฑฑฬออออออออออุออออออออออสอออออออฯออออออออออออออออออออสออออออฯอออออออออออออนฑฑ
ฑฑบDesc.     ณ                                                            บฑฑ
ฑฑบ          ณ                                                            บฑฑ
ฑฑฬออออออออออุออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออนฑฑ
ฑฑบUso       ณ                                                            บฑฑ
ฑฑศออออออออออฯออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออผฑฑ
ฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑฑ
฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿฿
*/

Static Function EmbarNew(cVar,nOpc)

Local cRet := ""
Local cRes := ""

Default cVar := ""
Default nOpc := 1

//*Tratamento Padrใo
cRet := Embaralha(cVar,nOpc)

//*Tratamento devido atualiza็ใo Protheus
If SubStr(cRet,1,2) == "#@"
   	cRes := DtoC(CtoD("01/01/96") + Load2in4(SubStr(cRet,16)))
  	cRes += " - "
  	cRes += AllTrim(UsrRetName(SubStr(cRet,3,6)))
ElseIf !Empty(cRet)
   	cRes := DtoC(CtoD("01/01/96") + Load2in4(SubStr(cRet,16)))
   	cRes += " - "
  	cRes += SubStr(cRet,1,15)
EndIf

Return(cRes)
