const std = @import("std");
const testing = std.testing;

const c = @cImport({
    @cInclude("greener_reporter/greener_reporter.h");
    @cInclude("greener_servermock/greener_servermock.h");
});

fn getFixtureNames(allocator: std.mem.Allocator) ![][]const u8 {
    const servermock = c.greener_servermock_new();
    defer {
        var err: ?*const c.greener_servermock_error_t = null;
        c.greener_servermock_delete(servermock, @ptrCast(&err));
    }

    var names: [*c][*c]const u8 = null;
    var num_names: u32 = 0;
    var err: ?*const c.greener_servermock_error_t = null;

    c.greener_servermock_fixture_names(servermock, @ptrCast(&names), &num_names, @ptrCast(&err));
    if (err != null) {
        const msg = std.mem.span(err.?.message);
        std.debug.print("failed to get fixture names: {s}\n", .{msg});
        return error.FixtureNamesFailed;
    }

    if (num_names == 0) {
        std.debug.print("no fixtures found\n", .{});
        return error.NoFixtures;
    }

    var result = try allocator.alloc([]const u8, num_names);
    for (0..num_names) |i| {
        const name_ptr = names[i];
        const name = std.mem.span(name_ptr);
        result[i] = try allocator.dupe(u8, name);
    }

    return result;
}

fn processFixture(allocator: std.mem.Allocator, fixture_name: []const u8) !void {
    const servermock = c.greener_servermock_new();

    const name_c = try allocator.dupeZ(u8, fixture_name);
    defer allocator.free(name_c);

    var calls: [*c]const u8 = null;
    var responses: [*c]const u8 = null;
    var err: ?*const c.greener_servermock_error_t = null;

    c.greener_servermock_fixture_calls(servermock, name_c.ptr, @ptrCast(&calls), @ptrCast(&err));
    if (err != null) {
        const msg = std.mem.span(err.?.message);
        std.debug.print("failed to get fixture calls: {s}\n", .{msg});
        return error.FixtureCallsFailed;
    }

    c.greener_servermock_fixture_responses(servermock, name_c.ptr, @ptrCast(&responses), @ptrCast(&err));
    if (err != null) {
        const msg = std.mem.span(err.?.message);
        std.debug.print("failed to get fixture responses: {s}\n", .{msg});
        return error.FixtureResponsesFailed;
    }

    c.greener_servermock_serve(servermock, responses, @ptrCast(&err));
    if (err != null) {
        const msg = std.mem.span(err.?.message);
        std.debug.print("failed to serve: {s}\n", .{msg});
        return error.ServeFailed;
    }

    const port = c.greener_servermock_get_port(servermock, @ptrCast(&err));
    if (err != null) {
        const msg = std.mem.span(err.?.message);
        std.debug.print("failed to get port: {s}\n", .{msg});
        return error.GetPortFailed;
    }

    const endpoint_str = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{port});
    defer allocator.free(endpoint_str);
    const endpoint = try allocator.dupeZ(u8, endpoint_str);
    defer allocator.free(endpoint);

    const api_key = "some-api-token";

    var reporter_error: ?*const c.greener_reporter_error_t = null;
    const reporter = c.greener_reporter_new(endpoint.ptr, api_key.ptr, @ptrCast(&reporter_error));
    if (reporter_error != null) {
        const msg = std.mem.span(reporter_error.?.message);
        std.debug.print("failed to create reporter: {s}\n", .{msg});
        return error.ReporterCreateFailed;
    }

    const calls_str = std.mem.span(calls);
    const responses_str = std.mem.span(responses);

    const calls_parsed = try std.json.parseFromSlice(std.json.Value, allocator, calls_str, .{});
    defer calls_parsed.deinit();

    const calls_array = calls_parsed.value.object.get("calls").?.array;

    for (calls_array.items) |call| {
        try makeCall(allocator, reporter, call, responses_str);
    }

    var del_error: ?*const c.greener_reporter_error_t = null;
    c.greener_reporter_delete(reporter, @ptrCast(&del_error));
    if (del_error != null) {
        const msg = std.mem.span(del_error.?.message);
        std.debug.print("failed to delete reporter: {s}\n", .{msg});
    }

    var assert_error: ?*const c.greener_servermock_error_t = null;
    c.greener_servermock_assert(servermock, calls, @ptrCast(&assert_error));
    if (assert_error != null) {
        const msg = std.mem.span(assert_error.?.message);
        std.debug.print("assert failed: {s}\n", .{msg});
        return error.AssertFailed;
    }
}

fn makeCall(
    allocator: std.mem.Allocator,
    reporter: ?*c.greener_reporter_t,
    call: std.json.Value,
    responses_str: []const u8,
) !void {
    const func = call.object.get("func").?.string;
    const payload = call.object.get("payload").?;

    if (std.mem.eql(u8, func, "createSession")) {
        const responses_parsed = try std.json.parseFromSlice(std.json.Value, allocator, responses_str, .{});
        defer responses_parsed.deinit();

        const response = responses_parsed.value.object.get("createSessionResponse").?;
        const status = response.object.get("status").?.string;

        const session_id_opt = payload.object.get("id");
        const description_opt = payload.object.get("description");
        const baggage_opt = payload.object.get("baggage");
        const labels_opt = payload.object.get("labels");

        var session_id_buf: ?[:0]u8 = null;
        var description_buf: ?[:0]u8 = null;
        var baggage_buf: ?[:0]u8 = null;
        var labels_buf: ?[:0]u8 = null;

        defer {
            if (session_id_buf) |b| allocator.free(b);
            if (description_buf) |b| allocator.free(b);
            if (baggage_buf) |b| allocator.free(b);
            if (labels_buf) |b| allocator.free(b);
        }

        const session_id_ptr: ?[*:0]const u8 = if (session_id_opt) |sid| blk: {
            if (sid == .string) {
                session_id_buf = try allocator.dupeZ(u8, sid.string);
                break :blk @ptrCast(session_id_buf.?.ptr);
            } else {
                break :blk null;
            }
        } else null;

        const description_ptr: ?[*:0]const u8 = if (description_opt) |desc| blk: {
            if (desc == .string) {
                description_buf = try allocator.dupeZ(u8, desc.string);
                break :blk @ptrCast(description_buf.?.ptr);
            } else {
                break :blk null;
            }
        } else null;

        const baggage_ptr: ?[*:0]const u8 = if (baggage_opt) |bag| blk: {
            if (bag != .null) {
                var out: std.Io.Writer.Allocating = .init(allocator);
                defer out.deinit();
                try std.json.Stringify.value(bag, .{}, &out.writer);
                const baggage_json = out.written();
                baggage_buf = try allocator.dupeZ(u8, baggage_json);
                break :blk @ptrCast(baggage_buf.?.ptr);
            } else {
                break :blk null;
            }
        } else null;

        const labels_ptr: ?[*:0]const u8 = if (labels_opt) |lbl| blk: {
            if (lbl == .string) {
                labels_buf = try allocator.dupeZ(u8, lbl.string);
                break :blk @ptrCast(labels_buf.?.ptr);
            } else {
                break :blk null;
            }
        } else null;

        if (std.mem.eql(u8, status, "success")) {
            var err: ?*const c.greener_reporter_error_t = null;
            const session = c.greener_reporter_session_create(
                reporter,
                session_id_ptr,
                description_ptr,
                baggage_ptr,
                labels_ptr,
                @ptrCast(&err),
            );

            if (err != null) {
                const msg = std.mem.span(err.?.message);
                std.debug.print("failed to create session: {s}\n", .{msg});
                return error.SessionCreateFailed;
            }

            const expected_id = response.object.get("payload").?.object.get("id").?.string;
            const actual_id = std.mem.span(session.*.id);

            if (!std.mem.eql(u8, actual_id, expected_id)) {
                std.debug.print("incorrect created session id: actual {s}, expected {s}\n", .{ actual_id, expected_id });
                return error.SessionIdMismatch;
            }

            c.greener_reporter_session_delete(session);
        } else if (std.mem.eql(u8, status, "error")) {
            var err: ?*const c.greener_reporter_error_t = null;
            _ = c.greener_reporter_session_create(
                reporter,
                session_id_ptr,
                description_ptr,
                baggage_ptr,
                labels_ptr,
                @ptrCast(&err),
            );

            if (err == null) {
                std.debug.print("session creation succeeded, should've failed\n", .{});
                return error.SessionShouldHaveFailed;
            }

            const expected_message = response.object.get("payload").?.object.get("message").?.string;
            const error_msg = std.mem.span(err.?.message);
            const expected_full = try std.fmt.allocPrint(allocator, "failed session request: {s}", .{expected_message});
            defer allocator.free(expected_full);

            if (std.mem.indexOf(u8, error_msg, expected_full) == null) {
                std.debug.print("incorrect error message: actual '{s}', expected to contain '{s}'\n", .{ error_msg, expected_full });
                return error.ErrorMessageMismatch;
            }
        } else {
            std.debug.print("unknown response status: {s}\n", .{status});
            return error.UnknownStatus;
        }
    } else if (std.mem.eql(u8, func, "report")) {
        const responses_parsed = try std.json.parseFromSlice(std.json.Value, allocator, responses_str, .{});
        defer responses_parsed.deinit();

        const response = responses_parsed.value.object.get("reportResponse").?;
        const status = response.object.get("status").?.string;

        var errors = std.ArrayList(?*const c.greener_reporter_error_t){};
        defer errors.deinit(allocator);

        const testcases = payload.object.get("testcases").?.array;
        for (testcases.items) |tc| {
            const session_id = tc.object.get("sessionId").?.string;
            const testcase_name = tc.object.get("testcaseName").?.string;
            const test_status = tc.object.get("status").?.string;
            const testcase_classname = tc.object.get("testcaseClassname");
            const testcase_file = tc.object.get("testcaseFile");
            const testsuite = tc.object.get("testsuite");

            const session_id_c = try allocator.dupeZ(u8, session_id);
            defer allocator.free(session_id_c);
            const testcase_name_c = try allocator.dupeZ(u8, testcase_name);
            defer allocator.free(testcase_name_c);
            const status_c = try allocator.dupeZ(u8, test_status);
            defer allocator.free(status_c);

            var testcase_classname_c: ?[:0]u8 = null;
            var testcase_file_c: ?[:0]u8 = null;
            var testsuite_c: ?[:0]u8 = null;
            defer {
                if (testcase_classname_c) |b| allocator.free(b);
                if (testcase_file_c) |b| allocator.free(b);
                if (testsuite_c) |b| allocator.free(b);
            }

            const testcase_classname_ptr: ?[*:0]const u8 = if (testcase_classname) |tc_cn| blk: {
                if (tc_cn == .string) {
                    testcase_classname_c = try allocator.dupeZ(u8, tc_cn.string);
                    break :blk @ptrCast(testcase_classname_c.?.ptr);
                } else {
                    break :blk null;
                }
            } else null;

            const testcase_file_ptr: ?[*:0]const u8 = if (testcase_file) |tc_f| blk: {
                if (tc_f == .string) {
                    testcase_file_c = try allocator.dupeZ(u8, tc_f.string);
                    break :blk @ptrCast(testcase_file_c.?.ptr);
                } else {
                    break :blk null;
                }
            } else null;

            const testsuite_ptr: ?[*:0]const u8 = if (testsuite) |ts| blk: {
                if (ts == .string) {
                    testsuite_c = try allocator.dupeZ(u8, ts.string);
                    break :blk @ptrCast(testsuite_c.?.ptr);
                } else {
                    break :blk null;
                }
            } else null;

            var err: ?*const c.greener_reporter_error_t = null;
            c.greener_reporter_testcase_create(
                reporter,
                session_id_c.ptr,
                testcase_name_c.ptr,
                testcase_classname_ptr,
                testcase_file_ptr,
                testsuite_ptr,
                status_c.ptr,
                null,
                null,
                @ptrCast(&err),
            );

            try errors.append(allocator, err);
        }

        const err = if (errors.items.len > 0) errors.items[0] else null;

        if (std.mem.eql(u8, status, "success")) {
            if (err != null) {
                const msg = std.mem.span(err.?.message);
                std.debug.print("failed to create testcase: {s}\n", .{msg});
                return error.TestcaseCreateFailed;
            }
        } else if (std.mem.eql(u8, status, "error")) {
            if (err == null) {
                std.debug.print("testcase creation succeeded, should've failed\n", .{});
                return error.TestcaseShouldHaveFailed;
            }

            const expected_message = response.object.get("payload").?.object.get("message").?.string;
            const error_msg = std.mem.span(err.?.message);
            const expected_full = try std.fmt.allocPrint(allocator, "failed testcase request: {s}", .{expected_message});
            defer allocator.free(expected_full);

            if (std.mem.indexOf(u8, error_msg, expected_full) == null) {
                std.debug.print("incorrect error message: actual '{s}', expected to contain '{s}'\n", .{ error_msg, expected_full });
                return error.ErrorMessageMismatch;
            }
        } else {
            std.debug.print("unknown response status: {s}\n", .{status});
            return error.UnknownStatus;
        }
    } else {
        std.debug.print("unknown function: {s}\n", .{func});
        return error.UnknownFunction;
    }
}

fn runIntegrationTest(allocator: std.mem.Allocator) !void {
    const fixture_names = try getFixtureNames(allocator);
    defer {
        for (fixture_names) |name| {
            allocator.free(name);
        }
        allocator.free(fixture_names);
    }

    for (fixture_names) |fixture_name| {
        std.debug.print("processing fixture {s}\n", .{fixture_name});
        try processFixture(allocator, fixture_name);
    }
}

test "ffi integration" {
    try runIntegrationTest(testing.allocator);
}
