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
