const std = @import("std");
const build_options = @import("build_options");
const number = @import("number.zig");
const tape = @import("tape.zig");
const calc = @import("calc.zig");
const keyboard = @import("keyboard.zig");

const gtk = @cImport({
    @cInclude("gtk/gtk.h");
});

// ── Global state (needed for GTK C callbacks) ──────────────
var engine: calc.CalcEngine = undefined;
var fin: calc.FinRegisters = undefined;
var kb: keyboard.Keyboard = undefined;
var input_buf: [64]u8 = undefined;
var input_len: usize = 0;
var decimal_places: u8 = 2;
var t: tape.Tape = undefined;
var allocator: std.mem.Allocator = undefined;

// GTK widgets we need to update
var input_label: *gtk.GtkWidget = undefined;
var tape_box: *gtk.GtkWidget = undefined;
var tape_scroll: *gtk.GtkWidget = undefined;
var btn_widgets: [keyboard.ROWS][keyboard.COLS]*gtk.GtkWidget = undefined;

// ── Entry point ────────────────────────────────────────────
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    t = tape.Tape.init(allocator);
    defer t.deinit();

    engine = calc.CalcEngine.init();
    fin = calc.FinRegisters.init();
    kb = keyboard.Keyboard.init();
    input_len = 0;
    decimal_places = 2;

    const app = gtk.gtk_application_new("com.finc.calculator", gtk.G_APPLICATION_DEFAULT_FLAGS);
    defer gtk.g_object_unref(app);

    _ = g_signal_connect(app, "activate", &onActivate, null);

    const status = gtk.g_application_run(@ptrCast(app), 0, null);
    std.process.exit(@intCast(status));
}

// ── Application activate ───────────────────────────────────
fn onActivate(app: *gtk.GtkApplication, _: gtk.gpointer) callconv(.c) void {
    const window = gtk.gtk_application_window_new(app);
    gtk.gtk_window_set_title(@ptrCast(window), build_options.app_name ++ "  v" ++ build_options.version);
    gtk.gtk_window_set_default_size(@ptrCast(window), 420, 900);

    gtk.gtk_window_set_icon_name(@ptrCast(window), "fin-c");

    // CSS styling
    loadCss();

    // Main vertical layout
    const vbox = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 0);
    gtk.gtk_window_set_child(@ptrCast(window), vbox);

    // 1. Tape area (scrolled)
    tape_scroll = gtk.gtk_scrolled_window_new();
    gtk.gtk_scrolled_window_set_policy(@ptrCast(tape_scroll), gtk.GTK_POLICY_NEVER, gtk.GTK_POLICY_AUTOMATIC);
    gtk.gtk_widget_set_vexpand(tape_scroll, 1);
    gtk.gtk_widget_add_css_class(tape_scroll, "tape-scroll");
    gtk.gtk_box_append(@ptrCast(vbox), tape_scroll);

    tape_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 0);
    gtk.gtk_widget_set_halign(tape_box, gtk.GTK_ALIGN_FILL);
    gtk.gtk_widget_set_valign(tape_box, gtk.GTK_ALIGN_END);
    gtk.gtk_widget_set_vexpand(tape_box, 1);
    gtk.gtk_widget_add_css_class(tape_box, "tape-box");
    gtk.gtk_scrolled_window_set_child(@ptrCast(tape_scroll), tape_box);

    // 2. Input line
    input_label = gtk.gtk_label_new("0");
    gtk.gtk_widget_set_halign(input_label, gtk.GTK_ALIGN_FILL);
    gtk.gtk_label_set_xalign(@ptrCast(input_label), 1.0);
    gtk.gtk_widget_add_css_class(input_label, "input-line");
    gtk.gtk_box_append(@ptrCast(vbox), input_label);

    // 3. Keyboard grid — compact, no vertical expand
    const grid = gtk.gtk_grid_new();
    gtk.gtk_grid_set_row_homogeneous(@ptrCast(grid), 1);
    gtk.gtk_grid_set_column_homogeneous(@ptrCast(grid), 1);
    gtk.gtk_grid_set_row_spacing(@ptrCast(grid), 2);
    gtk.gtk_grid_set_column_spacing(@ptrCast(grid), 4);
    gtk.gtk_widget_set_vexpand(grid, 0);
    gtk.gtk_widget_add_css_class(grid, "keyboard");
    gtk.gtk_box_append(@ptrCast(vbox), grid);

    for (0..keyboard.ROWS) |ri| {
        for (0..keyboard.COLS) |ci| {
            const btn_def = kb.getBtn(ri, ci);
            const button = gtk.gtk_button_new_with_label(toC(btn_def.label));
            applyBtnCss(button, btn_def.style);
            gtk.gtk_grid_attach(@ptrCast(grid), button, @intCast(ci), @intCast(ri), 1, 1);
            gtk.gtk_widget_set_hexpand(button, 1);
            btn_widgets[ri][ci] = button;

            // Encode row/col into user_data pointer
            const data: usize = ri * keyboard.COLS + ci;
            _ = g_signal_connect(button, "clicked", &onButtonClicked, @ptrFromInt(data));
        }
    }

    // Keyboard event controller
    const key_ctrl = gtk.gtk_event_controller_key_new();
    gtk.gtk_widget_add_controller(
        @as(*gtk.GtkWidget, @ptrCast(window)),
        @ptrCast(key_ctrl),
    );
    _ = g_signal_connect(key_ctrl, "key-pressed", &onKeyPressed, @as(?*anyopaque, @ptrCast(window)));

    // Scroll controller for tape
    const scroll_ctrl = gtk.gtk_event_controller_scroll_new(
        gtk.GTK_EVENT_CONTROLLER_SCROLL_VERTICAL,
    );
    gtk.gtk_widget_add_controller(tape_scroll, @ptrCast(scroll_ctrl));

    gtk.gtk_window_present(@ptrCast(window));
}

// ── CSS ────────────────────────────────────────────────────
fn loadCss() void {
    const css =
        \\window { background-color: #3c3c41; }
        \\.tape-scroll { margin: 8px 8px 0 8px; background-color: #fffbfa; border-radius: 4px; }
        \\.tape-box { padding: 8px 16px; }
        \\.tape-entry { font-family: "JetBrains Mono", monospace; font-size: 15px; color: #1e1e1e; min-height: 28px; }
        \\.tape-entry-value { }
        \\.tape-entry-op { color: #78787e; margin-left: 8px; }
        \\.tape-entry-result { font-weight: bold; border-bottom: 1px solid #1e1e1e; }
        \\.input-line { font-family: "JetBrains Mono", monospace; font-size: 18px; color: #dcffdc;
        \\  background-color: #2d2d32; padding: 10px 24px 10px 16px; margin: 0 8px; }
        \\.keyboard { padding: 2px 8px 4px 8px; }
        \\.keyboard button { font-family: "JetBrains Mono", monospace; font-size: 14px;
        \\  color: #f0f0f0; border: none; border-radius: 6px; min-height: 28px; padding: 4px 0; }
        \\.btn-normal { background-color: #55555a; }
        \\.btn-normal:hover { background-color: #65656a; }
        \\.btn-operator { background-color: #b47832; }
        \\.btn-operator:hover { background-color: #c48842; }
        \\.btn-equals { background-color: #3c8c50; }
        \\.btn-equals:hover { background-color: #4c9c60; }
        \\.btn-clear { background-color: #a03c3c; }
        \\.btn-clear:hover { background-color: #b04c4c; }
        \\.btn-function { background-color: #46648c; }
        \\.btn-function:hover { background-color: #56749c; }
    ;

    const provider = gtk.gtk_css_provider_new();
    gtk.gtk_css_provider_load_from_string(provider, css);
    gtk.gtk_style_context_add_provider_for_display(
        gtk.gdk_display_get_default(),
        @ptrCast(provider),
        gtk.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
}

fn applyBtnCss(button: *gtk.GtkWidget, style: keyboard.BtnStyle) void {
    const class = switch (style) {
        .normal => "btn-normal",
        .operator => "btn-operator",
        .equals => "btn-equals",
        .clear => "btn-clear",
        .function => "btn-function",
    };
    gtk.gtk_widget_add_css_class(button, class);
}

// ── Button click callback ──────────────────────────────────
fn onButtonClicked(_: *gtk.GtkButton, user_data: gtk.gpointer) callconv(.c) void {
    const data: usize = @intFromPtr(user_data);
    const row = data / keyboard.COLS;
    const col = data % keyboard.COLS;
    const action = kb.getBtn(row, col).action;
    processAction(action);
    refreshDisplay();
}

// ── Key press callback ─────────────────────────────────────
fn onKeyPressed(_: *gtk.GtkEventControllerKey, keyval: gtk.guint, _: gtk.guint, state: gtk.GdkModifierType, user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
    const ctrl = (state & gtk.GDK_CONTROL_MASK) != 0;

    // Clipboard: Ctrl+V / Ctrl+C
    if (ctrl and keyval == gtk.GDK_KEY_v) {
        const window: *gtk.GtkWindow = @ptrCast(@alignCast(user_data));
        const display = gtk.gtk_widget_get_display(@as(*gtk.GtkWidget, @ptrCast(window)));
        const clipboard = gtk.gdk_display_get_clipboard(display);
        gtk.gdk_clipboard_read_text_async(clipboard, null, &onPasteReady, null);
        return 1;
    }
    if (ctrl and keyval == gtk.GDK_KEY_c) {
        handleCopy(user_data);
        return 1;
    }

    const action: ?keyboard.Action = mapKey(keyval);
    if (action) |a| {
        processAction(a);
        refreshDisplay();
        return 1;
    }
    return 0;
}

fn mapKey(keyval: gtk.guint) ?keyboard.Action {
    return switch (keyval) {
        gtk.GDK_KEY_0, gtk.GDK_KEY_KP_0 => .{ .digit = '0' },
        gtk.GDK_KEY_1, gtk.GDK_KEY_KP_1 => .{ .digit = '1' },
        gtk.GDK_KEY_2, gtk.GDK_KEY_KP_2 => .{ .digit = '2' },
        gtk.GDK_KEY_3, gtk.GDK_KEY_KP_3 => .{ .digit = '3' },
        gtk.GDK_KEY_4, gtk.GDK_KEY_KP_4 => .{ .digit = '4' },
        gtk.GDK_KEY_5, gtk.GDK_KEY_KP_5 => .{ .digit = '5' },
        gtk.GDK_KEY_6, gtk.GDK_KEY_KP_6 => .{ .digit = '6' },
        gtk.GDK_KEY_7, gtk.GDK_KEY_KP_7 => .{ .digit = '7' },
        gtk.GDK_KEY_8, gtk.GDK_KEY_KP_8 => .{ .digit = '8' },
        gtk.GDK_KEY_9, gtk.GDK_KEY_KP_9 => .{ .digit = '9' },
        gtk.GDK_KEY_period, gtk.GDK_KEY_KP_Decimal, gtk.GDK_KEY_comma => .dot,
        gtk.GDK_KEY_KP_Add => .{ .operator = .add },
        gtk.GDK_KEY_KP_Subtract, gtk.GDK_KEY_minus => .{ .operator = .sub },
        gtk.GDK_KEY_KP_Multiply => .{ .operator = .mul },
        gtk.GDK_KEY_KP_Divide, gtk.GDK_KEY_slash => .{ .operator = .div },
        gtk.GDK_KEY_Return, gtk.GDK_KEY_KP_Enter, gtk.GDK_KEY_equal => .equals,
        gtk.GDK_KEY_BackSpace => .backspace,
        gtk.GDK_KEY_Escape => .clear,
        gtk.GDK_KEY_Delete => .clear_entry,
        else => null,
    };
}

// ── Clipboard ──────────────────────────────────────────────
fn onPasteReady(source: ?*gtk.GObject, result: ?*gtk.GAsyncResult, _: gtk.gpointer) callconv(.c) void {
    const text = gtk.gdk_clipboard_read_text_finish(
        @ptrCast(@alignCast(source)),
        result,
        null,
    );
    if (text) |txt| {
        const clip_str = std.mem.span(txt);
        if (clip_str.len > 0) {
            const len = number.Decimal.parsePaste(clip_str, &input_buf);
            if (len > 0) input_len = len;
            refreshDisplay();
        }
        gtk.g_free(txt);
    }
}

fn handleCopy(user_data: gtk.gpointer) void {
    var copy_buf: [128]u8 = undefined;
    var text: []const u8 = undefined;

    if (input_len > 0) {
        text = input_buf[0..input_len];
    } else if (engine.has_value) {
        text = engine.accumulator.format(&copy_buf);
    } else {
        return;
    }

    const window: *gtk.GtkWindow = @ptrCast(@alignCast(user_data));
    const display = gtk.gtk_widget_get_display(@as(*gtk.GtkWidget, @ptrCast(window)));
    const clipboard = gtk.gdk_display_get_clipboard(display);
    gtk.gdk_clipboard_set_text(clipboard, toC(text));
}

// ── Process action (shared logic with raylib version) ──────
fn processAction(action: keyboard.Action) void {
    switch (action) {
        .digit => |d| {
            if (input_len < 63) {
                input_buf[input_len] = d;
                input_len += 1;
            }
        },
        .dot => {
            const slice = input_buf[0..input_len];
            var has_dot = false;
            for (slice) |c| {
                if (c == '.') {
                    has_dot = true;
                    break;
                }
            }
            if (!has_dot and input_len < 63) {
                input_buf[input_len] = '.';
                input_len += 1;
            }
        },
        .negate => {
            if (input_len > 0 and input_buf[0] == '-') {
                std.mem.copyForwards(u8, input_buf[0 .. input_len - 1], input_buf[1..input_len]);
                input_len -= 1;
            } else if (input_len < 63) {
                std.mem.copyBackwards(u8, input_buf[1 .. input_len + 1], input_buf[0..input_len]);
                input_buf[0] = '-';
                input_len += 1;
            }
        },
        .operator => |op| {
            if (input_len > 0) {
                const val = number.Decimal.parse(input_buf[0..input_len], decimal_places);
                t.addEntry(.{ .value = val, .operator = engine.pending_op, .is_result = false });
                engine.pushValue(val, decimal_places);
                input_len = 0;
            }
            engine.setOp(op);
        },
        .equals => {
            if (input_len > 0) {
                const val = number.Decimal.parse(input_buf[0..input_len], decimal_places);
                t.addEntry(.{ .value = val, .operator = engine.pending_op, .is_result = false });
                engine.pushValue(val, decimal_places);
                input_len = 0;
            }
            const result = engine.compute(decimal_places);
            t.addEntry(.{ .value = result, .operator = .equals, .is_result = true });
            engine.reset();
            engine.pushValue(result, decimal_places);
        },
        .clear => {
            engine.reset();
            fin.clear();
            input_len = 0;
        },
        .clear_entry => {
            input_len = 0;
        },
        .backspace => {
            if (input_len > 0) input_len -= 1;
        },
        .fin_toggle => {
            kb.fin_mode = !kb.fin_mode;
            refreshButtons();
        },
        .decimal_places_up => {
            if (decimal_places < 8) decimal_places += 1;
        },
        .decimal_places_down => {
            if (decimal_places > 0) decimal_places -= 1;
        },
        .percent => {
            if (input_len > 0) {
                var val = number.Decimal.parse(input_buf[0..input_len], decimal_places);
                val = engine.applyPercent(val, decimal_places);
                t.addEntry(.{ .value = val, .operator = engine.pending_op, .is_result = false });
                engine.pushValue(val, decimal_places);
                input_len = 0;
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
            if (input_len > 0) {
                const val = number.Decimal.parse(input_buf[0..input_len], decimal_places);
                fin.set(reg, val.toF64());
                t.addEntry(.{ .value = val, .operator = null, .is_result = false, .label = reg_label });
                input_len = 0;
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
            if (input_len > 0 and engine.has_value) {
                const margin_dec = number.Decimal.parse(input_buf[0..input_len], decimal_places);
                const margin = margin_dec.toF64();
                const cost = engine.accumulator.toF64();
                const price = calc.FinRegisters.markup(cost, margin);
                const price_dec = number.Decimal.fromF64(price, decimal_places);
                t.addEntry(.{ .value = margin_dec, .operator = null, .is_result = false, .label = "MU%" });
                t.addEntry(.{ .value = price_dec, .operator = null, .is_result = true, .label = "MU" });
                engine.reset();
                engine.pushValue(price_dec, decimal_places);
                input_len = 0;
            }
        },
    }
}

// ── Display refresh ────────────────────────────────────────
fn refreshDisplay() void {
    // Update input line
    if (input_len > 0) {
        gtk.gtk_label_set_text(@ptrCast(input_label), toC(input_buf[0..input_len]));
    } else {
        gtk.gtk_label_set_text(@ptrCast(input_label), "0");
    }

    // Rebuild tape
    refreshTape();
}

fn refreshTape() void {
    // Remove all children
    var child = gtk.gtk_widget_get_first_child(tape_box);
    while (child != null) {
        const next = gtk.gtk_widget_get_next_sibling(child);
        gtk.gtk_box_remove(@ptrCast(tape_box), child);
        child = next;
    }

    // Add entries
    const entries = t.entries.items;
    for (entries) |entry| {
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

        // Build display string: "  value   op"
        var line_buf: [160]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{s}  {s}", .{ val_str, tag_str }) catch "?";

        const row = gtk.gtk_label_new(toC(line));
        gtk.gtk_label_set_xalign(@ptrCast(row), 1.0);
        gtk.gtk_widget_add_css_class(row, "tape-entry");
        if (entry.is_result) {
            gtk.gtk_widget_add_css_class(row, "tape-entry-result");
        }
        gtk.gtk_box_append(@ptrCast(tape_box), row);
    }

    // Scroll to bottom
    scrollToBottom();
}

fn scrollToBottom() void {
    const vadj = gtk.gtk_scrolled_window_get_vadjustment(@ptrCast(tape_scroll));
    if (vadj != null) {
        const upper = gtk.gtk_adjustment_get_upper(vadj);
        const page = gtk.gtk_adjustment_get_page_size(vadj);
        gtk.gtk_adjustment_set_value(vadj, upper - page);
    }
}

fn refreshButtons() void {
    for (0..keyboard.ROWS) |ri| {
        for (0..keyboard.COLS) |ci| {
            const btn_def = kb.getBtn(ri, ci);
            gtk.gtk_button_set_label(@ptrCast(btn_widgets[ri][ci]), toC(btn_def.label));

            // Remove old style classes and apply new
            gtk.gtk_widget_remove_css_class(btn_widgets[ri][ci], "btn-normal");
            gtk.gtk_widget_remove_css_class(btn_widgets[ri][ci], "btn-operator");
            gtk.gtk_widget_remove_css_class(btn_widgets[ri][ci], "btn-equals");
            gtk.gtk_widget_remove_css_class(btn_widgets[ri][ci], "btn-clear");
            gtk.gtk_widget_remove_css_class(btn_widgets[ri][ci], "btn-function");
            applyBtnCss(btn_widgets[ri][ci], btn_def.style);
        }
    }
}

// ── Helpers ────────────────────────────────────────────────
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

// g_signal_connect helper — Zig cannot resolve the G_CALLBACK macro,
// so we call g_signal_connect_data directly.
fn g_signal_connect(
    instance: anytype,
    signal: [*c]const u8,
    callback: anytype,
    data: ?*anyopaque,
) gtk.gulong {
    return gtk.g_signal_connect_data(
        @as(gtk.gpointer, @ptrCast(instance)),
        signal,
        @as(gtk.GCallback, @ptrCast(callback)),
        data,
        null,
        0,
    );
}
