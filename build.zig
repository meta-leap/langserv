const std = @import("std");

const lib_zag = std.build.Pkg{
    .name = "zag",
    .path = "../zag/api.zig",
};
const lib_jsonic = std.build.Pkg{
    .name = "jsonic",
    .path = "../jsonic/api.zig",
    .dependencies = &[_]std.build.Pkg{lib_zag},
};
const lib_lsp = std.build.Pkg{
    .name = "lsp",
    .path = "./api.zig",
    .dependencies = &[_]std.build.Pkg{ lib_zag, lib_jsonic },
};

fn addPackageDepsTo(it: *std.build.LibExeObjStep) void {
    it.addPackage(lib_zag);
    it.addPackage(lib_jsonic);
    it.addPackage(lib_lsp);
}

pub fn build(bld: *std.build.Builder) void {
    const mode = bld.standardReleaseOptions();

    const demo = bld.addTest("tests.zig");
    demo.setBuildMode(mode);
    addPackageDepsTo(demo);
    bld.step("demo", "no-op for now").dependOn(&demo.step);
}
