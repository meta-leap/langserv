const std = @import("std");

pub const ErrorCodes = enum(isize) {
    RequestCancelled = -32800,
    ContentModified = -32801,
};
