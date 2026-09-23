# PRD — DevPorts

App de barra de menus do macOS que mostra quais portas estão ocupadas e de qual projeto é cada processo dev. Também deixa encerrar, reiniciar e abrir terminal sem sair dele.

## Problem Statement
O Activity Monitor lista dezenas de processos `node`, `java` e `dart` sem dizer de qual projeto vêm, e não mostra portas. Na prática isso causa três problemas:
- "porta 3000 em uso" vira uma caça com `lsof`;
- servidores esquecidos ficam rodando por dias (por exemplo, workers do next órfãos e 12 daemons Gradle);
- não há como saber, de relance, se um servidor está exposto na rede.

## Solution
Um app nativo na barra de menus, o DevPorts. Ele cruza `lsof`, `ps` e `sysctl` para listar:
- as portas dev;
- os processos dev agrupados por projeto (a pasta com `.git`, `package.json` etc.).

O encerramento é seguro, e um terminal integrado permite reiniciar servidores com log, rodar scripts e abrir um shell na pasta do projeto.

## User Stories
1. Como dev, quero ver no ícone da barra quantas portas dev estão ocupadas, para saber de relance se algo ficou rodando.
2. Como dev, quero ver cada porta com o projeto dono, o comando legível, o uptime e a RAM, para identificar o processo sem `lsof`.
3. Como dev, quero saber se uma porta está exposta na rede, para não deixar um servidor aberto sem querer.
4. Como dev, quero ver os processos dev sem porta agrupados por projeto (MCPs, daemons Gradle, workers), para achar o que está consumindo recursos.
5. Como dev, quero buscar por porta, processo ou projeto, e saber quando uma porta está livre.
6. Como dev, quero encerrar um processo com um clique, e forçar se ele não responder.
7. Como dev, quero encerrar todos os processos de um grupo, com confirmação.
8. Como dev, quero nunca matar o processo errado quando um PID for reciclado.
9. Como dev, quero ver os processos de sistema quando precisar (por exemplo, o AirPlay na 5000), escondidos por padrão.
10. Como dev, quero um log das ações do app: o que foi encerrado, com qual sinal e o resultado.
11. Como dev, quero abrir um shell na pasta do projeto dentro do app.
12. Como dev, quero rodar os scripts do `package.json` de um projeto, com a saída colorida ao vivo.
13. Como dev, quero reiniciar um servidor que subi em outro terminal e passar a ver o log dele no app, confirmando o comando antes.
14. Como dev, quero ser avisado, ao sair do app, quando houver sessões rodando.

## Implementation Decisions
- **Plataforma:**
  - SwiftUI, com AppKit onde precisar;
  - `MenuBarExtra` com estilo `.window` e `LSUIElement` (sem ícone no Dock);
  - a janela Terminal troca a política de ativação para `.regular` enquanto está aberta.
- **Projeto:** XcodeGen, macOS 14+, Swift 6.0, sem assinatura (uso pessoal). Mesmo layout do claude-control-panel.
- **Coleta** (polling a cada 5 s e ao abrir o popover):
  - portas: `lsof -nP -iTCP -sTCP:LISTEN -Fpn`;
  - processos: `ps -axww -o pid=,ppid=,rss=,lstart=,comm=` com `LC_ALL=C`;
  - argv exato: `sysctl(KERN_PROCARGS2)`, lendo só o argv e ignorando o ambiente;
  - cwd: `lsof -a -d cwd`.
- **Classificação:**
  - é dev quem bate com a regex dev no executável ou tem projeto detectado;
  - portas a partir de 49152 ficam ocultas por padrão;
  - grupos por projeto, senão `~/pasta`, senão "Sistema".
- **Encerrar:**
  - SIGTERM no clique; SIGKILL em "Forçar";
  - o `lstart` é conferido antes de todo sinal;
  - grupo e processo de sistema pedem confirmação inline.
- **Terminal:**
  - `LocalProcessTerminalView` do SwiftTerm (MIT) para shell, scripts e reinício;
  - shell de login `zsh -l`, para herdar o PATH do nvm;
  - no reinício, o argv é relançado entre aspas, depois de confirmar o comando exato.
- **Referência estudada:** o Homebrew.app (console com PTY e parser ANSI). Nenhum código foi copiado, porque a licença dele (AGPL-3.0) não é compatível com MIT.

## Testing Decisions
- XCTest no limite das funções puras:
  - parsing de `lsof`, `ps` e `KERN_PROCARGS2`;
  - rótulo, projeto, grupo, uptime e classificação;
  - guarda de PID reciclado;
  - gerenciador de pacotes e ordem dos scripts;
  - comando raiz, descendentes e aspas.
- Os casos são definidos antes da implementação (25 casos no plano). UI e layout não levam teste.

## Out of Scope
- UDP.
- Nome de container Docker.
- Processos de outros usuários ou do root.
- Toggle "abrir no login".
- Notificações.
- Exportar o transcript do terminal.
- Restaurar sessões depois de reabrir o app.
- Relançar com o ambiente original do processo.

## Further Notes
- Uso pessoal primeiro, com repo público (MIT). Distribuição assinada e notarizada fica para depois.
- Identidade visual: [DESIGN.md](DESIGN.md).
