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
        if (self.pos == self.buf.len) {
            std.debug.panic("advanced past buffer end", .{});
        }
        self.pos += 1;
        return self.peek();
    }

    pub fn back(self: *Cursor) void {
        if (self.pos == 0) {
            std.debug.panic("can't back", .{});
        }
        self.pos -= 1;
    }
};

const Toker = struct {
    cur: Cursor,

    pub fn init(c: Cursor) Toker {
        return .{
            .cur = c,
        };
    }

    pub fn read_ident(self: *Toker) void {
        const start = self.cur.pos;
        while (true) {
            const c = self.cur.next();
            switch (c) {
                'a'...'z' => {},
                else => {
                    self.cur.back();
                    break;
                },
            }
        }
        const end = self.cur.pos;
        if (end == start) {
            std.debug.panic("TODO {c}", .{self.cur.peek()});
        }
    }
};

fn parse(buf: *std.ArrayList(u8)) void {
    var toker = Toker.init(Cursor.init(buf.items));
    toker.read_ident();
}

pub fn main() anyerror!void {
    try std.os.chdir("/home/evmar/ninja");
    const f = try std.fs.cwd().openFile("build.ninja", std.fs.File.OpenFlags{ .read = true });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var alloc = &arena.allocator;
    var buf = std.ArrayList(u8).init(alloc);
    try f.reader().readAllArrayList(&buf, 1 << 20);
    parse(&buf);
    std.log.info("All your codebase are belong to us. {d}", .{buf.items.len});
}
