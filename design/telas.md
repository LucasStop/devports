# Telas

Inventário de telas e estados do DevPorts. Protótipos estáticos em [`design/telas/`](telas/) (abrir o `.html` no navegador; claro e escuro lado a lado, tokens de [`DESIGN.md`](../DESIGN.md)).

Status: `rascunho` (proposta, sem aprovação), `em revisão`, `aprovada`, `implementada`.

O repo é anterior à regra "protótipo antes de tela". As telas já no app entram como `implementada`: foram aprovadas no canvas de 2026-09-23 (ver `DESIGN.md`) e os protótipos abaixo foram refeitos a partir do código. Tela nova só é implementada depois de `aprovada`.

## Popover da barra de menus · [`popover.html`](telas/popover.html)

| Id | Tela / estado | Status |
|---|---|---|
| P01 | Lista (portas + grupos fechados) | implementada |
| P02 | Grupo aberto | implementada |
| P03 | Vazio | implementada |
| P04 | Busca sem resultado | implementada |
| P05 | Busca: porta livre | implementada |
| P06 | Busca: porta em uso por outro usuário | implementada |
| P07 | Linha encerrando | implementada |
| P08 | Não respondeu em 5 s (Forçar) | implementada |
| P09 | Confirmação de linha de sistema | implementada |
| P10 | Confirmação de grupo | implementada |
| P11 | Faixa de erro | implementada |
| P12 | Faixa de reinício | implementada |
| P13 | Faixa de sair | implementada |
| P14 | Menu de contexto da linha | implementada |
| P15 | Lista com botão de pausa | implementada |
| P16 | Linha suspensa | implementada |
| P17 | Dica do botão de pausa | implementada |
| P18 | Grupo com processo suspenso | implementada |

Nota: a linha do topo de todas as telas do popover (sem ícone e título) tem o seletor `Portas | Apps | Terminal` e o botão de atualizar à direita, sempre fixa no alto; a busca fica logo abaixo. O rodapé perdeu o botão "Terminal" e ganhou "Ajustes".

## Aba Apps · [`apps.html`](telas/apps.html)

| Id | Tela / estado | Status |
|---|---|---|
| H01 | Seletor de abas no cabeçalho | implementada |
| A01 | Lista por CPU | implementada |
| A02 | App expandido (helpers) | implementada |
| A03 | App suspenso | implementada |
| A04 | Confirmação de pausa de grupo | implementada |
| A05 | Processo protegido (cadeado + dica) | implementada |
| A06 | Busca sem resultado | implementada |
| A07 | Menu de ordenação | implementada |
| A08 | Mostrar sistema ligado | implementada |
| A09 | Faixa de erro (outro usuário) | implementada |
| A10 | Primeira leitura (CPU "—") | implementada |

## Terminal no popover · [`terminal-popover.html`](telas/terminal-popover.html)

| Id | Tela / estado | Status |
|---|---|---|
| TP01 | Sem sessão | implementada |
| TP02 | Sessão rodando | implementada |
| TP03 | Parando | implementada |
| TP04 | Parando: não respondeu | implementada |
| TP05 | Terminou | implementada |
| TP06 | Shell ocioso | implementada |
| TP07 | Shell encerrado com erro | implementada |
| TP08 | Ações (log) | implementada |
| TP09 | Sessões abertas na janela | implementada |
| S01 | Configuração: padrão Popover | implementada |
| S02 | Configuração: padrão Janela | implementada |

## Ajustes · [`ajustes.html`](telas/ajustes.html)

| Id | Tela / estado | Status |
|---|---|---|
| AJ01 | Mesmo tamanho em todas as abas | implementada |
| AJ02 | Um tamanho por aba | implementada |
| AJ03 | Terminal: padrão Janela | implementada |

## Janela Terminal · [`terminal.html`](telas/terminal.html)

| Id | Tela / estado | Status |
|---|---|---|
| T01 | Ações com log | implementada |
| T02 | Ações vazio | implementada |
| T03 | Sessão rodando | implementada |
| T04 | Sessão rodando em porta exposta | implementada |
| T05 | Parando | implementada |
| T06 | Parando: não respondeu | implementada |
| T07 | Terminou | implementada |
| T08 | Shell ocioso | implementada |
| T09 | Shell encerrado com erro | implementada |

## Item da barra de menus · [`barra-de-menus.html`](telas/barra-de-menus.html)

| Id | Tela / estado | Status |
|---|---|---|
| M01 | Com portas (glifo + contagem) | implementada |
| M02 | Sem portas (só glifo) | implementada |

## Decisões das telas novas (P15 a P18)

- Botão ⏸/▶ de 26 pt antes do ✕, só em linha dev. Linha de sistema não ganha o botão: congelar processo de sistema é risco sem ganho.
- Suspenso: LED cinza (token Inativo), selo `SUSPENSO` (mesmo estilo do `SISTEMA`) e texto secundário. Nenhuma cor nova.
- Dica do botão: "Suspender next dev, pid 4101. A porta continua ocupada e novas conexões ficam esperando."
- Retomar é um clique, sem confirmação. Sem item novo no menu de contexto (o botão basta).

## Decisões das telas novas (Apps, Terminal no popover)

- Apps: só pausa/retoma (sem encerrar); o app e todos os helpers de uma vez; grupo com mais de um processo pede confirmação com a contagem. Helpers não têm botão próprio.
- Protegidos (Finder, Dock, WindowServer, loginwindow, SystemUIServer, kernel_task, launchd, o próprio DevPorts) e processos de outro usuário: cadeado, sem botão.
- CPU é média entre duas leituras; na primeira aparece "—". Ordenar por CPU (padrão), Memória ou Nome.
- Ao sair, o DevPorts retoma tudo que ele pausou.
- Terminal: aba do popover por padrão; "Abrir em janela" move as mesmas sessões para a janela (só um lugar por vez, o outro mostra TP09). Configuração "Abrir Terminal em" no menu ⋯. A 440 pt a barra de status ocupa duas linhas.
- Ajustes: botão "Ajustes" no rodapé abre o painel dentro do popover. Tamanho do popover: interruptor "Mesmo tamanho em todas as abas" (um par largura/altura) ou largura e altura por aba (Portas, Apps, Terminal). Largura 360 a 720 pt (padrão 440); altura Automática (cresce com o conteúdo, teto 660 pt) ou Fixa de 300 a 660 pt. "Restaurar padrão" volta a 440 pt automático. Terminal em janela: o tamanho da aba Terminal não se aplica.
