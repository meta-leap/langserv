const std = @import("std");

pub fn build(bld: *std.build.Builder) void {
    const mode = bld.standardReleaseOptions();

    const prog = bld.addExecutable("dummylangserver", "dummylangserver/main.zig");
    prog.setBuildMode(mode);
    addPackageDepsTo(prog);
    if (std.os.getenv("PATH")) |env_path|
        if (std.mem.indexOf(u8, env_path, ":/home/_/b:")) |_| // only locally at my end:
            prog.setOutputDir("/home/_/b/"); // place binary into in-PATH bin dir
    prog.install();

    const run_cmd = prog.run();
    if (bld.args) |args|
        run_cmd.addArgs(args);
    run_cmd.step.dependOn(bld.getInstallStep());
    bld.step("run", "Run the program, use -- for passing args").dependOn(&run_cmd.step);

    const demo = bld.addTest("tests.zig");
    demo.setBuildMode(mode);
    addPackageDepsTo(demo);
    bld.step("demo", "no-op. just tests if compiles. for actual demo of `dummylangserver`, use `zig build run` instead").dependOn(&demo.step);
}

fn addPackageDepsTo(it: *std.build.LibExeObjStep) void {
    it.addPackagePath("zag", "../zag/api.zig");
    it.addPackagePath("jsonic", "../jsonic/api.zig");
    it.addPackagePath("lsp", "api.zig");
}
