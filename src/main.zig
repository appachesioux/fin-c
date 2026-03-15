const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});
const build_options = @import("build_options");

const number = @import("number.zig");
const tape = @import("tape.zig");
const calc = @import("calc.zig");
const keyboard = @import("keyboard.zig");

// Layout
const WINDOW_W = 420;
const WINDOW_H = 700;

// Colors
const COLOR_BG = rl.Color{ .r = 60, .g = 60, .b = 65, .a = 255 };
const COLOR_TAPE = rl.Color{ .r = 255, .g = 255, .b = 250, .a = 255 };
const COLOR_TAPE_TEXT = rl.Color{ .r = 30, .g = 30, .b = 30, .a = 255 };
const COLOR_TAPE_OP = rl.Color{ .r = 120, .g = 120, .b = 130, .a = 255 };
const COLOR_INPUT_BG = rl.Color{ .r = 45, .g = 45, .b = 50, .a = 255 };
const COLOR_INPUT_TEXT = rl.Color{ .r = 220, .g = 255, .b = 220, .a = 255 };
const COLOR_BTN = rl.Color{ .r = 85, .g = 85, .b = 90, .a = 255 };
const COLOR_BTN_OP = rl.Color{ .r = 180, .g = 120, .b = 50, .a = 255 };
const COLOR_BTN_EQ = rl.Color{ .r = 60, .g = 140, .b = 80, .a = 255 };
const COLOR_BTN_TEXT = rl.Color{ .r = 240, .g = 240, .b = 240, .a = 255 };
const COLOR_BTN_CLEAR = rl.Color{ .r = 160, .g = 60, .b = 60, .a = 255 };
const COLOR_BTN_FN = rl.Color{ .r = 70, .g = 100, .b = 140, .a = 255 };

const FONT_SIZE: f32 = 22;
const LINE_HEIGHT: f32 = 28;
const TAPE_MARGIN: f32 = 16;

const font_data = @embedFile("JetBrainsMono-Regular.ttf");
var font: rl.Font = undefined;

// Button press feedback
var pressed_row: ?usize = null;
var pressed_col: ?usize = null;
var press_timer: u8 = 0;
const PRESS_FRAMES: u8 = 6;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(WINDOW_W, WINDOW_H, build_options.app_name ++ "  v" ++ build_options.version);
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    const font_size_int: c_int = @intFromFloat(FONT_SIZE * 2);
    font = rl.LoadFontFromMemory(".ttf", font_data, @intCast(font_data.len), font_size_int, null, 0);
    rl.SetTextureFilter(font.texture, rl.TEXTURE_FILTER_BILINEAR);
    defer rl.UnloadFont(font);

    var t = tape.Tape.init(allocator);
    defer t.deinit();

    var engine = calc.CalcEngine.init();
    var fin = calc.FinRegisters.init();
    var kb = keyboard.Keyboard.init();
    var input_buf: [64]u8 = undefined;
    var input_len: usize = 0;
    var decimal_places: u8 = 2;

    while (!rl.WindowShouldClose()) {
        const win_w: f32 = @floatFromInt(rl.GetScreenWidth());
        const win_h: f32 = @floatFromInt(rl.GetScreenHeight());
        const kb_h = win_h / 4.0;
        const input_h: f32 = 40.0;
        const tape_h = win_h - kb_h - input_h;

        // Scroll
        const wheel = rl.GetMouseWheelMove();
        if (wheel != 0) {
            t.scroll(wheel * 30.0, tape_h);
        }

        // Tick press timer
        if (press_timer > 0) {
            press_timer -= 1;
            if (press_timer == 0) {
                pressed_row = null;
                pressed_col = null;
            }
        }

        // Mouse click on keyboard
        if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
            const mouse = rl.GetMousePosition();
            if (kb.handleClick(mouse.x, mouse.y, win_w, win_h, kb_h)) |action| {
                setPressedFromAction(action, &kb);
                processAction(action, &engine, &fin, &t, &input_buf, &input_len, decimal_places, &kb, &decimal_places);
            }
        }

        // Clipboard: Ctrl+V paste, Ctrl+C copy
        if (rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL)) {
            if (rl.IsKeyPressed(rl.KEY_V)) {
                const clip = rl.GetClipboardText();
                if (clip != null) {
                    const clip_str = std.mem.span(clip);
                    if (clip_str.len > 0) {
                        const len = number.Decimal.parsePaste(clip_str, &input_buf);
                        if (len > 0) input_len = len;
                    }
                }
            }
            if (rl.IsKeyPressed(rl.KEY_C)) {
                if (input_len > 0) {
                    rl.SetClipboardText(toC(input_buf[0..input_len]));
                } else if (engine.has_value) {
                    var fmt_buf: [128]u8 = undefined;
                    const formatted = engine.accumulator.format(&fmt_buf);
                    rl.SetClipboardText(toC(formatted));
                }
            }
        }

        // Physical keyboard
        if (handlePhysicalKey()) |action| {
            setPressedFromAction(action, &kb);
            processAction(action, &engine, &fin, &t, &input_buf, &input_len, decimal_places, &kb, &decimal_places);
        }

        rl.BeginDrawing();
        rl.ClearBackground(COLOR_BG);

        drawTapeArea(0, 0, win_w, tape_h, &t);
        drawInputLine(0, tape_h, win_w, input_h, input_buf[0..input_len]);
        drawKeyboard(0, tape_h + input_h, win_w, kb_h, &kb);

        rl.EndDrawing();
    }
}

// ── Rendering ──────────────────────────────────────────────

fn drawTapeArea(x: f32, y: f32, w: f32, h: f32, t: *tape.Tape) void {
    rl.DrawRectangleRec(.{ .x = x + 8, .y = y + 8, .width = w - 16, .height = h - 8 }, COLOR_TAPE);

    rl.BeginScissorMode(
        @intFromFloat(x + 8),
        @intFromFloat(y + 8),
        @intFromFloat(w - 16),
        @intFromFloat(h - 8),
    );

    const entries = t.entries.items;
    if (entries.len > 0) {
        var draw_y = y + h - LINE_HEIGHT - 8 + t.scroll_offset;

        var i: usize = entries.len;
        while (i > 0) {
            i -= 1;
            if (draw_y < y - LINE_HEIGHT) break;
            if (draw_y > y + h) {
                draw_y -= LINE_HEIGHT;
                continue;
            }

            const entry = entries[i];
            var fmt_buf: [128]u8 = undefined;
            const val_str = entry.value.format(&fmt_buf);

            const tag_str: [*c]const u8 = if (entry.label) |lbl|
                toC(lbl)
            else if (entry.operator) |op| switch (op) {
                .add => "+",
                .sub => "-",
                .mul => "x",
                .div => "/",
                .equals => "=",
            } else " ";

            const tag_width = measureText(tag_str, FONT_SIZE);
            const val_width = measureText(toC(val_str), FONT_SIZE);
            const op_right_x = x + w - TAPE_MARGIN - 16;
            const val_x = op_right_x - tag_width - 8 - val_width;

            const color = if (entry.is_result) COLOR_TAPE_TEXT else COLOR_TAPE_TEXT;

            drawText(toC(val_str), val_x, draw_y, FONT_SIZE, color);
            drawText(tag_str, op_right_x - tag_width, draw_y, FONT_SIZE, COLOR_TAPE_OP);

            if (entry.is_result) {
                rl.DrawLineEx(
                    .{ .x = x + TAPE_MARGIN + 8, .y = draw_y + FONT_SIZE + 2 },
                    .{ .x = x + w - TAPE_MARGIN - 16, .y = draw_y + FONT_SIZE + 2 },
                    1.0,
                    COLOR_TAPE_TEXT,
                );
            }

            draw_y -= LINE_HEIGHT;
        }
    }

    rl.EndScissorMode();

    // Top shadow for paper effect
    rl.DrawRectangleGradientV(
        @intFromFloat(x + 8),
        @intFromFloat(y + 8),
        @intFromFloat(w - 16),
        20,
        rl.Color{ .r = 200, .g = 200, .b = 195, .a = 100 },
        rl.Color{ .r = 255, .g = 255, .b = 250, .a = 0 },
    );
}

fn drawInputLine(x: f32, y: f32, w: f32, h: f32, text: []const u8) void {
    rl.DrawRectangleRec(.{ .x = x + 8, .y = y, .width = w - 16, .height = h }, COLOR_INPUT_BG);

    if (text.len > 0) {
        const tw = measureText(toC(text), FONT_SIZE);
        const tx = x + w - TAPE_MARGIN - 24 - tw;
        drawText(toC(text), tx, y + (h - FONT_SIZE) / 2, FONT_SIZE, COLOR_INPUT_TEXT);
    } else {
        const tw = measureText("0", FONT_SIZE);
        const tx = x + w - TAPE_MARGIN - 24 - tw;
        drawText("0", tx, y + (h - FONT_SIZE) / 2, FONT_SIZE, rl.Color{ .r = 120, .g = 160, .b = 120, .a = 255 });
    }
}

fn drawKeyboard(x: f32, y: f32, w: f32, h: f32, kb: *const keyboard.Keyboard) void {
    const rows: f32 = @floatFromInt(keyboard.ROWS);
    const btn_h = (h - 8) / rows;
    const mouse = rl.GetMousePosition();
    const pressed = rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT);

    for (0..keyboard.ROWS) |ri| {
        const cols: f32 = @floatFromInt(keyboard.COLS);
        const btn_w = (w - 16) / cols;

        for (0..keyboard.COLS) |ci| {
            const btn = kb.getBtn(ri, ci);
            const bx = x + 8 + @as(f32, @floatFromInt(ci)) * btn_w + 2;
            const by = y + 4 + @as(f32, @floatFromInt(ri)) * btn_h + 2;
            const bw = btn_w - 4;
            const bh = btn_h - 4;

            const rect = rl.Rectangle{ .x = bx, .y = by, .width = bw, .height = bh };
            const hovered = rl.CheckCollisionPointRec(mouse, rect);

            const base_color = btnColor(btn.style);
            const is_pressed = (pressed_row == ri and pressed_col == ci) or (hovered and pressed);
            const color = if (is_pressed) darken(base_color) else if (hovered) brighten(base_color) else base_color;

            rl.DrawRectangleRounded(rect, 0.2, 4, color);

            const label = btn.label;
            const tw = measureText(toC(label), FONT_SIZE);
            const tx = bx + (bw - tw) / 2;
            const ty = by + (bh - FONT_SIZE) / 2;
            drawText(toC(label), tx, ty, FONT_SIZE, COLOR_BTN_TEXT);
        }
    }
}

fn btnColor(style: keyboard.BtnStyle) rl.Color {
    return switch (style) {
        .normal => COLOR_BTN,
        .operator => COLOR_BTN_OP,
        .equals => COLOR_BTN_EQ,
        .clear => COLOR_BTN_CLEAR,
        .function => COLOR_BTN_FN,
    };
}

fn brighten(c: rl.Color) rl.Color {
    return .{
        .r = @min(255, c.r + 20),
        .g = @min(255, c.g + 20),
        .b = @min(255, c.b + 20),
        .a = c.a,
    };
}

fn darken(c: rl.Color) rl.Color {
    return .{
        .r = c.r -| 40,
        .g = c.g -| 40,
        .b = c.b -| 40,
        .a = c.a,
    };
}

/// Convert a Zig slice to a C string pointer (using rotating static buffers).
var c_str_bufs: [4][256]u8 = undefined;
var c_str_idx: usize = 0;
fn toC(text: []const u8) [*c]const u8 {
    const idx = c_str_idx;
    c_str_idx = (c_str_idx + 1) % 4;
    const len = @min(text.len, c_str_bufs[idx].len - 1);
    @memcpy(c_str_bufs[idx][0..len], text[0..len]);
    c_str_bufs[idx][len] = 0;
    return &c_str_bufs[idx];
}

fn drawText(text: [*c]const u8, x: f32, y: f32, size: f32, color: rl.Color) void {
    rl.DrawTextEx(font, text, .{ .x = x, .y = y }, size, 1, color);
}

fn measureText(text: [*c]const u8, size: f32) f32 {
    return rl.MeasureTextEx(font, text, size, 1).x;
}

fn setPressedFromAction(action: keyboard.Action, kb: *const keyboard.Keyboard) void {
    for (0..keyboard.ROWS) |ri| {
        for (0..keyboard.COLS) |ci| {
            if (std.meta.eql(kb.getBtn(ri, ci).action, action)) {
                pressed_row = ri;
                pressed_col = ci;
                press_timer = PRESS_FRAMES;
                return;
            }
        }
    }
}

// ── Input Processing ───────────────────────────────────────

fn processAction(
    action: keyboard.Action,
    engine: *calc.CalcEngine,
    fin: *calc.FinRegisters,
    t: *tape.Tape,
    input_buf: *[64]u8,
    input_len: *usize,
    decimal_places: u8,
    kb: *keyboard.Keyboard,
    dp_ptr: *u8,
) void {
    switch (action) {
        .digit => |d| {
            if (input_len.* < 63) {
                input_buf[input_len.*] = d;
                input_len.* += 1;
            }
        },
        .dot => {
            const slice = input_buf[0..input_len.*];
            var has_dot = false;
            for (slice) |c| {
                if (c == '.') {
                    has_dot = true;
                    break;
                }
            }
            if (!has_dot and input_len.* < 63) {
                input_buf[input_len.*] = '.';
                input_len.* += 1;
            }
        },
        .negate => {
            if (input_len.* > 0 and input_buf[0] == '-') {
                std.mem.copyForwards(u8, input_buf[0 .. input_len.* - 1], input_buf[1..input_len.*]);
                input_len.* -= 1;
            } else if (input_len.* < 63) {
                std.mem.copyBackwards(u8, input_buf[1 .. input_len.* + 1], input_buf[0..input_len.*]);
                input_buf[0] = '-';
                input_len.* += 1;
            }
        },
        .operator => |op| {
            if (input_len.* > 0) {
                const val = number.Decimal.parse(input_buf[0..input_len.*], decimal_places);
                t.addEntry(.{ .value = val, .operator = engine.pending_op, .is_result = false });
                engine.pushValue(val, decimal_places);
                input_len.* = 0;
            }
            engine.setOp(op);
        },
        .equals => {
            if (input_len.* > 0) {
                const val = number.Decimal.parse(input_buf[0..input_len.*], decimal_places);
                t.addEntry(.{ .value = val, .operator = engine.pending_op, .is_result = false });
                engine.pushValue(val, decimal_places);
                input_len.* = 0;
            }
            const result = engine.compute(decimal_places);
            t.addEntry(.{ .value = result, .operator = .equals, .is_result = true });
            engine.reset();
            engine.pushValue(result, decimal_places);
        },
        .clear => {
            engine.reset();
            fin.clear();
            input_len.* = 0;
        },
        .clear_entry => {
            input_len.* = 0;
        },
        .backspace => {
            if (input_len.* > 0) {
                input_len.* -= 1;
            }
        },
        .fin_toggle => {
            kb.fin_mode = !kb.fin_mode;
        },
        .decimal_places_up => {
            if (dp_ptr.* < 8) dp_ptr.* += 1;
        },
        .decimal_places_down => {
            if (dp_ptr.* > 0) dp_ptr.* -= 1;
        },
        .percent => {
            if (input_len.* > 0) {
                var val = number.Decimal.parse(input_buf[0..input_len.*], decimal_places);
                val = engine.applyPercent(val, decimal_places);
                t.addEntry(.{ .value = val, .operator = engine.pending_op, .is_result = false });
                engine.pushValue(val, decimal_places);
                input_len.* = 0;
            }
        },
        .fin_reg => |reg| {
            const reg_label: []const u8 = switch (reg) {
                .pv => "PV",
                .fv => "FV",
                .n => "n",
                .i => "i",
                .pmt => "PMT",
            };

            if (input_len.* > 0) {
                // Store value in register
                const val = number.Decimal.parse(input_buf[0..input_len.*], decimal_places);
                fin.set(reg, val.toF64());
                t.addEntry(.{ .value = val, .operator = null, .is_result = false, .label = reg_label });
                input_len.* = 0;
            } else {
                // Try to solve
                if (fin.solve()) |result| {
                    const result_label: []const u8 = switch (result.reg) {
                        .pv => "PV",
                        .fv => "FV",
                        .n => "n",
                        .i => "i",
                        .pmt => "PMT",
                    };
                    const result_dec = number.Decimal.fromF64(result.val, decimal_places);
                    t.addEntry(.{ .value = result_dec, .operator = null, .is_result = true, .label = result_label });
                    engine.reset();
                    engine.pushValue(result_dec, decimal_places);
                }
            }
        },
        .fin_markup => {
            // Markup: need cost in input, margin in accumulator (or vice versa)
            // Use: cost in accumulator, margin in input
            if (input_len.* > 0 and engine.has_value) {
                const margin_dec = number.Decimal.parse(input_buf[0..input_len.*], decimal_places);
                const margin = margin_dec.toF64();
                const cost = engine.accumulator.toF64();
                const price = calc.FinRegisters.markup(cost, margin);
                const price_dec = number.Decimal.fromF64(price, decimal_places);
                t.addEntry(.{ .value = margin_dec, .operator = null, .is_result = false, .label = "MU%" });
                t.addEntry(.{ .value = price_dec, .operator = null, .is_result = true, .label = "MU" });
                engine.reset();
                engine.pushValue(price_dec, decimal_places);
                input_len.* = 0;
            }
        },
    }
}

fn handlePhysicalKey() ?keyboard.Action {
    const key = rl.GetKeyPressed();
    if (key == 0) return null;

    return switch (key) {
        rl.KEY_ZERO, rl.KEY_KP_0 => .{ .digit = '0' },
        rl.KEY_ONE, rl.KEY_KP_1 => .{ .digit = '1' },
        rl.KEY_TWO, rl.KEY_KP_2 => .{ .digit = '2' },
        rl.KEY_THREE, rl.KEY_KP_3 => .{ .digit = '3' },
        rl.KEY_FOUR, rl.KEY_KP_4 => .{ .digit = '4' },
        rl.KEY_FIVE, rl.KEY_KP_5 => .{ .digit = '5' },
        rl.KEY_SIX, rl.KEY_KP_6 => .{ .digit = '6' },
        rl.KEY_SEVEN, rl.KEY_KP_7 => .{ .digit = '7' },
        rl.KEY_EIGHT, rl.KEY_KP_8 => .{ .digit = '8' },
        rl.KEY_NINE, rl.KEY_KP_9 => .{ .digit = '9' },
        rl.KEY_PERIOD, rl.KEY_KP_DECIMAL => .dot,
        rl.KEY_KP_ADD => .{ .operator = .add },
        rl.KEY_KP_SUBTRACT, rl.KEY_MINUS => .{ .operator = .sub },
        rl.KEY_KP_MULTIPLY => .{ .operator = .mul },
        rl.KEY_KP_DIVIDE, rl.KEY_SLASH => .{ .operator = .div },
        rl.KEY_ENTER, rl.KEY_KP_ENTER, rl.KEY_EQUAL => .equals,
        rl.KEY_BACKSPACE => .backspace,
        rl.KEY_ESCAPE => .clear,
        rl.KEY_DELETE => .clear_entry,
        else => null,
    };
}
