const std = @import("std");

var global_gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
const global_alloc = global_gpa.allocator();

pub const greener_reporter = opaque {};
pub const greener_reporter_session = extern struct {
    id: [*:0]const u8,
};
pub const greener_reporter_error = extern struct {
    code: c_int,
    ingress_code: c_int,
    message: [*:0]const u8,
};

pub const GREENER_REPORTER_ERROR: c_int = 1;
pub const GREENER_REPORTER_ERROR_INVALID_ARGUMENT: c_int = 2;
pub const GREENER_REPORTER_ERROR_INGRESS: c_int = 3;

pub export fn greener_reporter_new(
    endpoint: ?[*:0]const u8,
    api_key: ?[*:0]const u8,
    err: *?*const greener_reporter_error,
) ?*greener_reporter {
    err.* = null;

    var err_detail: ?ErrorDetail = null;
    const reporter = Reporter.init(
        global_alloc,
        endpoint,
        api_key,
        &err_detail,
    ) catch |e| {
        err.* = createError(global_alloc, e, err_detail);
        return null;
    };

    return @ptrCast(reporter);
}

pub export fn greener_reporter_delete(
    reporter: *greener_reporter,
    err: *?*const greener_reporter_error,
) void {
    err.* = null;

    const r: *Reporter = @ptrCast(@alignCast(reporter));

    r.deinit() catch |e| {
        err.* = createError(global_alloc, e, null);
    };
    global_alloc.destroy(r);
}

pub export fn greener_reporter_report_error_pop(
    reporter: *greener_reporter,
    err: *?*const greener_reporter_error,
) void {
    err.* = null;

    const r: *Reporter = @ptrCast(@alignCast(reporter));

    if (r.popReportError()) |err_info| {
        err.* = createError(r.alloc, err_info.err, err_info.detail);
    }
}

pub export fn greener_reporter_session_create(
    reporter: *greener_reporter,
    session_id: ?[*:0]const u8,
    description: ?[*:0]const u8,
    baggage: ?[*:0]const u8,
    labels: ?[*:0]const u8,
    err: *?*const greener_reporter_error,
) ?*const greener_reporter_session {
    err.* = null;

    const r: *Reporter = @ptrCast(@alignCast(reporter));

    var err_detail: ?ErrorDetail = null;
    const session = Session.init(
        global_alloc,
        session_id,
        description,
        baggage,
        labels,
        &err_detail,
    ) catch |e| {
        err.* = createError(global_alloc, e, err_detail);
        return null;
    };

    err_detail = null;
    const session_id_res = r.createSession(session, &err_detail) catch |e| {
        err.* = createError(global_alloc, e, err_detail);
        return null;
    };

    const session_res = global_alloc.create(greener_reporter_session) catch |e| {
        err.* = createError(global_alloc, e, null);
        return null;
    };
    session_res.* = greener_reporter_session{ .id = session_id_res };

    return session_res;
}

pub export fn greener_reporter_testcase_create(
    reporter: *greener_reporter,
    session_id: ?[*:0]const u8,
    testcase_name: ?[*:0]const u8,
    testcase_classname: ?[*:0]const u8,
    testcase_file: ?[*:0]const u8,
    testsuite: ?[*:0]const u8,
    status: ?[*:0]const u8,
    output: ?[*:0]const u8,
    baggage: ?[*:0]const u8,
    err: *?*const greener_reporter_error,
) void {
    err.* = null;

    const r: *Reporter = @ptrCast(@alignCast(reporter));

    var err_detail: ?ErrorDetail = null;
    const testcase = Testcase.init(
        global_alloc,
        session_id,
        testcase_name,
        testcase_classname,
        testcase_file,
        testsuite,
        status,
        output,
        baggage,
        &err_detail,
    ) catch |e| {
        err.* = createError(global_alloc, e, err_detail);
        return;
    };

    r.createTestcase(testcase);
}

pub export fn greener_reporter_session_delete(
    session: *const greener_reporter_session,
) void {
    global_alloc.free(@constCast(std.mem.span(session.id)));
    global_alloc.destroy(session);
}

pub export fn greener_reporter_error_delete(
    err: *const greener_reporter_error,
) void {
    global_alloc.free(@constCast(std.mem.span(err.message)));
    global_alloc.destroy(err);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

const Error = error{
    InvalidArgument,
    Ingress,
    Unknown,
};

const ErrorDetail = struct {
    message: []const u8,
    ingress_code: ?u16,
};

const ErrorInfo = struct {
    err: anyerror,
    detail: ErrorDetail,
};

const Label = struct {
    key: []const u8,
    value: ?[]const u8,
};

const Session = struct {
    alloc: std.mem.Allocator,
    id: ?[]const u8,
    description: ?[]const u8,
    baggage: ?std.json.Parsed(std.json.Value),
    labels: ?[]const Label,

    fn init(
        alloc: std.mem.Allocator,
        session_id: ?[*:0]const u8,
        description: ?[*:0]const u8,
        baggage: ?[*:0]const u8,
        labels: ?[*:0]const u8,
        error_detail: *?ErrorDetail,
    ) !Session {
        error_detail.* = null;

        const session_id_owned = if (session_id) |id| blk: {
            const id_str = std.mem.span(id);
            if (id_str.len == 0) break :blk null;
            break :blk try alloc.dupe(u8, id_str);
        } else null;
        errdefer if (session_id_owned) |id| alloc.free(id);

        const description_owned = if (description) |desc| blk: {
            const desc_str = std.mem.span(desc);
            if (desc_str.len == 0) break :blk null;
            break :blk try alloc.dupe(u8, desc_str);
        } else null;
        errdefer if (description_owned) |desc| alloc.free(desc);

        var baggage_owned = if (baggage) |bag| blk: {
            const bag_str = std.mem.span(bag);
            if (bag_str.len == 0) {
                break :blk null;
            }
            const bag_json = std.json.parseFromSlice(
                std.json.Value,
                alloc,
                bag_str,
                .{},
            ) catch {
                error_detail.* = ErrorDetail{
                    .message = try alloc.dupe(u8, "cannot parse baggage"),
                    .ingress_code = null,
                };
                return Error.InvalidArgument;
            };
            break :blk bag_json;
        } else null;
        errdefer if (baggage_owned) |*p| p.deinit();

        const labels_owned = if (labels) |ls| blk: {
            const ls_str = std.mem.span(ls);
            if (ls_str.len == 0) {
                break :blk null;
            }

            var ls_arr = std.ArrayListUnmanaged(Label){};
            errdefer {
                for (ls_arr.items) |l| {
                    alloc.free(l.key);
                    if (l.value) |v| alloc.free(v);
                }
                ls_arr.deinit(alloc);
            }

            var l_iter = std.mem.splitScalar(u8, ls_str, ',');
            while (l_iter.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " \t");
                if (trimmed.len == 0) continue;

                var kv_iter = std.mem.splitScalar(u8, trimmed, '=');
                const key_src = kv_iter.next() orelse continue;
                const value_src = kv_iter.next();

                const key_owned = try alloc.dupe(u8, key_src);
                errdefer alloc.free(key_owned);
                const value_owned = if (value_src) |v|
                    try alloc.dupe(u8, v)
                else
                    null;
                errdefer if (value_owned) |v| alloc.free(v);

                try ls_arr.append(alloc, Label{
                    .key = key_owned,
                    .value = value_owned,
                });
            }

            if (ls_arr.items.len == 0) {
                ls_arr.deinit(alloc);
                break :blk null;
            }

            break :blk try ls_arr.toOwnedSlice(alloc);
        } else null;

        return Session{
            .alloc = alloc,
            .id = session_id_owned,
            .description = description_owned,
            .baggage = baggage_owned,
            .labels = labels_owned,
        };
    }

    fn deinit(self: Session) void {
        if (self.id) |id| self.alloc.free(id);
        if (self.description) |desc| self.alloc.free(desc);
        if (self.baggage) |b| b.deinit();
        if (self.labels) |ls| {
            for (ls) |l| {
                self.alloc.free(l.key);
                if (l.value) |value| self.alloc.free(value);
            }
            self.alloc.free(ls);
        }
    }

    fn request(self: *const Session) SessionRequest {
        return SessionRequest{
            .id = self.id,
            .description = self.description,
            .baggage = if (self.baggage) |b| b.value else null,
            .labels = self.labels,
        };
    }
};

const SessionRequest = struct {
    id: ?[]const u8,
    description: ?[]const u8,
    baggage: ?std.json.Value,
    labels: ?[]const Label,
};

const TestcaseStatus = enum {
    pass,
    fail,
    @"error",
    skip,

    fn fromString(s: []const u8) Error!TestcaseStatus {
        const map = std.StaticStringMap(TestcaseStatus).initComptime(.{
            .{ "pass", .pass },
            .{ "fail", .fail },
            .{ "error", .@"error" },
            .{ "skip", .skip },
        });
        return map.get(s) orelse Error.InvalidArgument;
    }
};

const Testcase = struct {
    alloc: std.mem.Allocator,
    session_id: []const u8,
    testcase_name: []const u8,
    testcase_classname: ?[]const u8,
    testcase_file: ?[]const u8,
    testsuite: ?[]const u8,
    status: TestcaseStatus,
    output: ?[]const u8,
    baggage: ?std.json.Parsed(std.json.Value),

    fn init(
        alloc: std.mem.Allocator,
        session_id: ?[*:0]const u8,
        testcase_name: ?[*:0]const u8,
        testcase_classname: ?[*:0]const u8,
        testcase_file: ?[*:0]const u8,
        testsuite: ?[*:0]const u8,
        status: ?[*:0]const u8,
        output: ?[*:0]const u8,
        baggage: ?[*:0]const u8,
        err_detail: *?ErrorDetail,
    ) !Testcase {
        err_detail.* = null;

        if (session_id == null) {
            err_detail.* = ErrorDetail{
                .message = try alloc.dupe(u8, "session_id is null"),
                .ingress_code = null,
            };
            return Error.InvalidArgument;
        }

        if (testcase_name == null) {
            err_detail.* = ErrorDetail{
                .message = try alloc.dupe(u8, "testcase_name is null"),
                .ingress_code = null,
            };
            return Error.InvalidArgument;
        }

        if (status == null) {
            err_detail.* = ErrorDetail{
                .message = try alloc.dupe(u8, "status is null"),
                .ingress_code = null,
            };
            return Error.InvalidArgument;
        }

        const status_str = std.mem.span(status.?);
        const testcase_status = TestcaseStatus.fromString(status_str) catch |err| {
            err_detail.* = ErrorDetail{
                .message = try alloc.dupe(u8, "invalid testcase status"),
                .ingress_code = null,
            };
            return err;
        };

        const session_id_owned = try alloc.dupe(u8, std.mem.span(session_id.?));
        errdefer alloc.free(session_id_owned);

        const testcase_name_owned = try alloc.dupe(u8, std.mem.span(testcase_name.?));
        errdefer alloc.free(testcase_name_owned);

        const testcase_classname_owned = if (testcase_classname) |tc|
            try alloc.dupe(u8, std.mem.span(tc))
        else
            null;
        errdefer if (testcase_classname_owned) |tc| alloc.free(tc);

        const testcase_file_owned = if (testcase_file) |tf|
            try alloc.dupe(u8, std.mem.span(tf))
        else
            null;
        errdefer if (testcase_file_owned) |tf| alloc.free(tf);

        const testsuite_owned = if (testsuite) |ts|
            try alloc.dupe(u8, std.mem.span(ts))
        else
            null;
        errdefer if (testsuite_owned) |ts| alloc.free(ts);

        const output_owned = if (output) |out|
            try alloc.dupe(u8, std.mem.span(out))
        else
            null;
        errdefer if (output_owned) |out| alloc.free(out);

        var baggage_owned = if (baggage) |bag| blk: {
            const bag_str = std.mem.span(bag);
            if (bag_str.len == 0) {
                break :blk null;
            }
            const bag_json = std.json.parseFromSlice(
                std.json.Value,
                alloc,
                bag_str,
                .{},
            ) catch {
                err_detail.* = ErrorDetail{
                    .message = try alloc.dupe(u8, "cannot parse baggage"),
                    .ingress_code = null,
                };
                return Error.InvalidArgument;
            };
            break :blk bag_json;
        } else null;
        errdefer if (baggage_owned) |*p| p.deinit();

        return Testcase{
            .alloc = alloc,
            .session_id = session_id_owned,
            .testcase_name = testcase_name_owned,
            .testcase_classname = testcase_classname_owned,
            .testcase_file = testcase_file_owned,
            .testsuite = testsuite_owned,
            .status = testcase_status,
            .output = output_owned,
            .baggage = baggage_owned,
        };
    }

    fn deinit(self: Testcase) void {
        self.alloc.free(self.session_id);
        self.alloc.free(self.testcase_name);
        if (self.testcase_classname) |s| self.alloc.free(s);
        if (self.testcase_file) |s| self.alloc.free(s);
        if (self.testsuite) |s| self.alloc.free(s);
        if (self.output) |s| self.alloc.free(s);
        if (self.baggage) |b| b.deinit();
    }

    fn request(self: *const Testcase) TestcaseRequest {
        return TestcaseRequest{
            .sessionId = self.session_id,
            .testcaseName = self.testcase_name,
            .testcaseClassname = self.testcase_classname,
            .testcaseFile = self.testcase_file,
            .testsuite = self.testsuite,
            .status = self.status,
            .output = self.output,
            .baggage = if (self.baggage) |b| b.value else null,
        };
    }
};

const TestcaseRequest = struct {
    sessionId: []const u8,
    testcaseName: []const u8,
    testcaseClassname: ?[]const u8,
    testcaseFile: ?[]const u8,
    testsuite: ?[]const u8,
    status: TestcaseStatus,
    output: ?[]const u8,
    baggage: ?std.json.Value,
};

const TestcaseBatchRequest = struct {
    testcases: []const TestcaseRequest,
};

fn createError(
    alloc: std.mem.Allocator,
    e: anyerror,
    detail_opt: ?ErrorDetail,
) ?*const greener_reporter_error {
    const code = switch (e) {
        Error.InvalidArgument => GREENER_REPORTER_ERROR,
        Error.Ingress => GREENER_REPORTER_ERROR_INGRESS,
        else => GREENER_REPORTER_ERROR,
    };

    const detail = if (detail_opt) |d|
        d
    else
        ErrorDetail{
            .message = switch (e) {
                Error.InvalidArgument => "invalid argument error",
                Error.Ingress => "ingress error",
                else => "unknown error",
            },
            .ingress_code = 0,
        };

    const msg = alloc.dupeZ(u8, detail.message) catch |alloc_err| {
        std.debug.print("ERROR: Failed to allocate memory for error message: {}\n", .{alloc_err});
        if (detail_opt) |d| {
            alloc.free(d.message);
        }
        return null;
    };

    if (detail_opt) |d| {
        alloc.free(d.message);
    }

    const err = alloc.create(greener_reporter_error) catch |alloc_err| {
        std.debug.print("ERROR: Failed to allocate memory for error struct: {}\n", .{alloc_err});
        alloc.free(msg);
        return null;
    };
    err.* = greener_reporter_error{
        .code = code,
        .ingress_code = detail.ingress_code orelse 0,
        .message = msg,
    };
    return err;
}

const MessageType = enum {
    exit,
    timer,
    report,
};

const Message = struct {
    type: MessageType,
    payload: usize,
};

fn MessageRingBuffer(comptime capacity: usize) type {
    return struct {
        buffer: [capacity]Message,
        read_idx: usize,
        write_idx: usize,
        item_count: usize,

        const Self = @This();

        fn init() Self {
            return Self{
                .buffer = undefined,
                .read_idx = 0,
                .write_idx = 0,
                .item_count = 0,
            };
        }

        fn push(self: *Self, msg: Message) void {
            if (self.item_count >= self.buffer.len) {
                self.read_idx = (self.read_idx + 1) % self.buffer.len;
                self.item_count -= 1;
            }
            self.buffer[self.write_idx] = msg;
            self.write_idx = (self.write_idx + 1) % self.buffer.len;
            self.item_count += 1;
        }

        fn pop(self: *Self) ?Message {
            if (self.item_count == 0) {
                return null;
            }
            const msg = self.buffer[self.read_idx];
            self.read_idx = (self.read_idx + 1) % self.buffer.len;
            self.item_count -= 1;
            return msg;
        }

        fn len(self: *const Self) usize {
            return self.item_count;
        }

        fn cap(self: *const Self) usize {
            return self.buffer.len;
        }

        fn clear(self: *Self) void {
            self.read_idx = 0;
            self.write_idx = 0;
            self.item_count = 0;
        }
    };
}

const Reporter = struct {
    alloc: std.mem.Allocator,
    endpoint: []const u8,
    api_key: []const u8,

    shutdown: std.atomic.Value(bool),
    main_thread: ?std.Thread,
    timer_thread: ?std.Thread,

    msg_queue_mutex: std.Thread.Mutex,
    msg_queue_cond: std.Thread.Condition,
    msg_queue: MessageRingBuffer(100),

    testcase_arr_mutex: std.Thread.Mutex,
    testcase_arr: std.ArrayList(Testcase),

    timer_mutex: std.Thread.Mutex,
    timer_cond: std.Thread.Condition,

    errors_mutex: std.Thread.Mutex,
    errors: std.ArrayList(ErrorInfo),

    flush_rate_ms: u64,
    testcase_batch_size: u64,

    fn init(
        alloc: std.mem.Allocator,
        endpoint: ?[*:0]const u8,
        api_key: ?[*:0]const u8,
        err_detail: *?ErrorDetail,
    ) !*Reporter {
        err_detail.* = null;

        if (endpoint == null) {
            err_detail.* = ErrorDetail{
                .message = try alloc.dupe(u8, "endpoint is null"),
                .ingress_code = null,
            };
            return Error.InvalidArgument;
        }

        if (api_key == null) {
            err_detail.* = ErrorDetail{
                .message = try alloc.dupe(u8, "api_key is null"),
                .ingress_code = null,
            };
            return Error.InvalidArgument;
        }

        const endpoint_str = std.mem.span(endpoint.?);
        const api_key_str = std.mem.span(api_key.?);

        const endpoint_owned = try alloc.dupe(u8, endpoint_str);
        errdefer alloc.free(endpoint_owned);

        const api_key_owned = try alloc.dupe(u8, api_key_str);
        errdefer alloc.free(api_key_owned);

        const reporter = try alloc.create(Reporter);
        errdefer alloc.destroy(reporter);

        reporter.* = Reporter{
            .alloc = alloc,
            .endpoint = endpoint_owned,
            .api_key = api_key_owned,
            .shutdown = std.atomic.Value(bool).init(false),
            .main_thread = null,
            .timer_thread = null,
            .msg_queue_mutex = .{},
            .msg_queue_cond = .{},
            .msg_queue = MessageRingBuffer(100).init(),
            .testcase_arr_mutex = .{},
            .testcase_arr = std.ArrayList(Testcase){},
            .timer_mutex = .{},
            .timer_cond = .{},
            .errors_mutex = .{},
            .errors = std.ArrayList(ErrorInfo){},
            .flush_rate_ms = 5000,
            .testcase_batch_size = 100,
        };

        reporter.main_thread = try std.Thread.spawn(.{}, processThread, .{reporter});

        return reporter;
    }

    fn deinit(self: *Reporter) !void {
        self.shutdown.store(true, .release);

        {
            self.timer_mutex.lock();
            defer self.timer_mutex.unlock();
            self.timer_cond.signal();
        }

        {
            self.msg_queue_mutex.lock();
            defer self.msg_queue_mutex.unlock();
            self.msg_queue.push(Message{ .type = .exit, .payload = 0 });
            self.msg_queue_cond.signal();
        }

        if (self.main_thread) |thread| {
            thread.join();
        }

        self.msg_queue.clear();

        for (self.testcase_arr.items) |tc| {
            tc.deinit();
        }
        self.testcase_arr.deinit(self.alloc);

        for (self.errors.items) |err_info| {
            self.alloc.free(err_info.detail.message);
        }
        self.errors.deinit(self.alloc);

        self.alloc.free(self.api_key);
        self.alloc.free(self.endpoint);
    }

    fn processThread(self: *Reporter) !void {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const thread_alloc = arena.allocator();

        self.timer_thread = try std.Thread.spawn(.{}, timerThreadFn, .{self});

        while (true) {
            self.msg_queue_mutex.lock();

            while (self.msg_queue.len() == 0) {
                self.msg_queue_cond.wait(&self.msg_queue_mutex);
            }
            const msg = self.msg_queue.pop().?;

            self.msg_queue_mutex.unlock();

            switch (msg.type) {
                .exit => {
                    if (self.timer_thread) |thread| {
                        thread.join();
                    }
                    try self.sendReports(thread_alloc);

                    return;
                },
                .timer => {
                    try self.sendReports(thread_alloc);
                },
                .report => {
                    if (msg.payload > self.testcase_batch_size) {
                        try self.sendReports(thread_alloc);
                    }
                },
            }
        }
    }

    fn timerThreadFn(self: *Reporter) !void {
        while (!self.shutdown.load(.acquire)) {
            const deadline_ns = std.time.nanoTimestamp() + self.flush_rate_ms * std.time.ns_per_ms;

            {
                self.timer_mutex.lock();
                defer self.timer_mutex.unlock();
                while (!self.shutdown.load(.acquire)) {
                    const now_ns = std.time.nanoTimestamp();
                    if (now_ns >= deadline_ns) {
                        break;
                    }

                    const remaining_ns: u64 = @intCast(deadline_ns - now_ns);
                    std.Thread.Condition.timedWait(
                        &self.timer_cond,
                        &self.timer_mutex,
                        remaining_ns,
                    ) catch |e| switch (e) {
                        error.Timeout => break,
                        else => return e,
                    };
                }
            }

            if (self.shutdown.load(.acquire)) {
                break;
            }

            self.msg_queue_mutex.lock();
            defer self.msg_queue_mutex.unlock();
            self.msg_queue.push(Message{ .type = .timer, .payload = 0 });
            self.msg_queue_cond.signal();
        }
    }

    fn sendReports(self: *Reporter, thread_alloc: std.mem.Allocator) !void {
        self.testcase_arr_mutex.lock();
        defer self.testcase_arr_mutex.unlock();

        if (self.testcase_arr.items.len == 0) {
            return;
        }

        const requests = try thread_alloc.alloc(TestcaseRequest, self.testcase_arr.items.len);
        defer thread_alloc.free(requests);

        for (self.testcase_arr.items, 0..) |tc, i| {
            requests[i] = tc.request();
        }

        const request = TestcaseBatchRequest{ .testcases = requests };

        defer {
            for (self.testcase_arr.items) |tc| {
                tc.deinit();
            }
            self.testcase_arr.clearRetainingCapacity();
        }

        var out: std.Io.Writer.Allocating = .init(thread_alloc);
        defer out.deinit();

        try std.json.Stringify.value(request, .{}, &out.writer);
        const json_str = out.written();

        var err_detail: ?ErrorDetail = null;
        const resp_body = self.postJson(
            thread_alloc,
            "/api/v1/ingress/testcases",
            json_str,
            &err_detail,
        ) catch |e| {
            if (err_detail) |detail| {
                self.errors_mutex.lock();
                defer self.errors_mutex.unlock();

                try self.errors.append(self.alloc, ErrorInfo{
                    .err = e,
                    .detail = detail,
                });
            }
            return;
        };
        defer thread_alloc.free(resp_body);

        self.msg_queue_mutex.lock();
        defer self.msg_queue_mutex.unlock();
        self.msg_queue.clear();
    }

    fn popReportError(self: *Reporter) ?ErrorInfo {
        self.errors_mutex.lock();
        defer self.errors_mutex.unlock();

        if (self.errors.items.len == 0) {
            return null;
        }

        return self.errors.orderedRemove(0);
    }

    fn postJson(
        self: *Reporter,
        alloc: std.mem.Allocator,
        path: []const u8,
        json_body: []u8,
        error_detail: *?ErrorDetail,
    ) ![]const u8 {
        const url = try std.fmt.allocPrint(alloc, "{s}{s}", .{ self.endpoint, path });
        defer alloc.free(url);

        const uri = try std.Uri.parse(url);

        var client = std.http.Client{ .allocator = alloc };
        defer client.deinit();

        var req = try client.request(.POST, uri, .{
            .extra_headers = &.{
                .{ .name = "X-API-Key", .value = self.api_key },
                .{ .name = "Content-Type", .value = "application/json" },
            },
        });
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = json_body.len };
        try req.sendBodyComplete(json_body);

        var redirect_buffer: [2048]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        const status = response.head.status;
        if (status != .ok and status != .created) {
            const status_code = @intFromEnum(status);

            var transfer_buffer: [2048]u8 = undefined;
            const body_reader = response.reader(&transfer_buffer);
            const body = try body_reader.*.allocRemaining(alloc, std.Io.Limit.limited(1024 * 1024));
            defer alloc.free(body);

            const resp_json = try std.json.parseFromSlice(std.json.Value, alloc, body, .{});
            defer resp_json.deinit();

            const error_message = if (resp_json.value.object.get("message")) |msg_value|
                if (msg_value == .string)
                    try std.fmt.allocPrint(
                        self.alloc,
                        "failed session request: {s}",
                        .{msg_value.string},
                    )
                else
                    try self.alloc.dupe(u8, "failed session request: unknown error")
            else
                try self.alloc.dupe(u8, "failed session request: unknown error");

            error_detail.* = ErrorDetail{
                .message = error_message,
                .ingress_code = status_code,
            };
            return Error.Ingress;
        }

        var transfer_buffer: [2048]u8 = undefined;
        const body_reader = response.reader(&transfer_buffer);
        return try body_reader.*.allocRemaining(alloc, std.Io.Limit.limited(1024 * 1024));
    }

    fn createSession(
        self: *Reporter,
        session: Session,
        err_detail: *?ErrorDetail,
    ) ![*:0]const u8 {
        err_detail.* = null;
        defer session.deinit();

        var out: std.Io.Writer.Allocating = .init(self.alloc);
        defer out.deinit();

        try std.json.Stringify.value(session.request(), .{}, &out.writer);
        const json_str = out.written();

        const resp_body = try self.postJson(self.alloc, "/api/v1/ingress/sessions", json_str, err_detail);
        defer self.alloc.free(resp_body);

        const resp_json = try std.json.parseFromSlice(std.json.Value, self.alloc, resp_body, .{});
        defer resp_json.deinit();

        const id_value = resp_json.value.object.get("id") orelse {
            err_detail.* = ErrorDetail{
                .message = try self.alloc.dupe(u8, "response missing 'id' field"),
                .ingress_code = null,
            };
            return Error.Unknown;
        };

        const session_id = try self.alloc.dupeZ(u8, id_value.string);
        return session_id;
    }

    fn createTestcase(
        self: *Reporter,
        testcase: Testcase,
    ) void {
        self.testcase_arr_mutex.lock();
        self.testcase_arr.append(self.alloc, testcase) catch {
            testcase.deinit();
            self.testcase_arr_mutex.unlock();
            return;
        };
        const arr_len = self.testcase_arr.items.len;
        self.testcase_arr_mutex.unlock();

        self.msg_queue_mutex.lock();
        defer self.msg_queue_mutex.unlock();
        self.msg_queue.push(Message{ .type = .report, .payload = arr_len });
        self.msg_queue_cond.signal();
    }
};

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

test "MessageRingBuffer: init creates empty buffer" {
    const queue = MessageRingBuffer(10).init();
    try std.testing.expectEqual(@as(usize, 0), queue.len());
    try std.testing.expectEqual(@as(usize, 10), queue.cap());
}

test "MessageRingBuffer: push messages" {
    var queue = MessageRingBuffer(10).init();

    queue.push(Message{ .type = .timer, .payload = 0 });
    queue.push(Message{ .type = .exit, .payload = 0 });
    queue.push(Message{ .type = .report, .payload = 5 });

    try std.testing.expectEqual(@as(usize, 3), queue.len());

    const msg1 = queue.pop().?;
    try std.testing.expectEqual(MessageType.timer, msg1.type);
    try std.testing.expectEqual(@as(usize, 0), msg1.payload);

    const msg2 = queue.pop().?;
    try std.testing.expectEqual(MessageType.exit, msg2.type);
    try std.testing.expectEqual(@as(usize, 0), msg2.payload);

    const msg3 = queue.pop().?;
    try std.testing.expectEqual(MessageType.report, msg3.type);
    try std.testing.expectEqual(@as(usize, 5), msg3.payload);

    try std.testing.expectEqual(@as(usize, 0), queue.len());
}

test "MessageRingBuffer: pop from empty queue returns null" {
    var queue = MessageRingBuffer(10).init();

    const removed = queue.pop();
    try std.testing.expectEqual(@as(?Message, null), removed);
}

test "MessageRingBuffer: ring behavior drops oldest message when full" {
    var queue = MessageRingBuffer(10).init();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        queue.push(Message{ .type = .timer, .payload = 0 });
    }

    try std.testing.expectEqual(@as(usize, 10), queue.len());

    queue.push(Message{ .type = .exit, .payload = 0 });

    try std.testing.expectEqual(@as(usize, 10), queue.len());

    i = 0;
    while (i < 9) : (i += 1) {
        const msg = queue.pop().?;
        try std.testing.expectEqual(MessageType.timer, msg.type);
    }

    const last_msg = queue.pop().?;
    try std.testing.expectEqual(MessageType.exit, last_msg.type);

    try std.testing.expectEqual(@as(usize, 0), queue.len());
}

test "MessageRingBuffer: clear from full buffer" {
    var queue = MessageRingBuffer(5).init();

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        queue.push(Message{ .type = .report, .payload = i });
    }

    try std.testing.expectEqual(@as(usize, 5), queue.len());

    queue.clear();

    try std.testing.expectEqual(@as(usize, 0), queue.len());
}
