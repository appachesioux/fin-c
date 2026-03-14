const std = @import("std");
const number = @import("number.zig");
const calc = @import("calc.zig");

pub const TapeEntry = struct {
    value: number.Decimal,
    operator: ?calc.Operator,
    is_result: bool,
    label: ?[]const u8 = null,
};

pub const Tape = struct {
    entries: std.ArrayList(TapeEntry),
    allocator: std.mem.Allocator,
    scroll_offset: f32,

    pub fn init(allocator: std.mem.Allocator) Tape {
        return .{
            .entries = .{},
            .allocator = allocator,
            .scroll_offset = 0,
        };
    }

    pub fn deinit(self: *Tape) void {
        self.entries.deinit(self.allocator);
    }

    pub fn addEntry(self: *Tape, entry: TapeEntry) void {
        self.entries.append(self.allocator, entry) catch {};
        self.scroll_offset = 0;
    }

    pub fn scroll(self: *Tape, delta: f32, tape_height: f32) void {
        self.scroll_offset += delta;
        const max_scroll = @as(f32, @floatFromInt(self.entries.items.len)) * 28.0 - tape_height + 40;
        if (max_scroll < 0) {
            self.scroll_offset = 0;
        } else {
            self.scroll_offset = @min(self.scroll_offset, max_scroll);
            self.scroll_offset = @max(self.scroll_offset, 0);
        }
    }
};
