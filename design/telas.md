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
| P15 | Lista com botão de pausa | aprovada |
| P16 | Linha suspensa | aprovada |
| P17 | Dica do botão de pausa | aprovada |
| P18 | Grupo com processo suspenso | aprovada |

Nota: o cabeçalho de P01 a P18 já mostra o seletor `Portas | Apps | Terminal` e o rodapé perdeu o botão "Terminal" (aprovado junto com as abas Apps e Terminal).

## Aba Apps · [`apps.html`](telas/apps.html)

| Id | Tela / estado | Status |
|---|---|---|
| H01 | Seletor de abas no cabeçalho | aprovada |
| A01 | Lista por CPU | aprovada |
| A02 | App expandido (helpers) | aprovada |
| A03 | App suspenso | aprovada |
| A04 | Confirmação de pausa de grupo | aprovada |
| A05 | Processo protegido (cadeado + dica) | aprovada |
| A06 | Busca sem resultado | aprovada |
| A07 | Menu de ordenação | aprovada |
| A08 | Mostrar sistema ligado | aprovada |
| A09 | Faixa de erro (outro usuário) | aprovada |
| A10 | Primeira leitura (CPU "—") | aprovada |

## Terminal no popover · [`terminal-popover.html`](telas/terminal-popover.html)

| Id | Tela / estado | Status |
|---|---|---|
| TP01 | Sem sessão | aprovada |
| TP02 | Sessão rodando | aprovada |
| TP03 | Parando | aprovada |
| TP04 | Parando: não respondeu | aprovada |
| TP05 | Terminou | aprovada |
| TP06 | Shell ocioso | aprovada |
| TP07 | Shell encerrado com erro | aprovada |
| TP08 | Ações (log) | aprovada |
| TP09 | Sessões abertas na janela | aprovada |
| S01 | Configuração: padrão Popover | aprovada |
| S02 | Configuração: padrão Janela | aprovada |

## Ajustes · [`ajustes.html`](telas/ajustes.html)

| Id | Tela / estado | Status |
|---|---|---|
| AJ01 | Mesmo tamanho em todas as abas | aprovada |
| AJ02 | Um tamanho por aba | aprovada |
| AJ03 | Terminal: padrão Janela | aprovada |

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
