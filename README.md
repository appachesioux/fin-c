# fin-c

Calculadora financeira com visual de bobina de papel, feita em Zig. Interface gráfica com raylib + raygui, multiplataforma (Linux, macOS, Windows).

<p align="center">
  <img src="screenshots/raylib.png" width="280" alt="fin-c">
</p>

Written with assistance from Claude Code

## Build e execução

```sh
zig build run
```
```sh
zig build -Doptimize=ReleaseSmall
```

Cross-compilação para Windows:
```sh
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-windows
```

Todas as dependências (raylib, raygui) são compiladas automaticamente — não precisa instalar nada no sistema além do Zig 0.15.2.

## Arquitetura

- `src/main.zig` — frontend raylib + raygui. Loop principal, renderização, input handling.
- `src/number.zig` — tipo `Decimal` com aritmética de ponto fixo baseada em `i128` (38 dígitos). Evita erros de float em cálculos contábeis. Formatação com separador de milhar (vírgula) e ponto decimal.
- `src/calc.zig` — engine de cálculo com modelo acumulador (como calculadora de mesa real). Operações: add, sub, mul, div, percent. Registradores financeiros (PV, FV, n, i, PMT) com resolução automática.
- `src/keyboard.zig` — layout do teclado virtual (6x4 grid). Dados puros, sem dependência de UI. Layout alternativo no modo FIN.
- `src/tape.zig` — estrutura da bobina de papel (histórico de operações com scroll).

## Formato numérico

- Separador de milhar: vírgula (1,000,000)
- Separador decimal: ponto (0.50)
- Ctrl+V detecta automaticamente o formato (BR/EU `1.000,50` ou US `1,000.50`) e normaliza.

## Funcionalidades

- Janela redimensionável (420x900 padrão)
- Visor de bobina de papel maximizado (teclado compacto), scroll via mouse wheel
- Teclado virtual clicável (CE, C, backspace, %, dígitos, operadores, =, +/-, FIN, DP+/DP-)
- Teclado físico (numpad + teclas comuns)
- Aritmética com i128 fixed-point (casas decimais configuráveis 0-8, padrão 2)
- Formatação com separadores de milhar
- Suporte a valores enormes (até 38 dígitos)
- Font monospace customizada (JetBrains Mono, embutida no binário via `@embedFile`)
- Feedback visual de botão pressionado (mouse e teclado físico)
- Clipboard: Ctrl+V (paste com detecção automática de formato BR/EU vs US) e Ctrl+C (copy)
- Modo financeiro (botão FIN alterna layout):
  - Registradores: PV, FV, n, i, PMT
  - Cálculo automático quando 4 de 5 registradores estão preenchidos
  - Fórmulas: juros compostos, valor presente, anuidade, número de períodos, taxa (Newton-Raphson)
  - Markup (preço = custo / (1 - margem/100))

## Decisões de design

- **i128 fixed-point em vez de f64**: exatidão decimal para operações contábeis. Funções financeiras que precisam de pow/ln convertem para f64 temporariamente.
- **Modelo acumulador, não árvore de expressão**: calculadora financeira de mesa funciona sequencialmente.
- **raylib + raygui**: visual consistente e idêntico em Windows, macOS e Linux. Binário auto-contido sem dependências de sistema.
- **ArrayList para tape**: cresce indefinidamente, memória trivial para uma sessão de calculadora.

## Futuro: GUI desktop nativa multiplataforma (NAppGUI)

O fin-c atual usa raylib e está funcionando bem. Para evoluir para um app desktop "de verdade" (Linux, macOS, Windows), com look nativo, menus do SO, file dialogs e instaladores próprios, o caminho escolhido — sem pressa, sem urgência, com fin-c raylib continuando a funcionar em paralelo — é **NAppGUI**.

### Por que NAppGUI

Avaliação feita entre as alternativas viáveis:

| Opção            | Veredicto                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------ |
| **GTK4**         | Já tentado. Quebra em macOS e Windows (deps gigantes, bundling chato). Descartado.                     |
| **Dear ImGui**   | Já tentado. Não engatou para app de produto final voltado a usuário comum.                             |
| **Tauri**        | Resolveria bundling/sign, mas força UI em HTML/JS e backend em Rust — sai do Zig. Descartado.         |
| **webview-zig**  | Tentador, mas bundling/assinatura/notarização nos 3 SOs vira projeto à parte. Inconsistência entre WebKit/WebView2/WebKitGTK. Sem type safety Zig↔JS. Descartado. |
| **capy / libui-ng** | Imaturos para produção cross-platform.                                                               |
| **Qt**           | Licenciamento + tamanho + binding Zig ruim.                                                            |
| **IUP**          | Sólido, nativo nos 3 SOs, mas estética datada. Backup caso NAppGUI trave.                              |
| **NAppGUI**      | **Escolhido.** C99, nativo nos 3 SOs (Cocoa/Win32/GTK3), Apache 2.0, binding Zig trivial via `extern`, footprint ~2-5 MB, sem runtime. |

**Trade-offs aceitos:**
- Setup inicial chato (CMake + linkagem por SO), mas é uma vez.
- API estilo C anos 2000 (sem reactive, mais boilerplate por tela).
- Widgets fixos — customização visual limitada (ok para app financeiro tipo formulário/tabela/gráficos).
- No Linux usa GTK3 internamente (não GTK4) — abstraído, não precisamos escrever GTK, e GTK3 é muito mais estável que GTK4 nos outros SOs.

**O que NAppGUI entrega:**
- Um binário, um build, três SOs — de verdade, sem runtime nem webview.
- Tudo em Zig+C, type safety ponta a ponta via `extern`.
- Menus, atalhos, file dialogs e acessibilidade nativos.

### Plano de implementação (a executar com calma)

1. **Vendorizar NAppGUI** em `vendor/nappgui/` (decidir na hora: submódulo git ou pasta copiada).
2. **Build separado via CMake**: script `0-build-nappgui.sh` (preferido sobre invocar CMake do `build.zig` — mais limpo e idiomático Zig). Gera `.a` em `vendor/nappgui/build/`:
   `sewer`, `osbs`, `core`, `geom2d`, `draw2d`, `osgui`, `gui`, `osapp`.
3. **Bindings Zig mínimos** em `src/nappgui.zig`: `extern` para `osmain`, `window_create`, `window_show`, `osapp_run`, label, button.
4. **Segundo executável `fin-c-gui`** no `build.zig` (mantendo `fin-c` raylib intacto), linkando os `.a` + frameworks por SO via `switch (target.result.os.tag)`:
   - macOS: `Cocoa`, `Carbon`
   - Windows: `user32`, `gdi32`, `comctl32`, `uxtheme`, `ole32`, etc.
   - Linux: `gtk-3`, `gdk-3`, `pthread`
5. **`src/gui_main.zig`**: janela 600x400 "fin-c" com label — smoke test mínimo.
6. **Migração incremental**: portar `number.zig`/`calc.zig`/`tape.zig` (que já são puros, sem UI) e construir nova UI em cima. raylib continua como alvo paralelo durante toda a migração.

### Estado atual

fin-c está funcionando bem com raylib. NAppGUI é o caminho de evolução de longo prazo, **sem urgência**. O raylib permanece como alvo principal e funcional enquanto a migração não acontece.
