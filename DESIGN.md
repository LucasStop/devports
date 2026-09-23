# DevPorts — DESIGN.md

Memória de design/brand do projeto. O `/frontend-design` lê este arquivo antes de gerar UI, pra manter identidade consistente sem re-explicar a cada sessão. Regras globais em `~/.claude/CLAUDE.md` valem; aqui só a identidade visual do repo.

Aprovado em 2026-09-23 no canvas de design (privado do autor): ícone A, glifo 4, paleta e telas abaixo.

## Brand
- Produto: app de barra de menus do macOS que mostra as portas ocupadas e de qual projeto é cada processo dev, com encerrar e terminal integrado.
- Personalidade: técnico, calmo, nativo, preciso.
- Conceito: porta de rede (RJ45) com LEDs. Verde = porta local ativa. Âmbar = porta exposta na rede.
- Referências que gosto: barra de menus e popovers do próprio macOS, Homebrew.app (console, estados vazios), densidade do Activity Monitor.
- Anti-referências: dashboard web com cards, degradês, ícone genérico de "servidor", emoji.

## Ícone e glifo
- **Ícone do app (A · Porta):** corpo alumínio `#ECEEF1` em squircle (824/1024), soquete `#1C1F24` com recorte RJ45, 8 pinos `#D4A72C`, LED verde `#2FBF71` à esquerda e âmbar `#F2A531` à direita.
  - `design/icon.svg`: arte mestre, usada de 64 px para cima.
  - `design/icon-small.svg`: versão de 16 e 32 px, sem pinos, soquete e LEDs maiores.
- **Glifo da barra de menus (4 · Porta):** `design/glyph.svg`, template monocromático, traço 1,8 em grade 24, exibido a 16 pt.
  - O contador de portas dev fica ao lado, em SF Pro 13 medium, e some quando é zero.

## Cores (tokens)

| Token | Claro | Escuro | Uso |
|---|---|---|---|
| Fundo | `#F6F6F7` | `#232326` | Popover e janelas (no app: material do sistema) |
| Texto | `#1D1D1F` | `#F2F2F7` | Texto principal (`.primary`) |
| Secundário | `#6E6E73` | `#A1A1A6` | Metadados, contagens, legendas (`.secondary`) |
| Separador | `#E3E3E8` | `#38383C` | Divisórias e bordas (`separatorColor`) |
| Destaque · LED verde | `#17803F` | `#3DD68C` | Porta local, botão principal, foco |
| Rede · LED âmbar | `#C77700` (LED), `#9A5000` (texto do selo) | `#FFB547` | Porta exposta na rede, avisos |
| Destrutivo | `#C62828` | `#FF6B6B` | Encerrar, Forçar, erros |
| Inativo · LED cinza | `#AEAEB2` | `#6E6E73` | Processo de sistema, sessão parada |

- Dark mode: sim. No app, fundo, texto, secundário e separador usam as cores semânticas do sistema; só destaque, rede, destrutivo e inativo viram colorsets (Any/Dark) no Asset Catalog.
- Contraste: texto ≥ 4,5:1 e LED ≥ 3:1 contra o fundo nos dois modos, com os valores acima.

## Terminal (tema)
- **Escuro:** fundo `#14161A`, texto `#D7DAE0`, cursor `#3DD68C`.
  - ANSI 0–7: `#1C1F24 #FF6B6B #3DD68C #FFB547 #6CB6FF #D2A8FF #56D4DD #D7DAE0`
  - ANSI 8–15: `#5C6370 #FF8A8A #6BE3A8 #FFD27A #9CCBFF #E2C5FF #8BE9F0 #FFFFFF`
- **Claro:** fundo `#FBFBFA`, texto `#24292F`, cursor `#17803F`.
  - ANSI 0–7: `#24292F #C62828 #17803F #9A6700 #0969DA #8250DF #1B7C83 #6E7781`
  - ANSI 8–15: `#57606A #E5534B #1F9D55 #B08800 #218BFF #A475F9 #3192AA #8C959F`

## Tipografia
- Fonte display/heading: SF Pro (sistema) · Corpo: SF Pro · Mono: SF Mono.
- Escala:
  - 13 semibold: nome do app e número da porta (este em SF Mono);
  - 13 regular: título da linha;
  - 11 regular secundário: metadados;
  - 11 semibold secundário: cabeçalho de seção;
  - selo 9,5 bold com tracking 0,04 em;
  - terminal: SF Mono 12,5.
- Peso/tracking: pesos do sistema, sem tracking extra fora do selo.

## Layout & espaçamento
- Grid base: 2 pt. Popover com 440 pt de largura e até 660 pt de altura; padding lateral 14.
- Alturas: linha de porta 40, grupo 32, processo filho 30, rodapé 44, cabeçalho de seção 26.
- Raio: popover 12, campo 7, botão 6, selo 4. Sombra: nenhuma própria (a do sistema).
- Densidade: compacta.

## Componentes (padrões)
- **Linha de porta:** LED 7 pt · porta em SF Mono (58 pt) · título, com selo `REDE` quando exposta · metadados (`projeto · exe · uptime · RAM`) · botões ↗ e ✕ de 26 pt.
- **Grupo de processos:** chevron · nome (projeto, `~/pasta` ou "Sistema") · `N processos · RAM`. Aberto, mostra os processos filhos e "Encerrar todos".
- **Botões:** pequeno (24 pt) com borda sutil; destrutivo em vermelho; primário preenchido com o destaque. Botões só de ícone com 26 pt e `accessibilityLabel`.
- **Confirmação:** faixa inline tingida (vermelha para destruir, verde para reiniciar) com botão primário e Cancelar. Nunca modal, porque o `MenuBarExtra` fecha quando um alert abre.
- **Feedback:**
  - encerrando mostra spinner e "encerrando…";
  - sem resposta em 5 s, o botão vira "Forçar";
  - erro aparece em faixa no rodapé;
  - vazio usa `ContentUnavailableView`;
  - busca por porta livre responde "Porta N livre".
- **Terminal:**
  - abas com LED de status (verde rodando, cinza parado, vermelho saiu com erro);
  - barra de status com pid, porta, selo e uptime, mais Reiniciar e Parar;
  - aba fixa "Ações" com o log.
- **Ícones:** SF Symbols no app (`arrow.up.right`, `xmark`, `arrow.clockwise`, `terminal`, `magnifyingglass`, `chevron.right`, `chevron.down`, `list.bullet`, `plus`).

## Tom & voz (microcopy)
- Idioma da UI: pt-BR · Tratamento: você, informal e direto.
- Mensagens curtas; erro diz o que houve e o que fazer. Exemplos:
  - "Nenhuma porta dev em uso"
  - "Porta 4000 livre"
  - "Não respondeu em 5 s"
  - "Encerrar os 12 processos de ~/.gradle?"
  - "Reiniciar com `yarn run dev` em oparceiro_panel?"
  - "2 sessões rodando no Terminal. Sair encerra as duas."

## Regras (anti "AI slop")
- Nada de degradê arco-íris, emoji decorativo ou "glassmorphism" sem propósito
- Estados completos: hover, focus-visible, disabled, loading, vazio, erro
- Acessibilidade: contraste AA, foco visível, `accessibilityLabel` em botão só de ícone, navegável por teclado
- Espaçamento consistente com o grid base; sem números mágicos
- Cor só com significado: verde = local/ok, âmbar = rede/aviso, vermelho = destrutivo/erro, cinza = sistema/parado
- Nenhum dado sensível na UI ou no log: argv completo só em tooltip, nunca no log de ações; ambiente de processo nunca lido

## Referências visuais
- Canvas aprovado em 2026-09-23 (privado do autor): ícones A/B/C, glifos 1–5, paleta, popover claro e escuro, 8 estados, janela Terminal e aba Ações.
