# Indicador ZiahTrader MA VP

> **Tipo:** Indicador standalone para MetaTrader 5.
> **Arquivo:** `MQL5/Indicators/ZiahTrader_MA_VP.mq5` (`.ex5` apos compilacao).
> **Versao atual:** v2.3 (calibragem unica universal -- MA Start + MA Ref paralelas + VP Livre opcional, 4 plots, 17 niveis de referencia, otimizacoes B1-B6 preservadas).
> **Distribuicao:** opcional, junto com o EA ZiahTrader.

---

## 1. Proposito

O Indicador ZiahTrader MA VP e uma ferramenta de **transparencia visual** para
o operador acompanhar no chart MT5 o regime de volatilidade do preco do par
operado. Exibe duas medias moveis exponenciais (EMAs) -- **MA Start** e **MA
Ref** -- calculadas sobre o sinal **VP** (`n_sigma`, retorno de 24 horas
normalizado pela volatilidade composta), mais uma linha opcional de **VP
Livre** com janela em horas configuravel pelo operador. A calibragem e
universal: a partir da v2.3 o indicador opera sem distincao entre direcao
de compra e direcao de venda -- ha um unico conjunto de parametros e o
operador interpreta visualmente as linhas conforme o regime observado.

---

## 2. Principio P3 -- independencia total do EA

O indicador e **standalone**:

- Zero `#include` de cabecalhos do EA.
- Zero dependencia de variaveis globais do EA.
- Pode ser compilado e instalado em qualquer terminal MT5, mesmo sem o EA
  presente.
- O **EA NAO depende do indicador** -- o EA implementa seu proprio calculo
  interno equivalente. Remover o indicador do chart nao afeta o EA.

A relacao entre EA e indicador e de **espelhamento matematico**: ambos
implementam o mesmo pipeline VP v2 portado do velocimetro do Portal Ziah
Trader, mas em ambientes independentes.

---

## 3. O que aparece no chart

O indicador abre uma **sub-janela separada** (separate window) abaixo do
chart principal, com:

| Plot | Linha | Cor | Estilo | Significado |
|---|---|---|---|---|
| 0 | VP | cinza (clrSilver) | pontilhada fina | n_sigma instantaneo (volatilidade composta normalizada) |
| 1 | MA Start | azul forte (clrDodgerBlue) | continua | EMA Start (paralela sobre n_sigma) |
| 2 | MA Ref | azul claro (clrAqua) | continua | EMA Ref (paralela sobre n_sigma) |
| 3 | VP Livre | laranja (clrOrange) | tracejada | VP com janela em horas configuravel (opcional) |

Alem dos 4 plots, sao desenhadas **17 linhas horizontais de referencia**
(niveis -8 a +8 sigma) como objetos `OBJ_HLINE`, sempre ativas, em cinza
pontilhado fino. Servem de escala visual para leitura do regime. Cada
instancia do indicador no chart usa um conjunto unico de HLINEs por
sub-janela (nomes subwin-aware), permitindo duas instancias coexistindo
sem colisao visual.

O operador liga/desliga as 3 linhas configuraveis em conjunto via toggle
unico `InpShow_Lines`. Plot 0 (VP) e sempre visivel quando o indicador
esta carregado.

Para ler o valor sigma de uma HLINE especifica, usar o crosshair do MT5
(passar o mouse sobre a linha). Labels visuais dentro do plot foram
descartados na v2.1 para nao poluir a area de plotagem.

---

## 4. Formula resumida

O indicador calcula, a cada nova amostra valida do VP:

```
n_sigma  =  ret_24h / sigma_final
EMA[t]   =  alpha * n_sigma[t] + (1 - alpha) * EMA[t-1]    com alpha = 2 / (N + 1)
```

Onde:

- `ret_24h` -- retorno do preco nos ultimos 23-24 horas (janela de 288 barras M5)
- `sigma_final` -- volatilidade composta hibrida: combinacao do componente
  historico (`sigma_hist`, EWMA D1 sobre retornos winsorizados, com lambda=0.92)
  e do componente recente (`sigma_real`, std amostral M5 sobre retornos
  winsorizados)
- `N` -- periodo da EMA (input do usuario, valor inteiro >= 2)

Detalhes do pipeline VP v2 em `specs/SPEC_INDICADOR_MA_VP.md`. Origem do
pipeline e historico de portabilidade em `relatorios/RELATORIO_ORIGEM_VP_v2.md`.

---

## 5. Inputs (5 totais, 1 grupo unico)

### 5.1 Grupo `=== Calibragem MAs VP ===`

| Input | Tipo | Default | Descricao |
|---|---|---|---|
| `InpMA_Start_Period` | int | 14 | Periodo da MA Start (0 desativa) |
| `InpMA_Ref_Period` | int | 0 | Periodo da MA Referencia (0 desativa) |
| `InpVP_Livre_Hours` | int | 23 | VP Livre: janela em horas (0=off, max=720) |
| `InpVP_Livre_Smooth` | int | 15 | VP Livre: suavizacao EMA (0=off, >0=periodo EMA in-place) |
| `InpShow_Lines` | bool | true | Exibir linhas (toggle unico para MA Start, MA Ref e VP Livre) |

### 5.2 Modo das MAs

Ambas as MAs (Start e Ref) operam em **modo paralela**: a EMA Ref e
calculada diretamente sobre `n_sigma`, em paralelo com a EMA Start. As
duas "competem" sobre o mesmo sinal.

A v2.0 mantinha slots reservados para um modo alternativo (cadeia /
suavizada, em que a Ref consumia a saida ja suavizada da Start). Esses
slots foram removidos definitivamente em v2.1 e a separacao direcional
COMPRA/VENDA foi colapsada em v2.3 para uma calibragem unica. Detalhes
em `legado/CHANGELOG_LEGADO.md`.

---

## 6. Como instalar no MT5

1. Copiar `ZiahTrader_MA_VP.ex5` para a pasta `MQL5/Indicators/` do seu
   terminal MetaTrader 5.
2. Reiniciar o MetaTrader 5 ou clicar com o botao direito em
   **"Navegador" -> Indicadores** e selecionar **"Atualizar"**.
3. Arrastar `ZiahTrader_MA_VP` do navegador para o chart do par desejado
   (XAUUSD ou outro).
4. Na janela de inputs, ajustar:
   - `InpShow_Lines` (toggle unico para MA Start, MA Ref e VP Livre).
   - Periodos das EMAs e janela do VP Livre (defaults sao calibrados
     para XAUUSD em chart M5; outros pares ou timeframes podem exigir
     ajuste empirico).
5. Confirmar. O indicador abre uma sub-janela abaixo do chart com ate
   4 linhas (VP + MA Start + MA Ref + VP Livre) + 17 niveis de
   referencia.

**Requisitos:** MetaTrader 5 com simbolo selecionado e acesso a historico
**D1** (minimo 420 barras) e **M5** (minimo 288 barras). Em par com historico
insuficiente, o indicador entra em estado de warmup ate dados suficientes
estarem disponiveis.

---

## 7. Relacao com o Portal `/resultados`

A pagina `/resultados` do portal Ziah Trader (`ziahtrader.com`) publica o
mesmo `n_sigma` calculado pelo backend Python do velocimetro. O indicador
implementa o mesmo pipeline em MQL5 nativo, com tolerancia de paridade
conceitual dentro de pequena margem numerica.

**Filosofia operacional:** "mesmo indicador, dois ambientes". O Portal e a
referencia auditavel; o indicador no chart e a leitura em tempo real para o
operador. Detalhes em `relatorios/RELATORIO_ORIGEM_VP_v2.md`.

---

## 8. Relacao com o EA ZiahTrader

O EA implementa internamente o mesmo pipeline VP v2 (mesma matematica, mesmas
constantes nucleares -- lambda=0.92, alpha=0.55, winsor 0.005/0.995). A
diferenca entre EA e indicador esta na **cadencia de amostragem** e nos
**defaults de periodo das EMAs**, conforme detalhado em
`investigacoes/DIVERGENCIA_CADENCIA_EA.md`.

**Equivalencia visual estrita NAO e esperada.** O indicador serve como
ferramenta visual de regime; o EA decide acoes de trading com base no seu
calculo interno. Use o indicador para entender o que o operador esta
acompanhando, nao para prever decisoes do EA.

---

## 9. Limitacoes conhecidas

- **Nao funciona no Strategy Tester.** O indicador depende de tick em tempo
  real para o calculo de midprice na vela corrente; o Tester nao alimenta
  `SymbolInfoTick()` da mesma forma. Em chart live (DEMO ou REAL) o
  indicador opera normalmente.
- **Cadencia visual depende do timeframe do chart.** Em M5, cada barra do
  chart amostra `n_sigma`; em H1, apenas 1 amostra por hora. EMAs do mesmo
  periodo em chart M5 e em chart H1 representam janelas de tempo
  diferentes.
- **Bootstrap em par novo.** Em par recem-disponibilizado no broker (pouco
  historico D1/M5), o indicador permanece em warmup ate os minimos serem
  atingidos.
- **Sem labels visuais nas HLINEs de referencia.** O operador le valor
  sigma de cada linha via crosshair (passa o mouse na linha). Decisao da
  v2.1 para nao poluir a area de plotagem -- ver
  `legado/CHANGELOG_LEGADO.md`.

### 9.1 Nota de performance (v2.1)

A v2.0 sofria de um problema de auto-rearm do full recalc a cada 5
segundos, causado por gaps naturalmente esperados em barras antigas
(historico D1 < 420 ou M5 < 288 no inicio da serie). A v2.1 restringe
a deteccao de gap a zona quente (ultimas `kM5_Window_Bars` barras),
elimina o loop reciclico, e adiciona 4 otimizacoes complementares
(shift M5 aritmetico, alphas pre-calculados, blocos por direcao
inativa, reserve em ArrayResize). Resultado: CPU do `terminal64.exe`
substancialmente reduzida apos a carga inicial; sem mais atrasos
perceptiveis em atualizacao de candle ou no funcionamento do EA
coabitando no mesmo terminal.

---

## 10. Documentacao detalhada

| Documento | Conteudo |
|---|---|
| `specs/SPEC_INDICADOR_MA_VP.md` | Formula completa, pipeline VP v2 passo a passo, buffers, validacao R4-R6, constantes internas, otimizacoes B1-B6 |
| `relatorios/RELATORIO_ORIGEM_VP_v2.md` | Historico de portabilidade do velocimetro do Portal para MQL5 (decisoes canonicas D1=260, M5=276, sem anualizacao) |
| `investigacoes/DIVERGENCIA_CADENCIA_EA.md` | Tabela comparativa de cadencias entre indicador (M5/H1) e EA, janelas efetivas das EMAs, nota sobre equivalencia nao-estrita |
| `sprints/SPRINT_CRIACAO_INDICADOR.md` | Cronologia de desenvolvimento do indicador: commit inicial f02ba42, evolucao para v2.0 admin-driven, v2.1 paralelas-only, v2.2 VP Livre, v2.3 unificacao |
| `legado/CHANGELOG_LEGADO.md` | Registro de remocoes e descontinuacoes (v2.1: MAs Suavizadas; v2.3: separacao direcional COMPRA/VENDA) |
| `CLAUDE.md` | Instrucoes para o Claude Code operar neste repositorio documental |

---

*Fim do README.md*
