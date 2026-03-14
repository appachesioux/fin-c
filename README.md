# fin-c

Calculadora financeira com visual de bobina de papel, feita em Zig + raylib.

Written with assistance from Claude Code

## Build e execução

```sh
zig build run
```
```sh
rm -rvf zig-out;
zig build -Doptimize=ReleaseSmall;
```


Requer Zig 0.15.2. Raylib é compilado automaticamente como dependência (não precisa instalar no sistema).

## Arquitetura

- `src/main.zig` — loop principal, renderização (raylib), input handling. Todo código que toca raylib fica aqui (Zig 0.15 não permite compartilhar tipos de `@cImport` entre módulos).
- `src/number.zig` — tipo `Decimal` com aritmética de ponto fixo baseada em `i128` (38 dígitos). Evita erros de float em cálculos contábeis. Formatação com separador de milhar (vírgula) e ponto decimal.
- `src/calc.zig` — engine de cálculo com modelo acumulador (como calculadora de mesa real). Operações: add, sub, mul, div, percent. Registradores financeiros (PV, FV, n, i, PMT) com resolução automática.
- `src/keyboard.zig` — layout do teclado virtual (6x4 grid). Dados puros, sem dependência de raylib. Layout alternativo no modo FIN.
- `src/tape.zig` — estrutura da bobina de papel (histórico de operações com scroll).

## Formato numérico

- Separador de milhar: vírgula (1,000,000)
- Separador decimal: ponto (0.50)
- Ctrl+V detecta automaticamente o formato (BR/EU `1.000,50` ou US `1,000.50`) e normaliza.

## Estado atual

### Implementado
- Janela raylib redimensionável (420x700 padrão)
- Visor de bobina de papel branco com 3/4 da altura, scroll via mouse wheel
- Teclado virtual clicável (CE, C, backspace, %, dígitos, operadores, =, +/-, FIN, DP+/DP-)
- Teclado físico (numpad + teclas comuns)
- Aritmética com i128 fixed-point (casas decimais configuráveis 0-8, padrão 2)
- Formatação com separadores de milhar
- Suporte a valores enormes (até 38 dígitos)
- Operadores exibidos à direita dos valores na tape
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
- **Todo raylib em main.zig**: restrição do Zig 0.15 — `@cImport` em módulos diferentes gera tipos incompatíveis.
- **ArrayList para tape**: cresce indefinidamente, memória trivial para uma sessão de calculadora.
