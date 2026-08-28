#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'
#Include 'FWMVCDef.ch'

// Funcoes utilitarias compartilhadas pelos motores de NFe/NFCe (parse de
// JSON, filial por CNPJ, numeracao, upsert de cliente/fornecedor, etc).

// Executa MATA120 (pedido de compra) via ExecAuto
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

// Executa MATA103 (nota fiscal de entrada/devolucao) via ExecAuto
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

// Le uma chave (ou uma chave alternativa) de um objeto JSON como string
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

// Le uma chave (ou uma chave alternativa) de um objeto JSON como numero
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

// Remove pontuacao (., -, /) de um documento (CNPJ/CPF)
User Function PI_LIMPA_X(c)
    Local cRet := StrTran(AllTrim(c), ".", "")
    cRet := StrTran(cRet, "-", "")
    cRet := StrTran(cRet, "/", "")
Return cRet

// Converte string de data (ISO) pra Date; vazio cai em dDataBase
User Function PI_DATA_X(c)
    If Empty(c)
        Return dDataBase
    EndIf
    Return SToD(StrTran(SubStr(c, 1, 10), "-", ""))

// Resolve empresa/filial (SM0) a partir do CNPJ
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

// Resolve cliente (SA1) ou fornecedor (SA2) por CNPJ/CPF
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

// Centro de custo padrao do produto (SB1), com fallback
User Function PI_CCUSTO_X(cProd)
    Local cCust := Posicione("SB1", 1, xFilial("SB1") + PadR(cProd, TamSx3("B1_COD")[1]), "B1_CC")
    If Empty(cCust)
        cCust := "03801"
    EndIf
Return cCust

// Conta contabil do produto (SB1), com fallback via MV_XCCPAD
User Function PI_CONTA_X(cProd)
    Local cConta := Posicione("SB1", 1, xFilial("SB1") + PadR(cProd, TamSx3("B1_COD")[1]), "B1_CONTA")
    If Empty(cConta)
        cConta := SuperGetMv("MV_XCCPAD", .F., "11100901")
    EndIf
Return cConta

// Armazem/local padrao do produto (SB1), com fallback
User Function PI_LOCAL_X(cProd)
    Local cLoc := Posicione("SB1", 1, xFilial("SB1") + PadR(cProd, TamSx3("B1_COD")[1]), "B1_LOCPAD")
    If Empty(cLoc)
        cLoc := "01"
    EndIf
Return cLoc

// Natureza de operacao do cliente (SA1), com fallback
User Function PI_NAT_X(cCli, cLoja, oJson)
    Local cNat := Posicione("SA1", 1, xFilial("SA1") + cCli + cLoja, "A1_NATUREZ")
    If Empty(cNat)
        cNat := "OUTROS"
    EndIf
Return cNat

// UF do cliente/fornecedor (SA1/SA2), com fallback
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

// Grava a chave de acesso da NFe no cabecalho fiscal (SF2)
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

// Ajustes finos de item antes do motor fiscal - hoje sem efeito (stub)
User Function PI_FIXPROD(cProd, oItem)
Return

// Stub reservado
Static Function FZ_FIX_TES(cTES)
Return

// Condicao de pagamento a usar - hoje repassa o valor recebido
User Function PI_COND_X(c)
Return c

// Condicao de pagamento padrao (fallback)
User Function PI_COND1_X()
Return "001"

// Ponto de ajuste de FCA no cabecalho antes do motor - hoje sem efeito (stub)
User Function PI_SETFCA(cTab, cCod, cLoja, cCond, oHead)
Return

// Grava em disco o log de erro do ExecAuto (GetAutoGrLog)
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

// Inverte o CFOP entre entrada (1/2/3) e saida (5/6/7) conforme a operacao
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

// Resolve empresa/filial (SM0) por CNPJ - usado no fluxo de transferencia/CONVENIOS
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

// Valida existencia de CEST (F0G) ou NCM (SYD) no cadastro fiscal
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

// Monta uma mensagem legivel a partir do retorno de oModel:GetErrorMessage() (string ou array de 9 posicoes)
Static Function MontaErroModel(uErro)
	Local cMsg   := ""
	Local cCampo := ""
	Local cValor := ""

	If ValType(uErro) == "A"
		If Len(uErro) >= 9
			cCampo := AllTrim(cValToChar(uErro[4]))
			cValor := AllTrim(cValToChar(uErro[9]))
			cMsg := "Conteudo invalido para o campo " + cCampo
			If !Empty(cValor)
				cMsg += ": " + cValor
			EndIf
		Else
			cMsg := "Erro de validacao do model."
		EndIf
	Else
		cMsg := cValToChar(uErro)
	EndIf
Return cMsg

// Upsert de cliente (SA1) via MVC - dedup por A1_LEGADO
User Function PI_CLI_X(oJson)
    Local aRet       := {.F., "", ""}
    Local bErrBlock
    Local cErrorMsg  := ""
    Local cProxCod   := ""
    Local cVLeg      := ""
    Local cEstAux    := ""
    Local oModel     := Nil
    Local oSA1Mod    := Nil
    Local cQryAux    := ""
    Local cAliAux    := ""

    bErrBlock := ErrorBlock({ |e| cErrorMsg := e:Description, Break(e) })

    Begin Sequence

        cVLeg := SubStr(U_PI_STR_X(oJson, "codigo"), 1, 15)

        If !Empty(cVLeg)
            cQryAux := "SELECT A1_COD FROM " + RetSqlName("SA1") + " WHERE A1_LEGADO = '" + cVLeg + "' AND D_E_L_E_T_ = ' '"
            cAliAux := GetNextAlias()
            MpSysOpenQuery(cQryAux, cAliAux)
            If (cAliAux)->(!Eof())
                cProxCod := AllTrim((cAliAux)->A1_COD)
                (cAliAux)->(DbCloseArea())
                aRet := {.T., "Cliente ja cadastrado (mantido): " + cVLeg, cProxCod}
                Break
            EndIf
            (cAliAux)->(DbCloseArea())
        EndIf

        cEstAux := Upper(U_PI_STR_X(oJson, "estado"))

        If "SAO PAULO" $ cEstAux .Or. "SÃO PAULO" $ cEstAux
            cEstAux := "SP"
        Else
            cEstAux := Left(cEstAux, 2)
        EndIf

        cProxCod := GetSxeNum("SA1", "A1_COD")

        oModel := FWLoadModel("CRMA980")
        oModel:SetOperation(MODEL_OPERATION_INSERT)
        oModel:Activate()

        oSA1Mod := oModel:GetModel("SA1MASTER")

        oSA1Mod:SetValue("A1_COD"    , cProxCod)
        oSA1Mod:SetValue("A1_LOJA"   , "01")
        oSA1Mod:SetValue("A1_NOME"   , Upper(U_PI_STR_X(oJson, "nome")))
        oSA1Mod:SetValue("A1_NREDUZ" , SubStr(Upper(U_PI_STR_X(oJson, "nome")), 1, 20))
        oSA1Mod:SetValue("A1_CGC"    , U_PI_STR_X(oJson, "cpf"))
        oSA1Mod:SetValue("A1_END"    , Upper(U_PI_STR_X(oJson, "endereco")))
        oSA1Mod:SetValue("A1_BAIRRO" , Upper(U_PI_STR_X(oJson, "bairro")))
        oSA1Mod:SetValue("A1_MUN"    , Upper(U_PI_STR_X(oJson, "municipio")))
        oSA1Mod:SetValue("A1_EST"    , cEstAux)
        oSA1Mod:SetValue("A1_CEP"    , U_PI_STR_X(oJson, "cep"))
        oSA1Mod:SetValue("A1_DDD"    , U_PI_STR_X(oJson, "ddd"))
        oSA1Mod:SetValue("A1_TEL"    , U_PI_STR_X(oJson, "telefone"))
        oSA1Mod:SetValue("A1_EMAIL"  , Lower(U_PI_STR_X(oJson, "email")))
        oSA1Mod:SetValue("A1_TIPO"   , "F")
        If Len(U_PI_STR_X(oJson, "cpf")) = 11
            oSA1Mod:SetValue("A1_PESSOA" , "F")
        ElseIf Len(U_PI_STR_X(oJson, "cpf")) = 14
            oSA1Mod:SetValue("A1_PESSOA" , "J")
        EndIf
        oSA1Mod:SetValue("A1_LEGADO" , cVLeg)
        oSA1Mod:SetValue("A1_XCODRH" , U_PI_STR_X(oJson, "cod_RH"))
        oSA1Mod:SetValue("A1_TPOFUNC", U_PI_STR_X(oJson, "tpo_Funcionario"))

        oSA1Mod:SetValue("A1_COD_MUN", U_PI_STR_X(oJson, "cod_Municipio"))

        If !Empty(U_PI_STR_X(oJson, "cod_mun"))
            oSA1Mod:SetValue("A1_COD_MUN", U_PI_STR_X(oJson, "cod_mun"))
        EndIf

        If oModel:VldData()
            If oModel:CommitData()
                ConfirmSX8()
                aRet := {.T., "Cliente cadastrado: " + cProxCod, cProxCod}
            Else
                RollBackSX8()
                aRet := {.F., MontaErroModel(oModel:GetErrorMessage()), ""}
            EndIf
        Else
            RollBackSX8()
            aRet := {.F., MontaErroModel(oModel:GetErrorMessage()), ""}
        EndIf

        If oModel != Nil
            oModel:DeActivate()
            oModel:Destroy()
            oModel := Nil
        EndIf

    End Sequence

    ErrorBlock(bErrBlock)

    If !Empty(cErrorMsg) .And. !aRet[1]
        aRet := {.F., cErrorMsg, ""}
    EndIf

Return aRet

// Upsert de fornecedor (SA2) via MVC (MATA020) - insert ou update por CNPJ
User Function PI_FORN_X(jItem)
    Local aRet      := {.F., "", ""}
    Local cCNPJ     := ""
    Local cMun      := ""
    Local cProxCod  := ""
    Local cLoja     := ""
    Local oModel    := Nil

    Private lMsErroAuto := .F.
    Private lMsHelpAuto := .F.

    cCNPJ := U_PI_LIMPA_X(cValToChar(jItem['num_CNPJ_CPF']))
    cMun  := AllTrim(cValToChar(jItem['nom_Municipio']))

    If Empty(cMun)
        Return {.F., "O campo Municipio (nom_Municipio) e obrigatorio e nao foi preenchido.", ""}
    EndIf

    DbSelectArea("SA2")
    SA2->(DbSetOrder(3))

    oModel := FwLoadModel("MATA020")

    If !Empty(cCNPJ) .And. SA2->(MsSeek(FWxFilial("SA2") + cCNPJ))
        oModel:SetOperation(MODEL_OPERATION_UPDATE)
        cProxCod := SA2->A2_COD
        cLoja    := SA2->A2_LOJA
    Else
        oModel:SetOperation(MODEL_OPERATION_INSERT)
        cProxCod := GetSxeNum("SA2", "A2_COD")
        cLoja    := "01"
        ConfirmSX8()
    EndIf

    oModel:Activate()
    oModel:SetValue("SA2MASTER", "A2_COD"   , cProxCod)
    oModel:SetValue("SA2MASTER", "A2_LOJA"  , cLoja)
    oModel:SetValue("SA2MASTER", "A2_NOME"  , Left(cValToChar(jItem["nom_Fornecedor"]), 40))
    oModel:SetValue("SA2MASTER", "A2_NREDUZ", Left(cValToChar(jItem["nom_Fantasia"]), 20))
    oModel:SetValue("SA2MASTER", "A2_TIPO"  , Upper(AllTrim(cValToChar(jItem["tpo_Pessoa"]))))
    oModel:SetValue("SA2MASTER", "A2_CGC"   , cCNPJ)

    oModel:SetValue("SA2MASTER", "A2_EST" , Upper(AllTrim(cValToChar(jItem["cod_UF"]))))
    oModel:SetValue("SA2MASTER", "A2_MUN" , Left(cMun, 30))
    oModel:SetValue("SA2MASTER", "A2_CEP" , StrTran(cValToChar(jItem["num_CEP"]), "-", ""))
    oModel:SetValue("SA2MASTER", "A2_COD_MUN", AllTrim(cValToChar(jItem["cod_IBGE"])))
    oModel:SetValue("SA2MASTER", "A2_CODPAIS", cValToChar(jItem["cod_pais"]))

    oModel:SetValue("SA2MASTER", "A2_END"   , Left(cValToChar(jItem["nom_Logradouro"]), 40))
    oModel:SetValue("SA2MASTER", "A2_BAIRRO", Left(cValToChar(jItem["nom_Bairro"]), 30))
    oModel:SetValue("SA2MASTER", "A2_INSCR" , AllTrim(cValToChar(jItem["num_InscricaoEstadual"])))

    oModel:SetValue("SA2MASTER", "A2_BANCO"  , cValToChar(jItem["cod_Banco"]))
    oModel:SetValue("SA2MASTER", "A2_AGENCIA", cValToChar(jItem["num_Agencia"]))
    oModel:SetValue("SA2MASTER", "A2_NUMCON" , cValToChar(jItem["num_Conta"]))
    oModel:SetValue("SA2MASTER", "A2_DVCTA"  , cValToChar(jItem["num_ContaDig"]))

    oModel:SetValue("SA2MASTER", "A2_RISCO" , "A")
    oModel:SetValue("SA2MASTER", "A2_MSBLQL", IIF(Upper(cValToChar(jItem["flg_Ativo"])) == "S", "2", "1"))

    If oModel:VldData()
        If oModel:CommitData()
            aRet := {.T., "Fornecedor incluido com sucesso: " + cProxCod, cProxCod}
        Else
            aRet := {.F., MontaErroModel(oModel:GetErrorMessage()), ""}
        EndIf
    Else
        aRet := {.F., MontaErroModel(oModel:GetErrorMessage()), ""}
    EndIf

    oModel:DeActivate()
    oModel:Destroy()
    oModel := Nil

Return aRet

// Gera/valida o numero fiscal (SX8), checando duplicidade e limpando SFT/SF3 orfaos
User Function PI_NUMERA_X(cTabFis, cCampoDoc, cSer, cCod, cLoja, cNumInformado)
	Local cNF          := ""
	Local cQryAux      := ""
	Local cAliAux      := ""
	Local cPrefixo     := Left(cCampoDoc, 2)
	Local cCampoCliFor := IIF(cPrefixo == "F2", "F2_CLIENTE", "F1_FORNECE")
	Local cCampoLoja   := cPrefixo + "_LOJA"
	Local cCampoSer    := cPrefixo + "_SERIE"

	Default cNumInformado := ""

	If !Empty(cNumInformado)
		cNF := PadL(AllTrim(cNumInformado), TamSx3(cCampoDoc)[1], "0")
	Else
		cNF := GetSxeNum(cTabFis, cCampoDoc)
		While .T.
			cQryAux := "SELECT " + cCampoDoc + " FROM " + RetSqlName(cTabFis) + " WHERE " + cCampoDoc + " = '" + PadL(AllTrim(cNF), TamSx3(cCampoDoc)[1], "0") + "' AND D_E_L_E_T_ = ' '"
			cAliAux := GetNextAlias()
			MpSysOpenQuery(cQryAux, cAliAux)
			If (cAliAux)->(Eof())
				(cAliAux)->(DbCloseArea())
				Exit
			EndIf
			(cAliAux)->(DbCloseArea())
			cNF := Soma1(cNF)
		EndDo
		ConfirmSx8()
		cNF := PadL(AllTrim(cNF), TamSx3(cCampoDoc)[1], "0")
	EndIf

	cQryAux := "SELECT " + cCampoDoc + " FROM " + RetSqlName(cTabFis) + " WHERE " + cCampoDoc + " = '" + cNF + "' AND " + cCampoSer + " = '" + cSer + "' AND " + cCampoCliFor + " = '" + cCod + "' AND " + cCampoLoja + " = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	If (cAliAux)->(!Eof())
		(cAliAux)->(DbCloseArea())
		Return {.T., cNF, .T.}
	EndIf
	(cAliAux)->(DbCloseArea())

	cQryAux := "UPDATE " + RetSqlName("SFT") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE FT_NFISCAL = '" + cNF + "' AND FT_SERIE = '" + cSer + "' AND FT_CLIEFOR = '" + cCod + "' AND FT_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	TCSqlExec(cQryAux)
	cQryAux := "UPDATE " + RetSqlName("SF3") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE F3_NFISCAL = '" + cNF + "' AND F3_SERIE = '" + cSer + "' AND F3_CLIEFOR = '" + cCod + "' AND F3_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	TCSqlExec(cQryAux)

Return {.T., cNF, .F.}
