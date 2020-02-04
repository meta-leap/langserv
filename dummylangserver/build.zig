const std = @import("std");

const lib_zag = std.build.Pkg{
    .name = "zag",
    .path = "../../zag/api.zig",
};
const lib_jsonic = std.build.Pkg{
    .name = "jsonic",
    .path = "../../jsonic/api.zig",
    .dependencies = &[_]std.build.Pkg{lib_zag},
};
const lib_lsp = std.build.Pkg{
    .name = "lsp",
    .path = "../api.zig",
    .dependencies = &[_]std.build.Pkg{ lib_zag, lib_jsonic },
};

fn addPackageDepsTo(it: *std.build.LibExeObjStep) void {
    it.addPackage(lib_lsp);
    it.addPackage(lib_jsonic);
    it.addPackage(lib_zag);
    // it.addPackagePath("zag", "../../zag/api.zig");
    // it.addPackagePath("lsp", "../api.zig");
    // it.addPackagePath("jsonic", "../../jsonic/api.zig");
}

pub fn build(bld: *std.build.Builder) void {
    const mode = bld.standardReleaseOptions();

    const prog = bld.addExecutable("dummylangserver", "./main.zig");
    prog.setBuildMode(mode);
    addPackageDepsTo(prog);
    if (std.os.getenv("PATH")) |env_path|
        if (std.mem.indexOf(u8, env_path, ":/home/_/b:")) |_| // only locally at my end:
            prog.setOutputDir("/home/_/b/"); // place binary into in-PATH bin dir
    prog.install();

    // const run_cmd = prog.run();
    // if (bld.args) |args|
    //     run_cmd.addArgs(args);
    // run_cmd.step.dependOn(bld.getInstallStep());
    // bld.step("run", "Run the program, use -- for passing args").dependOn(&run_cmd.step);
}
