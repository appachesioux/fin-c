const std = @import("std");
const number = @import("number.zig");
const keyboard = @import("keyboard.zig");

pub const Operator = enum {
    add,
    sub,
    mul,
    div,
    equals,
};

pub const CalcEngine = struct {
    accumulator: number.Decimal,
    has_value: bool,
    pending_op: ?Operator,

    pub fn init() CalcEngine {
        return .{
            .accumulator = number.Decimal.ZERO,
            .has_value = false,
            .pending_op = null,
        };
    }

    pub fn reset(self: *CalcEngine) void {
        self.accumulator = number.Decimal.ZERO;
        self.has_value = false;
        self.pending_op = null;
    }

    pub fn pushValue(self: *CalcEngine, val: number.Decimal, scale: u8) void {
        if (!self.has_value) {
            self.accumulator = val;
            self.has_value = true;
            return;
        }

        if (self.pending_op) |op| {
            self.accumulator = applyOp(self.accumulator, val, op, scale);
        } else {
            self.accumulator = val;
        }
    }

    pub fn setOp(self: *CalcEngine, op: Operator) void {
        self.pending_op = op;
    }

    pub fn compute(self: *CalcEngine, scale: u8) number.Decimal {
        _ = scale;
        return self.accumulator;
    }

    pub fn applyPercent(self: *CalcEngine, val: number.Decimal, scale: u8) number.Decimal {
        // percent of accumulator: acc * val / 100
        const hundred = number.Decimal.fromInt(100, scale);
        const pct = number.Decimal.div(val, hundred, scale);
        return number.Decimal.mul(self.accumulator, pct, scale);
    }

    fn applyOp(a: number.Decimal, b: number.Decimal, op: Operator, scale: u8) number.Decimal {
        return switch (op) {
            .add => number.Decimal.add(a, b),
            .sub => number.Decimal.sub(a, b),
            .mul => number.Decimal.mul(a, b, scale),
            .div => number.Decimal.div(a, b, scale),
            .equals => b,
        };
    }
};

// ── Financial registers ────────────────────────────────────

pub const FinRegisters = struct {
    pv: ?f64,
    fv: ?f64,
    n: ?f64,
    i: ?f64,
    pmt: ?f64,

    pub fn init() FinRegisters {
        return .{ .pv = null, .fv = null, .n = null, .i = null, .pmt = null };
    }

    pub fn clear(self: *FinRegisters) void {
        self.* = init();
    }

    pub fn set(self: *FinRegisters, reg: keyboard.FinRegister, val: f64) void {
        switch (reg) {
            .pv => self.pv = val,
            .fv => self.fv = val,
            .n => self.n = val,
            .i => self.i = val,
            .pmt => self.pmt = val,
        }
    }

    pub fn get(self: *const FinRegisters, reg: keyboard.FinRegister) ?f64 {
        return switch (reg) {
            .pv => self.pv,
            .fv => self.fv,
            .n => self.n,
            .i => self.i,
            .pmt => self.pmt,
        };
    }

    /// Count how many registers are set.
    fn setCount(self: *const FinRegisters) u8 {
        var c: u8 = 0;
        if (self.pv != null) c += 1;
        if (self.fv != null) c += 1;
        if (self.n != null) c += 1;
        if (self.i != null) c += 1;
        if (self.pmt != null) c += 1;
        return c;
    }

    /// Find the missing register (only if exactly one is missing).
    fn missingReg(self: *const FinRegisters) ?keyboard.FinRegister {
        if (self.setCount() != 4) return null;
        if (self.pv == null) return .pv;
        if (self.fv == null) return .fv;
        if (self.n == null) return .n;
        if (self.i == null) return .i;
        if (self.pmt == null) return .pmt;
        return null;
    }

    /// Try to solve for the missing register. Returns the register solved and its value.
    pub fn solve(self: *FinRegisters) ?struct { reg: keyboard.FinRegister, val: f64 } {
        const missing = self.missingReg() orelse return null;
        const pv = self.pv orelse 0;
        const fv = self.fv orelse 0;
        const n = self.n orelse 0;
        const rate = (self.i orelse 0) / 100.0; // convert % to decimal
        const pmt = self.pmt orelse 0;

        const result: f64 = switch (missing) {
            .fv => blk: {
                // FV = PV * (1+i)^n + PMT * ((1+i)^n - 1) / i
                const factor = std.math.pow(f64, 1.0 + rate, n);
                if (rate == 0) {
                    break :blk pv + pmt * n;
                }
                break :blk pv * factor + pmt * (factor - 1.0) / rate;
            },
            .pv => blk: {
                // PV = (FV - PMT * ((1+i)^n - 1) / i) / (1+i)^n
                const factor = std.math.pow(f64, 1.0 + rate, n);
                if (factor == 0) break :blk 0;
                if (rate == 0) {
                    break :blk fv - pmt * n;
                }
                break :blk (fv - pmt * (factor - 1.0) / rate) / factor;
            },
            .pmt => blk: {
                // PMT = (FV - PV * (1+i)^n) * i / ((1+i)^n - 1)
                const factor = std.math.pow(f64, 1.0 + rate, n);
                if (rate == 0) {
                    if (n == 0) break :blk 0;
                    break :blk (fv - pv) / n;
                }
                const denom = factor - 1.0;
                if (denom == 0) break :blk 0;
                break :blk (fv - pv * factor) * rate / denom;
            },
            .n => blk: {
                // n = ln((PMT - FV*i) / (PMT + PV*i)) / ln(1+i)
                if (rate == 0) {
                    if (pmt == 0) break :blk 0;
                    break :blk (fv - pv) / pmt;
                }
                const ln_base = @log(1.0 + rate);
                if (ln_base == 0) break :blk 0;
                const num = pmt - fv * rate;
                const den = pmt + pv * rate;
                if (den == 0 or num / den <= 0) break :blk 0;
                break :blk @log(num / den) / ln_base;
            },
            .i => blk: {
                // Solve by Newton-Raphson
                break :blk solveRate(pv, fv, n, pmt);
            },
        };

        self.set(missing, if (missing == .i) result * 100.0 else result);
        return .{ .reg = missing, .val = if (missing == .i) result * 100.0 else result };
    }

    /// Markup: price = cost / (1 - margin/100)
    pub fn markup(cost: f64, margin: f64) f64 {
        const denom = 1.0 - margin / 100.0;
        if (denom <= 0) return 0;
        return cost / denom;
    }

    fn solveRate(pv: f64, fv: f64, n: f64, pmt: f64) f64 {
        // Newton-Raphson to find i where:
        // f(i) = PV*(1+i)^n + PMT*((1+i)^n - 1)/i - FV = 0
        var rate: f64 = 0.1; // initial guess 10%
        var iter: u32 = 0;
        while (iter < 200) : (iter += 1) {
            if (rate <= -1.0) rate = 0.001;
            const factor = std.math.pow(f64, 1.0 + rate, n);
            const f_val = pv * factor + pmt * (factor - 1.0) / rate - fv;
            // derivative
            const d_factor = n * std.math.pow(f64, 1.0 + rate, n - 1.0);
            const d_val = pv * d_factor + pmt * (d_factor * rate - (factor - 1.0)) / (rate * rate);
            if (@abs(d_val) < 1e-15) break;
            const new_rate = rate - f_val / d_val;
            if (@abs(new_rate - rate) < 1e-12) {
                rate = new_rate;
                break;
            }
            rate = new_rate;
        }
        return rate;
    }
};
