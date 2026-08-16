#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

/*
+----------------------------------------------------------------------------+
| Autor: Antonio Nunes O Jr / Jose Carlos - Artiq                            |
| Data: 07/2026                                                              |
| Descritivo: FATPI01U - Utilitarios Compartilhados                         |
|             Compilar ANTES de todos os outros fontes FATPI01x              |
+----------------------------------------------------------------------------+
*/

User Function PI_EXE120_X(c,i)
    Local cM := ""
    Private INCLUI := .T.
    Private lMsErroAuto := .F.
    Private lAutoErrNoFile := .T.
    Private __cBatch := "1"
    Private cCadastro := "PC"
    MSExecAuto({|x,y,z| MATA120(x,y,z)},1,c,i)
    If lMsErroAuto 
        RollBackSx8() 
        cM := U_PI_LOG_X("MATA120") 
        Return {.F., cM} 
    EndIf
Return {.T., "OK"}

User Function PI_EXE103_X(c, i, cTipo)
    Local cM := ""
    Private INCLUI := .T.
    Private lMsErroAuto := .F.
    Private lAutoErrNoFile := .T.
    Private __cBatch := "1"
    Private cCadastro := "NFE"
    MSExecAuto({|x, y, z| MATA103(x, y, z)}, c, i, 3)
    If lMsErroAuto
        RollBackSx8()
        If cTipo == "D" 
            cM := U_PI_LOG_X("MATA103_DEV") 
        Else 
            cM := U_PI_LOG_X("MATA103") 
        EndIf
        Return {.F., cM}
    EndIf
Return {.T., "OK"}

User Function PI_STR_X(o, k1, k2)
    Local x := ""
    If o != Nil 
        x := o[k1]
        If x == Nil .And. k2 != Nil
            x := o[k2]
        EndIf
    EndIf
    
    If ValType(x) == "C"
        Return AllTrim(x)
    ElseIf ValType(x) == "N"
        Return cValToChar(x)
    ElseIf ValType(x) == "L"
        If x
            Return "S"
        Else
            Return ""
        EndIf
    EndIf
Return ""

User Function PI_VAL_X(o, k1, k2)
    Local x := 0
    If o != Nil 
        x := o[k1]
        If x == Nil .And. k2 != Nil
            x := o[k2]
        EndIf
    EndIf

    If ValType(x) == "N"
        Return x
    ElseIf ValType(x) == "C"
        Return Val(x)
    EndIf
Return 0

User Function PI_LIMPA_X(c)
    Local cRet := StrTran(AllTrim(c), ".", "")
    cRet := StrTran(cRet, "-", "")
    cRet := StrTran(cRet, "/", "")
Return cRet

User Function PI_DATA_X(c)
    If Empty(c) 
        Return dDataBase 
    EndIf
    Return SToD(StrTran(SubStr(c, 1, 10), "-", ""))

User Function PI_FILIAL_X(cCgc)
    Local aRet := {}
    Local cAliasSM0 := GetNextAlias()
    Local cQuery := "SELECT M0_CODIGO, M0_CODFIL FROM " + RetSqlName("SM0") + " WHERE M0_CGC = '" + U_PI_LIMPA_X(cCgc) + "' AND D_E_L_E_T_ = ' '"
    
    DbUseArea(.T., "TOPCONN", TcGenQry(,,cQuery), cAliasSM0, .T., .T.)
    
    If (cAliasSM0)->(!Eof())
        AAdd(aRet, AllTrim((cAliasSM0)->M0_CODIGO))
        AAdd(aRet, AllTrim((cAliasSM0)->M0_CODFIL))
    EndIf
    
    (cAliasSM0)->(DbCloseArea())
Return aRet

User Function PI_BUSCA_X(cT, cK, cF, cC, cL, cFi)
    Local cA := GetNextAlias()
    Local cField := ""
    Local cQ := ""

    If cT == "SA1"
        cField := "A1_CGC"
        cQ := "SELECT A1_COD AS COD, A1_LOJA AS LOJA FROM " + RetSqlName(cT) + " WHERE " + cField + " = '" + cK + "' AND D_E_L_E_T_ = ' '"
    Else
        cField := "A2_CGC"
        cQ := "SELECT A2_COD AS COD, A2_LOJA AS LOJA FROM " + RetSqlName(cT) + " WHERE " + cField + " = '" + cK + "' AND D_E_L_E_T_ = ' '"
    EndIf
    
    MpSysOpenQuery(cQ, cA)
    
    If (cA)->(!Eof())
        cC := (cA)->COD
        cL := (cA)->LOJA
        cFi := cF
    EndIf
    
    (cA)->(DbCloseArea())
Return

User Function PI_CCUSTO_X(cProd)
    Local cCust := Posicione("SB1", 1, xFilial("SB1") + PadR(cProd, TamSx3("B1_COD")[1]), "B1_CC")
    If Empty(cCust)
        cCust := "03801"
    EndIf
Return cCust

User Function PI_CONTA_X(cProd)
    Local cConta := Posicione("SB1", 1, xFilial("SB1") + PadR(cProd, TamSx3("B1_COD")[1]), "B1_CONTA")
    If Empty(cConta)
        cConta := SuperGetMv("MV_XCCPAD", .F., "11100901")
    EndIf
Return cConta

User Function PI_LOCAL_X(cProd)
    Local cLoc := Posicione("SB1", 1, xFilial("SB1") + PadR(cProd, TamSx3("B1_COD")[1]), "B1_LOCPAD")
    If Empty(cLoc)
        cLoc := "01"
    EndIf
Return cLoc

User Function PI_NAT_X(cCli, cLoja, oJson)
    Local cNat := Posicione("SA1", 1, xFilial("SA1") + cCli + cLoja, "A1_NATUREZ")
    If Empty(cNat)
        cNat := "OUTROS"
    EndIf
Return cNat

User Function PI_UF_X(cTab, cCod, cLoja)
    Local cEst := "SP"
    DbSelectArea(cTab)
    (cTab)->(DbSetOrder(1))
    If (cTab)->(DbSeek(xFilial(cTab) + cCod + cLoja))
        If cTab == "SA1"
            cEst := SA1->A1_EST
        Else
            cEst := SA2->A2_EST
        EndIf
    EndIf
Return cEst

User Function PI_CHVNFE_X(cDoc, cLeg, cSer, oHead, cPed)
    Local cChave := U_PI_STR_X(oHead, "cod_ChaveNFe")
    If Select("SF2") > 0
        DbSelectArea("SF2")
        SF2->(DbSetOrder(1))
        If SF2->(DbSeek(xFilial("SF2") + PadR(cDoc, TamSx3("F2_DOC")[1]) + PadR(cSer, TamSx3("F2_SERIE")[1])))
            RecLock("SF2", .F.)
            If SF2->(FieldPos("F2_CHVNFE")) > 0
                SF2->F2_CHVNFE := PadR(cChave, TamSx3("F2_CHVNFE")[1])
            EndIf
            If SF2->(FieldPos("F2_LEGADO")) > 0
                SF2->F2_LEGADO := cLeg
            EndIf
            SF2->(MsUnlock())
        EndIf
    EndIf
Return

User Function PI_FIXPROD(cProd, oItem)
Return

Static Function FZ_FIX_TES(cTES)
Return

User Function PI_COND_X(c)
Return c

User Function PI_COND1_X()
Return "001"

User Function PI_SETFCA(cTab, cCod, cLoja, cCond, oHead)
Return

User Function PI_LOG_X(cRotina)
    Local cErrLog := ""
    Local aLogAut := GetAutoGrLog()
    Local cFile   := ""
    Local nL      := 0
    Local cDt     := DToS(Date())
    Local cHr     := StrTran(Time(), ":", "-")
    
    cErrLog += "Rotina: " + cRotina + CRLF 
    cErrLog += "Data/Hora: " + cDt + " " + cHr + CRLF 
    cErrLog += "--------------------------------------------------" + CRLF
    
    If ValType(aLogAut) == "A"
        For nL := 1 To Len(aLogAut) 
            cErrLog += aLogAut[nL] + CRLF 
        Next nL
    Else
        cErrLog += "Erro generico sem log detalhado do ExecAuto." + CRLF
    EndIf
    
    cFile := "\system\FATPI01_" + cRotina + "_" + cDt + "_" + cHr + ".log"
    MemoWrite(cFile, cErrLog) 
    ConOut("[TRAT_ERR] Log gravado em: " + cFile)
Return cErrLog

// ==========================================================================
// INVERSAO DE PARZINHO DE CFOP (ESPELHAMENTO FISCAL)
// ==========================================================================
User Function PI_INVCFOP(cCFOP, cOper)
    Local cRet := AllTrim(cCFOP)

    If cOper == "E" .Or. cOper == "D"
        If Left(cRet, 1) == "5"
            cRet := "1" + SubStr(cRet, 2)
        ElseIf Left(cRet, 1) == "6"
            cRet := "2" + SubStr(cRet, 2)
        ElseIf Left(cRet, 1) == "7"
            cRet := "3" + SubStr(cRet, 2)
        EndIf
    ElseIf cOper == "S"
        If Left(cRet, 1) == "1"
            cRet := "5" + SubStr(cRet, 2)
        ElseIf Left(cRet, 1) == "2"
            cRet := "6" + SubStr(cRet, 2)
        ElseIf Left(cRet, 1) == "3"
            cRet := "7" + SubStr(cRet, 2)
        EndIf
    EndIf

Return PadR(cRet, TamSx3("D1_CF")[1])

/*
+----------------------------------------------------------------------------+
| Autor: Antonio Nunes O Jr | Data: 07/04/2026                               |
| Descritivo: FATPI01NF - Auto-Entrada de Transferencia (CONVENIOS)          |
+----------------------------------------------------------------------------+
*/
User Function FATPIEMP(c)
	Local aR := {}
	Local cA := GetNextAlias()
	Local cQ := ""

	cQ := "SELECT M0_CODIGO, M0_CODFIL FROM " + RetSqlName("SM0") + " WHERE REPLACE(REPLACE(REPLACE(M0_CGC, '.', ''), '-', ''), '/', '') = '" + c + "'"
	MpSysOpenQuery(cQ, cA)

	If (cA)->(!Eof())
		aAdd(aR, AllTrim((cA)->M0_CODIGO))
		aAdd(aR, AllTrim((cA)->M0_CODFIL))
	EndIf
	(cA)->(DbCloseArea())
Return aR

Static Function BuscaCad(cCad,nOpc)

	Local lRet := .F.
	Local nTam := IIF(nOpc = 1,TamSx3("F0G_CEST")[1],TamSx3("YD_TEC")[1])

	cCad := PADR(ALLTRIM(cCad),nTam,'')

	If nOpc = 1
		DbSelectArea('F0G')
		F0G->(DbSetOrder(1))
		If F0G->(DbSeek(xFilial("F0G") + cCad))
			lRet := .T.
		Endif
	Elseif nOpc = 2
		DbSelectArea('SYD')
		SYD->(DbSetOrder(1))
		If SYD->(DbSeek(xFilial("SYD") + cCad))
			lRet := .T.
		Endif
	Endif

Return lRet
