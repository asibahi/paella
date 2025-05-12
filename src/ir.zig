const std = @import("std");

pub const Prgm = struct {
    func_def: FuncDef,

    // pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    //     self.func_def.deinit(alloc);
    //     alloc.destroy(self.func_def);
    // }
};

pub const FuncDef = struct {
    name: []const u8,
    instrs: std.ArrayListUnmanaged(Instr),

    // pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    //     alloc.free(self.name);
    //     self.instrs.deinit(alloc);
    // }
};

pub const Instr = union(enum) {
    ret: Value,
    unop_negate: Unary,
    unop_complement: Unary,

    pub const Unary = struct {
        src: Value,
        dst: Value,

        pub fn init(src: Value, dst: Value) @This() {
            return .{ .src = src, .dst = dst };
        }
    };
};

pub const Value = union(enum) {
    constant: u64,
    variable: []const u8,
};
