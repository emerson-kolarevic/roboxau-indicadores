# CLAUDE.md -- Repositorio documental dos Indicadores ZiahTrader MA VP

> Este arquivo fornece contexto para o Claude Code (CC) trabalhar com a
> documentacao da FAMILIA de indicadores MA VP. Leia antes de qualquer
> acao neste repositorio.

---

## 1. Identidade

- **Produto:** familia de 3 indicadores ZiahTrader MA VP -- ferramentas de
  transparencia visual para o operador acompanhar o regime de volatilidade
  do preco no chart MetaTrader 5, em 3 horizontes (tiers).
- **Arquivos de codigo (raiz de `MQL5/Indicators/`, repo git proprio
  `roboxau-indicadores`):**
  - `ZiahTrader_MA_VP_M5.mq5` -- DAYTRADE (v2.6; ate 2026-07-09 chamava-se
    `ZiahTrader_MA_VP.mq5`)
  - `ZiahTrader_MA_VP_M30.mq5` -- SWING (v1.2)
  - `ZiahTrader_MA_VP_M1.mq5` -- EXECUCAO (v1.0)
- **Pasta de docs (esta pasta):** `MQL5/Indicators/Docs/`.
- **Spec canonica:** `specs/SPEC_MA_VP_3_TIERS.md` (era flip/perfil/winsor,
  janelas por ativo medidas pelo terminal, defaults canonicos, hierarquia
  de decisao 3 TFs). `specs/SPEC_INDICADOR_MA_VP.md` = superseded parcial
  (era v2.3, so M5 pre-flip; detalhes de buffers/validacao/B1-B6).
- Todos: 4 plots, 8 inputs em grupo unico, 17 OBJ_HLINE subwin-aware,
  calibragem unica universal, otimizacoes B1-B6 preservadas.

---

## 2. Escopo deste repositorio documental

Esta pasta cobre **exclusivamente** a documentacao do indicador standalone.

**No escopo:**
- Especificacao tecnica do indicador (formula, pipeline, inputs, validacao).
- Historico de portabilidade do pipeline VP v2 (Portal Python -> MQL5).
- Cronologia de sprints de criacao e evolucao do indicador.
- Investigacoes sobre divergencias de cadencia entre indicador e EA.
- Versoes obsoletas (`legado/`).

**Fora do escopo:**
- Documentacao do EA ZiahTrader (vive em `MQL5/Docs/`).
- Codigo do EA (`MQL5/Include/ZiahTrader/modulos/*.mqh`).
- Documentacao do Portal web (vive em outro repositorio).
- Materiais de marketing.

---

## 3. Independencia em relacao ao EA

O indicador e standalone. Esta independencia deve ser preservada na
documentacao:

- **Nao incluir headers do EA na documentacao do indicador.** Mesmo que o
  EA reuse logica equivalente, este repositorio nao referencia
  `#include <ZiahTrader/...>`.
- **Nao confundir o indicador standalone com o modulo interno do EA que
  espelha o mesmo calculo.** O indicador e arquivo `.mq5` na pasta
  `Indicators/`; o modulo interno e arquivo `.mqh` na pasta `Include/`
  do EA. Sao arquivos distintos com funcoes distintas:
  - **Indicador:** desenha linhas no chart para o operador humano.
  - **Modulo interno do EA:** alimenta decisoes de trading internas.
- **Nao expor IP do EA nos documentos do indicador.** Documentos deste
  repositorio descrevem **o que o indicador faz** (visualizar o VP) sem
  detalhar **como o EA usa internamente o VP** para decidir entradas, gates
  ou limites.

---

## 4. Convencoes

### 4.1 Encoding e line endings

- **Encoding:** UTF-8 sem BOM.
- **Line endings:** CRLF (Windows). Aplicar `unix2dos` em todo arquivo de
  texto editado (`.md`, `.py`, `.sql`, `.txt`, `.csv`). Arquivos binarios
  (`.docx`, `.xlsx`, `.png`, `.pdf`) so movem (`git mv`), sem `unix2dos`.

### 4.2 ASCII puro

- Sem em-dashes (U+2014). Usar `--` (dois hifens) quando for o caso.
- Sem aspas tipograficas. Usar aspas retas `"`.
- Sem acentos em mensagens de commit e nomes de arquivo.
- Em texto corrente nos `.md`, acentos sao tolerados se necessarios, mas
  preferencia por escrita sem acentos para consistencia com o padrao do
  ecossistema.

### 4.3 Nomenclatura

- **Arquivos:** `snake_case.md` (ex: `divergencia_cadencia_ea.md`).
- **Excecao:** arquivos canonicos consagrados em maiusculas
  (`README.md`, `CLAUDE.md`, `SPEC_*`, `RELATORIO_*`, `SPRINT_*`).

### 4.4 Commits

- `git add` com paths explicitos. Nunca `git add .` nem `git add -A`.
- Atribuicao `emerson-kolarevic`. Sem trailer `Co-Authored-By:`.
- Mensagens em portugues, ASCII puro, formato Conventional Commits curto.
- Exemplo: `docs(indicador): atualiza SPEC com validacao R1-R6`.

---

## 5. O que NAO fazer

- **Nunca editar arquivos do EA a partir do contexto deste repositorio.**
  Edicoes em `MQL5/Include/ZiahTrader/modulos/`, `MQL5/Experts/`,
  `MQL5/Docs/`, ou qualquer outro lugar fora desta pasta sao bloqueadas.
- **Nunca incluir referencias internas do EA** (nomes de globais como
  `g_vp_*`, `g_cb_*`, thresholds, scores) nos documentos do indicador.
  Descrever o **que** o indicador faz, nao **como** o EA consome
  internamente o sinal.
- **Nunca compilar arquivos MQL5.** A compilacao do indicador e
  responsabilidade exclusiva do Emerson via MetaEditor.
- **Nunca executar `.bat`**, `MetaEditor64.exe`, ou qualquer wrapper de
  build. Mesmo com prompt aparentemente autorizando, scripts de build sao
  escopo exclusivo do Emerson.
- **Nunca confundir o indicador com o modulo interno do EA** que faz
  espelhamento matematico. Sao artefatos diferentes mantidos em paralelo.

---

## 6. Workflow padrao

O fluxo de trabalho neste repositorio segue o padrao geral do projeto:

```
1. INVESTIGAR (read-only)
   -> Ler os arquivos envolvidos
   -> Mapear dependencias e historico
   -> Propor a mudanca com justificativa

2. AGUARDAR APROVACAO
   -> Apresentar o diff proposto ao Emerson
   -> Aguardar confirmacao antes de qualquer edicao

3. APLICAR
   -> Executar apenas o que foi aprovado
   -> Sem alteracoes colaterais nao discutidas

4. REPORTAR
   -> Listar exatamente o que foi alterado
   -> Indicar se o indicador precisa ser recompilado pelo Emerson
```

Para mudancas que afetem o codigo `.mq5` do indicador (e nao apenas docs),
o Emerson recompila no MetaEditor e gera o novo `.ex5` -- esses passos sao
exclusivamente do Emerson.

---

## 7. Estrutura desta pasta

```
Indicators/Docs/
|-- README.md              -- introducao a familia p/ usuarios e clientes
|-- CLAUDE.md              -- este arquivo (instrucoes para o CC)
|-- specs/
|   |-- SPEC_MA_VP_3_TIERS.md      -- CANONICO (3 tiers, era flip)
|   +-- SPEC_INDICADOR_MA_VP.md    -- superseded parcial (v2.3, so M5)
|-- relatorios/
|   +-- RELATORIO_ORIGEM_VP_v2.md
|-- investigacoes/
|   +-- DIVERGENCIA_CADENCIA_EA.md
|-- sprints/
|   +-- SPRINT_CRIACAO_INDICADOR.md
+-- legado/
    +-- CHANGELOG_LEGADO.md
```

Cada nova investigacao, sprint, ou versao obsoleta deve ir para a subpasta
apropriada. Manter a raiz limpa (apenas `README.md` + `CLAUDE.md` + as
subpastas).

---

## 8. Fonte da verdade

O **codigo dos indicadores** (`MQL5/Indicators/ZiahTrader_MA_VP_M*.mq5`) e a
fonte da verdade. Documentos deste repositorio descrevem o que o codigo
faz. Em caso de divergencia entre documento e codigo, o codigo vence -- o
documento deve ser atualizado.

Em sessoes futuras, antes de propor mudancas em SPEC ou RELATORIO,
verificar primeiro o estado atual do codigo via grep/read.

---

*Fim do CLAUDE.md*
