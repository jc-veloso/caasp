#Include 'Protheus.ch'
#Include 'TbiConn.ch'
#Include 'TopConn.ch'
#Include 'RestFul.ch'

/*
+----------------------------------------------------------------------------+
| Autor: Jose Carlos - Artiq                                                 |
| Data: 07/2026                                                              |
| Descritivo: FATPI09 - Endpoint dedicado de NFCe (modelo 65)               |
|             Endpoint: POST /fatpi09/v2                                    |
|                                                                             |
| Extraido do FATPI01_V2 (branch cModDoc=="65"). NFCe e sempre venda ao      |
| consumidor (cOper="S" fixo) � por isso toda a logica de Devolucao (ZZB),   |
| Entrada (ZZC) e Transferencia/CONVENIOS foi removida, assim como a         |
| validacao de emitente em SA2 (o PDV emite a nota, nao precisa ser          |
| fornecedor cadastrado) e a baixa em SFT/SF3 (fiscal e do PDV, nao nosso).  |
|                                                                             |
| [PROD-PENDENTE] Jose Carlos - Artiq - 08/2026                             |
|   A checagem de existencia de produto (1a passada no SB1) que existia     |
|   aqui foi removida. O iPaaS agora manda o campo prod_Pendente na raiz    |
|   do payload (irmao de 'notas') e este endpoint so le e confia nele,      |
|   repassando pro ZZD_PRDPEN via ZZX_Gravar. Deteccao de produto faltante  |
|   e responsabilidade do iPaaS (endpoint proprio, fora deste escopo).      |
|                                                                             |
| [REV2-SYNC-FIX] Jose Carlos - Artiq - 07/2026                             |
|   Este endpoint SO valida payload e classifica/enfileira na ZZD. Nao      |
|   chama motor fiscal nenhum                                               |
|   � nao depende de U_FATCFOP01 nem de U_PI_LOJA_X no caminho sincrono. |
|   Resolucao de cliente, numeracao, CFOP/TES e o disparo do ExecAuto       |
|   LOJA701 (U_PI_LOJA_X) migraram pro FATZZD01.prw (Job) � mesmo        |
|   motivo do ajuste ja feito no FATPI01_V2 pra NFe: quem processa e o Job. |
|   Por isso este arquivo pode ser compilado/testado isoladamente, sem      |
|   precisar do FATCFOP01 disponivel (s� o Job precisa dele).              |
|                                                                             |
| [PENDENTE-FISCAL] Jose Carlos - Artiq - 07/2026                          |
|   RISCO CONHECIDO, decisao consciente de adiar: o ExecAuto LOJA701       |
|   RECALCULA impostos via TES/CFOP no momento da inclusao do orcamento.   |
|   Mas a NFCe ja foi emitida/autorizada pela SEFAZ com os valores que o   |
|   PDV da CAASP calculou � dai o Antonio ter gravado direto nas tabelas   |
|   SIGALOJA no motor original (mesmo padrao do FATPI08/U_FATPI08NF, que   |
|   nao recalcula, so grava o que veio do PDV). Existe um flag/parametro   |
|   no SIGALOJA pra aceitar valor ja calculado sem recalcular (mencionado  |
|   em reuniao, nome exato nao confirmado). Decisao: manter LOJA701 como   |
|   esta por ora � reavaliar como melhoria/adaptacao DEPOIS de alinhar     |
|   com o cliente. Se migrar, o candidato natural e adaptar a escrita      |
|   direta do U_FATPI08NF para NFCe (U_FZ_PROS_NFCE), no lugar do          |
|   ExecAuto. A implementacao de U_PI_LOJA_X agora vive no FATZZD01.prw.|
|                                                                             |
| ATENCAO � pontos assumidos que precisam de revisao antes do teste do JOB:  |
|   1) Nome dos campos de valor total do JSON de NFCe (vlr_TotalProduto/     |
|      vlr_NotaFiscal) � copiados do padrao ja comprovado no Recibo          |
|      (FATPI08/U_FATPI08NF). Se o JSON de NFCe usar nomes diferentes,       |
|      ajustar em U_PI_LOJA_X (agora em FATZZD01.prw).                    |
|   2) L4_FORMA (forma de pagamento) � hoje grava o texto cru vindo do JSON  |
|      (des_FormaPagamento). Se o SLOJA exigir um DE-PARA para codigo        |
|      proprio (dinheiro/cartao/etc.), precisa mapear antes de gravar.       |
|   3) LQ_TIPOCLI fixado em "F" (pessoa fisica) � ajustar se houver cenario  |
|      de venda NFCe para pessoa juridica.                                   |
+----------------------------------------------------------------------------+
*/

WSRESTFUL FATPI09_V2 DESCRIPTION 'NFCe - Venda ao Consumidor CAASP'
	WSMETHOD POST DESCRIPTION 'Processamento NFCe' WSSYNTAX "/fatpi09/v2" PATH "/fatpi09/v2" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST WSRECEIVE WSSERVICE FATPI09_V2
	// --- 1. DECLARACAO GERAL DE VARIAVEIS ---
	Local lRet         := .T.
	Local cJson        := Self:GetContent()
	Local jJson        := JsonObject():New()
	Local jRes         := JsonObject():New()
	Local nStat        := 200
	Local cModDoc      := ""
	Local aInv         := {}
	Local oHead        := Nil
	Local aPrd         := {}
	Local aEmp         := {}
//	Local aRet         := {}
	Local cCnpj        := ""
	Local cChvNFe      := ""
//	Local cNF          := ""
//	Local cSer         := ""
//	Local lOk          := .T.
//	Local cTab         := "SA1"
//	Local cCod         := ""
//	Local cLoja        := ""
//	Local cFil         := ""
//	Local cCliD        := "000001"
//	Local dVencto      := CToD("//")
//	Local cCondSafe    := ""
//	Local cLeg         := ""
//	Local nI           := 0
	Local cQryAux      := ""
	Local cAliAux      := ""
//	Local cAuxC        := ""
//	Local cProdLeg     := ""
//	Local cProdInt     := ""
	Local cProdPend    := ""

	Local cCheckCFOP   := ""
//	Local oMotorRegras := Nil
//	Local aRetCfop     := {}
//	Local nValNF       := 0
	Local cNatOp       := ""
//	Local cCnpjEmit    := ""
//	Local cUsuario     := ""

	Local cOldRestNfe  := ""
//	Local cCn          := ""
	Local cStatusFila  := ""
	Local cErrMsgFila  := ""
//	Local lCest        := .T.
//	Local lNcm         := .T.
//	Local aProdPend    := {}

	Private __cBatch    := "1"
	Private __cXEvento  := "LOJ"

	// --- 2. PREPARACAO DE AMBIENTE ---
	// [PREPAREIN] Jose Carlos - Artiq - 08/2026
	// RpcSetEnv/RpcClearEnv removidos - nao se usa dentro de WSRESTFUL (TDN
	// oficial, "Abertura de ambiente em Web Service", a partir da 12.1.27).
	// O ambiente ja vem pronto via PREPAREIN do appserver.ini, e
	// empresa/filial resolvidos pelo header TenantId da requisicao. Chamar
	// RpcSetEnv de novo aqui conflitava com esse ambiente ja aberto - foi a
	// causa do erro visto em teste. Vale so pros endpoints REST; os Jobs
	// (FATZZA01...FATZZF01) continuam precisando, eles rodam via Schedule
	// sem PREPAREIN.
	cOldRestNfe := SuperGetMv("MV_RESTNFE", .F., "S")
	PutMv("MV_RESTNFE", "N")

	Self:SetContentType('application/json')

	If !Empty(jJson:FromJson(cJson))
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['detalhe']   := "Estrutura JSON"
		jRes['mensagem']  := "JSON invalido ou vazio."

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf

	// --- 3. IDENTIFICACAO DO OBJETO ---
	aInv := jJson['notas']
	If ValType(aInv) != "A"
		aInv := jJson['items']
	EndIf

	If ValType(aInv) != "A" .Or. Len(aInv) == 0
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Payload"
		jRes['mensagem']  := "Array 'notas' ausente ou vazio."

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf

	oHead   := aInv[1]
	cModDoc := U_PI_STR_X(oHead, 'cod_Mod', 'modelo')
	aPrd    := oHead['itens']
	cNatOp  := Upper(AllTrim(U_PI_STR_X(oHead, 'des_NatOp')))
	// [PERF] Chave de acesso extraida uma vez so � reaproveitada em todo o resto da funcao
	// (era chamada U_PI_STR_X(oHead,'cod_ChaveNFe') 7x com o mesmo resultado)
	cChvNFe := AllTrim(U_PI_STR_X(oHead, 'cod_ChaveNFe'))

	// [prod_Pendente] iPaaS agora informa se ha produto pendente direto no
	// payload (raiz, irmao de 'notas') - endpoint so le e confia, nao checa
	// mais o SB1 aqui (ver secao 7 removida / ZZX_Gravar mais abaixo).
	cProdPend := AllTrim(U_PI_STR_X(jJson, 'prod_Pendente'))
	If Empty(cProdPend) ; cProdPend := "N" ; EndIf

	// [GUARDA] Este endpoint e exclusivo de NFCe. Nao processa modelo 55.
	If cModDoc != "65"
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "ModeloIncorreto"
		jRes['mensagem']  := "FATPI09 aceita apenas NFCe (modelo 65). Documento recebido: modelo " + cModDoc + ". Envie para /fatpi01/v2."

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf

	If ValType(aPrd) == "A" .And. Len(aPrd) > 0
		cCheckCFOP := Upper(U_PI_STR_X(aPrd[1], 'cod_ProdutoCFOP', 'cfop'))
	EndIf

	cCnpj := U_PI_LIMPA_X(U_PI_STR_X(oHead, 'num_SubseccaoCNPJ', 'num_SubseccaoCNPJ'))
	aEmp  := U_PI_FILIAL_X(cCnpj)

	If Len(aEmp) < 2
		nStat := 200
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "Filial"
		jRes['detalhe']   := cCnpj
		jRes['mensagem']  := "Filial nao encontrada para CNPJ: " + AllTrim(cCnpj)

		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf

	// --- 4. DUPLICIDADE � verifica na propria fila ZZD (nota nao existe em SF2 ainda, GravaBatch/LOJA701 cria depois) ---
	cQryAux := "SELECT ZZD_STATUS, ZZD_ERRMSG FROM " + RetSqlName("ZZD") + " WHERE ZZD_CHVNFE = '" + cChvNFe + "' AND ZZD_FILIAL = '" + xFilial("ZZD") + "' AND D_E_L_E_T_ = ' '"
	cAliAux := GetNextAlias()
	MpSysOpenQuery(cQryAux, cAliAux)
	If (cAliAux)->(!Eof())
		cStatusFila := AllTrim((cAliAux)->ZZD_STATUS)
		cErrMsgFila := AllTrim((cAliAux)->ZZD_ERRMSG)
		(cAliAux)->(DbCloseArea())

		nStat := 200
		jRes['status']     := nStat
		jRes['resultado']  := "Sucesso"
		jRes['doc']        := "Nota: " + aEmp[2] + " - " + cChvNFe
		jRes['statusFila'] := cStatusFila
		Do Case
			Case cStatusFila == "P"
				jRes['info'] := "NFCe ja recebida, aguardando processamento na fila."
			Case cStatusFila == "A"
				jRes['info'] := "NFCe ja recebida, em processamento no momento."
			Case cStatusFila == "S"
				jRes['info'] := "NFCe ja processada com sucesso anteriormente."
			Case cStatusFila == "E"
				jRes['info'] := "NFCe ja recebida, mas o processamento anterior falhou: " + IIF(Empty(cErrMsgFila), "(sem detalhe registrado)", cErrMsgFila)
			Otherwise
				jRes['info'] := "NFCe ja existe na fila."
		EndCase
		Self:setStatus(nStat)
		Self:SetResponse(EncodeUTF8(jRes:toJSON()))
		PutMv("MV_RESTNFE", cOldRestNfe)
		Return .T.
	EndIf
	(cAliAux)->(DbCloseArea())

	// --- 7. ENFILEIRA NA ZZD PARA O JOB PROCESSAR ---
	// [REV2-SYNC-FIX] CFOP/TES e o disparo do LOJA701 migraram pro FATZZD01 (Job).
	// O endpoint nao depende mais de U_FATCFOP01 no caminho sincrono � so
	// valida, classifica e grava o JSON cru. Mesmo padrao ja usado pra NFe.
	// [QTPROD] Jose Carlos - Artiq - 08/2026 - vem pronto no JSON, tag
	// qt_Produto na raiz da nota (oHead) - so le e repassa (ver
	// instrucao_qtprod.md). Grava aqui, no endpoint de ingestao - nao em
	// ZZD_MotorNFCe (FATZZD01.prw), que so processa a linha ja gravada e
	// nunca escreve na ZZD (a instrucao original apontava o motor por
	// engano, mesmo padrao de discrepancia ja visto antes nesse arquivo).
	If ZZX_Gravar("ZZD", "NFC", "CHVNFE", cChvNFe, jJson:toJSON(), "", "", cProdPend, AllTrim(U_PI_STR_X(oHead, 'qt_Produto')))
		nStat := 201
		jRes['status']    := nStat
		jRes['resultado'] := "Sucesso"
		jRes['doc']       := "NFCe enfileirada: " + cChvNFe
		jRes['info']      := "Nota registrada para processamento assincrono."
	Else
		nStat := 230  // [IPASS-FIX] Falha de sistema (grava��o na fila) - 2xx pra nao quebrar o iPaaS em transporte, distinto de 200 (falha de payload/validacao)
		jRes['status']    := nStat
		jRes['resultado'] := "Falha"
		jRes['erro']      := "FilaMuroZ"
		jRes['mensagem']  := "Falha ao gravar na fila ZZD. Tente novamente."
	EndIf

	Self:setStatus(nStat)
	Self:SetResponse(EncodeUTF8(jRes:toJSON()))
	FreeObj(jJson)
	FreeObj(jRes)

Return lRet

// ==========================================================================
// [NOVA] ZZX_Gravar - Grava registro na tabela Muro Z
// Copia local (Static = escopo do arquivo), mesma assinatura usada no
// FATPI01_V2 e FATPI08_V2 � ver comentario la sobre consolidacao futura.
// [ZZF] Ganhou o parametro cPrdPend (default "N") � usado para represar a
// nota com PRDPEND='S' quando ha produto pendente de cadastro. A gravacao
// em si na ZZF agora e responsabilidade do endpoint FATPI10 (fila de
// produtos pendentes), via U_ZZF_GRV (FATZZF01.prw).
// [QTPROD] Jose Carlos - Artiq - 08/2026 - ganhou cQtProd (default ""),
// parametro dedicado (nao reusa cCampoExtra) porque QTPROD e universal as 6
// tabelas de nota - mesmo raciocinio do cPrdPend, ver [QTPROD] em
// U_ZZX_Gravar (FATZZF01.prw) e instrucao_qtprod.md.
// ==========================================================================
Static Function ZZX_Gravar(cTabMuro, cProc, cCampoChave, cChvRef, cJsonPayload, cCampoExtra, cValorExtra, cPrdPend, cQtProd)
	Local lOk  := .F.
	Local cCod := ""

	Default cCampoExtra := ""
	Default cValorExtra := ""
	Default cPrdPend    := "N"
	Default cQtProd     := ""

	cCod := GetSxeNum(cTabMuro, cTabMuro + "_COD")

	DbSelectArea(cTabMuro)
	If RecLock(cTabMuro, .T.)
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_FILIAL"), xFilial(cTabMuro)))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_COD"),    PadR(cCod, TamSx3(cTabMuro + "_COD")[1])))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_PROC"),   PadR(cProc, TamSx3(cTabMuro + "_PROC")[1])))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_STATUS"), "P"))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_" + cCampoChave), PadR(cChvRef, TamSx3(cTabMuro + "_" + cCampoChave)[1])))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_JSON"),   cJsonPayload))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_DTINCL"), Date()))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_HRINCL"), Time()))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_PRDPEN"),cPrdPend))
		(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_ERRMSG"), ""))
		// [FIX-CLIFOR-BRANCO] Jose Carlos - Artiq - 08/2026
		// ZZD_CLIPEN/ZZD_FORPEN ficavam em branco num registro novo (RecLock
		// nao aplica o default do SIGACFG num INCLUI assim, fora de MVC) - a
		// query do FATZZD01.prw filtra por "= 'N'" literal, entao branco
		// nunca batia e a nota ficava presa pra sempre. Guarda FieldPos por
		// seguranca (mesmo padrao ja usado pro _QTPROD logo abaixo).
		If FieldPos(cTabMuro + "_CLIPEN") > 0
			(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_CLIPEN"), "N"))
		EndIf
		If FieldPos(cTabMuro + "_FORPEN") > 0
			(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_FORPEN"), "N"))
		EndIf
		// Campo numerico (N) no SIGACFG - Val(), nao FieldPut direto do texto
		// (confirmado com Jose Carlos, ver instrucao_qtprod.md).
		If FieldPos(cTabMuro + "_QTPROD") > 0
			(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_QTPROD"), Val(cQtProd)))
		EndIf
		If !Empty(cCampoExtra)
			(cTabMuro)->(FieldPut(FieldPos(cTabMuro + "_" + cCampoExtra), cValorExtra))
		EndIf
		(cTabMuro)->(MsUnlock())
		ConfirmSx8()
		lOk := .T.
	Else
		RollBackSx8()
	EndIf
Return lOk

