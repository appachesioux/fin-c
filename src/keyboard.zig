const calc = @import("calc.zig");

pub const BtnStyle = enum {
    normal,
    operator,
    equals,
    clear,
    function,
};

pub const FinRegister = enum {
    pv,
    fv,
    n,
    i,
    pmt,
};

pub const Action = union(enum) {
    digit: u8,
    dot,
    negate,
    operator: calc.Operator,
    equals,
    clear,
    clear_entry,
    backspace,
    percent,
    fin_toggle,
    decimal_places_up,
    decimal_places_down,
    fin_reg: FinRegister,
    fin_markup,
};

pub const BtnDef = struct {
    label: []const u8,
    action: Action,
    style: BtnStyle,
};

pub const COLS = 4;
pub const ROWS = 6;

pub const layout: [ROWS][COLS]BtnDef = .{
    .{
        .{ .label = "CE", .action = .clear_entry, .style = .clear },
        .{ .label = "C", .action = .clear, .style = .clear },
        .{ .label = "<", .action = .backspace, .style = .function },
        .{ .label = "%", .action = .percent, .style = .function },
    },
    .{
        .{ .label = "7", .action = .{ .digit = '7' }, .style = .normal },
        .{ .label = "8", .action = .{ .digit = '8' }, .style = .normal },
        .{ .label = "9", .action = .{ .digit = '9' }, .style = .normal },
        .{ .label = "/", .action = .{ .operator = .div }, .style = .operator },
    },
    .{
        .{ .label = "4", .action = .{ .digit = '4' }, .style = .normal },
        .{ .label = "5", .action = .{ .digit = '5' }, .style = .normal },
        .{ .label = "6", .action = .{ .digit = '6' }, .style = .normal },
        .{ .label = "x", .action = .{ .operator = .mul }, .style = .operator },
    },
    .{
        .{ .label = "1", .action = .{ .digit = '1' }, .style = .normal },
        .{ .label = "2", .action = .{ .digit = '2' }, .style = .normal },
        .{ .label = "3", .action = .{ .digit = '3' }, .style = .normal },
        .{ .label = "-", .action = .{ .operator = .sub }, .style = .operator },
    },
    .{
        .{ .label = "0", .action = .{ .digit = '0' }, .style = .normal },
        .{ .label = ",", .action = .dot, .style = .normal },
        .{ .label = "+/-", .action = .negate, .style = .function },
        .{ .label = "+", .action = .{ .operator = .add }, .style = .operator },
    },
    .{
        .{ .label = "FIN", .action = .fin_toggle, .style = .function },
        .{ .label = "DP-", .action = .decimal_places_down, .style = .function },
        .{ .label = "DP+", .action = .decimal_places_up, .style = .function },
        .{ .label = "=", .action = .equals, .style = .equals },
    },
};

const fin_row_4: [COLS]BtnDef = .{
    .{ .label = "0", .action = .{ .digit = '0' }, .style = .normal },
    .{ .label = "PV", .action = .{ .fin_reg = .pv }, .style = .function },
    .{ .label = "FV", .action = .{ .fin_reg = .fv }, .style = .function },
    .{ .label = "n", .action = .{ .fin_reg = .n }, .style = .function },
};

const fin_row_5: [COLS]BtnDef = .{
    .{ .label = "FIN", .action = .fin_toggle, .style = .function },
    .{ .label = "PMT", .action = .{ .fin_reg = .pmt }, .style = .function },
    .{ .label = "i", .action = .{ .fin_reg = .i }, .style = .function },
    .{ .label = "MU", .action = .fin_markup, .style = .function },
};

pub const Keyboard = struct {
    fin_mode: bool,

    pub fn init() Keyboard {
        return .{ .fin_mode = false };
    }

    pub fn getBtn(self: *const Keyboard, row: usize, col: usize) BtnDef {
        if (self.fin_mode) {
            if (row == 4) return fin_row_4[col];
            if (row == 5) return fin_row_5[col];
        }
        return layout[row][col];
    }

    pub fn handleClick(self: *const Keyboard, mouse_x: f32, mouse_y: f32, win_w: f32, win_h: f32, kb_h: f32) ?Action {
        const kb_y = win_h - kb_h;
        if (mouse_y < kb_y) return null;

        const btn_h = (kb_h - 8) / @as(f32, ROWS);
        const btn_w = (win_w - 16) / @as(f32, COLS);

        const row_f = (mouse_y - kb_y - 4) / btn_h;
        if (row_f < 0) return null;
        const row_idx = @as(usize, @intFromFloat(row_f));
        if (row_idx >= ROWS) return null;

        const col_f = (mouse_x - 8) / btn_w;
        if (col_f < 0) return null;
        const col_idx = @as(usize, @intFromFloat(col_f));
        if (col_idx >= COLS) return null;

        return self.getBtn(row_idx, col_idx).action;
    }
};
