const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");
const build_options = @import("build_options");

const number = @import("number.zig");
const tape = @import("tape.zig");
const calc = @import("calc.zig");
const keyboard = @import("keyboard.zig");

// Layout
const WINDOW_W = 420;
const WINDOW_H = 900;

const font_data = @embedFile("JetBrainsMono-Regular.ttf");
const icon_data = @embedFile("icon.png");

// Button press feedback
var pressed_row: ?usize = null;
var pressed_col: ?usize = null;
var press_timer: u8 = 0;
const PRESS_FRAMES: u8 = 6;

// Fonts (different sizes)
var font_tape: rl.Font = undefined;
var font_input: rl.Font = undefined;
var font_btn: rl.Font = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(WINDOW_W, WINDOW_H, build_options.app_name ++ "  v" ++ build_options.version);
    defer rl.closeWindow();

    // Window icon
    const icon = rl.loadImageFromMemory(".png", icon_data) catch unreachable;
    rl.setWindowIcon(icon);
    rl.unloadImage(icon);

    rl.setTargetFPS(60);

    // Load fonts at different sizes
    font_tape = rl.loadFontFromMemory(".ttf", font_data, 20, null) catch unreachable;
    font_input = rl.loadFontFromMemory(".ttf", font_data, 22, null) catch unreachable;
    font_btn = rl.loadFontFromMemory(".ttf", font_data, 16, null) catch unreachable;
    defer rl.unloadFont(font_tape);
    defer rl.unloadFont(font_input);
    defer rl.unloadFont(font_btn);

    // Set raygui font and style
    gui.setFont(font_btn);
    gui.setStyle(.default, .{ .default = .text_size }, 16);
    gui.setStyle(.default, .{ .default = .text_spacing }, 1);
    gui.setStyle(.default, .{ .default = .background_color }, colorToInt(.{ .r = 60, .g = 60, .b = 65, .a = 255 }));

    var t = tape.Tape.init(allocator);
    defer t.deinit();

    var engine = calc.CalcEngine.init();
    var fin = calc.FinRegisters.init();
    var kb = keyboard.Keyboard.init();
    var input_buf: [64]u8 = undefined;
    var input_len: usize = 0;
    var decimal_places: u8 = 2;
    var scroll_to_bottom = false;

    // Tape scroll state
    var tape_scroll = rl.Vector2{ .x = 0, .y = 0 };

    while (!rl.windowShouldClose()) {
        // Tick press timer
        if (press_timer > 0) {
            press_timer -= 1;
            if (press_timer == 0) {
                pressed_row = null;
                pressed_col = null;
            }
        }

        // Physical keyboard
        // Clipboard: Ctrl+V paste, Ctrl+C copy
        if (rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control)) {
            if (rl.isKeyPressed(.v)) {
                const clip = rl.getClipboardText();
                if (clip.len > 0) {
                    const len = number.Decimal.parsePaste(clip, &input_buf);
                    if (len > 0) input_len = len;
                }
            }
            if (rl.isKeyPressed(.c)) {
                if (input_len > 0) {
                    rl.setClipboardText(toSentinel(input_buf[0..input_len]));
                } else if (engine.has_value) {
                    var fmt_buf: [128]u8 = undefined;
                    const formatted = engine.accumulator.format(&fmt_buf);
                    rl.setClipboardText(toSentinel(formatted));
                }
            }
        }

        if (handlePhysicalKey()) |action| {
            setPressedFromAction(action, &kb);
            const prev_count = t.entries.items.len;
            processAction(action, &engine, &fin, &t, &input_buf, &input_len, decimal_places, &kb, &decimal_places);
            if (t.entries.items.len > prev_count) scroll_to_bottom = true;
        }

        rl.beginDrawing();
        rl.clearBackground(.{ .r = 60, .g = 60, .b = 65, .a = 255 });

        const win_w: f32 = @floatFromInt(rl.getScreenWidth());
        const win_h: f32 = @floatFromInt(rl.getScreenHeight());

        // Calculate layout
        const kb_rows: f32 = @floatFromInt(keyboard.ROWS);
        const btn_h: f32 = 34;
        const kb_h = btn_h * kb_rows + 12;
        const input_h: f32 = 40;
        const tape_h = win_h - kb_h - input_h;

        drawTapeArea(win_w, tape_h, &t, &scroll_to_bottom, &tape_scroll);
        drawInputLine(win_w, tape_h, input_h, input_buf[0..input_len]);
        drawKeyboard(win_w, tape_h + input_h, kb_h, &kb, &engine, &fin, &t, &input_buf, &input_len, decimal_places, &decimal_places, &scroll_to_bottom);

        // Subtle border around tape area (drawn last so nothing covers it)
        rl.drawRectangleLinesEx(.{ .x = 0, .y = 0, .width = win_w, .height = tape_h }, 1, .{ .r = 100, .g = 100, .b = 95, .a = 200 });

        rl.endDrawing();
    }
}

// ── Color Helpers ───────────────────────────────────────

fn colorToInt(c: rl.Color) i32 {
    return @as(i32, @bitCast(@as(u32, c.r) | (@as(u32, c.g) << 8) | (@as(u32, c.b) << 16) | (@as(u32, c.a) << 24)));
}

fn brighten(c: rl.Color, amount: u8) rl.Color {
    return .{
        .r = c.r +| amount,
        .g = c.g +| amount,
        .b = c.b +| amount,
        .a = c.a,
    };
}

fn darken(c: rl.Color, amount: u8) rl.Color {
    return .{
        .r = c.r -| amount,
        .g = c.g -| amount,
        .b = c.b -| amount,
        .a = c.a,
    };
}

// ── Tape Area ───────────────────────────────────────────

fn drawTapeArea(win_w: f32, tape_h: f32, t: *tape.Tape, scroll_to_bottom: *bool, tape_scroll: *rl.Vector2) void {
    const tape_rect = rl.Rectangle{ .x = 0, .y = 0, .width = win_w, .height = tape_h };

    // Paper background
    rl.drawRectangleRec(tape_rect, .{ .r = 255, .g = 251, .b = 250, .a = 255 });

    // Calculate content height
    const line_h: f32 = 24;
    const padding: f32 = 8;
    const entries = t.entries.items;
    var content_h: f32 = padding;
    for (entries) |entry| {
        content_h += line_h;
        if (entry.is_result) content_h += 2; // separator
    }
    content_h += padding;

    // Auto-scroll to bottom when new entry added
    if (scroll_to_bottom.*) {
        const max_scroll = @max(content_h - tape_h, 0);
        tape_scroll.y = -max_scroll;
        scroll_to_bottom.* = false;
    }

    // Mouse wheel scroll (only when mouse is in tape area)
    const mouse_pos = rl.getMousePosition();
    if (rl.checkCollisionPointRec(mouse_pos, tape_rect)) {
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            tape_scroll.y += wheel * 30;
            // Clamp scroll
            const max_scroll = @max(content_h - tape_h, 0);
            tape_scroll.y = @min(tape_scroll.y, 0);
            tape_scroll.y = @max(tape_scroll.y, -max_scroll);
        }
    }

    // Clip to tape area
    rl.beginScissorMode(@intFromFloat(0), @intFromFloat(0), @intFromFloat(win_w), @intFromFloat(tape_h));

    // Draw entries — aligned to bottom (paper tape grows upward)
    const start_y = if (content_h < tape_h) tape_h - content_h else 0;
    var y: f32 = start_y + padding + tape_scroll.y;
    for (entries) |entry| {
        if (y + line_h >= -line_h and y <= tape_h + line_h) {
            var fmt_buf: [128]u8 = undefined;
            const val_str = entry.value.format(&fmt_buf);

            const tag_str: []const u8 = if (entry.label) |lbl|
                lbl
            else if (entry.operator) |op| switch (op) {
                .add => "+",
                .sub => "-",
                .mul => "x",
                .div => "/",
                .equals => "=",
            } else " ";

            // Measure text
            const val_size = rl.measureTextEx(font_tape, toSentinel(val_str), 20, 1);
            const tag_size = rl.measureTextEx(font_tape, toSentinel(tag_str), 20, 1);

            // Right-align: value + gap + tag
            const val_x = win_w - 16 - tag_size.x - 8 - val_size.x;

            const val_color: rl.Color = if (entry.is_result) .{ .r = 10, .g = 10, .b = 10, .a = 255 } else .{ .r = 30, .g = 30, .b = 30, .a = 255 };
            rl.drawTextEx(font_tape, toSentinel(val_str), .{ .x = val_x, .y = y }, 20, 1, val_color);
            rl.drawTextEx(font_tape, toSentinel(tag_str), .{ .x = win_w - 16 - tag_size.x, .y = y }, 20, 1, .{ .r = 120, .g = 120, .b = 126, .a = 255 });

            if (entry.is_result) {
                rl.drawLine(@intFromFloat(8), @intFromFloat(y + line_h - 2), @intFromFloat(win_w - 8), @intFromFloat(y + line_h - 2), .{ .r = 200, .g = 200, .b = 200, .a = 255 });
            }
        }
        y += line_h;
        if (entry.is_result) y += 2;
    }

    rl.endScissorMode();

    // Shadow gradient at top (draw over content)
    const shadow_h: i32 = 20;
    var si: i32 = 0;
    while (si < shadow_h) : (si += 1) {
        const alpha: u8 = @intFromFloat(100.0 * (1.0 - @as(f32, @floatFromInt(si)) / @as(f32, @floatFromInt(shadow_h))));
        rl.drawLine(0, si, @intFromFloat(win_w), si, .{ .r = 200, .g = 200, .b = 195, .a = alpha });
    }

    // Scrollbar indicator (simple)
    if (content_h > tape_h) {
        const bar_h = @max(tape_h * tape_h / content_h, 20);
        const max_scroll = content_h - tape_h;
        const scroll_ratio = if (max_scroll > 0) -tape_scroll.y / max_scroll else 0;
        const bar_y = scroll_ratio * (tape_h - bar_h);
        rl.drawRectangleRounded(.{ .x = win_w - 6, .y = bar_y, .width = 4, .height = bar_h }, 1.0, 4, .{ .r = 160, .g = 160, .b = 165, .a = 150 });
    }

}

// ── Input Line ──────────────────────────────────────────

fn drawInputLine(win_w: f32, y: f32, h: f32, text: []const u8) void {
    // Background
    rl.drawRectangleRec(.{ .x = 0, .y = y, .width = win_w, .height = h }, .{ .r = 45, .g = 45, .b = 50, .a = 255 });

    const display_text: []const u8 = if (text.len > 0) text else "0";
    const text_color: rl.Color = if (text.len > 0) .{ .r = 220, .g = 255, .b = 220, .a = 255 } else .{ .r = 120, .g = 160, .b = 120, .a = 255 };

    const text_size = rl.measureTextEx(font_input, toSentinel(display_text), 22, 1);
    const text_x = win_w - text_size.x - 12;
    const text_y = y + (h - text_size.y) / 2.0;
    rl.drawTextEx(font_input, toSentinel(display_text), .{ .x = text_x, .y = text_y }, 22, 1, text_color);
}

// ── Keyboard ────────────────────────────────────────────

fn drawKeyboard(
    win_w: f32,
    y: f32,
    h: f32,
    kb: *keyboard.Keyboard,
    engine: *calc.CalcEngine,
    fin: *calc.FinRegisters,
    t: *tape.Tape,
    input_buf: *[64]u8,
    input_len: *usize,
    decimal_places: u8,
    dp_ptr: *u8,
    scroll_to_bottom: *bool,
) void {
    const cols: f32 = @floatFromInt(keyboard.COLS);
    const rows: f32 = @floatFromInt(keyboard.ROWS);
    const gap: f32 = 4;
    const pad: f32 = 6;
    const btn_w = (win_w - pad * 2 - (cols - 1) * gap) / cols;
    const btn_h = (h - pad * 2 - (rows - 1) * gap) / rows;

    for (0..keyboard.ROWS) |ri| {
        for (0..keyboard.COLS) |ci| {
            const btn = kb.getBtn(ri, ci);
            const is_pressed = (pressed_row == ri and pressed_col == ci);

            const bx = pad + @as(f32, @floatFromInt(ci)) * (btn_w + gap);
            const by = y + pad + @as(f32, @floatFromInt(ri)) * (btn_h + gap);
            const rect = rl.Rectangle{ .x = bx, .y = by, .width = btn_w, .height = btn_h };

            // Button colors based on style
            const base = btnStyleColor(btn.style);
            const mouse_pos = rl.getMousePosition();
            const hovered = rl.checkCollisionPointRec(mouse_pos, rect);

            const color = if (is_pressed)
                darken(base, 40)
            else if (hovered)
                brighten(base, 20)
            else
                base;

            // Draw button
            rl.drawRectangleRounded(rect, 0.3, 4, color);

            // Button text (centered)
            const label_str = toSentinel(btn.label);
            const text_size = rl.measureTextEx(font_btn, label_str, 16, 1);
            const tx = bx + (btn_w - text_size.x) / 2.0;
            const ty = by + (btn_h - text_size.y) / 2.0;
            rl.drawTextEx(font_btn, label_str, .{ .x = tx, .y = ty }, 16, 1, .{ .r = 240, .g = 240, .b = 240, .a = 255 });

            // Click detection
            if (hovered and rl.isMouseButtonPressed(.left)) {
                setPressedFromAction(btn.action, kb);
                const prev_count = t.entries.items.len;
                processAction(btn.action, engine, fin, t, input_buf, input_len, decimal_places, kb, dp_ptr);
                if (t.entries.items.len > prev_count) scroll_to_bottom.* = true;
            }
        }
    }
}

fn btnStyleColor(style: keyboard.BtnStyle) rl.Color {
    return switch (style) {
        .normal => .{ .r = 85, .g = 85, .b = 90, .a = 255 },
        .operator => .{ .r = 180, .g = 120, .b = 50, .a = 255 },
        .equals => .{ .r = 60, .g = 140, .b = 80, .a = 255 },
        .clear => .{ .r = 160, .g = 60, .b = 60, .a = 255 },
        .function => .{ .r = 70, .g = 100, .b = 140, .a = 255 },
    };
}

// ── Helpers ─────────────────────────────────────────────

var c_str_bufs: [4][256]u8 = undefined;
var c_str_idx: usize = 0;
fn toSentinel(text: []const u8) [:0]const u8 {
    const idx = c_str_idx;
    c_str_idx = (c_str_idx + 1) % 4;
    const len = @min(text.len, c_str_bufs[idx].len - 1);
    @memcpy(c_str_bufs[idx][0..len], text[0..len]);
    c_str_bufs[idx][len] = 0;
    return c_str_bufs[idx][0..len :0];
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

// ── Input Processing ────────────────────────────────────

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
                const val = number.Decimal.parse(input_buf[0..input_len.*], decimal_places);
                fin.set(reg, val.toF64());
                t.addEntry(.{ .value = val, .operator = null, .is_result = false, .label = reg_label });
                input_len.* = 0;
            } else {
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
    const key = rl.getKeyPressed();
    if (key == .null) return null;

    return switch (key) {
        .zero, .kp_0 => .{ .digit = '0' },
        .one, .kp_1 => .{ .digit = '1' },
        .two, .kp_2 => .{ .digit = '2' },
        .three, .kp_3 => .{ .digit = '3' },
        .four, .kp_4 => .{ .digit = '4' },
        .five, .kp_5 => .{ .digit = '5' },
        .six, .kp_6 => .{ .digit = '6' },
        .seven, .kp_7 => .{ .digit = '7' },
        .eight, .kp_8 => .{ .digit = '8' },
        .nine, .kp_9 => .{ .digit = '9' },
        .period, .kp_decimal => .dot,
        .kp_add => .{ .operator = .add },
        .kp_subtract, .minus => .{ .operator = .sub },
        .kp_multiply => .{ .operator = .mul },
        .kp_divide, .slash => .{ .operator = .div },
        .enter, .kp_enter, .equal => .equals,
        .backspace => .backspace,
        .escape => .clear,
        .delete => .clear_entry,
        else => null,
    };
}
