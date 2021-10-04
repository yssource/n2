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
        if (c == 0) {
            std.debug.panic("advanced past buffer end", .{});
        }
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

    pub fn format(self: *ParseErrorContext, alloc: *std.mem.Allocator, buf: []const u8) ![]u8 {
        const loc = std.zig.findLineColumn(buf, self.pos);
        var out = std.ArrayList(u8).init(alloc);
        try out.writer().print("parse error at {d}:{d}: unexpected '{c}'\n", .{ loc.line+1, loc.column+1, self.unexpected });
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

    pub fn read_stmt(self: *Parser) !void {
        switch (self.cur.next()) {
            '#' => try self.skip_comment(),
            '\n' => {},
            else => {
                self.cur.back();
                const ident = try self.read_ident();
                try self.skip_spaces();
                const c = self.cur.next();
                if (c != '=') {
                    self.cur.back();
                    return self.unexpected();
                }
                try self.skip_spaces();
                const varparts = try self.read_var();
                std.log.info("{s} = {s}", .{ident, varparts});
            },
        }
    }

    fn skip_comment(self: *Parser) !void {
        while (true) {
            const c = self.cur.next();
            switch (c) {
                0 => return self.unexpected(),
                '\n' => break,
                else => {}
            }
        }
    }

    fn skip_spaces(self: *Parser) !void {
        while (self.cur.next() == ' ') {
        }
        self.cur.back();
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
            return self.unexpected();
        }
        return self.cur.buf[start..end];
    }

    fn read_var(self: *Parser) ![]EvalPart {
        var parts = std.ArrayList(EvalPart).init(self.alloc);
        var start = self.cur.pos;
        while (true) {
            const c = self.cur.next();
            switch (c) {
                '\n' => break,
                '$' => {
                    const end = self.cur.pos;
                    if (end > start) {
                        try parts.append(EvalPart{.literal=self.cur.buf[start..end]});
                    }
                    try parts.append(try self.read_escape());
                    start = self.cur.pos;
                },
                0 => {
                    self.cur.back();
                    return self.unexpected();
                },
                else => {},
            }
        }
        const end = self.cur.pos;
        if (end > start) {
            try parts.append(EvalPart{.literal=self.cur.buf[start..end]});
        }
        return parts.items;
    }

    fn read_escape(self: *Parser) !EvalPart {
        const c = self.cur.next();
        switch (c) {
            '\n' => {
                const part = EvalPart{.literal=self.cur.buf[self.cur.pos-1..self.cur.pos] };
                try self.skip_spaces();
                return part;
            },
            else => {
                self.cur.back();
                const ident = try self.read_ident();
                return EvalPart{.varref=ident};
            }
        }
    }

    fn unexpected(self: *Parser) ParseError {
        self.err.* = ParseErrorContext{ .pos = self.cur.pos, .unexpected = self.cur.peek() };
        return error.ParseError;
    }
};

fn parse(alloc: *std.mem.Allocator, buf: *std.ArrayList(u8), err: *?ParseErrorContext) !void {
    var parser = Parser.init(alloc, Cursor.init(buf.items), err);

    while (true) {
        try parser.read_stmt();
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
    std.log.info("All your codebase are belong to us. {d}", .{buf.items.len});
}
