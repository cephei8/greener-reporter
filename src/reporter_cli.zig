const std = @import("std");
const reporter = @import("reporter.zig");

const ENVVAR_ENDPOINT = "GREENER_INGRESS_ENDPOINT";
const ENVVAR_API_KEY = "GREENER_INGRESS_API_KEY";

const CliError = error{
    MissingEndpoint,
    MissingApiKey,
    MissingCommand,
    InvalidCommand,
    InvalidStatus,
    MissingSessionId,
    MissingTestcaseName,
    DuplicateLabel,
    EmptyLabelKey,
    ReporterError,
};

fn printUsage(writer: *std.Io.Writer, program_name: []const u8) !void {
    try writer.print(
        \\Usage: {s} [OPTIONS] <COMMAND>
        \\
        \\Options:
        \\  --endpoint <ENDPOINT>    Greener ingress endpoint URL [env: {s}]
        \\  --api-key <API_KEY>      API key for authentication [env: {s}]
        \\  -h, --help               Print help
        \\
        \\Commands:
        \\  create                   Create results
        \\
    , .{ program_name, ENVVAR_ENDPOINT, ENVVAR_API_KEY });
}

fn printCreateUsage(writer: *std.Io.Writer, program_name: []const u8) !void {
    try writer.print(
        \\Usage: {s} [OPTIONS] create <COMMAND>
        \\
        \\Commands:
        \\  session                  Create session
        \\  testcase                 Create test case
        \\
    , .{program_name});
}

fn printSessionUsage(writer: *std.Io.Writer, program_name: []const u8) !void {
    try writer.print(
        \\Usage: {s} [OPTIONS] create session [SESSION_OPTIONS]
        \\
        \\Session Options:
        \\  --id <ID>                ID for the session
        \\  --baggage <JSON>         Additional metadata as JSON
        \\  --label <LABEL>          Labels in `key` or `key=value` format (can be repeated)
        \\  -h, --help               Print help
        \\
    , .{program_name});
}

fn printTestcaseUsage(writer: *std.Io.Writer, program_name: []const u8) !void {
    try writer.print(
        \\Usage: {s} [OPTIONS] create testcase [TESTCASE_OPTIONS]
        \\
        \\Testcase Options:
        \\  --session-id <ID>        Session ID for the test case (required)
        \\  --name <NAME>            Name of the test case (required)
        \\  --output <OUTPUT>        Output from the test case
        \\  --classname <CLASS>      Class name of the test case
        \\  --file <FILE>            File path of the test case
        \\  --testsuite <SUITE>      Test suite name
        \\  --status <STATUS>        Test case status (pass, fail, error, skip) [default: pass]
        \\  --baggage <JSON>         Additional metadata as JSON
        \\  -h, --help               Print help
        \\
    , .{program_name});
}

const SessionArgs = struct {
    id: ?[:0]const u8 = null,
    baggage: ?[:0]const u8 = null,
    labels: ?[:0]const u8 = null,
};

const TestcaseArgs = struct {
    session_id: ?[:0]const u8 = null,
    name: ?[:0]const u8 = null,
    output: ?[:0]const u8 = null,
    classname: ?[:0]const u8 = null,
    file: ?[:0]const u8 = null,
    testsuite: ?[:0]const u8 = null,
    status: [:0]const u8 = "pass",
    baggage: ?[:0]const u8 = null,
};

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !struct {
    endpoint: ?[:0]const u8,
    api_key: ?[:0]const u8,
    command: ?[]const u8,
    subcommand: ?[]const u8,
    session_args: SessionArgs,
    testcase_args: TestcaseArgs,
    help: bool,
} {
    var endpoint: ?[:0]const u8 = null;
    var api_key: ?[:0]const u8 = null;
    var command: ?[]const u8 = null;
    var subcommand: ?[]const u8 = null;
    var session_args = SessionArgs{};
    var testcase_args = TestcaseArgs{};
    var help = false;

    var labels_list = std.ArrayListUnmanaged([]const u8){};
    defer labels_list.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            help = true;
            continue;
        }

        // global options
        if (std.mem.eql(u8, arg, "--endpoint")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            endpoint = try allocator.dupeZ(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--api-key")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            api_key = try allocator.dupeZ(u8, args[i]);
        }
        // commands
        else if (command == null) {
            command = arg;
        } else if (subcommand == null and std.mem.eql(u8, command.?, "create")) {
            subcommand = arg;
        }
        // session options
        else if (subcommand != null and std.mem.eql(u8, subcommand.?, "session")) {
            if (std.mem.eql(u8, arg, "--id")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                session_args.id = try allocator.dupeZ(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--baggage")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                session_args.baggage = try allocator.dupeZ(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--label")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                try labels_list.append(allocator, args[i]);
            }
        }
        // testcase options
        else if (subcommand != null and std.mem.eql(u8, subcommand.?, "testcase")) {
            if (std.mem.eql(u8, arg, "--session-id")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                testcase_args.session_id = try allocator.dupeZ(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--name")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                testcase_args.name = try allocator.dupeZ(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--output")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                testcase_args.output = try allocator.dupeZ(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--classname")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                testcase_args.classname = try allocator.dupeZ(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--file")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                testcase_args.file = try allocator.dupeZ(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--testsuite")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                testcase_args.testsuite = try allocator.dupeZ(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--status")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                testcase_args.status = try allocator.dupeZ(u8, args[i]);
            } else if (std.mem.eql(u8, arg, "--baggage")) {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                testcase_args.baggage = try allocator.dupeZ(u8, args[i]);
            }
        }
    }

    // join labels with commas if any were provided
    if (labels_list.items.len > 0) {
        var labels_str = std.ArrayListUnmanaged(u8){};
        defer labels_str.deinit(allocator);

        for (labels_list.items, 0..) |label, idx| {
            if (idx > 0) try labels_str.append(allocator, ',');
            try labels_str.appendSlice(allocator, label);
        }

        session_args.labels = try allocator.dupeZ(u8, labels_str.items);
    }

    return .{
        .endpoint = endpoint,
        .api_key = api_key,
        .command = command,
        .subcommand = subcommand,
        .session_args = session_args,
        .testcase_args = testcase_args,
        .help = help,
    };
}

fn getEnvVar(allocator: std.mem.Allocator, name: []const u8) !?[:0]const u8 {
    const value = std.posix.getenv(name) orelse return null;
    return try allocator.dupeZ(u8, value);
}

fn createSession(
    writer: *std.Io.Writer,
    rep: *reporter.greener_reporter,
    args: SessionArgs,
) !void {
    var err: ?*const reporter.greener_reporter_error = null;
    const session = reporter.greener_reporter_session_create(
        rep,
        if (args.id) |id| id.ptr else null,
        null, // description
        if (args.baggage) |b| b.ptr else null,
        if (args.labels) |l| l.ptr else null,
        &err,
    );

    if (err) |e| {
        defer reporter.greener_reporter_error_delete(e);
        const msg = std.mem.span(e.message);
        try writer.print("Error creating session: {s}\n", .{msg});
        return CliError.ReporterError;
    }

    if (session) |s| {
        defer reporter.greener_reporter_session_delete(s);
        const session_id = std.mem.span(s.id);
        try writer.print("Created session ID: {s}\n", .{session_id});
    }
}

fn createTestcase(
    writer: *std.Io.Writer,
    rep: *reporter.greener_reporter,
    args: TestcaseArgs,
) !void {
    if (args.session_id == null) {
        try writer.print("Error: --session-id is required\n", .{});
        return CliError.MissingSessionId;
    }

    if (args.name == null) {
        try writer.print("Error: --name is required\n", .{});
        return CliError.MissingTestcaseName;
    }

    // validate status
    const valid_statuses = [_][]const u8{ "pass", "fail", "error", "skip" };
    var valid = false;
    for (valid_statuses) |s| {
        if (std.mem.eql(u8, args.status, s)) {
            valid = true;
            break;
        }
    }
    if (!valid) {
        try writer.print("Error: Invalid status: {s}. Valid values: pass, fail, error, skip\n", .{args.status});
        return CliError.InvalidStatus;
    }

    var err: ?*const reporter.greener_reporter_error = null;
    reporter.greener_reporter_testcase_create(
        rep,
        args.session_id.?.ptr,
        args.name.?.ptr,
        if (args.classname) |c| c.ptr else null,
        if (args.file) |f| f.ptr else null,
        if (args.testsuite) |t| t.ptr else null,
        args.status.ptr,
        if (args.output) |o| o.ptr else null,
        if (args.baggage) |b| b.ptr else null,
        &err,
    );

    if (err) |e| {
        defer reporter.greener_reporter_error_delete(e);
        const msg = std.mem.span(e.message);
        try writer.print("Error creating testcase: {s}\n", .{msg});
        return CliError.ReporterError;
    }

    try writer.print("Testcase created successfully\n", .{});

    while (true) {
        reporter.greener_reporter_report_error_pop(rep, &err);
        if (err) |e| {
            defer reporter.greener_reporter_error_delete(e);
            const msg = std.mem.span(e.message);
            try writer.print("Warning: Report error: {s}\n", .{msg});
        } else {
            break;
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const args_raw = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args_raw);

    const parsed = try parseArgs(allocator, args_raw);

    const endpoint = parsed.endpoint orelse try getEnvVar(allocator, ENVVAR_ENDPOINT);
    const api_key = parsed.api_key orelse try getEnvVar(allocator, ENVVAR_API_KEY);

    if (parsed.help) {
        if (parsed.command) |cmd| {
            if (std.mem.eql(u8, cmd, "create")) {
                if (parsed.subcommand) |subcmd| {
                    if (std.mem.eql(u8, subcmd, "session")) {
                        try printSessionUsage(stdout, args_raw[0]);
                        try stdout.flush();
                        return;
                    } else if (std.mem.eql(u8, subcmd, "testcase")) {
                        try printTestcaseUsage(stdout, args_raw[0]);
                        try stdout.flush();
                        return;
                    }
                }
                try printCreateUsage(stdout, args_raw[0]);
                try stdout.flush();
                return;
            }
        }
        try printUsage(stdout, args_raw[0]);
        try stdout.flush();
        return;
    }

    if (endpoint == null) {
        try stdout.print("Error: --endpoint is required (or set {s} environment variable)\n", .{ENVVAR_ENDPOINT});
        try stdout.flush();
        return CliError.MissingEndpoint;
    }

    if (api_key == null) {
        try stdout.print("Error: --api-key is required (or set {s} environment variable)\n", .{ENVVAR_API_KEY});
        try stdout.flush();
        return CliError.MissingApiKey;
    }

    if (parsed.command == null) {
        try stdout.print("Error: missing command\n\n", .{});
        try printUsage(stdout, args_raw[0]);
        try stdout.flush();
        return CliError.MissingCommand;
    }

    const command = parsed.command.?;
    if (!std.mem.eql(u8, command, "create")) {
        try stdout.print("Error: unknown command: {s}\n\n", .{command});
        try printUsage(stdout, args_raw[0]);
        try stdout.flush();
        return CliError.InvalidCommand;
    }

    if (parsed.subcommand == null) {
        try stdout.print("Error: missing subcommand\n\n", .{});
        try printCreateUsage(stdout, args_raw[0]);
        try stdout.flush();
        return CliError.MissingCommand;
    }

    var err: ?*const reporter.greener_reporter_error = null;
    const rep = reporter.greener_reporter_new(
        endpoint.?.ptr,
        api_key.?.ptr,
        &err,
    );

    if (err) |e| {
        defer reporter.greener_reporter_error_delete(e);
        const msg = std.mem.span(e.message);
        try stdout.print("Error initializing reporter: {s}\n", .{msg});
        try stdout.flush();
        return CliError.ReporterError;
    }

    if (rep == null) {
        try stdout.print("Error: failed to initialize reporter\n", .{});
        try stdout.flush();
        return CliError.ReporterError;
    }

    defer {
        var del_err: ?*const reporter.greener_reporter_error = null;
        reporter.greener_reporter_delete(rep.?, &del_err);
        if (del_err) |e| {
            defer reporter.greener_reporter_error_delete(e);
            const msg = std.mem.span(e.message);
            stdout.print("Warning: Error during cleanup: {s}\n", .{msg}) catch {};
        }
    }

    const subcommand = parsed.subcommand.?;
    if (std.mem.eql(u8, subcommand, "session")) {
        try createSession(stdout, rep.?, parsed.session_args);
        try stdout.flush();
    } else if (std.mem.eql(u8, subcommand, "testcase")) {
        try createTestcase(stdout, rep.?, parsed.testcase_args);
        try stdout.flush();
    } else {
        try stdout.print("Error: unknown subcommand: {s}\n\n", .{subcommand});
        try printCreateUsage(stdout, args_raw[0]);
        try stdout.flush();
        return CliError.InvalidCommand;
    }
}
