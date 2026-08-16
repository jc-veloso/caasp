#Include 'Protheus.ch'

/*
+----------------------------------------------------------------------------+
| Fonte: FATCFOP.prw                                                         |
| Autor: Antonio Nunes O Jr                                                  |
| Data: 02/04/2026                                                           |
| Descritivo: Motor OOP para Validacao e Excecoes de CFOPs especificos       |
+----------------------------------------------------------------------------+
*/

/*/{Protheus.doc} FATCFOP01
Funcao Wrapper para instanciar a Classe de Regras (Respeitando a nomenclatura)
@author Antonio Nunes O Jr
@since 02/04/2026
/*/
User Function FATCFOP01()
    // Declaracao de Variaveis Locais
    Local oRegras := Nil
    
    oRegras := ValidaCFOP():New()
Return oRegras

// ==========================================================================
// DEFINICAO DA CLASSE DE REGRAS FISCAIS
// ==========================================================================
CLASS ValidaCFOP
    DATA aEntradas
    DATA aSaidas

    METHOD New() CONSTRUCTOR
    METHOD IsEntrada(cCFOP)
    METHOD IsSaida(cCFOP)
    METHOD ProcessaRegras(oItemJson, cCFOP, cTES)
ENDCLASS

// ==========================================================================
// METODO CONSTRUTOR: CARGA DE TODOS OS CFOPS MAPEADOS
// ==========================================================================
METHOD New() CLASS ValidaCFOP
    ::aEntradas := {}
    ::aSaidas   := {}

    // --- CARGA DAS ENTRADAS CFOP ---
    AAdd(::aEntradas, "1102") // COMPRA [Qtd NFs: 38330]
    AAdd(::aEntradas, "1403") // COMPRA [Qtd NFs: 21295]
    AAdd(::aEntradas, "1202") // DEVOLUCAO DE VENDA DE MERCADORIA... [Qtd NFs: 599 / 68 / 3 / 1]
    AAdd(::aEntradas, "1411") // DEVOLUCAO DE VENDA DE MERCADORIA... [Qtd NFs: 463 / 15 / 2]
    AAdd(::aEntradas, "1557") // TRANSF. MAT. USO OU CONSUMO DENTRO DO ESTADO [Qtd NFs: 242]
    AAdd(::aEntradas, "2102") // COMPRA [Qtd NFs: 56]
    AAdd(::aEntradas, "1152") // TRANSF. MERC. [Qtd NFs: 27]
    AAdd(::aEntradas, "2403") // COMPRA [Qtd NFs: 10]
    AAdd(::aEntradas, "1409") // TRANSF. MERC. [Qtd NFs: 4]
    AAdd(::aEntradas, "1904") // RET. DE REMESSA P/ VENDA FORA DO ESTABELECIMENTO [Qtd NFs: 4]
    AAdd(::aEntradas, "1910") // COMPRA [Qtd NFs: 3]

    // --- CARGA DAS SAIDAS CFOP ---
    AAdd(::aSaidas, "5405") // VENDA [Qtd NFs: 87999]
    AAdd(::aSaidas, "5152") // TRANSFERENCIA DE MERCADORIA [Qtd NFs: 1432 / 250 / 25]
    AAdd(::aSaidas, "5409") // TRANSFERENCIA DE MERCADORIA [Qtd NFs: 1363 / 274]
    AAdd(::aSaidas, "5202") // DEVOLUCAO DE COMPRA [Qtd NFs: 936 / 4]
    AAdd(::aSaidas, "5411") // DEVOLUCAO DE COMPRA [Qtd NFs: 499 / 2]
    AAdd(::aSaidas, "5557") // TRANSF. MAT. USO OU CONSUMO DENTRO DO ESTADO [Qtd NFs: 311 / 9]
    AAdd(::aSaidas, "5927") // LANC BAIXA ESTOQUE DECOR DE PERDA... [Qtd NFs: 173 / 1]
    AAdd(::aSaidas, "5605") // TRANSF SALDO DEVEDOR DE ICMS... [Qtd NFs: 81]
    AAdd(::aSaidas, "5602") // TRANSF SALDO CREDOR DE ICMS... [Qtd NFs: 43]
    AAdd(::aSaidas, "5929") // LANCAMENTO DE MERCADORIA QUE JA POSSUI ECF [Qtd NFs: 38 / 1]
    AAdd(::aSaidas, "5904") // REM P/ VENDA FORA DO ESTABELECIMENTO [Qtd NFs: 16]
    AAdd(::aSaidas, "5949") // OUTRAS SAIDAS [Qtd NFs: 2]
    AAdd(::aSaidas, "6202") // DEVOLUCAO DE COMPRA DE FORA DO ESTADO [Qtd NFs: 1]
    AAdd(::aSaidas, "6929") // LANCAMENTO EFETUADO EM DECORRENCIA DA ECF [Qtd NFs: 1]

Return Self

// ==========================================================================
// METODO: VERIFICA SE A CFOP PERTENCE AO GRUPO DE ENTRADAS
// ==========================================================================
METHOD IsEntrada(cCFOP) CLASS ValidaCFOP
    // Declaracao de Variaveis Locais
    Local lRet := .F.
    Local nPos := 0
    
    nPos := AScan(::aEntradas, {|x| x == cCFOP})
    
    If nPos > 0
        lRet := .T.
    EndIf
Return lRet

// ==========================================================================
// METODO: VERIFICA SE A CFOP PERTENCE AO GRUPO DE SAIDAS
// ==========================================================================
METHOD IsSaida(cCFOP) CLASS ValidaCFOP
    // Declaracao de Variaveis Locais
    Local lRet := .F.
    Local nPos := 0
    
    nPos := AScan(::aSaidas, {|x| x == cCFOP})
    
    If nPos > 0
        lRet := .T.
    EndIf
Return lRet

// ==========================================================================
// METODO PRINCIPAL: TRATAMENTO DE EXCECOES BASEADO NO JSON
// ==========================================================================
METHOD ProcessaRegras(oItemJson, cCFOP, cTES) CLASS ValidaCFOP
    // Declaracao de Variaveis Locais
    Local aRetorno  := {}
    Local cNovoCFOP := cCFOP
    Local cNovoTES  := cTES
    Local cNatOp    := ""
    Local cCstIcms  := ""

    // Protecao de Leitura do JSON (Evitar Error Log se a tag nao existir)
    If ValType(oItemJson) == "J" .Or. ValType(oItemJson) == "O"
        Begin Sequence
            cNatOp := oItemJson['des_NatOp']
        End Sequence
        Begin Sequence
            cCstIcms := oItemJson['cod_CSTIcms'] // Exemplo de campo extra para tomada de decisao
        End Sequence
    EndIf

    If cNatOp == Nil
        cNatOp := ""
    EndIf
    If cCstIcms == Nil
        cCstIcms := ""
    EndIf

    cNatOp := Upper(AllTrim(cNatOp))

    // ----------------------------------------------------------------------
    // BLOCO DE REGRAS - ENTRADAS
    // ----------------------------------------------------------------------
    If ::IsEntrada(cNovoCFOP)
        Do Case
            Case cNovoCFOP == "1102" .Or. cNovoCFOP == "2102"
                // COMPRA NORMAL (Dentro e Fora do Estado)
                
            Case cNovoCFOP == "1403" .Or. cNovoCFOP == "2403"
                // COMPRA COM ST

            Case cNovoCFOP == "1202" .Or. cNovoCFOP == "1411"
                // DEVOLUCAO DE VENDA (Normal e ST)

            Case cNovoCFOP == "1557"
                // TRANSF. MAT. USO OU CONSUMO
                
            Case cNovoCFOP == "1152" .Or. cNovoCFOP == "1409"
                // TRANSFERENCIA DE MERCADORIA
                
            Case cNovoCFOP == "1904"
                // RETORNO DE REMESSA P/ VENDA FORA DO ESTAB.
                
            Case cNovoCFOP == "1910"
                // COMPRA DE ATIVO / OUTROS
                
        EndCase
    EndIf

    // ----------------------------------------------------------------------
    // BLOCO DE REGRAS - SAIDAS
    // ----------------------------------------------------------------------
    If ::IsSaida(cNovoCFOP)
        Do Case
            Case cNovoCFOP == "5405"
                // VENDA ST (Gigante volume: 87.999 NFs)

            Case cNovoCFOP == "5152" .Or. cNovoCFOP == "5409"
                // TRANSFERENCIA DE MERCADORIA (Normal e ST)

            Case cNovoCFOP == "5202" .Or. cNovoCFOP == "6202" .Or. cNovoCFOP == "5411"
                // DEVOLUCAO DE COMPRA (Normal, Fora do Estado e ST)

            Case cNovoCFOP == "5557"
                // TRANSFERENCIA USO OU CONSUMO

            Case cNovoCFOP == "5927"
                // BAIXA DE ESTOQUE (Perda, Roubo, etc)

            Case cNovoCFOP == "5602" .Or. cNovoCFOP == "5605"
                // TRANSFERENCIA SALDO CREDOR/DEVEDOR ICMS

            Case cNovoCFOP == "5929" .Or. cNovoCFOP == "6929"
                // LANCAMENTO REFERENTE A ECF

            Case cNovoCFOP == "5904"
                // REMESSA PARA VENDA FORA DO ESTAB.

            Case cNovoCFOP == "5949"
                // OUTRAS SAIDAS (Tratamento Coringa)
                
        EndCase
    EndIf

    // O Retorno da classe sempre devolve o Array com o [1] CFOP e [2] TES corrigidos.
    AAdd(aRetorno, cNovoCFOP)
    AAdd(aRetorno, cNovoTES)

Return aRetorno
