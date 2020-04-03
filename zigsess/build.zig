const std = @import("std");

pub fn build(bld: *std.build.Builder) void {
    const build_mode = bld.standardReleaseOptions();
    const demo = bld.addTest("demo.zig");
    demo.setMainPkgPath("..");
    demo.setBuildMode(build_mode);
    bld.step("demo", "somewhere between smoke-test and demo").dependOn(&demo.step);
}
