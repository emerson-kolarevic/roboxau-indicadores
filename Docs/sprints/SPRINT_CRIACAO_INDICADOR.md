# Sprint -- Criacao e evolucao do Indicador ZiahTrader MA VP

> **Tipo:** Cronologia de desenvolvimento (registro historico).
> **Escopo:** versao inicial v1.x, transicao para v2.0 admin-driven,
> commits chave e decisoes de design relevantes ao indicador standalone.

---

## 1. Versao inicial (commit f02ba42)

Em sessao de portabilidade do pipeline VP v2 do Portal Ziah Trader para
MQL5 nativo (sessao 2026-04-28 noite), foi criado o indicador
standalone `ZiahTrader_MA_VP.mq5` com o objetivo de **dar transparencia
visual ao operador** sobre o regime de volatilidade que o EA passaria a
consumir internamente.

### 1.1 Caracteristicas da versao inicial

- 2 EMAs sobre `n_sigma` (Fast e Slow).
- Inputs simples: `InpMA_Fast_Period` e `InpMA_Slow_Period`.
- Defaults: Fast = 10, Slow = 50 (calibrados para chart M5).
- Pipeline VP v2 portado fielmente (mesma matematica do Portal,
  validada com paridade conceitual dentro de pequena margem).
- Cache D1 por chave de dia.
- Cache M5 por chave (substituido por gate temporal em versoes
  posteriores).

### 1.2 Funcao na arquitetura

- Ferramenta opcional de monitoramento humano em tempo real.
- Distribuido junto com o EA mas sem dependencia operacional -- o EA
  funciona com ou sem o indicador instalado.
- Espelho matematico (paralelo, nao integrado) do calculo equivalente
  internalizado no EA.

### 1.3 Documentos relevantes desta fase

A criacao inicial do indicador foi documentada dentro dos relatorios da
sessao 2026-04-28 (sub-sprints SS1 a SS5 da portabilidade VP Portal -> EA).
Esses relatorios vivem no repositorio do EA e cobrem o contexto do
pipeline VP v2 em si; a separacao formal da documentacao do indicador
em repositorio proprio (esta pasta `Indicators/Docs/`) so foi feita em
sessao posterior (2026-05-16).

---

## 2. Evolucao para v2.0 admin-driven (sessao 2026-05-11)

Apos consolidacao do EA em arquitetura de 3 camadas (Camada 1 = gates de
entrada, Camada 2 = gestao de basket ativo, Camada 3 = observabilidade),
o EA ganhou um mecanismo interno admin-driven para calibragem dinamica
das EMAs de start e referencia (modulo equivalente a `28_admin_ma_calibragem`
no codigo do EA -- escopo do EA, nao deste repositorio).

Para manter o **principio de paridade visual** ("o operador deve ver no
chart o que o EA enxerga internamente"), o indicador standalone foi
reescrito como **v2.0 admin-driven**, espelhando o esquema de inputs
admin-driven do EA.

### 2.1 Mudancas estruturais vs v1.x

| Aspecto | v1.x (inicial) | v2.0 (atual) |
|---|---|---|
| Numero de EMAs | 2 (Fast + Slow) | 4 (BUY Start + BUY Ref + SELL Start + SELL Ref) |
| Inputs | 2 inputs simples | 10 inputs (2 toggles + 8 calibragem) |
| Validacao | nenhuma | R1-R6 (espelha o modulo admin-driven do EA) |
| Defaults | Fast = 10, Slow = 50 | BUY 20/70 + SELL 30/50 |
| Cores | 2 cores | 4 cores (BUY azulado + SELL avermelhado) |
| Linhas de referencia | nenhuma | 17 OBJ_HLINE (-8 a +8 sigma, sempre ativas) |
| Toggles | nenhum | InpShow_Buy, InpShow_Sell |
| Inputs tecnicos | expostos | internalizados como `const` (kD1, kLambda, kAlpha, etc) |
| Buffers de plot | 7 (incluindo Delta Raw, Delta Smooth, thresholds) | 5 (VP + 4 EMAs) |
| Cache M5 | sim (raiz de divergencia conhecida) | removido (substituido por gate 300s) |
| Cores Bullish/Bearish | misturadas | BUY azulado, SELL avermelhado (separacao visual clara) |
| PRICE NOW na vela corrente | close M5 | midprice live via SymbolInfoTick |
| Gate temporal | nenhum | 300s na vela corrente |

### 2.2 Bugs corrigidos na v2.0

Documentados no proprio cabecalho do codigo do indicador
(`ZiahTrader_MA_VP.mq5` linhas 4 a 35):

- **Bug 4.1 -- Gate MTF zerava buffers em retentativa.** Quando o
  historico D1 ou M5 era insuficiente, a versao anterior retornava `0`
  no `OnCalculate`, o que zerava todos os buffers. Substituido por
  `return prev_calculated` para preservar o que ja foi desenhado.
- **Bug 4.2 -- Linhas somem ao mudar calibragem.** Em
  `REASON_PARAMETERS` / `RECOMPILE` / `CHARTCHANGE`, os statics dos
  ultimos valores ficavam stale e nao havia full recalc forcado. Agora
  `UninitializeReason()` e detectado em `OnInit`, statics sao zeradas e
  flag `s_need_full_reset` forca full recalc no proximo `OnCalculate`.

### 2.3 Decisoes de design na v2.0

- **OBJ_HLINE em vez de `#property indicator_level`:** evita
  compressao do auto-scale do eixo Y em timeframes maiores.
- **OnDeinit so deleta OBJ_HLINE em REMOVE/PROGRAM/CLOSE:** em
  `PARAMETERS` / `RECOMPILE` / `CHARTCHANGE` os objetos sao preservados
  e reaproveitados via `ObjectFind`, evitando piscadelas visuais.
- **Cache D1 PRESERVADO:** nao causa divergencia (chave por dia, EWMA
  D1 estavel intra-dia). Cache M5 REMOVIDO porque a chave por M5
  causava divergencia conhecida com o Portal.
- **Slots `Start.Suavizada` reservados:** validacao R1 forca a 0;
  reservado para versoes futuras se houver necessidade de mais nivel de
  suavizacao na cadeia.

---

## 3. Linha do tempo resumida

| Data aproximada | Evento |
|---|---|
| 2026-04-28 noite | Criacao inicial do indicador (commit `f02ba42`); 2 EMAs simples, pipeline VP v2 portado |
| 2026-04-29 a 2026-05-10 | Evolucao do EA em torno do pipeline VP v2 (Camada 1 do produto, mecanismos internos de gates e calibragem) |
| 2026-05-11 | Rewrite do indicador para v2.0 (admin-driven, 4 EMAs, 10 inputs, validacao R1-R6, 17 OBJ_HLINE) |
| 2026-05-16 | Separacao formal da documentacao do indicador para repositorio proprio (`Indicators/Docs/`) |
| 2026-05-19 | v2.1 entregue: remocao definitiva das MAs VP Suavizadas (10 -> 6 inputs, R1/R2/R3 removidas), otimizacoes de performance B1-B6 (mata o full recalc reciclico que degradava a CPU em v2.0), fix de OBJ_HLINE multi-instancia (prefixo subwin-aware permitindo BUY e SELL no mesmo chart sem colisao), descarte de labels visuais nas HLINEs (operador usa crosshair). Ver `../legado/CHANGELOG_LEGADO.md` para detalhes das remocoes. |
| 2026-05-19 | v2.2 entregue: adicao de 2 linhas opcionais de VP Livre (janela em horas configuravel, cap 720, suavizacao EMA opcional in-place). 6 -> 10 inputs (4 inputs novos `InpVP_Short_*_Hours/_Smooth` por direcao). Pipeline VP intocado -- VP Livre reusa `sigma_final` e `price_now` via out params adicionados em `_NSigmaAsOfBarra`. Assume chart M5 (formula `horas * 12` para derivar janela em candles M5). |
| 2026-05-19 | v2.3 entregue: unificacao da calibragem (remove distincao COMPRA/VENDA). 10 -> 5 inputs em 1 grupo unico (`=== Calibragem MAs VP ===`), 7 -> 4 buffers/plots, 2 toggles -> 1 (`InpShow_Lines`), variaveis e statics direcionais colapsadas (`s_buy_*`/`s_sell_*` -> `s_ma_*`; `s_last_buy_*`/`s_last_sell_*`/`s_last_vp_short_*` -> `s_last_ma_*`/`s_last_vp_livre`). R6 simplificada (uma direcao apenas). Defaults novos: Start=14, Ref=0, VP_Livre=23h/Smooth=15. Pipeline VP, formulas EMA, gate 300s, OBJ_HLINE e otimizacoes B1-B6 preservados bit-a-bit. Ver `../legado/CHANGELOG_LEGADO.md`. |

Commits especificos dos passos de v2.0/v2.1/v2.2/v2.3 estao registrados no
historico git do repositorio MQL5 e na documentacao consolidada do EA --
nao duplicados aqui.

---

## 4. Sub-sprints futuras (registro)

### 4.1 Calibragem oficial dos defaults

Os defaults atuais (Start=14, Ref=0, VP_Livre=23h/Smooth=15) foram
estabelecidos pelo Emerson na v2.3 durante a unificacao da calibragem,
sob observacao empirica em chart M5. Defaults anteriores (BUY 20/70 +
SELL 30/50) foram aposentados junto com a separacao direcional.
Calibragem oficial contra ground truth (janelas conhecidas de mercado,
casos canonicos) e responsabilidade de sprint dedicada e fica sob
doutrina geral de calibragem do projeto.

### 4.2 Slots `Start.Suavizada` -- DESCARTADO DEFINITIVAMENTE em v2.1

**Status:** encerrado em 2026-05-19. Decisao do Emerson de 2026-05-18:
MAs VP nao usarao cadeia (suavizada) no roadmap previsivel; apenas
paralelas. Slots foram removidos do codigo e da SPEC. Ver
`../legado/CHANGELOG_LEGADO.md` para a lista completa de simbolos,
funcoes e validacoes removidas.

Se em algum momento futuro a feature for revisitada, o desenho devera
ser refeito do zero (nao havera codigo dormente para reativar).

### 4.3 Indicadores derivados

Possiveis indicadores adicionais que poderiam ser construidos a partir
do mesmo pipeline VP v2 (delta entre Start e Ref, score normalizado
0..100, etc) ficam fora do escopo do indicador MA VP atual. Cada
indicador novo deveria ser arquivo separado em `MQL5/Indicators/`,
mantendo standalone.

---

## 5. Referencias para auditoria

- Codigo do indicador: `MQL5/Indicators/ZiahTrader_MA_VP.mq5`
- Especificacao tecnica: `../specs/SPEC_INDICADOR_MA_VP.md`
- Origem do pipeline VP v2: `../relatorios/RELATORIO_ORIGEM_VP_v2.md`
- Divergencia de cadencia indicador vs EA: `../investigacoes/DIVERGENCIA_CADENCIA_EA.md`

Sessoes de desenvolvimento detalhadas (sub-sprints SS1-SS5 do VP Portal,
Camada 1, modulo 27, modulo 28) sao mantidas na documentacao do EA --
fora do escopo deste repositorio.

---

*Fim do SPRINT_CRIACAO_INDICADOR.md*
