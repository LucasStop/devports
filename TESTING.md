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

O que depende de teclado no popover está em [MANUAL-TESTS.md](MANUAL-TESTS.md).

Resultado: ok, parcial (o que faltou está dito), inconclusivo, roteiro manual (depende de teclado no popover, que a automação não alcança) ou não verificado. Evidência: screenshot da UI e saída do sistema.

| # | Cenário | Resultado |
|---|---|---|
| **A** | **Portas e processos dev** | |
| 1 | Lista, LED, metadados, selo REDE em `0.0.0.0` e não em `127.0.0.1` | ok: 3 portas, selo REDE só na :8080, LED e metadados (print `08-portas-geral`) |
| 2 | Grupo fechado/aberto; busca por texto, `:3005`, porta livre, `:80` de outro usuário, sem resultado | parcial: grupo abre e fecha (print `04-grupo-sistema-aberto`); busca só no roteiro manual, o campo não aceita digitação por automação |
| 3 | ✕ manda TERM com spinner; processo com `trap '' TERM` vira "Forçar" em 5 s e o KILL resolve | ok: "Não respondeu em 5 s" apareceu, Forçar matou o node e a porta liberou (`ps` e `lsof`); spinner não observado |
| 4 | Linha de sistema; "Encerrar todos" com confirmação | ok: grupo Sistema e confirmação "Encerrar os 7 processos de Sistema?", cancelada (prints `04-*`) |
| 5 | ⌘R e polling de 5 s | parcial: lista atualizou após matar servidores por fora; ⌘R no roteiro manual |
| **B** | **Suspender dev** | |
| 6 | ⏸ → `T`, porta segue ocupada, `curl -m 3` trava, selo SUSPENSO; ▶ → responde | ok: `TN`, porta ocupada, `curl -m 3` trava, SUSPENSO; ▶ volta com 200 |
| 7 | ✕ em suspenso encerra de fato | ok: ✕ em suspenso encerrou o processo (`ps` vazio, porta livre) |
| 8 | Dica de suspender; linha de sistema sem ⏸ | não verificado |
| 9 | Servidor pausado pela linha volta a rodar ao sair (⌘Q) | ok (B3): :8080 pausado voltou a `SN` ao Sair, curl 200 |
| **C** | **Aba Apps** | |
| 10 | Ordenar CPU/Memória/Nome; "—" na primeira leitura, sem picos > 100 %; `yes` perto de 100 % | parcial: `yes` em 98 a 99 %, sem picos acima de 100 % (B2); ordenação por Nome e "—" da primeira leitura não verificados |
| 11 | TextEdit ⏸ e ▶ | parcial: pausa de app testada com `yes` (`TN`), TextEdit não testado |
| 12 | Pai com 3 filhos: expandir, confirmação com contagem, todos `T`, todos voltam | parcial: expandir 4 processos, confirmação "3 processos auxiliares", todos `TN` (prints `12-*`); ▶ do app não verificado na UI |
| 13 | Protegidos com cadeado; "Mostrar sistema"; outro usuário com cadeado | ok: cadeado em Orca e DevPorts; "Mostrar sistema" 380 para 578 com WindowServer SISTEMA e cadeado (prints `13-*`) |
| 14 | 30 s parado na aba Apps: a aba não volta para Portas | ok (B1): 32 s na aba Apps, a aba não voltou para Portas |
| 15 | Busca; lista longa sem cortar o topo | parcial: topo da lista não cortado (print `13-apps-topo-cadeado`); busca no roteiro manual |
| 16 | Sair com apps pausados retoma tudo; processo já `T` antes continua `T` | parcial: Sair retomou o processo pausado (`yes` voltou a `RN`); processo já `T` antes não testado |
| 17 | `kill -9` no DevPorts: fica `T`; reabrir mostra SUSPENSO e ▶ funciona | ok: após `kill -9` ficou `TN`, reabrir mostrou SUSPENSO e ▶ retomou (curl 200) |
| 18 | Pid reciclado não recebe sinal | coberto só por teste de integração (`testOtherStartTimeGetsNoSignal`), sem rodada ao vivo |
| **D** | **Terminal** | |
| 19 | Sem sessão → Nova sessão; "Terminal na pasta"; Scripts (`yarn run dev` no fixture) | parcial: Nova sessão cria `zsh` filho do DevPorts; "Terminal na pasta" e Scripts no roteiro manual |
| 20 | Digitar, colar, Ctrl-C, clicar fora, reabrir: histórico intacto e teclado chega ao terminal | inconclusivo: o teclado não chegou ao terminal por automação (type-text, clique e `osascript`); roteiro manual |
| 21 | Esc dentro do terminal (vim/less) não fecha o popover | roteiro manual |
| 22 | Barra: rodando, parando 5 s, Forçar, terminou, ocioso, código ≠ 0, Abrir :porta | roteiro manual |
| 23 | "Abrir em janela" e "Trazer para o popover" várias vezes: nunca em branco; fechar a janela volta o host | roteiro manual |
| 24 | "Abrir Terminal em: Janela": Rodar script, Reiniciar, Terminal na pasta e a própria aba abrem a janela | roteiro manual |
| 25 | Reiniciar com log (faixa → TERM → nova aba) e falha de reinício | roteiro manual |
| 26 | Reiniciar e fechar o popover: o comando volta sem reabrir | roteiro manual |
| 27 | Sair com sessões: faixa, nenhum job órfão (`pgrep`) | roteiro manual |
| 28 | Ícone no Dock só com a janela aberta | roteiro manual |
| **E** | **Ajustes** | |
| 29 | Mesmo tamanho: largura 360/440/720; altura Automática e Fixa 300/660; teto 660 com lista longa; rodapé colado embaixo | ok: larguras 360/440/720, altura Fixa 300/660, Automática com teto 660, medidas na janela (via `defaults write`) |
| 30 | Por aba: trocar de aba muda o tamanho; Terminal em janela mostra "sem efeito" | parcial: Portas 400, Apps 600 e Terminal 500x300 mudam ao trocar de aba; aviso "sem efeito" não verificado |
| 31 | Persiste ao reabrir; `defaults write` com lixo cai no padrão; "Restaurar padrão" | parcial: valor inválido cai em 440 e largura 9999 limita em 720; "Restaurar padrão" e reabrir não verificados |
| 32 | Linha do topo fixa em todas as abas, com banner, faixa de sair e Ajustes | não verificado |
| 33 | Busca limpa ao trocar de aba | roteiro manual: a checagem automática foi inválida (o campo não filtrou) |
| **F** | **Transversais** | |
| 34 | Barra de menus com contagem (some em zero); claro, escuro, contraste aumentado | parcial: ícone mostra `2` com 2 portas e some em zero; claro, escuro e contraste não testados (mudam configuração do sistema) |
| 35 | Teclado ⌘R/⌘Q/Tab; `accessibilityLabel` presentes | parcial: `accessibilityLabel` presentes em todos os botões; teclado no roteiro manual |
| 36 | 10 min com popover aberto (CPU e memória do DevPorts); abrir/fechar 50x; 20 sessões | roteiro manual |
| 37 | Aba Ações sem argv nem segredo | ok: ações mostram só `kill -STOP/-CONT <pid> # nome`, sem argv nem segredo (print `37-terminal-acoes`) |

### Achados da primeira rodada

- Nenhum defeito novo nos cenários que rodaram; B1, B2 e B3 confirmados no app real (14, 10, 9).
- V1 a V4 seguem em aberto: dependem de teclado no popover, que a automação não alcança. Roteiro manual a cargo do mantenedor.
- Digitar no popover não funciona por automação (nem `orca computer`, nem `osascript`): a busca (2, 15, 33) também vai para o roteiro manual.
