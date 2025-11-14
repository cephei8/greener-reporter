const std = @import("std");

var global_gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
const global_alloc = global_gpa.allocator();

pub const greener_servermock = opaque {};
pub const greener_servermock_error = extern struct {
    message: [*:0]const u8,
};

pub export fn greener_servermock_new() *greener_servermock {
    const servermock = Servermock.init(global_alloc) catch unreachable;
    return @ptrCast(servermock);
}

pub export fn greener_servermock_delete(
    servermock: *greener_servermock,
    err: *?*const greener_servermock_error,
) void {
    err.* = null;
    const s: *Servermock = @ptrCast(@alignCast(servermock));
    s.deinit();
}

pub export fn greener_servermock_serve(
    servermock: *greener_servermock,
    responses: [*:0]const u8,
    err: *?*const greener_servermock_error,
) void {
    err.* = null;

    const s: *Servermock = @ptrCast(@alignCast(servermock));
    const rs = std.mem.span(responses);

    s.serve(rs) catch |e| {
        const msg = global_alloc.dupeZ(u8, @errorName(e)) catch return;
        const error_obj = global_alloc.create(greener_servermock_error) catch {
            global_alloc.free(msg);
            return;
        };
        error_obj.* = .{ .message = msg };
        err.* = error_obj;
    };
}

pub export fn greener_servermock_get_port(
    servermock: *greener_servermock,
    err: *?*const greener_servermock_error,
) i32 {
    err.* = null;

    const s: *Servermock = @ptrCast(@alignCast(servermock));
    return s.port;
}

pub export fn greener_servermock_assert(
    servermock: *greener_servermock,
    calls: [*:0]const u8,
    err: *?*const greener_servermock_error,
) bool {
    err.* = null;

    const s: *Servermock = @ptrCast(@alignCast(servermock));
    const cs = std.mem.span(calls);

    s.assertCalls(cs) catch |e| {
        const msg = global_alloc.dupeZ(u8, @errorName(e)) catch return false;
        const error_obj = global_alloc.create(greener_servermock_error) catch {
            global_alloc.free(msg);
            return false;
        };
        error_obj.* = .{ .message = msg };
        err.* = error_obj;
        return false;
    };

    return true;
}

pub export fn greener_servermock_fixture_names(
    servermock: *greener_servermock,
    names: *?[*]const [*:0]const u8,
    num_names: *u32,
    err: *?*const greener_servermock_error,
) void {
    err.* = null;

    const s: *Servermock = @ptrCast(@alignCast(servermock));

    if (s.fixture_names_cache) |cache| {
        names.* = cache.names_ptr;
        num_names.* = cache.num_names;
        return;
    }

    const num_fixtures: u32 = @intCast(s.fixtures.items.len);
    if (num_fixtures == 0) {
        names.* = null;
        num_names.* = 0;
        return;
    }

    const names_array = global_alloc.alloc([*:0]const u8, num_fixtures) catch {
        const msg = global_alloc.dupeZ(u8, "failed to allocate memory") catch return;
        const error_obj = global_alloc.create(greener_servermock_error) catch {
            global_alloc.free(msg);
            return;
        };
        error_obj.* = .{ .message = msg };
        err.* = error_obj;
        return;
    };

    for (s.fixtures.items, 0..) |fixture, i| {
        names_array[i] = global_alloc.dupeZ(u8, fixture.name) catch {
            for (0..i) |j| {
                global_alloc.free(std.mem.span(names_array[j]));
            }
            global_alloc.free(names_array);
            const msg = global_alloc.dupeZ(u8, "failed to allocate memory") catch return;
            const error_obj = global_alloc.create(greener_servermock_error) catch {
                global_alloc.free(msg);
                return;
            };
            error_obj.* = .{ .message = msg };
            err.* = error_obj;
            return;
        };
    }

    s.fixture_names_cache = .{
        .names_ptr = names_array.ptr,
        .num_names = num_fixtures,
    };

    names.* = names_array.ptr;
    num_names.* = num_fixtures;
}

pub export fn greener_servermock_fixture_calls(
    servermock: *greener_servermock,
    fixture_name: [*:0]const u8,
    calls: *?[*:0]const u8,
    err: *?*const greener_servermock_error,
) void {
    err.* = null;

    const s: *Servermock = @ptrCast(@alignCast(servermock));
    const name = std.mem.span(fixture_name);

    for (s.fixture_calls_cache.items) |entry| {
        if (std.mem.eql(u8, std.mem.span(entry.name_ptr), name)) {
            calls.* = entry.data_ptr;
            return;
        }
    }

    for (s.fixtures.items) |fixture| {
        if (std.mem.eql(u8, fixture.name, name)) {
            const calls_str = global_alloc.dupeZ(u8, fixture.fixture.calls) catch {
                const msg = global_alloc.dupeZ(u8, "failed to allocate memory") catch return;
                const error_obj = global_alloc.create(greener_servermock_error) catch {
                    global_alloc.free(msg);
                    return;
                };
                error_obj.* = .{ .message = msg };
                err.* = error_obj;
                return;
            };

            const name_dup = global_alloc.dupeZ(u8, name) catch {
                global_alloc.free(calls_str);
                const msg = global_alloc.dupeZ(u8, "failed to allocate memory") catch return;
                const error_obj = global_alloc.create(greener_servermock_error) catch {
                    global_alloc.free(msg);
                    return;
                };
                error_obj.* = .{ .message = msg };
                err.* = error_obj;
                return;
            };

            s.fixture_calls_cache.append(global_alloc, FixtureCacheEntry{
                .name_ptr = name_dup,
                .data_ptr = calls_str,
            }) catch {
                global_alloc.free(calls_str);
                global_alloc.free(name_dup);
                const msg = global_alloc.dupeZ(u8, "failed to allocate memory") catch return;
                const error_obj = global_alloc.create(greener_servermock_error) catch {
                    global_alloc.free(msg);
                    return;
                };
                error_obj.* = .{ .message = msg };
                err.* = error_obj;
                return;
            };

            calls.* = calls_str;
            return;
        }
    }

    const msg = global_alloc.dupeZ(u8, "fixture not found") catch return;
    const error_obj = global_alloc.create(greener_servermock_error) catch {
        global_alloc.free(msg);
        return;
    };
    error_obj.* = .{ .message = msg };
    err.* = error_obj;
}

pub export fn greener_servermock_fixture_responses(
    servermock: *greener_servermock,
    fixture_name: [*:0]const u8,
    responses: *?[*:0]const u8,
    err: *?*const greener_servermock_error,
) void {
    err.* = null;

    const s: *Servermock = @ptrCast(@alignCast(servermock));
    const name = std.mem.span(fixture_name);

    for (s.fixture_responses_cache.items) |entry| {
        if (std.mem.eql(u8, std.mem.span(entry.name_ptr), name)) {
            responses.* = entry.data_ptr;
            return;
        }
    }

    for (s.fixtures.items) |fixture| {
        if (std.mem.eql(u8, fixture.name, name)) {
            const responses_str = global_alloc.dupeZ(u8, fixture.fixture.responses) catch {
                const msg = global_alloc.dupeZ(u8, "failed to allocate memory") catch return;
                const error_obj = global_alloc.create(greener_servermock_error) catch {
                    global_alloc.free(msg);
                    return;
                };
                error_obj.* = .{ .message = msg };
                err.* = error_obj;
                return;
            };

            const name_dup = global_alloc.dupeZ(u8, name) catch {
                global_alloc.free(responses_str);
                const msg = global_alloc.dupeZ(u8, "failed to allocate memory") catch return;
                const error_obj = global_alloc.create(greener_servermock_error) catch {
                    global_alloc.free(msg);
                    return;
                };
                error_obj.* = .{ .message = msg };
                err.* = error_obj;
                return;
            };

            s.fixture_responses_cache.append(global_alloc, FixtureCacheEntry{
                .name_ptr = name_dup,
                .data_ptr = responses_str,
            }) catch {
                global_alloc.free(responses_str);
                global_alloc.free(name_dup);
                const msg = global_alloc.dupeZ(u8, "failed to allocate memory") catch return;
                const error_obj = global_alloc.create(greener_servermock_error) catch {
                    global_alloc.free(msg);
                    return;
                };
                error_obj.* = .{ .message = msg };
                err.* = error_obj;
                return;
            };

            responses.* = responses_str;
            return;
        }
    }

    const msg = global_alloc.dupeZ(u8, "fixture not found") catch return;
    const error_obj = global_alloc.create(greener_servermock_error) catch {
        global_alloc.free(msg);
        return;
    };
    error_obj.* = .{ .message = msg };
    err.* = error_obj;
}

pub export fn greener_servermock_error_delete(err: *const greener_servermock_error) void {
    global_alloc.free(std.mem.span(err.message));
    global_alloc.destroy(err);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

const ApiCall = struct {
    func: []const u8,
    payload: std.json.Value,

    fn deinit(self: ApiCall, alloc: std.mem.Allocator) void {
        alloc.free(self.func);
    }
};

const Fixture = struct {
    calls: []const u8,
    responses: []const u8,

    fn deinit(self: Fixture, alloc: std.mem.Allocator) void {
        alloc.free(self.calls);
        alloc.free(self.responses);
    }
};

const NamedFixture = struct {
    name: []const u8,
    fixture: Fixture,

    fn deinit(self: NamedFixture, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        self.fixture.deinit(alloc);
    }
};

const FixtureCacheEntry = struct {
    name_ptr: [*:0]const u8,
    data_ptr: [*:0]const u8,
};

const ServerContext = struct {
    alloc: std.mem.Allocator,
    responses: std.json.Parsed(std.json.Value),
    recorded_calls: *std.ArrayList(ApiCall),
    mutex: *std.Thread.Mutex,
};

const Servermock = struct {
    alloc: std.mem.Allocator,
    port: i32,
    responses_str: []const u8,
    responses_json: std.json.Parsed(std.json.Value),
    recorded_calls: std.ArrayList(ApiCall),
    fixtures: std.ArrayList(NamedFixture),
    server_thread: ?std.Thread,
    tcp_server: ?*std.net.Server,
    shutdown: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,

    fixture_calls_cache: std.ArrayList(FixtureCacheEntry),
    fixture_responses_cache: std.ArrayList(FixtureCacheEntry),
    fixture_names_cache: ?struct {
        names_ptr: [*]const [*:0]const u8,
        num_names: u32,
    },

    fn init(alloc: std.mem.Allocator) !*Servermock {
        const servermock = try alloc.create(Servermock);
        errdefer alloc.destroy(servermock);

        servermock.* = Servermock{
            .alloc = alloc,
            .port = -1,
            .responses_str = &[_]u8{},
            .responses_json = undefined,
            .recorded_calls = std.ArrayList(ApiCall){},
            .fixtures = std.ArrayList(NamedFixture){},
            .server_thread = null,
            .tcp_server = null,
            .shutdown = std.atomic.Value(bool).init(false),
            .mutex = .{},
            .fixture_calls_cache = std.ArrayList(FixtureCacheEntry){},
            .fixture_responses_cache = std.ArrayList(FixtureCacheEntry){},
            .fixture_names_cache = null,
        };

        const empty_json = "{}";
        servermock.responses_json = try std.json.parseFromSlice(
            std.json.Value,
            alloc,
            empty_json,
            .{},
        );

        try initializeFixtures(servermock);

        return servermock;
    }

    fn deinit(self: *Servermock) void {
        if (self.server_thread != null) {
            self.shutdown.store(true, .release);
            if (self.server_thread) |thread| {
                thread.join();
            }
        }

        if (self.tcp_server) |server| {
            server.deinit();
            self.alloc.destroy(server);
        }

        for (self.recorded_calls.items) |call| {
            call.deinit(self.alloc);
        }
        self.recorded_calls.deinit(self.alloc);

        for (self.fixtures.items) |fixture| {
            fixture.deinit(self.alloc);
        }
        self.fixtures.deinit(self.alloc);

        for (self.fixture_calls_cache.items) |entry| {
            self.alloc.free(std.mem.span(entry.name_ptr));
            self.alloc.free(std.mem.span(entry.data_ptr));
        }
        self.fixture_calls_cache.deinit(self.alloc);

        for (self.fixture_responses_cache.items) |entry| {
            self.alloc.free(std.mem.span(entry.name_ptr));
            self.alloc.free(std.mem.span(entry.data_ptr));
        }
        self.fixture_responses_cache.deinit(self.alloc);

        if (self.fixture_names_cache) |cache| {
            for (0..cache.num_names) |i| {
                self.alloc.free(std.mem.span(cache.names_ptr[i]));
            }
            self.alloc.free(cache.names_ptr[0..cache.num_names]);
            self.fixture_names_cache = null;
        }

        if (self.responses_str.len > 0) {
            self.alloc.free(self.responses_str);
        }
        self.responses_json.deinit();

        self.alloc.destroy(self);
    }

    fn serve(self: *Servermock, responses: []const u8) !void {
        if (self.responses_str.len > 0) {
            self.alloc.free(self.responses_str);
        }
        self.responses_json.deinit();

        self.responses_str = try self.alloc.dupe(u8, responses);
        self.responses_json = try std.json.parseFromSlice(
            std.json.Value,
            self.alloc,
            self.responses_str,
            .{},
        );

        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        const tcp_server_value = try addr.listen(.{
            .reuse_address = true,
        });

        const bound_addr = tcp_server_value.listen_address;
        self.port = @intCast(bound_addr.in.getPort());

        const server_ptr = try self.alloc.create(std.net.Server);
        errdefer self.alloc.destroy(server_ptr);
        server_ptr.* = tcp_server_value;

        self.tcp_server = server_ptr;

        self.server_thread = try std.Thread.spawn(.{}, serverThread, .{self});
    }

    fn serverThread(self: *Servermock) !void {
        const tcp_server = self.tcp_server orelse return;

        var context = ServerContext{
            .alloc = self.alloc,
            .responses = self.responses_json,
            .recorded_calls = &self.recorded_calls,
            .mutex = &self.mutex,
        };

        while (!self.shutdown.load(.acquire)) {
            const connection = try tcp_server.accept();
            try handleConnection(connection, &context);
        }
    }

    fn assertCalls(self: *Servermock, expected_calls: []const u8) !void {
        const expected = try std.json.parseFromSlice(
            std.json.Value,
            self.alloc,
            expected_calls,
            .{},
        );
        defer expected.deinit();

        const calls_obj = expected.value.object.get("calls") orelse {
            return error.InvalidExpectedCalls;
        };
        const expected_arr = calls_obj.array;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.recorded_calls.items.len != expected_arr.items.len) {
            std.debug.print(
                "call count mismatch. expected {d} calls but got {d}.\n",
                .{ expected_arr.items.len, self.recorded_calls.items.len },
            );
            return error.CallCountMismatch;
        }

        for (expected_arr.items, 0..) |expected_call, i| {
            const actual_call = &self.recorded_calls.items[i];

            const expected_func = expected_call.object.get("func").?.string;
            if (!std.mem.eql(u8, expected_func, actual_call.func)) {
                std.debug.print(
                    "call {d} function mismatch. Expected '{s}' but got '{s}'\n",
                    .{ i, expected_func, actual_call.func },
                );
                return error.FunctionMismatch;
            }

            const expected_payload = expected_call.object.get("payload").?;
            if (!jsonEqual(expected_payload, actual_call.payload)) {
                std.debug.print(
                    "call {d} payload mismatch.\n",
                    .{i},
                );
                return error.PayloadMismatch;
            }
        }
    }
};

fn handleConnection(connection: std.net.Server.Connection, context: *ServerContext) !void {
    defer connection.stream.close();

    var buffer: [16384]u8 = undefined;
    const bytes_read = try connection.stream.read(&buffer);
    if (bytes_read == 0) return;

    const request = buffer[0..bytes_read];

    var lines = std.mem.splitScalar(u8, request, '\n');
    const first_line = lines.next() orelse return;
    var parts = std.mem.splitScalar(u8, first_line, ' ');
    const method = parts.next() orelse return;
    const path_raw = parts.next() orelse return;
    const path = std.mem.trimRight(u8, path_raw, "\r");

    const body = if (std.mem.indexOf(u8, request, "\r\n\r\n")) |idx|
        request[idx + 4 ..]
    else
        &[_]u8{};

    if (std.mem.eql(u8, method, "POST")) {
        if (std.mem.eql(u8, path, "/api/v1/ingress/sessions")) {
            try handleCreateSession(body, context, connection.stream);
            return;
        } else if (std.mem.eql(u8, path, "/api/v1/ingress/testcases")) {
            try handleCreateTestcases(body, context, connection.stream);
            return;
        }
    }

    _ = try connection.stream.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
}

fn handleCreateSession(body: []const u8, context: *ServerContext, stream: std.net.Stream) !void {
    var session_parsed = try std.json.parseFromSlice(
        std.json.Value,
        context.alloc,
        body,
        .{},
    );
    defer session_parsed.deinit();

    var session = session_parsed.value;

    if (session.object.getPtr("labels")) |labels_ptr| {
        if (labels_ptr.* != .null and labels_ptr.* == .array) {
            var labels_str = std.ArrayList(u8){};
            defer labels_str.deinit(context.alloc);

            for (labels_ptr.array.items, 0..) |label, i| {
                if (i > 0) try labels_str.append(context.alloc, ',');

                const key = label.object.get("key").?.string;
                try labels_str.appendSlice(context.alloc, key);

                if (label.object.get("value")) |value| {
                    if (value != .null and value == .string) {
                        try labels_str.append(context.alloc, '=');
                        try labels_str.appendSlice(context.alloc, value.string);
                    }
                }
            }

            const labels_string = try labels_str.toOwnedSlice(context.alloc);
            defer context.alloc.free(labels_string);

            const json_str = try std.fmt.allocPrint(context.alloc, "\"{s}\"", .{labels_string});
            defer context.alloc.free(json_str);

            const new_labels = try std.json.parseFromSlice(
                std.json.Value,
                context.alloc,
                json_str,
                .{},
            );
            defer new_labels.deinit();

            labels_ptr.* = new_labels.value;
        }
    }

    {
        context.mutex.lock();
        defer context.mutex.unlock();

        const func = try context.alloc.dupe(u8, "createSession");
        try context.recorded_calls.append(context.alloc, ApiCall{
            .func = func,
            .payload = session,
        });
    }

    const create_session_response = context.responses.value.object.get("createSessionResponse") orelse {
        _ = try stream.write("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n");
        return;
    };

    const status = create_session_response.object.get("status").?.string;
    const payload = create_session_response.object.get("payload").?;

    if (std.mem.eql(u8, status, "success")) {
        const id = payload.object.get("id").?.string;

        const response_body = try std.fmt.allocPrint(
            context.alloc,
            "{{\"id\":\"{s}\"}}",
            .{id},
        );
        defer context.alloc.free(response_body);

        const response_str = try std.fmt.allocPrint(
            context.alloc,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ response_body.len, response_body },
        );
        defer context.alloc.free(response_str);
        _ = try stream.write(response_str);
    } else {
        const code = payload.object.get("code").?.integer;
        const ingress_code = payload.object.get("ingressCode").?.integer;
        const message = payload.object.get("message").?.string;

        const response_body = try std.fmt.allocPrint(
            context.alloc,
            "{{\"code\":{d},\"ingressCode\":{d},\"message\":\"{s}\"}}",
            .{ code, ingress_code, message },
        );
        defer context.alloc.free(response_body);

        const response_str = try std.fmt.allocPrint(
            context.alloc,
            "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ response_body.len, response_body },
        );
        defer context.alloc.free(response_str);
        _ = try stream.write(response_str);
    }
}

fn handleCreateTestcases(body: []const u8, context: *ServerContext, stream: std.net.Stream) !void {
    const testcase = try std.json.parseFromSlice(
        std.json.Value,
        context.alloc,
        body,
        .{},
    );
    defer testcase.deinit();

    {
        context.mutex.lock();
        defer context.mutex.unlock();

        const func = try context.alloc.dupe(u8, "report");
        try context.recorded_calls.append(context.alloc, ApiCall{
            .func = func,
            .payload = testcase.value,
        });
    }

    const status = if (context.responses.value.object.get("status")) |s|
        s.string
    else
        "success";

    if (std.mem.eql(u8, status, "success")) {
        _ = try stream.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 0\r\n\r\n");
    } else {
        const report_response = context.responses.value.object.get("reportResponse").?;
        const payload = report_response.object.get("payload").?;

        const code = payload.object.get("code").?.integer;
        const ingress_code = payload.object.get("ingressCode").?.integer;
        const message = payload.object.get("message").?.string;

        const response_body = try std.fmt.allocPrint(
            context.alloc,
            "{{\"code\":{d},\"ingressCode\":{d},\"message\":\"{s}\"}}",
            .{ code, ingress_code, message },
        );
        defer context.alloc.free(response_body);

        const response_str = try std.fmt.allocPrint(
            context.alloc,
            "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ response_body.len, response_body },
        );
        defer context.alloc.free(response_str);
        _ = try stream.write(response_str);
    }
}

fn jsonEqual(a: std.json.Value, b: std.json.Value) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;

    return switch (a) {
        .null => true,
        .bool => |av| av == b.bool,
        .integer => |av| av == b.integer,
        .float => |av| av == b.float,
        .number_string => |av| std.mem.eql(u8, av, b.number_string),
        .string => |av| std.mem.eql(u8, av, b.string),
        .array => |av| {
            if (av.items.len != b.array.items.len) return false;
            for (av.items, b.array.items) |ai, bi| {
                if (!jsonEqual(ai, bi)) return false;
            }
            return true;
        },
        .object => |av| {
            if (av.count() != b.object.count()) return false;
            var iter = av.iterator();
            while (iter.next()) |entry| {
                const bv = b.object.get(entry.key_ptr.*) orelse return false;
                if (!jsonEqual(entry.value_ptr.*, bv)) return false;
            }
            return true;
        },
    };
}

fn initializeFixtures(servermock: *Servermock) !void {
    const fixture_json_data = try getFixtures(servermock.alloc);
    defer {
        for (fixture_json_data) |data| {
            servermock.alloc.free(data.name);
            servermock.alloc.free(data.calls_json);
            servermock.alloc.free(data.responses_json);
        }
        servermock.alloc.free(fixture_json_data);
    }

    for (fixture_json_data) |data| {
        const name = try servermock.alloc.dupe(u8, data.name);
        const calls = try servermock.alloc.dupe(u8, data.calls_json);
        const responses = try servermock.alloc.dupe(u8, data.responses_json);

        try servermock.fixtures.append(servermock.alloc, NamedFixture{
            .name = name,
            .fixture = Fixture{
                .calls = calls,
                .responses = responses,
            },
        });
    }
}

const FixtureJsonData = struct {
    name: []const u8,
    calls_json: []const u8,
    responses_json: []const u8,
};

fn getFixtures(alloc: std.mem.Allocator) ![]FixtureJsonData {
    var list = std.ArrayList(FixtureJsonData){};

    try list.append(alloc, .{
        .name = try alloc.dupe(u8, "createSessionWithId"),
        .calls_json = try alloc.dupe(u8,
            \\{
            \\  "calls": [
            \\    {
            \\      "func": "createSession",
            \\      "payload": {
            \\        "id": "c209c477-d186-49a7-ab83-2ba6dcb409b4",
            \\        "description": "some description",
            \\        "baggage": {
            \\          "a": "b"
            \\        },
            \\        "labels": "ab=2,cd"
            \\      }
            \\    }
            \\  ]
            \\}
        ),
        .responses_json = try alloc.dupe(u8,
            \\{
            \\  "createSessionResponse": {
            \\    "status": "success",
            \\    "payload": {
            \\      "id": "16af52dc-3296-4249-be93-3aaef3a85845"
            \\    }
            \\  },
            \\  "reportResponse": {
            \\    "status": "success",
            \\    "payload": null
            \\  }
            \\}
        ),
    });

    try list.append(alloc, .{
        .name = try alloc.dupe(u8, "createSessionWithoutId"),
        .calls_json = try alloc.dupe(u8,
            \\{
            \\  "calls": [
            \\    {
            \\      "func": "createSession",
            \\      "payload": {
            \\        "id": null,
            \\        "description": null,
            \\        "baggage": null,
            \\        "labels": null
            \\      }
            \\    }
            \\  ]
            \\}
        ),
        .responses_json = try alloc.dupe(u8,
            \\{
            \\  "createSessionResponse": {
            \\    "status": "success",
            \\    "payload": {
            \\      "id": "16af52dc-3296-4249-be93-3aaef3a85845"
            \\    }
            \\  },
            \\  "reportResponse": {
            \\    "status": "success",
            \\    "payload": null
            \\  }
            \\}
        ),
    });

    try list.append(alloc, .{
        .name = try alloc.dupe(u8, "createSessionResponseError"),
        .calls_json = try alloc.dupe(u8,
            \\{
            \\  "calls": [
            \\    {
            \\      "func": "createSession",
            \\      "payload": {
            \\        "id": null,
            \\        "description": null,
            \\        "baggage": null,
            \\        "labels": null
            \\      }
            \\    }
            \\  ]
            \\}
        ),
        .responses_json = try alloc.dupe(u8,
            \\{
            \\  "createSessionResponse": {
            \\    "status": "error",
            \\    "payload": {
            \\      "code": 3,
            \\      "ingressCode": 400,
            \\      "message": "error message"
            \\    }
            \\  },
            \\  "reportResponse": {
            \\    "status": "success",
            \\    "payload": null
            \\  }
            \\}
        ),
    });

    try list.append(alloc, .{
        .name = try alloc.dupe(u8, "report"),
        .calls_json = try alloc.dupe(u8,
            \\{
            \\  "calls": [
            \\    {
            \\      "func": "report",
            \\      "payload": {
            \\        "testcases": [
            \\          {
            \\            "sessionId": "16af52dc-3296-4249-be93-3aaef3a85111",
            \\            "testcaseName": "test_some_logic",
            \\            "testcaseClassname": "my_class",
            \\            "testcaseFile": "my_file.py",
            \\            "testsuite": "some test suite",
            \\            "status": "pass",
            \\            "output": null,
            \\            "baggage": null
            \\          }
            \\        ]
            \\      }
            \\    }
            \\  ]
            \\}
        ),
        .responses_json = try alloc.dupe(u8,
            \\{
            \\  "createSessionResponse": {
            \\    "status": "success",
            \\    "payload": {
            \\      "id": "16af52dc-3296-4249-be93-3aaef3a85845"
            \\    }
            \\  },
            \\  "reportResponse": {
            \\    "status": "success",
            \\    "payload": null
            \\  }
            \\}
        ),
    });

    try list.append(alloc, .{
        .name = try alloc.dupe(u8, "reportNameOnly"),
        .calls_json = try alloc.dupe(u8,
            \\{
            \\  "calls": [
            \\    {
            \\      "func": "report",
            \\      "payload": {
            \\        "testcases": [
            \\          {
            \\            "sessionId": "16af52dc-3296-4249-be93-3aaef3a85878",
            \\            "testcaseName": "test_some_logic",
            \\            "testcaseClassname": null,
            \\            "testcaseFile": null,
            \\            "testsuite": null,
            \\            "status": "skip",
            \\            "output": null,
            \\            "baggage": null
            \\          }
            \\        ]
            \\      }
            \\    }
            \\  ]
            \\}
        ),
        .responses_json = try alloc.dupe(u8,
            \\{
            \\  "createSessionResponse": {
            \\    "status": "success",
            \\    "payload": {
            \\      "id": "16af52dc-3296-4249-be93-3aaef3a85845"
            \\    }
            \\  },
            \\  "reportResponse": {
            \\    "status": "success",
            \\    "payload": null
            \\  }
            \\}
        ),
    });

    return try list.toOwnedSlice(alloc);
}
