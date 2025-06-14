const std = @import("std");
const print = std.debug.print;
const panic = std.debug.panic;

const allocator_zig = @import("allocator.zig");
const BlockHeader = allocator_zig.BlockHeader;
const PAGE_SIZE = allocator_zig.PAGE_SIZE;
const MAGIC_FREE = allocator_zig.MAGIC_FREE;
const MAGIC_ALLOCATED = allocator_zig.MAGIC_ALLOCATED;

const c = @cImport({
    @cInclude("sys/mman.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
});

fn get_errno() i32 {
    return c.__errno_location().*;
}

const FreeListAllocator = struct {
    free_list_head: ?*BlockHeader,

    pub fn new() FreeListAllocator {
        print("FreeListAllocator Initialized!\n", .{});
        return FreeListAllocator {
            .free_list_head = null
        };
    }

    pub fn request_memory(self: *FreeListAllocator, size: usize) *BlockHeader {
        _ = self; // autofix
        print("{s} Requesting memory from OS\n", .{"\x1b[32m[MEMORY REQUEST]\x1b[0m"});
        const aligned_size = ((size + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE;

        const ptr = c.mmap(
            null,
            aligned_size,
            c.PROT_READ | c.PROT_WRITE,
            c.MAP_PRIVATE | c.MAP_ANON,
            -1,
            0,
        );

        if (ptr == null or ptr == c.MAP_FAILED) {
            const err = get_errno();
            panic("{s} Pointer failed to initialize!\nReason: {d}\nSize given: {d} bytes", .{"\x1b[31m[ERROR]\x1b[0m", err, size});
        }
        // var header = @as(*BlockHeader, @ptrCast(ptr.?));
        var header = @as(*BlockHeader, @alignCast(@ptrCast(ptr.?)));

        print("{s} Setting current block as freed\n", .{"\x1b[32m[MEMORY REQUEST]\x1b[0m"});
        print("-- BEFORE --\n", .{});
        print("Address: 0x{X}\n", .{@intFromPtr(header)});
        print("Magic: {X}\n", .{header.magic});
        print("Size: {d}\n", .{header.size});
        print("Next block: {any}\n", .{header.next});
        print("Used: {}\n", .{header.used});

        header.magic = MAGIC_FREE;
        header.size = aligned_size - @sizeOf(BlockHeader);
        header.next = null;
        header.used = true;

        print("-- AFTER --\n", .{});
        print("Address: 0x{X}\n", .{@intFromPtr(header)});
        print("Magic: {X}\n", .{header.magic});
        print("Size: {d}\n", .{header.size});
        print("Next block: {any}\n", .{header.next});
        print("Used: {}\n", .{header.used});

        return header;
    }

    pub fn allocate(self: *FreeListAllocator, requested_size: usize) ?*u8 {
        var prev_block: ?*BlockHeader = null; // We dont have a previous block yet, so this is the initialized value
        var current_block = self.free_list_head;

        while (current_block != null) {
            // three keypoints:
            //      - Checks if its free
            //      - checks if its unused
            //      - checks if its big enough for splitting
            if ((!current_block.?.used)
            and (current_block.?.magic == MAGIC_FREE)
            and (current_block.?.size >= requested_size)) {
                print("Block size is suitable for splitting!\n", .{});
                const leftover = current_block.?.size - requested_size;

                if (leftover > @sizeOf(BlockHeader)) {
                    const new_block = @as(
                        *BlockHeader,
                        @as(*BlockHeader, @ptrFromInt(
                            @intFromPtr(@as(*BlockHeader, @ptrCast(current_block.?))) + (@sizeOf(BlockHeader) + requested_size))
                        )
                    );
                    new_block.magic = MAGIC_FREE;
                    new_block.size = leftover - @sizeOf(BlockHeader);
                    new_block.used = false;
                    new_block.next = current_block.?.next;

                    current_block.?.size = requested_size;
                    current_block.?.next = new_block;
                }
                switch (prev_block == null) {
                    true => self.free_list_head = current_block.?.next,
                    false => prev_block.?.next = current_block.?.next,
                }
            } else {
                print("Block size is not suitable for splitting!\n", .{});
            }
            prev_block = current_block;
            current_block = current_block.?.next;
        }

        print("{s} No suitable block found. Requesting more memory from OS\n", .{"\x1b[33m[WARNING]\x1b[0m"});
        const new_block: ?*BlockHeader = self.request_memory(requested_size + @sizeOf(BlockHeader));
        if (new_block == null) {
            panic("{s} Memory request failed, stopping the program\n", .{"\x1b[31m[ERROR]\x1b[0m"});
        } else {
            print("{s} Memory request succeed, returning a pointer\n", .{"\x1b[32m[MEMORY REQUEST]\x1b[0m"});
        }

        new_block.?.used = true;
        new_block.?.magic = MAGIC_ALLOCATED;
        new_block.?.size = requested_size;
        new_block.?.next = null;

        print("Returning allocated pointer\n", .{});
        print("Block used: {}\n", .{new_block.?.used});
        print("Raw block ptr: {any}\n", .{new_block});
        print("Block size: {}\n", .{new_block.?.size});

        const result = @intFromPtr(new_block.?) + @sizeOf(BlockHeader);
        return @ptrFromInt(result);
    }

    pub fn deallocate(self: *FreeListAllocator, ptr: ?*u8) void {
        if (ptr == null) {
            panic("Tried to deallocate a null pointer\n", .{});
        }
        const header: *BlockHeader = @alignCast(@ptrCast(@as(*u8, @ptrFromInt(@intFromPtr(ptr.?) - @sizeOf(BlockHeader)))));
        // if (header == null) {
        //     panic("Tried to deallocate a null header pointer\n", .{});
        // }
        // print("{s} Freeing header pointer: {d}\n", .{"\x1b[32m[FREE]\x1b[0m", @as(usize, @intFromPtr(header))});
        print("{s} Freeing header pointer: 0x{X}\n", .{"\x1b[32m[FREE]\x1b[0m", @intFromPtr(header)});

        if ((header.magic == MAGIC_FREE)
        or !(header.used)) {
            print("{s} Either the pointer's magic is not 0xC0DECAFE or the pointer's current block is not in use.\nCheck the output:\nmagic={X}\nused={}", .{"[ERROR]", header.magic, header.used});
            panic("Double free or invalid free detected!", .{});
        }

        header.used = false;
        header.magic = MAGIC_FREE;

        // chain the freed block to free_list_head
        header.next = self.free_list_head;
        self.free_list_head = header;

        _ = c.madvise(@ptrCast(header), header.size, c.MADV_DONTNEED);

        // ACTUALLY FREE IT FROM MEMORY
        // 64 is the.. requested size btw
        // const aligned_size = ((64 + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE;
        // const result = c.munmap(@ptrCast(header), aligned_size);
        // if (result != 0) {
        //     print("{s} munmap failed!\n", .{"\x1b[31m[ERROR]\x1b[0m"});
        //     panic("Failed to munmap allocated block", .{});
        // }
    }
};

export fn free_list_allocator_allocate(requested_size: usize) ?*u8 {
    var allocator = FreeListAllocator.new();
    return allocator.allocate(requested_size);
}

export fn free_list_allocator_deallocate(ptr: ?*u8) void {
    var allocator = FreeListAllocator.new();
    allocator.deallocate(ptr.?);
}

test "initialize FreeListAllocator" {
    print("\x1b[34m-- INITIALIZE FREELISTALLOCATOR TEST --\x1b[0m\n", .{});

    const allocator = FreeListAllocator.new();
    print("FreeListAllocator Info: {any}\n", .{allocator});
}

test "request memory FreeListAllocator" {
    print("\x1b[34m-- REQUEST MEMORY FREELISTALLOCATOR TEST --\x1b[0m\n", .{});

    var allocator = FreeListAllocator.new();
    const ptr = allocator.request_memory(4096);
    print("ptr: {any}\n", .{ptr});
}

test "allocate memory FreeListAllocator" {
    print("\x1b[34m-- ALLOCATE MEMORY FREELISTALLOCATOR TEST --\x1b[0m\n", .{});

    var allocator = FreeListAllocator.new();
    const ptr = allocator.allocate(32);
    print("ptr: {any}\n", .{ptr.?});
}

test "free memory FreeListAllocator" {
    print("\x1b[34m-- FREE MEMORY FREELISTALLOCATOR TEST --\x1b[0m\n", .{});

    var allocator = FreeListAllocator.new();
    const ptr = allocator.allocate(64);
    allocator.deallocate(ptr);
    print("ptr: {p}\n", .{ptr.?});
}

test "store value to memory address FreeListAllocator" {
    print("\x1b[34m-- STORE VALUE TO MEMORY ADDRESS FREELISTALLOCATOR TEST --\x1b[0m\n", .{});

    var allocator = FreeListAllocator.new();
    const ptr = allocator.allocate(64) orelse unreachable;
    // comptime {
    //     @compileLog(@typeName(@TypeOf(ptr)));
    //     @compileLog(@typeName(@TypeOf(ptr.*)));
    // }

    ptr.* = 42;
    print("{d}\n", .{ptr.*});

    allocator.deallocate(ptr);
}
