# Roteiro manual: teclado no popover

Cenários de [TESTING.md](TESTING.md) que a automação não alcança porque digitar no popover não funciona por `orca computer`, `osascript` nem `computer-use`: 2, 5, 15, 20 a 28, 33, 35 e 36.

Pré-requisito: app Debug aberto (`xcodebuild -project DevPorts.xcodeproj -scheme DevPorts -configuration Debug build` e abrir o `.app`, ou o instalado), porta 3000/3001 livres.
Fixture: `mkdir -p ~/e2e/web && cd ~/e2e/web && echo '{"name":"web","scripts":{"dev":"python3 -m http.server 3005","fail":"sh -c \"sleep 1; exit 3\""}}' > package.json`
Ao fim: `pgrep -fl "http.server|sleep"`, matar o que sobrar, `rm -rf ~/e2e`.

## A. Teclado no popover (20, V3)
1. Abra o popover, aba Terminal, "Nova sessão".
2. Digite `echo oi` + Enter. Esperado: aparece `oi`.
3. Cole (⌘V) um texto de 3 linhas. Esperado: colado no prompt.
4. `sleep 100` + Ctrl-C. Esperado: volta ao prompt.
5. Clique fora do popover, reabra. Esperado: histórico intacto, teclado ainda funciona sem clicar no terminal.
Falha típica: tecla não chega ao terminal (anote se precisa clicar antes).

## B. Esc (21, V2)
1. `less /etc/hosts` no terminal do popover, pressione Esc, depois `q`.
2. Esperado: o popover não fecha com Esc. Se fechar, anote (recomendar Janela para TUIs).
3. Repita com `vim` (Esc no modo insert).

## C. Barra de status (22)
Em `~/e2e/web`, aba Terminal, menu Ações, Scripts:
1. `dev`: barra mostra "rodando" e botão Abrir :3005 abre o navegador.
2. Pare: aparece "parando" por até 5 s; se ignorar, "Forçar".
3. `fail`: "saiu com código 3".
4. Ocioso (shell sem job): estado ocioso.

## D. Popover <-> janela (23, V1)
1. Com sessão ativa, "Abrir em janela", depois "Trazer para o popover". Repita 5 vezes.
2. Esperado: terminal nunca em branco, histórico preservado.
3. Com janela aberta, feche-a pelo botão vermelho: o terminal volta ao popover.

## E. Ajustes "Abrir Terminal em: Janela" (24)
1. Ajustes, Abrir em: Janela.
2. Esperado: abrem janela: "Rodar script", "Reiniciar", "Terminal na pasta" e clicar na aba Terminal.
3. A aba no popover mostra o aviso de que o terminal está na janela.

## F. Reiniciar (25, 26, V4)
1. Rode `dev`, na aba Portas use Reiniciar no :3005. Esperado: faixa com o comando, TERM, nova aba com o comando.
2. Quebre o reinício (renomeie `package.json`) e reinicie: esperado aviso de falha.
3. Reiniciar de novo e fechar o popover na hora; reabra após 10 s. Anote se o comando só voltou ao reabrir.

## G. Sair com sessões (27)
1. Com `dev` rodando numa sessão, Sair. Esperado: faixa de confirmação.
2. Confirme. `pgrep -fl http.server` deve vir vazio.

## H. Dock (28)
1. Ícone no Dock não aparece com só o popover.
2. Abra a janela do terminal: ícone aparece; feche: some.

## I. Teclado geral (35)
1. ⌘R atualiza a lista; Tab percorre os controles; ⌘Q sai.

## J. Estabilidade (36)
1. Popover aberto 10 min: `ps -o %cpu,rss -p $(pgrep -f DevPorts)` no início e no fim (CPU baixa, RSS sem crescer continuamente).
2. Abrir/fechar 50x e abrir 20 sessões: nenhum travamento nem aumento grande de memória.

## K. Busca (2, 15, 33, B7)
1. Aba Portas, digite `3005` na busca. Esperado: só a linha :3005; `zzzqq` mostra "Nada encontrado"; `:80` filtra por porta.
2. Com `3005` digitado, troque para Apps. Esperado: campo vazio e lista de Apps sem filtro (B7).
3. Em Apps, digite `Safari` ou um pid de helper. Esperado: filtra o app; troque para Portas e o campo também está vazio.
4. Lista longa de Apps: o topo não fica cortado e o rolar chega ao fim.

## L. ⌘R (5)
1. Com o popover aberto, mate um servidor por fora (`kill <pid>`) e pressione ⌘R. Esperado: a lista atualiza na hora, sem esperar 5 s.

## Registro
Para cada item anote: ok, falhou (o que viu) ou limite aceito. Passe de volta que eu abro issue + PR com fix e teste.
