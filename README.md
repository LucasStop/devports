# DevPorts

App de barra de menus do macOS que mostra quais portas estão ocupadas e de qual projeto é cada processo dev (`node`, `python`, `java`, bancos de dados). Também encerra processos e traz um terminal integrado.

Status: **em construção**. O plano está em [PRD.md](PRD.md) e a identidade visual em [DESIGN.md](DESIGN.md).

## Requisitos
- macOS 14 ou superior
- Xcode 26 ou superior (Swift 6.2)
- `brew install xcodegen`
- `xcodebuild -downloadComponent MetalToolchain` (o terminal integrado, SwiftTerm, compila shaders Metal)

## Build

```sh
xcodegen
xcodebuild -scheme DevPorts -configuration Release -derivedDataPath build -skipPackagePluginValidation
cp -R build/Build/Products/Release/DevPorts.app ~/Applications/
open ~/Applications/DevPorts.app
```

Para abrir junto com o login: Ajustes do Sistema › Geral › Itens de Início › `+` › DevPorts.

## Desenvolvimento

```sh
brew install lefthook gitleaks
lefthook install
```

- **pre-commit:** gitleaks e `swift format lint --strict` nos arquivos em stage.
- **CI no PR:** lint e testes no runner `macos-26`.

## Licença

[MIT](LICENSE)
