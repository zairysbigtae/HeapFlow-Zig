// NOTE: RUST OG CODE
// #[repr(C)]
// pub struct BlockHeader {
//     size: usize,
//     used: bool,
//     next: *mut BlockHeader,
//     magic: u32,
// }
pub const PAGE_SIZE = 4096;
pub const MAGIC_ALLOCATED = 0xC0CDECAFE;
pub const MAGIC_FREE = 0xDEADC0DE;

pub const BlockHeader = extern struct {
    size: usize,
    used: bool,
    next: ?*BlockHeader,
    magic: u64,
};

test "instance of BlockHeader" {
    const std = @import("std");
    var allocator = std.heap.page_allocator;

    const header_ptr = try allocator.create(BlockHeader);
    header_ptr.* = BlockHeader {
        .size = 4096,
        .used = false,
        .next = null,
        .magic = MAGIC_FREE,
    };

    allocator.destroy(header_ptr);
}
