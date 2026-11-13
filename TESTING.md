# Testes do DevPorts

Três níveis, do mais barato ao mais caro. Bug corrigido entra com teste no nível mais baixo que o reproduz.

1. **Unitário** (XCTest, CI): parsers alimentados com saída capturada de `ps`/`lsof`, regras puras (`Activity`, `Overview`, `Restart`, `SessionBar`, `PopoverSizes`) e o `Store` com scanner e `ProcessKiller` falsos. Nenhum sinal real.
2. **Integração** (XCTest, CI): `IntegrationTests` chama o sistema de verdade, só em processos que o próprio teste cria (`/bin/sleep`, `nc -l 127.0.0.1` em porta livre); o `tearDown` mata o que sobrar.
3. **E2E manual no app** (local, a cada rodada de mudança grande): o app Debug aberto, cliques e screenshots, conferência no sistema com `ps -o pid,stat,comm`, `lsof -iTCP -sTCP:LISTEN` e `curl -m 3`. Só alvos descartáveis: TextEdit, Calculadora e processos criados para o teste; nunca navegador, Xcode ou o terminal em uso. Portas de fixture: 3005, 5173, 8000, 8080 (3000 e 3001 ficam livres).

Rodar:

```sh
swift format lint --strict -r DevPorts DevPortsTests
xcodebuild test -project DevPorts.xcodeproj -scheme DevPorts -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

## Matriz

| Parte | Tipo | Ferramenta | Onde roda | Fora e por quê |
|---|---|---|---|---|
| Scanner de portas (`ProcessScanner`) | unitário (parsers), integração (`scan` acha listener em loopback, suspenso) | XCTest | CI | listener em `0.0.0.0` no teste de integração: pode abrir o aviso do firewall; o selo REDE fica no unitário e no E2E |
| Scanner de atividade (`ActivityScanner`, `Activity`) | unitário, integração (acha o próprio processo) | XCTest | CI | CPU real sob carga: só no E2E (`yes`) |
| Sinais (`ProcessKiller`) | unitário (sinal falso), integração (STOP/CONT/TERM em `sleep`) | XCTest | CI | processo de outro usuário: o CI não tem um; EPERM fica no unitário |
| Estado e regras (`Store`) | unitário | XCTest | CI | polling com relógio real: E2E |
| Terminal (`TerminalSessions`, barra) | unitário (`SessionBar`, troca de host) | XCTest | CI | pty e SwiftTerm de verdade: E2E (D) |
| Telas (`PopoverView`, `AppsView`, `AjustesView`, `TerminalWindow`) | unitário só onde há regra (aba mantida, Terminal em janela); previews; E2E | XCTest, Xcode Previews | CI, local | snapshot visual: sem ferramenta no projeto, os previews e o E2E cobrem |
| Tamanhos (`PopoverSizes`) | unitário (padrão, clamp, round trip do JSON) | XCTest | CI | medida em pixels: E2E (E) |

## Limites conhecidos

- Serviços XPC são filhos do `launchd`: pausar o Safari não pausa o `WebContent`, que aparece como linha própria.
- Pausar um app de terminal pausa todos os shells e servidores dentro dele.
- Se o DevPorts morrer à força, o que ele pausou fica `T`; ao reabrir aparece SUSPENSO e o ▶ retoma.

## Rodada E2E

Resultado: ok, falhou (vira issue + PR com teste) ou limite aceito. Evidência: screenshot da UI e saída do sistema.

| # | Cenário | Resultado |
|---|---|---|
| **A** | **Portas e processos dev** | |
| 1 | Lista, LED, metadados, selo REDE em `0.0.0.0` e não em `127.0.0.1` | pendente |
| 2 | Grupo fechado/aberto; busca por texto, `:3005`, porta livre, `:80` de outro usuário, sem resultado | pendente |
| 3 | ✕ manda TERM com spinner; processo com `trap '' TERM` vira "Forçar" em 5 s e o KILL resolve | pendente |
| 4 | Linha de sistema; "Encerrar todos" com confirmação | pendente |
| 5 | ⌘R e polling de 5 s | pendente |
| **B** | **Suspender dev** | |
| 6 | ⏸ → `T`, porta segue ocupada, `curl -m 3` trava, selo SUSPENSO; ▶ → responde | pendente |
| 7 | ✕ em suspenso encerra de fato | pendente |
| 8 | Dica de suspender; linha de sistema sem ⏸ | pendente |
| 9 | Servidor pausado pela linha volta a rodar ao sair (⌘Q) | pendente |
| **C** | **Aba Apps** | |
| 10 | Ordenar CPU/Memória/Nome; "—" na primeira leitura, sem picos > 100 %; `yes` perto de 100 % | pendente |
| 11 | TextEdit ⏸ e ▶ | pendente |
| 12 | Pai com 3 filhos: expandir, confirmação com contagem, todos `T`, todos voltam | pendente |
| 13 | Protegidos com cadeado; "Mostrar sistema"; outro usuário com cadeado | pendente |
| 14 | 30 s parado na aba Apps: a aba não volta para Portas | pendente |
| 15 | Busca; lista longa sem cortar o topo | pendente |
| 16 | Sair com apps pausados retoma tudo; processo já `T` antes continua `T` | pendente |
| 17 | `kill -9` no DevPorts: fica `T`; reabrir mostra SUSPENSO e ▶ funciona | pendente |
| 18 | Pid reciclado não recebe sinal | pendente |
| **D** | **Terminal** | |
| 19 | Sem sessão → Nova sessão; "Terminal na pasta"; Scripts (`yarn run dev` no fixture) | pendente |
| 20 | Digitar, colar, Ctrl-C, clicar fora, reabrir: histórico intacto e teclado chega ao terminal | pendente |
| 21 | Esc dentro do terminal (vim/less) não fecha o popover | pendente |
| 22 | Barra: rodando, parando 5 s, Forçar, terminou, ocioso, código ≠ 0, Abrir :porta | pendente |
| 23 | "Abrir em janela" e "Trazer para o popover" várias vezes: nunca em branco; fechar a janela volta o host | pendente |
| 24 | "Abrir Terminal em: Janela": Rodar script, Reiniciar, Terminal na pasta e a própria aba abrem a janela | pendente |
| 25 | Reiniciar com log (faixa → TERM → nova aba) e falha de reinício | pendente |
| 26 | Reiniciar e fechar o popover: o comando volta sem reabrir | pendente |
| 27 | Sair com sessões: faixa, nenhum job órfão (`pgrep`) | pendente |
| 28 | Ícone no Dock só com a janela aberta | pendente |
| **E** | **Ajustes** | |
| 29 | Mesmo tamanho: largura 360/440/720; altura Automática e Fixa 300/660; teto 660 com lista longa; rodapé colado embaixo | pendente |
| 30 | Por aba: trocar de aba muda o tamanho; Terminal em janela mostra "sem efeito" | pendente |
| 31 | Persiste ao reabrir; `defaults write` com lixo cai no padrão; "Restaurar padrão" | pendente |
| 32 | Linha do topo fixa em todas as abas, com banner, faixa de sair e Ajustes | pendente |
| 33 | Busca limpa ao trocar de aba | pendente |
| **F** | **Transversais** | |
| 34 | Barra de menus com contagem (some em zero); claro, escuro, contraste aumentado | pendente |
| 35 | Teclado ⌘R/⌘Q/Tab; `accessibilityLabel` presentes | pendente |
| 36 | 10 min com popover aberto (CPU e memória do DevPorts); abrir/fechar 50x; 20 sessões | pendente |
| 37 | Aba Ações sem argv nem segredo | pendente |
