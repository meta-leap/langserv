const std = @import("std");

pub fn build(bld: *std.build.Builder) void {
    const mode = bld.standardReleaseOptions();

    const demo = bld.addTest("tests.zig");
    demo.setMainPkgPath("..");
    demo.setBuildMode(mode);
    bld.step("demo", "no-op for now").dependOn(&demo.step);

    const prog_dummy = bld.addExecutable("dummylangserver", "dummylangserver/main.zig");
    prog_dummy.setMainPkgPath("..");
    prog_dummy.setBuildMode(mode);
    if (std.os.getenv("PATH")) |env_path|
        if (std.mem.indexOf(u8, env_path, ":/home/_/b:")) |_| // only locally at my end:
            prog_dummy.setOutputDir("/home/_/b/"); // place binary into in-PATH bin dir
    prog_dummy.install();

    const prog_wip = bld.addExecutable("wiplangserver", "wiplangserver/main.zig");
    prog_wip.setMainPkgPath("..");
    prog_wip.setBuildMode(mode);
    if (std.os.getenv("PATH")) |env_path|
        if (std.mem.indexOf(u8, env_path, ":/home/_/b:")) |_| // only locally at my end:
            prog_wip.setOutputDir("/home/_/b/"); // place binary into in-PATH bin dir
    prog_wip.install();
}
