# Investigacao -- Divergencia de cadencia entre indicador e EA

> **Tipo:** Investigacao tecnica de referencia (READ-ONLY descritiva).
> **Escopo:** documentar como e por que a cadencia de amostragem do
> `n_sigma` no indicador (chart-driven) difere da cadencia equivalente no
> modulo interno do EA (timer-driven), e o impacto disso sobre a
> equivalencia visual das EMAs.
> **Status:** descritivo; nao prescreve mudanca.

---

## 1. Por que indicador e EA podem divergir visualmente

Indicador e modulo interno do EA implementam **a mesma matematica**
(mesmo `sigma_hist`, `sigma_real`, `sigma_final`, mesma formula EMA com
`alpha = 2/(N+1)`). A divergencia visual entre o que aparece no chart
(indicador) e o que o modulo interno do EA calcula nao vem da formula --
vem de duas dimensoes ortogonais:

### 1.1 Cadencia de amostragem do sinal de entrada (`n_sigma`)

| Ambiente | Frequencia de uma nova amostra de `n_sigma` |
|---|---|
| Indicador no chart M5 | A cada nova barra M5 fechada (5 minutos), mais 1 amostra atualizada na vela corrente a cada 5 minutos (gate `kSampleIntervalSec = 300`) |
| Indicador no chart H1 | A cada nova barra H1 fechada (60 minutos), mais 1 amostra atualizada na vela corrente a cada 5 minutos |
| Indicador no chart M1 | A cada nova barra M1 fechada (1 minuto), mais 1 amostra atualizada na vela corrente a cada 5 minutos |
| Modulo interno do EA | A cada ciclo de OnTimer do EA (alta frequencia interna, governada por gates timer-driven do EA -- escopo do EA, nao do indicador) |

**Implicacao:** as EMAs do indicador "viajam" no eixo X proporcional ao
timeframe do chart. Mudar de M5 para H1 sem alterar o periodo da EMA
expande a janela efetiva da media por um fator de 12.

### 1.2 Defaults dos periodos das EMAs

Indicador (v2.3 atual, calibragem unica universal):

| Conjunto | Default Start | Default Ref |
|---|---|---|
| Unico (sem direcao) | 14 | 0 |

Desde v2.1, todas as MAs Ref operam exclusivamente em modo paralela
sobre `n_sigma` (ver `../legado/CHANGELOG_LEGADO.md` para o historico
da remocao dos slots Suavizada). A partir da v2.3, a separacao
direcional COMPRA/VENDA foi removida -- um unico conjunto de inputs
controla todas as linhas. Defaults anteriores (BUY 20/70 + SELL 30/50)
foram aposentados.

Modulo interno do EA pode usar defaults proprios diferentes,
internalizados em seu codigo de calibragem. **Os dois conjuntos de
defaults sao deliberadamente decididos para cada ambiente** e nao tem
obrigacao de coincidir.

---

## 2. Tabela de janelas efetivas das EMAs do indicador

Sob a hipotese de "1 nova amostra por barra do chart", a janela efetiva
da EMA (definida como o periodo onde concentra-se aproximadamente 86%
do peso, pela formula `2/(N+1)`) e:

| Chart | Periodo EMA = 14 | Periodo EMA = 20 | Periodo EMA = 30 | Periodo EMA = 50 | Periodo EMA = 70 |
|---|---|---|---|---|---|
| M1 (1 min/barra) | 14 min | 20 min | 30 min | 50 min | 70 min |
| M5 (5 min/barra) | 70 min = 1.2h | 100 min = 1.7h | 150 min = 2.5h | 250 min = 4.2h | 350 min = 5.8h |
| M15 (15 min/barra) | 210 min = 3.5h | 300 min = 5h | 450 min = 7.5h | 750 min = 12.5h | 1050 min = 17.5h |
| H1 (60 min/barra) | 14h | 20h | 30h | 50h = 2.1 dias | 70h = 2.9 dias |
| H4 (240 min/barra) | 56h = 2.3 dias | 80h = 3.3 dias | 120h = 5 dias | 200h = 8.3 dias | 280h = 11.7 dias |
| D1 (1440 min/barra) | 14 dias | 20 dias | 30 dias | 50 dias | 70 dias |

**Como ler a tabela:** um operador com `InpMA_Start_Period = 14` em
chart M5 ve uma EMA com janela efetiva de aproximadamente 1.2 horas. O
mesmo input em chart H1 da uma janela de 14 horas. As linhas
visualizadas sao matematicamente diferentes apesar do mesmo periodo
numerico -- o que muda e o sinal amostrado.

---

## 3. Por que isso e by-design e nao bug

A escolha de "1 amostra por barra do chart" foi feita por dois motivos:

1. **Simplicidade visual.** O operador escolhe o chart que quer
   acompanhar (M5 para day trading, H1 para swing leve, etc), e o
   indicador se alinha naturalmente a essa escala temporal. Nao precisa
   conversao mental do tipo "esse Periodo=20 em M5 equivale a Periodo=2
   em H1".

2. **Performance de calculo.** O calculo do pipeline VP v2 e nao-trivial
   (CopyRates D1 + M5, pct_change, winsor, EWMA, std, midprice). Fazer
   um calculo por barra do chart e suficiente para resposta visual fluida
   e evita oscilacoes sub-amostrais.

O modulo interno do EA usa cadencia diferente porque sua finalidade
e diferente (decisao de trading, nao visualizacao), e tem outros
mecanismos de cadencia internamente.

---

## 4. Implicacoes praticas

### 4.1 Equivalencia visual EA <-> indicador NAO e estrita

Mesmo com defaults identicos de periodos, as EMAs do indicador no chart M5
e as EMAs internas equivalentes do EA representam janelas temporais
diferentes -- portanto valores diferentes na mesma janela de mercado.

**Ambos podem estar matematicamente corretos simultaneamente.** A
divergencia visual e propria da diferenca de cadencia de amostragem, nao
de erro de implementacao.

### 4.2 Calibragem dos periodos

A calibragem dos periodos default do indicador (a partir da v2.3:
Start=14, Ref=0, VP_Livre=23h/Smooth=15) foi feita empiricamente pelo
Emerson observando o comportamento das EMAs em janelas conhecidas de
mercado, em chart M5. Defaults anteriores (BUY 20/70 + SELL 30/50, das
versoes v2.0 a v2.2) foram aposentados junto com a separacao
direcional na v2.3. Trocar para chart H1 sem recalibrar produz
visualizacao "esticada" no tempo, possivelmente fora do regime que o
operador esperava.

**Recomendacao operacional:** usar o chart M5 como referencia para
acompanhar o indicador no dia a dia. Outros timeframes podem ser uteis
para perspectiva, mas nao sao a configuracao calibrada.

### 4.3 Validacao cruzada e calibragem oficial

A validacao cruzada estrita entre indicador (em chart fixo) e modulo
interno do EA pode ser feita comparando:

- **Indicador:** valor de `BufVP[rates_total - 1]` (n_sigma da vela
  corrente) em chart M5 vs em chart H1 -- esperado **bater** porque o
  pipeline VP e o mesmo, so muda quando a amostra e atualizada.
- **Indicador vs Portal:** valor visualizado de `BufVP` no chart vs
  valor publicado em `/resultados` na mesma janela -- esperado bater
  dentro de pequena margem (consistente com paridade conceitual
  validada em 2026-04-28).
- **Indicador vs EA:** valores das EMAs do indicador vs valores das EMAs
  internas equivalentes do EA -- esperado **divergir** por cadencia,
  mesmo com periodos identicos.

Calibragem oficial dos periodos default e responsabilidade do Emerson
em sprint dedicada, conforme doutrina geral do projeto.

---

## 5. Resumo executivo

| Pergunta | Resposta curta |
|---|---|
| Indicador e EA usam a mesma matematica? | Sim. Mesmo pipeline VP v2, mesmas constantes nucleares, mesma formula EMA. |
| As EMAs do indicador batem com as do EA? | Nao necessariamente. Cadencias diferentes produzem valores diferentes. |
| Posso usar o indicador para prever decisoes do EA? | Nao. O EA tem ciclo de calculo proprio. O indicador serve para entender o regime, nao para antecipar acoes. |
| Os defaults do indicador funcionam em qualquer timeframe? | Foram calibrados para chart M5. Outros timeframes alteram a escala temporal das EMAs por um fator proporcional ao timeframe. |
| O `n_sigma` do indicador bate com o Portal? | Sim, dentro de pequena margem (paridade conceitual validada). |

---

## 6. Referencias

- Pipeline VP v2 -- detalhes em `../specs/SPEC_INDICADOR_MA_VP.md` sec 2.
- Historico de portabilidade -- `../relatorios/RELATORIO_ORIGEM_VP_v2.md`.
- Cronologia de evolucao do indicador -- `../sprints/SPRINT_CRIACAO_INDICADOR.md`.

---

*Fim do DIVERGENCIA_CADENCIA_EA.md*
