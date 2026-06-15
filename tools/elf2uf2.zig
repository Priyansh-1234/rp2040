// The Data used in the program is gotten from the official
// raspberry pi pico (rp2040) datasheet.
// https://pip-assets.raspberrypi.com/categories/814-rp2040/documents/RP-008371-DS-1-rp2040-datasheet.pdf
// The sections are provided for further info
const std = @import("std");
const Io = std.Io;

const magic_start_0 = 0x0A324655;
const magic_start_1 = 0x9E5D5157;
const magic_end = 0x0AB16F30;
const family_id_present = 0x00002000;

// Section 2.8.4.2 UF2 Format Details
const rp2040_family_id = 0xe48bff56;

const flash_addr = 0x1000_0000;

const Uf2Block = extern struct {
    magic_start_0: u32 = magic_start_0,
    magic_start_1: u32 = magic_start_1,
    flags: u32 = family_id_present,
    target_addr: u32,
    payload_size: u32 = 256,
    block_number: u32,
    num_blocks: u32,
    family_id: u32 = rp2040_family_id,
    data: [476]u8 = [_]u8{0} ** 476,
    magic_end: u32 = magic_end,
};

fn rp2040_boot2_checksum(bytes: []const u8) u32 {
    // Section 2.8.1.3.1. Checksum
    const crc32 = std.hash.crc.Crc(u32, .{
        .polynomial = 0x04c11db7,
        .initial = 0xffffffff,
        .reflect_input = false,
        .reflect_output = false,
        .xor_output = 0x00000000,
    });
    return crc32.hash(bytes);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 3) {
        return error.NotEnoughArguments;
    }

    const input_path = args[1];
    const output_path = args[2];

    const cwd = Io.Dir.cwd();
    const input_file = try cwd.openFile(io, input_path, .{ .mode = .read_only });
    defer input_file.close(io);

    const input_size = try input_file.length(io);
    const input_data = try allocator.alloc(u8, input_size);

    const size_read = try input_file.readPositionalAll(io, input_data, 0);
    std.debug.assert(size_read == input_size);

    if (input_size >= 256) {
        // The first 252 bytes contain the bootloader and there needs to be
        // a 4byte check sum in little endian after this.
        const checksum = rp2040_boot2_checksum(input_data[0..252]);
        // We can safely assume the 4bytes at the end of the first
        // 256 block is useless and can be overwritten
        std.mem.writeInt(u32, input_data[252..256], checksum, .little);
    }

    const output_file = try cwd.createFile(io, output_path, .{});
    defer output_file.close(io);

    var write_buffer: [4096]u8 = undefined;
    var file_writer = output_file.writer(io, &write_buffer);
    const writer = &file_writer.interface;

    const num_blocks: u32 = @truncate((input_size + 255) / 256);
    for (0..num_blocks) |i| {
        var block: Uf2Block = .{
            .num_blocks = num_blocks,
            .block_number = @truncate(i),
            .target_addr = flash_addr + @as(u32, @intCast(i * 256)),
        };

        const start = i * 256;
        const end = @min(start + 256, input_data.len);
        const size = end - start;
        @memcpy(block.data[0..size], input_data[start..end]);
        try writer.writeStruct(block, .little);
    }

    try writer.flush();
}
