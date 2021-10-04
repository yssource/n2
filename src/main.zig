const std = @import("std");

const Cursor = struct {
    buf: []const u8,
    pos: usize,

    pub fn init(buf: []const u8) Cursor {
        return .{
            .buf = buf,
            .pos = 0,
        };
    }

    pub fn peek(self: *Cursor) u8 {
        if (self.pos == self.buf.len) {
            return 0;
        }
        return self.buf[self.pos];
    }

    pub fn next(self: *Cursor) u8 {
        const c = self.peek();
        self.pos += 1;
        return c;
    }

    pub fn back(self: *Cursor) void {
        if (self.pos == 0) {
            std.debug.panic("can't back", .{});
        }
        self.pos -= 1;
    }
};

const ParseErrorContext = struct {
    pos: usize,
    unexpected: u8,
    context: []const u8,

    pub fn format(self: *ParseErrorContext, alloc: *std.mem.Allocator, buf: []const u8) ![]u8 {
        const loc = std.zig.findLineColumn(buf, self.pos);
        var out = std.ArrayList(u8).init(alloc);
        try out.writer().print("parsing {s} at {d}:{d}: unexpected '{c}'\n", .{ self.context, loc.line + 1, loc.column + 1, self.unexpected });
        try out.writer().print("{s}\n", .{loc.source_line});
        var i: usize = 0;
        while (i < loc.column) : (i += 1) {
            try out.writer().writeByte(' ');
        }
        try out.writer().writeAll("^\n");
        return out.items;
    }
};

const EvalPart = union(enum) {
    literal: []const u8,
    varref: []const u8,
};
const EvalString = struct {
    parts: []EvalPart,

    pub fn format(value: EvalString, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.writeByte('"');
        for (value.parts) |*part| {
            switch (part.*) {
                .literal => |str| try writer.print("[{s}]", .{str}),
                .varref => |str| try writer.print("${{{s}}}", .{str}),
            }
        }
        try writer.writeByte('"');
    }
};

const ParseError = error{ParseError};
const Parser = struct {
    alloc: *std.mem.Allocator,
    cur: Cursor,
    err: *?ParseErrorContext,

    pub fn init(alloc: *std.mem.Allocator, c: Cursor, err: *?ParseErrorContext) Parser {
        return .{
            .alloc = alloc,
            .cur = c,
            .err = err,
        };
    }

    pub fn read_stmt(self: *Parser) !bool {
        switch (self.cur.next()) {
            0 => return false,
            '#' => try self.skip_comment(),
            '\n' => {},
            else => {
                self.cur.back();
                const ident = try self.read_ident();
                self.skip_spaces();
                if (std.mem.eql(u8, ident, "build")) {
                    try self.read_build();
                } else if (std.mem.eql(u8, ident, "rule")) {
                    try self.read_rule();
                } else if (std.mem.eql(u8, ident, "default")) {
                    _ = try self.read_path();
                    try self.expect('\n', "default");
                } else {
                    const eval = try self.read_vardef();
                    std.log.info("{s} = {s}", .{ ident, eval });
                }
            },
        }
        return true;
    }

    fn skip_comment(self: *Parser) !void {
        while (true) {
            const c = self.cur.next();
            switch (c) {
                0 => return self.unexpected("comment"),
                '\n' => break,
                else => {},
            }
        }
    }

    fn skip_spaces(self: *Parser) void {
        while (self.cur.next() == ' ') {}
        self.cur.back();
    }

    fn read_rule(self: *Parser) !void {
        const name = try self.read_ident();
        _ = name;
        try self.expect('\n', "rule");
        try self.read_indented();
    }

    fn read_build(self: *Parser) !void {
        while (true) {
            const path = (try self.read_path()) orelse break;
            std.log.info("path {s}", .{path});
            self.skip_spaces();
        }
        try self.expect(':', "build colon");
        self.skip_spaces();
        const rule = try self.read_ident();
        self.skip_spaces();

        while (true) {
            const path = (try self.read_path()) orelse break;
            std.log.info("path {s}", .{path});
            self.skip_spaces();
        }

        if (self.cur.peek() == '|') {
            _ = self.cur.next();
            if (self.cur.peek() == '|') {
                self.cur.back();
            } else {
                self.skip_spaces();

                while (true) {
                    const path = (try self.read_path()) orelse break;
                    std.log.info("path {s}", .{path});
                    self.skip_spaces();
                }
            }
        }

        if (self.cur.peek() == '|') {
            _ = self.cur.next();
            if (self.cur.next() != '|') {
                self.cur.back();
                return self.unexpected("build inputs");
            }
            self.skip_spaces();

            while (true) {
                const path = (try self.read_path()) orelse break;
                std.log.info("path {s}", .{path});
                self.skip_spaces();
            }
        }

        try self.expect('\n', "build eol");

        try self.read_indented();

        std.log.info("build {s}", .{rule});
    }

    fn read_indented(self: *Parser) !void {
        while (self.cur.peek() == ' ') {
            self.skip_spaces();
            const varname = try self.read_ident();
            self.skip_spaces();
            const val = try self.read_vardef();
            std.log.info("  {s}={s}", .{ varname, val });
        }
    }

    fn read_ident(self: *Parser) ![]const u8 {
        const start = self.cur.pos;
        while (true) {
            const c = self.cur.next();
            switch (c) {
                'a'...'z', '_' => {},
                else => {
                    self.cur.back();
                    break;
                },
            }
        }
        const end = self.cur.pos;
        if (end == start) {
            return self.unexpected("identifier");
        }
        return self.cur.buf[start..end];
    }

    fn read_vardef(self: *Parser) !EvalString {
        try self.expect('=', "variable definition");
        self.skip_spaces();
        const eval = try self.read_eval(false);
        try self.expect('\n', "variable definition");
        return eval;
    }

    fn read_path(self: *Parser) !?EvalString {
        const eval = try self.read_eval(true);
        if (eval.parts.len == 0) return null;
        return eval;
    }

    fn read_eval(self: *Parser, comptime path: bool) !EvalString {
        var parts = std.ArrayList(EvalPart).init(self.alloc);
        var start = self.cur.pos;
        while (true) {
            const c = self.cur.next();
            switch (c) {
                '\n' => {
                    self.cur.back();
                    break;
                },
                '$' => {
                    const end = self.cur.pos - 1;
                    if (end > start) {
                        try parts.append(EvalPart{ .literal = self.cur.buf[start..end] });
                    }
                    const escape = try self.read_escape();
                    const nonempty = switch (escape) {
                        .literal => |*str| str.len > 0,
                        .varref => true,
                    };
                    if (nonempty) try parts.append(escape);
                    start = self.cur.pos;
                },
                0 => {
                    self.cur.back();
                    return self.unexpected("value");
                },
                ':', ' ', '|' => {
                    if (path) {
                        self.cur.back();
                        break;
                    }
                },
                else => {},
            }
        }
        const end = self.cur.pos;
        if (end > start) {
            try parts.append(EvalPart{ .literal = self.cur.buf[start..end] });
        }
        return EvalString{ .parts = parts.items };
    }

    fn read_escape(self: *Parser) !EvalPart {
        const c = self.cur.next();
        switch (c) {
            '\n' => {
                const part = EvalPart{ .literal = self.cur.buf[self.cur.pos..self.cur.pos] };
                self.skip_spaces();
                return part;
            },
            '{' => {
                const ident = try self.read_ident();
                try self.expect('}', "variable reference");
                return EvalPart{ .varref = ident };
            },
            else => {
                self.cur.back();
                const ident = try self.read_ident();
                return EvalPart{ .varref = ident };
            },
        }
    }

    fn expect(self: *Parser, c: u8, context: []const u8) !void {
        if (self.cur.next() != c) {
            self.cur.back();
            return self.unexpected(context);
        }
    }

    fn unexpected(self: *Parser, context: []const u8) ParseError {
        self.err.* = ParseErrorContext{
            .pos = self.cur.pos,
            .unexpected = self.cur.peek(),
            .context = context,
        };
        return error.ParseError;
    }
};

fn parse(alloc: *std.mem.Allocator, buf: *std.ArrayList(u8), err: *?ParseErrorContext) !void {
    var parser = Parser.init(alloc, Cursor.init(buf.items), err);

    while (try parser.read_stmt()) {
    }
}

pub fn main() anyerror!void {
    try std.os.chdir("/home/evmar/ninja");
    const f = try std.fs.cwd().openFile("build.ninja", std.fs.File.OpenFlags{ .read = true });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var alloc = &arena.allocator;
    var buf = std.ArrayList(u8).init(alloc);
    try f.reader().readAllArrayList(&buf, 1 << 20);
    var perr: ?ParseErrorContext = null;
    parse(alloc, &buf, &perr) catch |err| {
        if (err == error.ParseError) {
            std.log.info("err {s}", .{perr.?.format(alloc, buf.items)});
        }
    };
}
