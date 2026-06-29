# Relatorio -- Origem do pipeline VP v2 portado para o indicador

> **Tipo:** Relatorio historico (referencia complementar).
> **Escopo:** explicar de onde vem o pipeline `n_sigma` que o indicador
> calcula, registrar decisoes canonicas adotadas na portabilidade do
> velocimetro Python (Portal Ziah Trader) para MQL5 nativo.
> **Data de referencia:** 2026-04-28 (sessao de portabilidade VP Portal -> EA).
> **Status:** estavel; relatorio descritivo, nao normativo.

---

## 1. Contexto

O **velocimetro de volatilidade do Ziah Trader** nasceu como um servico
Python rodando em backend, alimentando o portal web `ziahtrader.com` na
pagina `/resultados`. O servico calcula um z-score `n_sigma` que representa
o regime de volatilidade do ouro em escala de 24 horas.

Originalmente o EA ZiahTrader tinha **seu proprio calculo legacy** de
volatilidade, com formula divergente da do Portal. Em abril de 2026, uma
investigacao identificou que essa divergencia produzia leituras
inconsistentes entre o que o Portal exibia publicamente e o que o EA
usava internamente, e a decisao foi **portar o pipeline do Portal para o
EA em MQL5 nativo** -- mantendo paridade conceitual entre os dois
ambientes.

Como o indicador standalone tambem precisa exibir o mesmo `n_sigma` no
chart do operador, o pipeline portado foi adotado igualmente pelo
indicador. Resultado: tres implementacoes do mesmo pipeline, em tres
ambientes:

| Ambiente | Implementacao | Proposito |
|---|---|---|
| Portal Ziah Trader | Python (pandas + numpy) | Exibicao publica em `/resultados` |
| EA ZiahTrader | MQL5 (modulo interno) | Decisoes internas de trading |
| Indicador MA VP | MQL5 (standalone) | Visualizacao no chart do operador |

**Filosofia operacional:** "mesmo indicador, tres ambientes". Divergencia
empirica significativa entre as tres implementacoes seria bug; pequena
margem numerica e tolerada como propria das diferencas de cadencia e
plataforma.

---

## 2. Causa-raiz da divergencia original (EA legacy vs Portal)

A investigacao de 2026-04-28 identificou que a divergencia entre o calculo
legacy do EA e o calculo do Portal era explicavel por **duas divergencias
materiais que apontavam no mesmo sentido**:

1. **EA legacy nao winsorizava retornos D1** antes da EWMA. Gaps diarios
   (pausa de aproximadamente 1 hora) e gap de fim de semana de XAU
   geravam log-retornos "fantasma" cujo quadrado era incorporado
   integralmente a EWMA, **inflacionando `sigma_hist`** artificialmente.
   Portal corrige isso aplicando `aplicar_winsor()` antes da EWMA.

2. **EA legacy usava `sigma_final = sigma_hist` puro**; Portal usa
   `sigma_final = alpha * sigma_hist + (1 - alpha) * sigma_real`
   (combinacao hibrida). Em mercado onde `sigma_real` recente esta calmo
   apos periodo historico volatil, o termo `(1 - alpha) * sigma_real`
   puxa o `sigma_final` hibrido para baixo, fazendo `|n_sigma| do Portal`
   ainda maior em relacao ao do EA legacy.

Outras divergencias menores (log-ret vs pct_change, tick `last` vs midprice,
inicializacao EWMA com `var_0 = r_0^2` vs `var_0 = 0`, anualizacao de
`sigma_real`) foram identificadas e tratadas durante a portabilidade.

---

## 3. Decisoes canonicas adotadas na portabilidade

Estas decisoes foram tomadas pelo Emerson na sessao 2026-04-28 (e ajustes
subsequentes nas sub-sprints SS1-SS5) e estao **codificadas tanto no
modulo interno do EA quanto no indicador standalone**. Permanecem como
referencia canonica para qualquer reimplementacao futura.

### 3.1 D1 = 260 barras (1 ano util global)

- **Razao:** ouro pausa fim de semana. 260 barras D1 cobrem aproximadamente
  1 ano util global.
- **Portal usa 366 (sera corrigido em sessao futura).**
- **Indicador:** o codigo atual usa `kD1_EWMA_Bars = 420` como buffer
  copiado, com `VP_NMIN_D1 = 30` como minimo para EWMA valida. O calculo
  da EWMA opera sobre todo o buffer disponivel, com fairness garantida
  pelo lambda 0.92 (peso da cauda decai rapidamente). A janela efetiva de
  uso e governada pelos parametros do EWMA, nao por trimming explicito.

### 3.2 M5 = 276 barras (23 horas efetivas)

- **Razao:** ouro pausa aproximadamente 1 hora por dia. 276 barras M5
  cobrem 23 horas efetivas.
- **Portal usa 288 (bug latente: captura barra de baixissima atividade na
  pausa; sera corrigido em sessao futura).**
- **Indicador:** o codigo atual usa `kM5_Window_Bars = 288` para
  consistencia com Portal hoje. Quando o Portal for corrigido para 276,
  a paridade fica perfeita sem nova mudanca no indicador (mesma janela
  conceitual).

### 3.3 `sigma_real` SEM anualizacao

- **Razao:** Portal calcula `sigma_real = float(ret_5m_w.std())` sem
  multiplicar por `sqrt(N)`. O nome `_24h` no Portal e apenas convencao;
  o valor e literalmente o std de retornos M5 winsorizados em escala
  5-min.
- **Combinacao hibrida intencionalmente mistura escalas (D1 + 5-min).**
  Multiplicar `sigma_real` por `sqrt(N)` para "alinhar a escala D1"
  seria matematicamente "mais correto" mas quebraria a paridade conceitual
  com Portal.
- **Indicador:** implementa `_StdSample` direto sobre retornos M5
  winsorizados, sem anualizacao. Confere com Portal.

### 3.4 Inicializacao EWMA com `var_0 = 0`

- **Razao:** Portal descartou conscientemente o padrao legado NIX
  (`var_0 = r_0^2`) em favor de `var_0 = 0`. Apos algumas dezenas de
  barras com decay 0.92, o peso da inicializacao decai a aproximadamente
  1%. Diferenca e detectavel nos primeiros ciclos pos-reset mas converge
  rapido.
- **Indicador:** implementa `_EwmaSigmaVar0` com `var = 0.0` inicial.

### 3.5 Winsor com quantis (0.005, 0.995)

- **Razao:** quantis 0.5%/99.5% correspondem ao perfil "agressivo" do
  Portal. Sao os mesmos quantis usados na producao do velocimetro.
- **Indicador:** implementa `_Winsor` com `kWinsor_Lower = 0.005` e
  `kWinsor_Upper = 0.995`.

### 3.6 Alpha = 0.55

- **Razao:** peso do `sigma_hist` na combinacao hibrida no perfil
  "agressivo" do Portal. Os outros perfis usam alpha = 0.70 (moderado) e
  alpha = 0.80 (conservador). A escolha do perfil agressivo reflete o
  dimensionamento do produto.
- **Indicador:** `kAlpha_Hibrido = 0.55`.

### 3.7 Lambda = 0.92

- **Razao:** lambda do EWMA RiskMetrics no perfil "agressivo" do Portal.
  Os outros perfis usam lambda = 0.94 (moderado) e lambda = 0.96
  (conservador).
- **Indicador:** `kLambda_EWMA = 0.92`.

### 3.8 Sem clamp em `n_sigma_raw`

- **Razao:** clamp era visual no Portal, aplicado separadamente em
  `supabase_writer.py` antes de exportar para a interface (`+/- 4` com
  arredondamento de 3 casas). O calculo nuclear nao clampa.
- **Indicador:** retorna `n_sigma` sem clamp. Valor pode ultrapassar
  +/- 8 em eventos extremos, embora as 17 linhas de referencia cobrem
  esse range tipico para leitura visual.

### 3.9 Midprice para tick em tempo real

- **Razao:** Portal usa `(tick.bid + tick.ask) / 2.0` como tick price em
  tempo real (com fallback para `tick.last`). EA legacy usava
  `tick.last -> tick.bid -> tick.ask` (precedencia diferente).
- **Indicador:** implementa `_GetCurrentPrice` com `(bid + ask) / 2.0`
  como prioridade, fallback para `last`, depois `bid`, depois `ask`,
  depois close da vela como ultimo recurso.

---

## 4. Validacao empirica da paridade

Em 2026-04-28 noite, apos aplicacao das 9 decisoes acima no modulo
interno do EA, a paridade foi validada empiricamente:

- Portal `/resultados` em janela de mercado: zona **"Tendencia descendente"**
  (`|n_sigma| > 2`).
- EA com pipeline portado: `n_sigma = -2.438` na mesma janela.

Razao teorica entre `sigma_final` esperado: aproximadamente 1.74x (calculo
detalhado pre-portabilidade).
Razao empirica observada: aproximadamente 1.73x. **Match dentro de 0.6%.**

Indicador standalone replica a mesma matematica que o modulo interno do
EA, herdando a mesma paridade com o Portal.

---

## 5. Referencias para auditoria

| Fonte | Local | Tipo |
|---|---|---|
| Pipeline original (Python) | `velocimetro_core.py` no repositorio do Portal | Codigo |
| Schema canonico do snapshot publicado | `velocimetro_snapshot` (tabela Supabase) | Schema |
| Exportador para Supabase | `supabase_writer.py` no repositorio do Portal | Codigo |
| Indicador standalone | `MQL5/Indicators/ZiahTrader_MA_VP.mq5` | Codigo |
| Modulo interno do EA (mirror matematico) | repositorio MQL5 (modulo interno, fora do escopo desta documentacao) | Codigo |

A descricao acima deve permitir reproduzir o calculo em qualquer linguagem
sem ambiguidade. Em caso de divergencia entre este relatorio e o codigo
do indicador, o codigo vence -- este documento deve ser atualizado.

---

## 6. Limites desta documentacao

Este relatorio cobre **a origem matematica do pipeline VP v2 e as
decisoes canonicas de portabilidade**. NAO cobre:

- Como o EA usa internamente o `n_sigma` para tomar decisoes de trading
  (gates, scores, mecanismos defensivos). Isso e escopo da documentacao
  do EA, mantida em outro repositorio.
- Como o Portal Ziah Trader exibe o `n_sigma` na interface, classificacao
  de zonas no portal, ou outros aspectos do servico Python. Isso e
  escopo da documentacao do Portal.
- Versoes anteriores do pipeline legacy (`20_volatilidade_preco.mqh`).
  Aposentado em sub-sprint posterior pelo EA; nao tem equivalente no
  indicador standalone.

---

*Fim do RELATORIO_ORIGEM_VP_v2.md*
