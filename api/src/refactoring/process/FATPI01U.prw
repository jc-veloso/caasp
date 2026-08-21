#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'
#Include 'FWMVCDef.ch'

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

// ==========================================================================
// PI_CLI_X — Upsert de Cliente (CRMA980), extraida de FATPI06.prw (DoPost)
// [ZZG] Jose Carlos - Artiq - 08/2026
// Extraida pra ser chamada tanto pelo endpoint sincrono (FATPI06.prw, que
// agora so faz parse+chamada) quanto pelo Job assincrono FATZZG01.prw
// (cliente/fornecedor pendente, ver instrucao_zzg_cliente_fornecedor.md).
// Retorno no mesmo formato de U_PI_PROD_X: {lOk, cMensagem, cCodProtheus}.
// Logica de negocio (model CRMA980, validacao de duplicidade via
// A1_LEGADO) e transcricao 1:1 do DoPost original - so trocou a fonte do
// JSON (de oSelf:GetContent() pra parametro ja parseado) e a saida (de
// oSelf:SetResponse pro array de retorno).
// ==========================================================================
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
                // [FIX-JA-CADASTRADO] Jose Carlos - Artiq - 08/2026
                // Achado em teste real (19/08): cliente ja cadastrado
                // retornava {.F., ...} - tratado como ERRO, o que travava a
                // liberacao da pendencia (U_ZZPENDOK/U_ZZ_LIBNF so rodam no
                // caminho lOk==.T. em FATZZG01.prw). Mas "ja cadastrado" nao
                // e falha - o objetivo (cliente existir) ja foi atingido.
                // Corrigido pra sucesso, devolvendo o A1_COD ja existente.
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
        // [FIX-SYNC-PICLI] Jose Carlos - Artiq - 08/2026
        // A1_PESSOA fixo em "F" era divergente do FATPI06.prw ja corrigido
        // contra payload real do Arthur (Json tabela muro Cliente.txt) -
        // ver instrucao_sync_pi_cli_forn.md, item 1.2. F/J por tamanho do
        // documento (CPF 11 digitos / CNPJ 14).
        If Len(U_PI_STR_X(oJson, "cpf")) = 11
            oSA1Mod:SetValue("A1_PESSOA" , "F")
        ElseIf Len(U_PI_STR_X(oJson, "cpf")) = 14
            oSA1Mod:SetValue("A1_PESSOA" , "J")
        EndIf
        oSA1Mod:SetValue("A1_LEGADO" , cVLeg)
        // [FIX-CLI-RH] Jose Carlos - Artiq - 08/2026
        // Campos novos pedidos pelo time - cod_RH/tpo_Funcionario do JSON
        // pra A1_XCODRH/A1_TPOFUNC (SA1).
        oSA1Mod:SetValue("A1_XCODRH" , U_PI_STR_X(oJson, "cod_RH"))
        oSA1Mod:SetValue("A1_TPOFUNC", U_PI_STR_X(oJson, "tpo_Funcionario"))

        // [FIX-SYNC-PICLI] Jose Carlos - Artiq - 08/2026
        // A1_COD_MUN sem default de cod_Municipio era divergente do
        // FATPI06.prw ja corrigido - ver instrucao_sync_pi_cli_forn.md,
        // item 1.1. Default primeiro, cod_mun sobrescreve se vier.
        // [FIX-CODMUN] Jose Carlos - Artiq - 08/2026
        // Chave de override era "cod_ibge", mas o payload real (fila ZZG,
        // testado 19/08) manda "cod_mun" - "cod_ibge" nunca vinha, override
        // nunca disparava, ficava so com cod_Municipio (que nao e um codigo
        // IBGE valido). Corrigido pra ler a chave certa.
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
                aRet := {.F., oModel:GetErrorMessage(), ""}
            EndIf
        Else
            RollBackSX8()
            aRet := {.F., oModel:GetErrorMessage(), ""}
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

// ==========================================================================
// PI_FORN_X — Upsert de Fornecedor (MATA020), extraida de FATPI03.PRW
// (WSMETHOD POST NEW). [ZZG] Jose Carlos - Artiq - 08/2026
// Processa UM fornecedor por chamada (nao o array/lote inteiro) - quem
// itera multiplos itens e o chamador (endpoint FATPI03.prw, ou o Job
// FATZZG01.prw pro fluxo assincrono). Retorno {lOk, cMensagem,
// cCodProtheus}, mesmo formato de U_PI_PROD_X/U_PI_CLI_X. Logica do model
// MATA020 (incluindo o bloco de dados bancarios) e transcricao 1:1 do
// loop original (FATPI03.PRW, linhas 90-167) - nao tinha ErrorBlock/Begin
// Sequence no original, mantido assim aqui tambem (excecao nao tratada
// propaga pro chamador - mesmo risco ja documentado como pendencia geral
// de tratamento de erro nos Jobs, nao resolvido so aqui).
// ==========================================================================
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
    // [FIX-SYNC-PIFORN] Jose Carlos - Artiq - 08/2026
    // A2_COD_MUN/A2_CODPAIS ausentes - divergente do FATPI03.PRW ja
    // corrigido contra payload real do Arthur (Json tabela muro
    // Fornecedor.txt) - ver instrucao_sync_pi_cli_forn.md, item 2.2.
    oModel:SetValue("SA2MASTER", "A2_COD_MUN", AllTrim(cValToChar(jItem["cod_IBGE"])))
    oModel:SetValue("SA2MASTER", "A2_CODPAIS", cValToChar(jItem["cod_pais"]))

    oModel:SetValue("SA2MASTER", "A2_END"   , Left(cValToChar(jItem["nom_Logradouro"]), 40))
    oModel:SetValue("SA2MASTER", "A2_BAIRRO", Left(cValToChar(jItem["nom_Bairro"]), 30))
    oModel:SetValue("SA2MASTER", "A2_INSCR" , AllTrim(cValToChar(jItem["num_InscricaoEstadual"])))

    oModel:SetValue("SA2MASTER", "A2_BANCO"  , cValToChar(jItem["cod_Banco"]))
    oModel:SetValue("SA2MASTER", "A2_AGENCIA", cValToChar(jItem["num_Agencia"]))
    // [FIX-SYNC-PIFORN] Jose Carlos - Artiq - 08/2026
    // A2_NUMCON lia num_ContaCorrente (campo errado) - divergente do
    // FATPI03.PRW ja corrigido - ver instrucao_sync_pi_cli_forn.md, item
    // 2.1. A2_DVCTA (digito) tambem ausente - item 2.2.
    oModel:SetValue("SA2MASTER", "A2_NUMCON" , cValToChar(jItem["num_Conta"]))
    oModel:SetValue("SA2MASTER", "A2_DVCTA"  , cValToChar(jItem["num_ContaDig"]))

    oModel:SetValue("SA2MASTER", "A2_RISCO" , "A")
    oModel:SetValue("SA2MASTER", "A2_MSBLQL", IIF(Upper(cValToChar(jItem["flg_Ativo"])) == "S", "2", "1"))

    If oModel:VldData()
        If oModel:CommitData()
            aRet := {.T., "Fornecedor incluido com sucesso: " + cProxCod, cProxCod}
        Else
            aRet := {.F., oModel:GetErrorMessage(), ""}
        EndIf
    Else
        aRet := {.F., oModel:GetErrorMessage(), ""}
    EndIf

    oModel:DeActivate()
    oModel:Destroy()
    oModel := Nil

Return aRet

// ==========================================================================
// PI_NUMERA_X — Numeracao de documento fiscal (SF2/F2_DOC ou SF1/F1_DOC),
// extraida de ZZ901_Classifica (FATZZ901.prw).
// [MOVIDO-ZZ901] Jose Carlos - Artiq - 08/2026
// Bug que originou a mudanca: ZZ901_Classifica trocava de ambiente pra
// resolver a filial real da nota (RpcSetEnv) e nunca voltava antes de
// gravar via U_ZZX_Gravar (que usa xFilial(), refletindo a filial ja
// trocada) - ZZA/ZZC gravavam com filial errada. Corrigido eliminando a
// troca de ambiente do classificador por completo: SA1/SA2/SF4/SX5 sao
// cadastro compartilhado entre filiais (confirmado - nao precisam de
// RpcSetEnv na filial real), so numeracao (GetSxeNum/SX8, por filial) e
// gravacao fiscal final realmente precisam. Os Jobs de destino
// (FATZZA01/B01/C01) ja trocam de ambiente pra filial real antes de
// chamar o motor fiscal - a numeracao move pra dentro desse trecho que ja
// existia, chamando esta funcao. Ver instrucao_mover_numeracao_para_jobs.md.
//
// cTabFis: "SF2" (Saida/NFCe) ou "SF1" (Devolucao/Entrada).
// cCampoDoc: "F2_DOC" ou "F1_DOC".
// cNumInformado (opcional): quando a nota ja vem com numero no payload
// (num_NF/num_NotaFiscal/cod_ReciboVenda - desvio que ja existia em
// ZZ901_Classifica, preservado aqui), usa esse numero em vez de gerar via
// GetSxeNum. Relevante principalmente pra Entrada (SF1/F1_DOC e o numero
// real da nota do fornecedor, nao um numero que o Protheus inventa).
//
// Confere disponibilidade do numero gerado (loop com Soma1, mesmo padrao
// que ja existia), confere duplicidade real (nota ja processada pra esse
// cCod/cLoja/cSer - mesma query que existia dentro do ZZ901_Classifica) e
// faz a limpeza SFT/SF3 (tambem movida de ZZ901_Classifica - so fazia
// sentido junto do numero definitivo). Chamar ANTES de qualquer efeito
// colateral fiscal do motor (nao so antes da gravacao final) - em
// FATZZC01.prw isso significa antes de U_PI_GERAPC_X, nao so antes de
// U_PI_GERANF_X: cLeg (parametro do GERAPC) e so referencia informativa
// (C7_OBS/C7_LEGADO, confirmado nao afeta numeracao fiscal), mas se a
// numeracao/duplicidade so fosse checada depois do GERAPC, uma nota
// duplicada em retry criaria um pedido de compra (SC7) novo antes de ser
// barrada - regressao em relacao ao comportamento original, onde a
// duplicidade era checada antes de QUALQUER chamada de motor.
//
// Retorno: {lOk, cNF, lDuplicado}
//   lOk == .T. e lDuplicado == .T. -> nota ja processada, cNF = numero ja
//     existente (quem chama decide o que fazer - tratar como sucesso sem
//     gravar de novo, nao como erro).
// ==========================================================================
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

	// Duplicidade real - mesma query que existia dentro do ZZ901_Classifica,
	// agora generica por SF2 (Saida/NFCe) ou SF1 (Devolucao/Entrada).
	cQryAux := "SELECT " + cCampoDoc + " FROM " + RetSqlName(cTabFis) + " WHERE " + cCampoDoc + " = '" + cNF + "' AND " + cCampoSer + " = '" + cSer + "' AND " + cCampoCliFor + " = '" + cCod + "' AND " + cCampoLoja + " = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	If (cAliAux)->(!Eof())
		(cAliAux)->(DbCloseArea())
		Return {.T., cNF, .T.}
	EndIf
	(cAliAux)->(DbCloseArea())

	// [REV2-EXTRACAO-NFCE] Limpeza SFT/SF3 - movida de ZZ901_Classifica, so
	// fazia sentido junto do numero definitivo (antes rodava logo apos a
	// checagem de duplicidade, mesmo lugar relativo aqui).
	cQryAux := "UPDATE " + RetSqlName("SFT") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE FT_NFISCAL = '" + cNF + "' AND FT_SERIE = '" + cSer + "' AND FT_CLIEFOR = '" + cCod + "' AND FT_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	TCSqlExec(cQryAux)
	cQryAux := "UPDATE " + RetSqlName("SF3") + " SET D_E_L_E_T_ = '*', R_E_C_D_E_L_ = R_E_C_N_O_ WHERE F3_NFISCAL = '" + cNF + "' AND F3_SERIE = '" + cSer + "' AND F3_CLIEFOR = '" + cCod + "' AND F3_LOJA = '" + cLoja + "' AND D_E_L_E_T_ = ' '"
	TCSqlExec(cQryAux)

Return {.T., cNF, .F.}
