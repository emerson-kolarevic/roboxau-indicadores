# CHANGELOG legado -- Indicador ZiahTrader MA VP

> Registro de simbolos, funcoes, inputs e validacoes descontinuados ao
> longo da evolucao do indicador. Cada entrada catalogada aqui marca
> uma remocao definitiva (nao apenas refator). Conteudo organizado por
> data + versao do indicador.
>
> **Escopo:** indicador standalone (`MQL5/Indicators/ZiahTrader_MA_VP.mq5`).
> Nao cobre o EA nem o Portal.

---

## 2026-05-19 -- v2.3: remocao da separacao COMPRA/VENDA (calibragem unica)

**Evento:** descarte definitivo da distincao direcional COMPRA/VENDA no
indicador. A partir da v2.3, ha um unico conjunto de parametros que
controla todas as linhas configuraveis (MA Start, MA Ref, VP Livre). O
operador interpreta visualmente as linhas conforme o regime observado
no chart, sem familias separadas por direcao.

**Motivacao:** decisao do Emerson em 2026-05-19. As 4 MAs direcionais
(BUY Start/Ref + SELL Start/Ref) e os 2 VP Livre direcionais nunca
representaram informacao diferente entre si -- todas operavam sobre o
mesmo `n_sigma` e o mesmo `sigma_final`. A separacao era um afford
visual herdado da v2.0 (admin-driven do EA), mas no indicador
standalone gerava ruido (10 inputs, 7 plots, dois conjuntos de
variaveis duplicadas) sem beneficio operacional. Limpeza foi
classificada como REFACTOR-SAFE -- nenhum calculo do pipeline VP foi
alterado, apenas a estrutura de inputs/buffers/variaveis foi
colapsada para um fluxo unico.

### Inputs removidos (10 -> 5)

| Input | Default antigo | Grupo |
|---|---|---|
| `InpShow_Buy` | true | COMPRA |
| `InpMA_Buy_Start_Bruta` | 20 | COMPRA |
| `InpMA_Buy_Ref_Bruta` | 70 | COMPRA |
| `InpVP_Short_Buy_Hours` | 0 | COMPRA |
| `InpVP_Short_Buy_Smooth` | 0 | COMPRA |
| `InpShow_Sell` | true | VENDA |
| `InpMA_Sell_Start_Bruta` | 30 | VENDA |
| `InpMA_Sell_Ref_Bruta` | 50 | VENDA |
| `InpVP_Short_Sell_Hours` | 0 | VENDA |
| `InpVP_Short_Sell_Smooth` | 0 | VENDA |

Substituidos por (5 inputs em 1 grupo `=== Calibragem MAs VP ===`):

| Input | Default novo |
|---|---|
| `InpMA_Start_Period` | 14 |
| `InpMA_Ref_Period` | 0 |
| `InpVP_Livre_Hours` | 23 |
| `InpVP_Livre_Smooth` | 15 |
| `InpShow_Lines` | true |

### Buffers/plots removidos (7 -> 4)

| Buffer/plot removido | Cor antiga | Substituido por |
|---|---|---|
| `BufBuyStart` (plot 1, "Buy Start", clrDodgerBlue SOLID) | azul forte | `BufMA_Start` (plot 1, "MA Start", clrDodgerBlue SOLID) |
| `BufBuyRef` (plot 2, "Buy Ref", clrAqua SOLID) | azul claro | `BufMA_Ref` (plot 2, "MA Ref", clrAqua SOLID) |
| `BufSellStart` (plot 3, "Sell Start", clrOrange SOLID) | laranja | (removido) |
| `BufSellRef` (plot 4, "Sell Ref", clrRed SOLID) | vermelho | (removido) |
| `BufVP_Short_Buy` (plot 5, "VP Livre Buy", clrDodgerBlue DASH) | azul tracejado | `BufVP_Livre` (plot 3, "VP Livre", clrOrange DASH) |
| `BufVP_Short_Sell` (plot 6, "VP Livre Sell", clrOrange DASH) | laranja tracejado | (removido) |

Plot 0 (VP, clrSilver DOT) preservado inalterado.

### Variaveis de estado removidas (8 colapsadas para 4)

```
// REMOVIDAS:
int    s_buy_start_bruta_eff;
int    s_buy_ref_bruta_eff;
int    s_sell_start_bruta_eff;
int    s_sell_ref_bruta_eff;
int    s_vp_short_buy_window;
int    s_vp_short_sell_window;
double s_vp_short_buy_alpha;
double s_vp_short_sell_alpha;

// SUBSTITUIDAS POR:
int    s_ma_start_eff;
int    s_ma_ref_eff;
int    s_vp_livre_window;
double s_vp_livre_alpha;
```

### Statics dos ultimos valores (gate 300s) removidos (6 -> 3)

```
// REMOVIDOS:
double s_last_buy_start;
double s_last_buy_ref;
double s_last_sell_start;
double s_last_sell_ref;
double s_last_vp_short_buy;
double s_last_vp_short_sell;

// SUBSTITUIDOS POR:
double s_last_ma_start;
double s_last_ma_ref;
double s_last_vp_livre;
```

`s_last_vp` e `s_last_sample_ts` preservados inalterados.

### Getters removidos (4 -> 2)

| Getter removido | Substituido por |
|---|---|
| `_GetBuyStartPeriod()` | `_GetMAStartPeriod()` |
| `_GetBuyRefPeriod()` | `_GetMARefPeriod()` |
| `_GetSellStartPeriod()` | (removido) |
| `_GetSellRefPeriod()` | (removido) |

### Validacoes -- R4-R6 simplificadas

R4, R5 e R6 preservadas mas reformuladas para uma unica direcao:

- **R4:** valida `InpMA_Start_Period` e `InpMA_Ref_Period` (era valida em
  4 vars direcionais).
- **R5:** valida `Start >= Ref` (paralelas) -- era 2 checks (BUY e SELL).
- **R6:** valida `Start == 0 E Ref == 0` (sem MA ativa) -- era 2 checks
  separados por direcao. Mensagem ajustada: `"R6: nenhum slot MA ativo"`.

### Branches removidos no OnCalculate

- Snapshots `buy_active`, `sell_active`, `vp_buy_active`, `vp_sell_active`
  colapsados em `lines_active` e `vp_livre_active`.
- 4 alphas EMA pre-calculados (`a_bs`, `a_br`, `a_ss`, `a_sr`) reduzidos
  a 2 (`a_s`, `a_r`).
- Blocos VP Livre BUY e VP Livre SELL colapsados em 1 bloco.
- Blocos EMA BUY (Start + Ref) e EMA SELL (Start + Ref) colapsados em 1
  bloco (Start + Ref).
- Re-uso de gate 300s reduzido de 7 statics para 5.

### ShortName

Antes (v2.2): `"ZT_MA_VP v2.2 [BUY X/Y Wh/sN | SELL X/Y Wh/sN]"`.
Depois (v2.3): `"ZT_MA_VP v2.3 [X/Y Wh/sN]"`.

Com defaults: `"ZT_MA_VP v2.3 [14/0 23h/s15]"`.

### Log de boot

Antes (v2.2): `"[ZT_MA_VP] v2.2 | BUY <ON|OFF> Start=X Ref=Y VP_Livre=Wh Smooth=N | SELL <ON|OFF> Start=X Ref=Y VP_Livre=Wh Smooth=N"`.
Depois (v2.3): `"[ZT_MA_VP] v2.3 | <ON|OFF> MA Start=X Ref=Y | VP_Livre=Wh Smooth=N"`.

### Total de linhas alteradas do `.mq5`

`.mq5` reduzido de 1005 linhas (v2.2) para 851 linhas (v2.3) -- diff de
~154 linhas, ~15%. Tamanho do arquivo: 45.004 -> 37.178 bytes.

### Pipeline VP -- ZERO alteracao

Confirmado bit-a-bit:

- `_PctChange`, `_Quantile`, `_Winsor`, `_StdSample`, `_EwmaSigmaVar0`:
  identicas.
- `_GetCurrentPrice` (midprice): identica.
- `_SigmaHistAsOf` (EWMA D1 + cache): identica.
- `_NSigmaAsOfBarra` (sigma_final hibrido + n_sigma + out params): identica.
- Formula EMA (`alpha = 2/(N+1)`, seed em `n_sigma`): identica.
- Formula VP Livre (`(price_now/close[i-w] - 1) / sigma_final` + EMA
  in-place opcional): identica.
- Gate 300s, gate MTF, cache D1, OBJ_HLINE subwin-aware: identicos.
- Otimizacoes B1, B3, B4, B5, B6: preservadas (B4/B5 adaptadas para
  fluxo unico, sem alteracao matematica).
- Constantes `kD1_EWMA_Bars`, `kLambda_EWMA`, `kAlpha_Hibrido`,
  `kWinsor_*`, `kM5_Window_Bars`, `kSampleIntervalSec`: identicas.

### Referencia para auditoria

Implementacao em sub-sprint de 2026-05-19. Aplicacao no terminal de
TESTES (`673D68314B7C44E1DAA423AD5665AC6F`). Detalhes do diff funcional
no `../sprints/SPRINT_CRIACAO_INDICADOR.md` sec 3 e no historico git.

### Reativacao futura (se aplicavel)

Se em algum momento futuro a separacao direcional COMPRA/VENDA for
revisitada, o desenho devera ser refeito do zero (nao havera codigo
dormente para reativar). Defaults antigos (BUY 20/70 + SELL 30/50) e
todos os identificadores direcionais foram removidos definitivamente.

---

## 2026-05-19 -- v2.1: remocao das MAs VP Suavizadas (cadeia)

**Evento:** descarte definitivo do modo cadeia/suavizada das MAs Ref.
A partir da v2.1, todas as 4 MAs (BUY Start, BUY Ref, SELL Start,
SELL Ref) operam exclusivamente em modo paralela sobre `n_sigma`.

**Motivacao:** decisao do Emerson em 2026-05-18 (SPEC_V5 sec 12). O
modo cadeia existia desde a v2.0 mas nunca foi ativado em producao --
os 4 slots `*_Suavizada` tinham default 0 e a validacao R1 forcava
zero permanentemente no slot Start.Suavizada. Manter codigo dormente
gerava ruido (validacoes R1/R2/R3 + branches no OnCalculate + getters
de modo) sem beneficio concreto. Limpeza foi classificada como
REFACTOR-SAFE -- nenhum comportamento mudou, apenas remocao de codigo
inerte.

### Inputs removidos (4)

| Input | Default antigo | Grupo |
|---|---|---|
| `InpMA_Buy_Start_Suavizada` | 0 | COMPRA |
| `InpMA_Buy_Ref_Suavizada` | 0 | COMPRA |
| `InpMA_Sell_Start_Suavizada` | 0 | VENDA |
| `InpMA_Sell_Ref_Suavizada` | 0 | VENDA |

Total de inputs do indicador: 10 -> 6.

### Variaveis de estado removidas (4)

```
int s_buy_start_suav_eff;
int s_buy_ref_suav_eff;
int s_sell_start_suav_eff;
int s_sell_ref_suav_eff;
```

### Validacoes removidas (R1, R2, R3)

| Regra removida | O que validava |
|---|---|
| **R1** | Forcava `Start.Suavizada` a 0 (slot reservado) -- agora nao existe mais slot. |
| **R2** | Em Ref, conflito `Bruta > 0` E `Suavizada > 0` -- agora nao ha mais opcao Suavizada. |
| **R3** | `Ref.Suavizada > 0` sem `Start.Bruta > 0` na mesma direcao (cadeia sem insumo) -- idem. |

Validacoes preservadas: R4 (periodo `< 2`), R5 (`Start.Bruta >=
Ref.Bruta`), R6 (direcao toda zerada).

### Funcoes removidas (2)

| Funcao | O que retornava |
|---|---|
| `_IsBuyRefSuavizada()` | `bool` -- true se Ref.Suavizada estava ativo na direcao BUY. |
| `_IsSellRefSuavizada()` | `bool` -- analogo para SELL. |

Getters `_GetBuyRefPeriod` e `_GetSellRefPeriod` foram simplificados
para retornar diretamente `s_*_ref_bruta_eff` (removido o fallback
condicional que checava o slot Suavizada).

### Branches removidos no OnCalculate

- Snapshot `const bool buy_chain = _IsBuyRefSuavizada()` -- removido.
- Snapshot `const bool sell_chain = _IsSellRefSuavizada()` -- removido.
- Bloco da BUY Ref: ternario `const double input_val = buy_chain ?
  BufBuyStart[i] : n_sigma;` -- substituido por uso direto de
  `n_sigma`.
- Bloco da SELL Ref: ternario analogo -- substituido por uso direto
  de `n_sigma`.

### ShortName

Antes (v2.0): `"ZT_MA_VP v2.0 [BUY 20/70s | SELL 30/50]"` (o sufixo
`s` indicava Ref.Suavizada ativo). Depois (v2.1): `"ZT_MA_VP v2.1
[BUY 20/70 | SELL 30/50]"` (sem flag de modo).

### Total de linhas removidas do `.mq5`

Aproximadamente 50 linhas (de 874 para ~820). Detalhes em
`../sprints/SPRINT_CRIACAO_INDICADOR.md` sec 3 (linha do tempo) +
historico git.

### Referencia para auditoria

Decisao do Emerson registrada em SPEC_V5 sec 12 (documento de planejamento
interno da v2.1). Implementacao em sub-sprint de 2026-05-19. Memoria
persistente do projeto: `feedback_indicador_ma_vp_visual.md` cobre a
decisao paralela (manter OBJ_HLINE em vez de indicator_level) e a
ausencia de labels visuais nas HLINEs.

### Reativacao futura (se aplicavel)

Se em algum momento futuro a feature de cadeia for revisitada, o
desenho devera ser refeito do zero -- nao havera codigo dormente para
"ligar de volta". O slot Suavizada nao existe mais como afford.

---

*Fim do CHANGELOG_LEGADO.md*
