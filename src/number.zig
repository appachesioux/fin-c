const std = @import("std");

/// Fixed-point decimal number backed by i128.
/// Internal value is scaled by 10^decimal_places.
pub const Decimal = struct {
    raw: i128,
    scale: u8, // decimal places

    pub const ZERO = Decimal{ .raw = 0, .scale = 2 };

    pub fn init(raw: i128, scale: u8) Decimal {
        return .{ .raw = raw, .scale = scale };
    }

    pub fn fromInt(value: i64, scale: u8) Decimal {
        const s = scaleMultiplier(scale);
        return .{ .raw = @as(i128, value) * s, .scale = scale };
    }

    fn scaleMultiplier(scale: u8) i128 {
        var m: i128 = 1;
        for (0..scale) |_| m *= 10;
        return m;
    }

    /// Parse a string like "123.45" or "-1000" into a Decimal.
    pub fn parse(buf: []const u8, scale: u8) Decimal {
        if (buf.len == 0) return Decimal{ .raw = 0, .scale = scale };

        var negative = false;
        var start: usize = 0;
        if (buf[0] == '-') {
            negative = true;
            start = 1;
        }

        var integer_part: i128 = 0;
        var frac_part: i128 = 0;
        var frac_digits: u8 = 0;
        var in_frac = false;

        for (buf[start..]) |c| {
            if (c == '.') {
                in_frac = true;
                continue;
            }
            if (c < '0' or c > '9') continue;

            if (in_frac) {
                if (frac_digits < scale) {
                    frac_part = frac_part * 10 + (c - '0');
                    frac_digits += 1;
                }
                // ignore extra fractional digits
            } else {
                integer_part = integer_part * 10 + (c - '0');
            }
        }

        // Pad fractional part if fewer digits than scale
        while (frac_digits < scale) {
            frac_part *= 10;
            frac_digits += 1;
        }

        var raw = integer_part * scaleMultiplier(scale) + frac_part;
        if (negative) raw = -raw;

        return .{ .raw = raw, .scale = scale };
    }

    pub fn add(a: Decimal, b: Decimal) Decimal {
        const unified = unifyScale(a, b);
        return .{ .raw = unified[0].raw + unified[1].raw, .scale = unified[0].scale };
    }

    pub fn sub(a: Decimal, b: Decimal) Decimal {
        const unified = unifyScale(a, b);
        return .{ .raw = unified[0].raw - unified[1].raw, .scale = unified[0].scale };
    }

    pub fn mul(a: Decimal, b: Decimal, result_scale: u8) Decimal {
        const s = scaleMultiplier(b.scale);
        const raw = @divTrunc(a.raw * b.raw, s);
        const result = Decimal{ .raw = raw, .scale = a.scale };
        return result.rescale(result_scale);
    }

    pub fn div(a: Decimal, b: Decimal, result_scale: u8) Decimal {
        if (b.raw == 0) return Decimal{ .raw = 0, .scale = result_scale };
        const s = scaleMultiplier(b.scale);
        const raw = @divTrunc(a.raw * s, b.raw);
        const result = Decimal{ .raw = raw, .scale = a.scale };
        return result.rescale(result_scale);
    }

    pub fn negate(self: Decimal) Decimal {
        return .{ .raw = -self.raw, .scale = self.scale };
    }

    pub fn rescale(self: Decimal, new_scale: u8) Decimal {
        if (self.scale == new_scale) return self;
        if (new_scale > self.scale) {
            var m: i128 = 1;
            for (0..new_scale - self.scale) |_| m *= 10;
            return .{ .raw = self.raw * m, .scale = new_scale };
        } else {
            var m: i128 = 1;
            for (0..self.scale - new_scale) |_| m *= 10;
            return .{ .raw = @divTrunc(self.raw, m), .scale = new_scale };
        }
    }

    pub fn toF64(self: Decimal) f64 {
        const s: f64 = @floatFromInt(scaleMultiplier(self.scale));
        const r: f64 = @floatFromInt(self.raw);
        return r / s;
    }

    pub fn fromF64(value: f64, scale: u8) Decimal {
        const s: f64 = @floatFromInt(scaleMultiplier(scale));
        const raw: i128 = @intFromFloat(@round(value * s));
        return .{ .raw = raw, .scale = scale };
    }

    /// Format the decimal as a string with thousands separators.
    /// Returns a slice into the provided buffer.
    pub fn format(self: Decimal, buf: []u8) []const u8 {
        var val = self.raw;
        var negative = false;
        if (val < 0) {
            negative = true;
            val = -val;
        }

        const s = scaleMultiplier(self.scale);
        var int_part = @divTrunc(val, s);
        const frac_part = @rem(val, s);

        // Build the string backwards
        var pos: usize = buf.len;

        // Fractional part
        if (self.scale > 0) {
            var frac = if (frac_part < 0) -frac_part else frac_part;
            var i: u8 = 0;
            while (i < self.scale) : (i += 1) {
                pos -= 1;
                buf[pos] = '0' + @as(u8, @intCast(@rem(frac, 10)));
                frac = @divTrunc(frac, 10);
            }
            pos -= 1;
            buf[pos] = '.'; // decimal point
        }

        // Integer part with dot separators for thousands
        if (int_part == 0) {
            pos -= 1;
            buf[pos] = '0';
        } else {
            var digit_count: u32 = 0;
            while (int_part > 0) {
                if (digit_count > 0 and digit_count % 3 == 0) {
                    pos -= 1;
                    buf[pos] = ',';
                }
                pos -= 1;
                buf[pos] = '0' + @as(u8, @intCast(@rem(int_part, 10)));
                int_part = @divTrunc(int_part, 10);
                digit_count += 1;
            }
        }

        if (negative) {
            pos -= 1;
            buf[pos] = '-';
        }

        return buf[pos..];
    }

    fn unifyScale(a: Decimal, b: Decimal) [2]Decimal {
        if (a.scale == b.scale) return .{ a, b };
        const target = @max(a.scale, b.scale);
        return .{ a.rescale(target), b.rescale(target) };
    }

    /// Parse a pasted string with auto-detection of numeric format.
    /// Handles: 1,000.50 (US) / 1.000,50 (BR/EU) / 1000.50 / 1000,50
    /// Returns the cleaned digits in out_buf (e.g. "1000.50") and the length.
    pub fn parsePaste(input: []const u8, out_buf: []u8) usize {
        // Strip whitespace, currency symbols, etc. Keep digits, dots, commas, minus
        var clean: [128]u8 = undefined;
        var clean_len: usize = 0;
        for (input) |c| {
            if ((c >= '0' and c <= '9') or c == '.' or c == ',' or c == '-') {
                if (clean_len < clean.len) {
                    clean[clean_len] = c;
                    clean_len += 1;
                }
            }
        }
        if (clean_len == 0) return 0;

        const buf = clean[0..clean_len];

        // Count dots and commas
        var dot_count: usize = 0;
        var comma_count: usize = 0;
        var last_dot: usize = 0;
        var last_comma: usize = 0;
        for (buf, 0..) |c, idx| {
            if (c == '.') {
                dot_count += 1;
                last_dot = idx;
            } else if (c == ',') {
                comma_count += 1;
                last_comma = idx;
            }
        }

        // Determine which is decimal separator:
        // - Multiple dots, zero/one comma → dots are thousands, comma is decimal (BR/EU: 1.000.000,50)
        // - Multiple commas, zero/one dot → commas are thousands, dot is decimal (US: 1,000,000.50)
        // - One dot, zero commas → dot is decimal (1000.50)
        // - Zero dots, one comma → comma is decimal (1000,50)
        // - One dot, one comma → whichever comes last is decimal
        const CommaIsDec = enum { yes, no };
        const comma_is_decimal: CommaIsDec = blk: {
            if (dot_count > 1 and comma_count <= 1) break :blk .yes;
            if (comma_count > 1 and dot_count <= 1) break :blk .no;
            if (dot_count == 1 and comma_count == 0) break :blk .no;
            if (dot_count == 0 and comma_count == 1) break :blk .yes;
            if (dot_count == 1 and comma_count == 1) {
                break :blk if (last_comma > last_dot) .yes else .no;
            }
            // No separators
            break :blk .no;
        };

        // Write normalized output: strip thousands separator, convert decimal separator to '.'
        var out_len: usize = 0;
        for (buf) |c| {
            if (c == '-') {
                if (out_len < out_buf.len) {
                    out_buf[out_len] = '-';
                    out_len += 1;
                }
            } else if (c >= '0' and c <= '9') {
                if (out_len < out_buf.len) {
                    out_buf[out_len] = c;
                    out_len += 1;
                }
            } else if (c == ',' and comma_is_decimal == .yes) {
                if (out_len < out_buf.len) {
                    out_buf[out_len] = '.';
                    out_len += 1;
                }
            } else if (c == '.' and comma_is_decimal == .no) {
                if (out_len < out_buf.len) {
                    out_buf[out_len] = '.';
                    out_len += 1;
                }
            }
            // else: thousands separator, skip
        }
        return out_len;
    }
};

test "parse and format" {
    var buf: [128]u8 = undefined;

    const d = Decimal.parse("1234.56", 2);
    const s = d.format(&buf);
    try std.testing.expectEqualStrings("1,234.56", s);
}

test "add" {
    const a = Decimal.parse("100.50", 2);
    const b = Decimal.parse("200.25", 2);
    const c = Decimal.add(a, b);
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("300.75", c.format(&buf));
}

test "large number" {
    var buf: [128]u8 = undefined;
    const d = Decimal.parse("999999999999.99", 2);
    const s = d.format(&buf);
    try std.testing.expectEqualStrings("999,999,999,999.99", s);
}
