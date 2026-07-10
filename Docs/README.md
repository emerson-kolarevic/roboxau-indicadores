# Indicadores ZiahTrader MA VP -- familia de 3 tiers

> **Tipo:** indicadores standalone para MetaTrader 5.
> **Arquivos:** `MQL5/Indicators/ZiahTrader_MA_VP_M5.mq5` (daytrade, v2.6) +
> `ZiahTrader_MA_VP_M30.mq5` (swing, v1.2) + `ZiahTrader_MA_VP_M1.mq5` (execucao, v1.0).
> (`.ex5` apos compilacao pelo Emerson.)
> **Spec canonica:** `specs/SPEC_MA_VP_3_TIERS.md` (formula, janelas por ativo, defaults, hierarquia).
> **Distribuicao:** opcional, junto com o EA ZiahTrader.

---

## 1. Proposito

Ferramentas de **transparencia visual** para o operador acompanhar no chart MT5
o regime de volatilidade do preco em tres horizontes. Cada indicador plota o
sinal **VP** (`n_sigma` -- retorno da janela normalizado pela volatilidade
composta) + duas EMAs sobre ele (**MA Start** e **MA Ref**) + **VP Livre**
opcional. Calibragem unica universal (sem direcao COMPRA/VENDA desde a v2.3).

| Tier | Arquivo | Chart | Horizonte | Papel |
|---|---|---|---|---|
| DAYTRADE | `ZiahTrader_MA_VP_M5` | M5 | ret 24h / vol diaria (D1) | regime do dia |
| SWING | `ZiahTrader_MA_VP_M30` | M30 | ret 7d / vol semanal (W1) | tendencia principal |
| EXECUCAO | `ZiahTrader_MA_VP_M1` | M1 | ret 1h / vol horaria (H1) | micro-timing |

Hierarquia operacional (visao 2026-07-09): **M30 + M5 ditam o corredor**
(convergencia = tendencia validada); **M1 e o decisor** dentro do corredor,
buscando micro pullbacks operacionais. Detalhe na sec 6 da spec.

---

## 2. Principio P3 -- independencia total do EA

Os indicadores sao **standalone**: zero `#include` do EA, zero variaveis
globais compartilhadas, compilam em qualquer terminal MT5 sem o EA. O EA
implementa internamente o mesmo pipeline (modulos proprios); a relacao e de
**espelhamento matematico**, nao de dependencia. Remover indicador do chart
nao afeta o EA.

---

## 3. O que aparece no chart (identico nos 3, em sub-janela separada)

| Plot | Linha | Cor | Estilo | Significado |
|---|---|---|---|---|
| 0 | VP | cinza (clrSilver) | pontilhada fina | n_sigma instantaneo do tier |
| 1 | MA Start | azul forte (clrDodgerBlue) | continua | EMA curta sobre n_sigma |
| 2 | MA Ref | azul claro (clrAqua) | continua | EMA longa sobre n_sigma |
| 3 | VP Livre | laranja (clrOrange) | tracejada | VP com janela em horas configuravel (opcional) |

Mais **17 OBJ_HLINE de referencia** (-8 a +8 sigma), subwin-aware (2+
instancias coexistem no mesmo chart -- prefixos ZTMAVP_REF_W /
ZTMAVPSW_REF_W / ZTMAVPM1_REF_W). Valor sigma de cada linha via crosshair.

---

## 4. Inputs (8, identicos nos 3) e defaults canonicos

| Input | Default | Descricao |
|---|---|---|
| `InpAtivo` | OURO | flip de janelas por ativo (OURO com gaps / BITCOIN 24-7) |
| `InpPerfil` | AGRESSIVO | lambda/alpha do sigma (CON/MOD/AGR/ULT -- ver spec sec 4) |
| `InpWinsor` | true | apara outliers de gap/spike nos retornos do sigma |
| `InpMA_Start_Period` | M5/M30: **6** ; M1: **4** | EMA curta (0=off) |
| `InpMA_Ref_Period` | M5/M30: **18** ; M1: **10** | EMA longa (0=off) |
| `InpVP_Livre_Hours` | 0 (off) | janela do VP Livre em horas (max 720) |
| `InpVP_Livre_Smooth` | 0 (off) | suavizacao EMA do VP Livre |
| `InpShow_Lines` | true | toggle unico das linhas configuraveis |

Defaults fixados por imagem de referencia (`Indicators/Tela_Parametros_Indicador.png`,
Emerson 2026-07-09). Janelas internas por ativo: ver tabela da spec sec 3
(contagens MEDIDAS pelo terminal via `ZT_DiagContagemCandles`).

---

## 5. Como instalar no MT5

1. Copiar os `.ex5` desejados para `MQL5/Indicators/` do terminal.
2. Atualizar o Navegador (botao direito -> Atualizar) ou reiniciar o MT5.
3. Arrastar cada indicador para o chart do TIMEFRAME correspondente ao seu
   tier (M5 / M30 / M1) -- rodar fora do TF de desenho gera aviso no log e
   cadencia visual incorreta.
4. Ajustar `InpAtivo` conforme o par (OURO p/ XAUUSD; BITCOIN p/ BTCUSD).

**Requisitos de historico:** DAYTRADE: D1 >= ~314 + M5 >= 276. SWING: W1 >=
~22 + M30 >= 230. EXECUCAO: H1 >= ~32 + M1 >= 60. Historico insuficiente =
warmup (plot vazio ate os minimos chegarem).

---

## 6. Relacao com o Portal e com o EA

- **Portal `/resultados`:** mesmo `n_sigma` do backend Python do velocimetro
  ("mesmo indicador, dois ambientes"); Portal = referencia auditavel,
  indicador = leitura em tempo real. Ver `relatorios/RELATORIO_ORIGEM_VP_v2.md`.
- **EA:** implementa o mesmo pipeline internamente (VP daytrade + VP swing).
  Cadencias e amostragem diferem -- **equivalencia visual estrita NAO e
  esperada** (ver `investigacoes/DIVERGENCIA_CADENCIA_EA.md`).

---

## 7. Limitacoes conhecidas

- **Nao funcionam no Strategy Tester** (dependem de `SymbolInfoTick()` live
  para o midprice da vela corrente).
- **Cadencia visual depende do TF do chart** -- rodar cada tier no seu TF.
- **Bootstrap em par novo:** warmup ate os minimos de historico.
- **Tier M1:** sigma_real com ~60 amostras e mais ruidoso que nos irmaos e o
  winsor e quase inerte no lado M1 (aceito por desenho -- spec sec 5).
  Historico M1 do broker limita o alcance do plot (XAU ~3.5 meses; BTC
  poucos dias em 2026-07).
- **Performance:** otimizacoes da v2.1 preservadas (zona quente, shift
  aritmetico, alphas pre-calculados); em chart M1 observar CPU na 1a carga.

---

## 8. Documentacao detalhada

| Documento | Conteudo |
|---|---|
| `specs/SPEC_MA_VP_3_TIERS.md` | **CANONICO** -- formula, janelas medidas, perfis, defaults, hierarquia 3 TFs |
| `specs/SPEC_INDICADOR_MA_VP.md` | [superseded parcial] era v2.3, so M5 pre-flip -- detalhes de buffers/validacao/B1-B6 |
| `relatorios/RELATORIO_ORIGEM_VP_v2.md` | portabilidade do velocimetro Portal -> MQL5 |
| `investigacoes/DIVERGENCIA_CADENCIA_EA.md` | cadencias indicador vs EA |
| `sprints/SPRINT_CRIACAO_INDICADOR.md` | cronologia do desenvolvimento (f02ba42 -> v2.3) |
| `legado/CHANGELOG_LEGADO.md` | remocoes e descontinuacoes historicas |
| `CLAUDE.md` | instrucoes para o Claude Code operar neste repositorio |

---

*Fim do README.md*
