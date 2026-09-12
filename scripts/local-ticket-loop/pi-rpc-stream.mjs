#!/usr/bin/env node

import { spawn } from "node:child_process";
import { closeSync, openSync, readFileSync, writeSync } from "node:fs";
import { StringDecoder } from "node:string_decoder";
import { createInterface } from "node:readline";

const HELP = `Usage:
  ./pi-rpc-stream.mjs [options] [-- <pi options>]

Options:
  --prompt <text>       Send an initial prompt after Pi starts
  --prompt-file <path>  Read the initial prompt from a UTF-8 file
  --pi-bin <path>       Pi executable (default: pi)
  --log <path>          Append raw inbound RPC JSONL with owner-only permissions
  --raw                 Print raw RPC JSONL instead of the human-readable stream
  --show-thinking       Stream model thinking deltas
  --stats-before-exit   Request session stats before exiting after settlement
  --stay-open           Keep the RPC session open after agent_settled
  --no-input            Disable interactive commands; requires an initial prompt
  --help                Show this help

Interactive commands:
  <text>          Prompt while idle, steer while the agent is active
  /prompt <text>  Send a normal prompt
  /steer <text>   Queue steering for the active agent
  /follow <text>  Queue a follow-up after the agent finishes
  /abort          Abort the current agent operation
  /state          Request current RPC state
  /stats          Request session usage and cost
  /quit           Terminate the RPC process

Examples:
  ./pi-rpc-stream.mjs --prompt "Review this repository" -- --model openai-codex/gpt-5.6-sol
  ./pi-rpc-stream.mjs --prompt-file issue-prompt.md --stay-open -- --session-dir .ralph/runs/2/pi
`;

function failUsage(message) {
	process.stderr.write(`pi rpc stream: ${message}\n\n${HELP}`);
	process.exit(2);
}

function parseCommandLine(argv) {
	const separatorIndex = argv.indexOf("--");
	const clientArgs =
		separatorIndex === -1 ? argv : argv.slice(0, separatorIndex);
	const piArgs = separatorIndex === -1 ? [] : argv.slice(separatorIndex + 1);
	const options = {
		logPath: null,
		noInput: false,
		piBin: "pi",
		prompt: null,
		promptFile: null,
		raw: false,
		showThinking: false,
		statsBeforeExit: false,
		stayOpen: false,
	};

	for (let index = 0; index < clientArgs.length; index += 1) {
		const argument = clientArgs[index];
		const takeValue = () => {
			index += 1;
			const value = clientArgs[index];
			if (value === undefined) failUsage(`${argument} requires a value`);
			return value;
		};

		switch (argument) {
			case "--help":
				process.stdout.write(HELP);
				process.exit(0);
			case "--log":
				options.logPath = takeValue();
				break;
			case "--no-input":
				options.noInput = true;
				break;
			case "--pi-bin":
				options.piBin = takeValue();
				break;
			case "--prompt":
				options.prompt = takeValue();
				break;
			case "--prompt-file":
				options.promptFile = takeValue();
				break;
			case "--raw":
				options.raw = true;
				break;
			case "--show-thinking":
				options.showThinking = true;
				break;
			case "--stats-before-exit":
				options.statsBeforeExit = true;
				break;
			case "--stay-open":
				options.stayOpen = true;
				break;
			default:
				failUsage(`unknown option: ${argument}`);
		}
	}

	if (options.prompt !== null && options.promptFile !== null) {
		failUsage("use only one of --prompt or --prompt-file");
	}
	if (options.promptFile !== null) {
		try {
			options.prompt = readFileSync(options.promptFile, "utf8");
		} catch (error) {
			failUsage(
				`cannot read prompt file ${options.promptFile}: ${error.message}`,
			);
		}
	}
	if (options.noInput && options.prompt === null) {
		failUsage("--no-input requires --prompt or --prompt-file");
	}
	if (
		piArgs.some(
			(argument) =>
				argument === "--mode" || argument === "-p" || argument === "--print",
		)
	) {
		failUsage(
			"do not pass --mode or --print; this client always launches Pi in RPC mode",
		);
	}

	return { options, piArgs };
}

function attachLfJsonReader(stream, onLine, onEnd) {
	const decoder = new StringDecoder("utf8");
	let buffer = "";

	stream.on("data", (chunk) => {
		buffer += decoder.write(chunk);
		while (true) {
			const newlineIndex = buffer.indexOf("\n");
			if (newlineIndex === -1) break;
			let line = buffer.slice(0, newlineIndex);
			buffer = buffer.slice(newlineIndex + 1);
			if (line.endsWith("\r")) line = line.slice(0, -1);
			onLine(line);
		}
	});

	stream.on("end", () => {
		buffer += decoder.end();
		if (buffer.length > 0)
			onLine(buffer.endsWith("\r") ? buffer.slice(0, -1) : buffer);
		onEnd();
	});
}

const { options, piArgs } = parseCommandLine(process.argv.slice(2));
let logDescriptor = null;
if (options.logPath !== null) {
	try {
		logDescriptor = openSync(options.logPath, "a", 0o600);
	} catch (error) {
		failUsage(`cannot open log file ${options.logPath}: ${error.message}`);
	}
}

const agent = spawn(options.piBin, ["--mode", "rpc", ...piArgs], {
	stdio: ["pipe", "pipe", "pipe"],
});

let agentStreaming = false;
let assistantLineOpen = false;
let nextRequestNumber = 1;
let pendingDialog = null;
let requestedExitCode = null;
let waitingForExitStats = false;
let secondInterruptDeadline = 0;
let forceKillTimer = null;
let inputInterface = null;

function writeRawLog(line) {
	if (logDescriptor !== null) writeSync(logDescriptor, `${line}\n`);
}

function endAssistantLine() {
	if (!assistantLineOpen) return;
	process.stdout.write("\n");
	assistantLineOpen = false;
}

function printEvent(message) {
	endAssistantLine();
	process.stdout.write(`${message}\n`);
}

function sendRpcCommand(command, keepProvidedId = false) {
	const payload = { ...command };
	if (!keepProvidedId && payload.id === undefined) {
		payload.id = `request-${nextRequestNumber}`;
		nextRequestNumber += 1;
	}
	if (!agent.stdin.writable) {
		printEvent("[error] Pi RPC stdin is closed");
		return false;
	}
	agent.stdin.write(`${JSON.stringify(payload)}\n`);
	return true;
}

function terminateAgent(exitCode) {
	if (requestedExitCode === null) requestedExitCode = exitCode;
	inputInterface?.close();
	if (agent.exitCode !== null || agent.signalCode !== null) return;
	agent.kill("SIGTERM");
	forceKillTimer = setTimeout(() => {
		if (agent.exitCode !== null || agent.signalCode !== null) return;
		if (requestedExitCode === 0) requestedExitCode = 1;
		process.stderr.write(
			"pi rpc stream: Pi did not stop cleanly; forcing termination\n",
		);
		agent.kill("SIGKILL");
	}, 2_000);
	forceKillTimer.unref();
}

function displayExtensionRequest(event) {
	const dialogMethods = new Set(["select", "confirm", "input", "editor"]);
	if (!dialogMethods.has(event.method)) {
		if (event.method === "notify") {
			printEvent(
				`[notification ${event.notifyType ?? "info"}] ${event.message ?? ""}`,
			);
		}
		return;
	}

	if (options.noInput) {
		const response =
			event.method === "confirm"
				? { type: "extension_ui_response", id: event.id, confirmed: false }
				: { type: "extension_ui_response", id: event.id, cancelled: true };
		sendRpcCommand(response, true);
		printEvent(
			`[extension ${event.method}] cancelled because interactive input is disabled`,
		);
		return;
	}

	pendingDialog = event;
	const optionsText = event.options?.length
		? ` (${event.options.map((value, index) => `${index + 1}:${value}`).join(", ")})`
		: "";
	printEvent(
		`[extension ${event.method}] ${event.title ?? event.message ?? "Response required"}${optionsText}`,
	);
	process.stderr.write("response> ");
}

function displayRpcEvent(event, rawLine) {
	writeRawLog(rawLine);
	if (options.raw) {
		process.stdout.write(`${rawLine}\n`);
		return;
	}

	switch (event.type) {
		case "response":
			if (!event.success)
				printEvent(
					`[error ${event.command ?? "rpc"}] ${event.error ?? "command rejected"}`,
				);
			else if (
				event.command === "get_state" ||
				event.command === "get_session_stats"
			) {
				printEvent(`[${event.command}] ${JSON.stringify(event.data)}`);
			}
			if (waitingForExitStats && event.command === "get_session_stats") {
				waitingForExitStats = false;
				terminateAgent(event.success ? 0 : 1);
			}
			break;
		case "agent_start":
			agentStreaming = true;
			printEvent("[agent started]");
			break;
		case "agent_settled":
			agentStreaming = false;
			printEvent("[settled]");
			if (
				options.prompt !== null &&
				!options.stayOpen &&
				!waitingForExitStats
			) {
				if (options.statsBeforeExit) {
					waitingForExitStats = true;
					if (!sendRpcCommand({ type: "get_session_stats" })) terminateAgent(1);
				} else {
					terminateAgent(0);
				}
			}
			break;
		case "message_update": {
			const update = event.assistantMessageEvent ?? {};
			const isVisibleDelta =
				update.type === "text_delta" ||
				(options.showThinking && update.type === "thinking_delta");
			if (!isVisibleDelta) break;
			if (!assistantLineOpen) {
				process.stdout.write(
					update.type === "thinking_delta" ? "thinking> " : "assistant> ",
				);
			}
			process.stdout.write(update.delta ?? "");
			assistantLineOpen = !(update.delta ?? "").endsWith("\n");
			break;
		}
		case "tool_execution_start":
			printEvent(`[tool ${event.toolName}]`);
			break;
		case "tool_execution_end":
			printEvent(`[tool ${event.toolName}: ${event.isError ? "error" : "ok"}]`);
			break;
		case "queue_update":
			printEvent(
				`[queue] steer=${event.steering?.length ?? 0} follow-up=${event.followUp?.length ?? 0}`,
			);
			break;
		case "compaction_start":
			printEvent(`[compaction started: ${event.reason}]`);
			break;
		case "compaction_end": {
			let outcome = "failed";
			if (event.aborted) outcome = "aborted";
			else if (event.result) outcome = "completed";
			printEvent(`[compaction ${outcome}]`);
			break;
		}
		case "auto_retry_start":
			printEvent(
				`[retry ${event.attempt}/${event.maxAttempts} in ${event.delayMs}ms]`,
			);
			break;
		case "auto_retry_end":
			printEvent(`[retry ${event.success ? "succeeded" : "failed"}]`);
			break;
		case "extension_error":
			printEvent(`[extension error] ${event.error}`);
			break;
		case "extension_ui_request":
			displayExtensionRequest(event);
			break;
		default:
			break;
	}
}

function answerPendingDialog(line) {
	const request = pendingDialog;
	pendingDialog = null;
	const trimmed = line.trim();
	if (trimmed === "/cancel") {
		sendRpcCommand(
			{ type: "extension_ui_response", id: request.id, cancelled: true },
			true,
		);
		return;
	}
	if (request.method === "confirm") {
		const confirmed = /^(y|yes|true|1)$/iu.test(trimmed);
		sendRpcCommand(
			{ type: "extension_ui_response", id: request.id, confirmed },
			true,
		);
		return;
	}
	if (request.method === "select") {
		const numericIndex = Number.parseInt(trimmed, 10) - 1;
		const value =
			Number.isInteger(numericIndex) &&
			request.options?.[numericIndex] !== undefined
				? request.options[numericIndex]
				: trimmed;
		sendRpcCommand(
			{ type: "extension_ui_response", id: request.id, value },
			true,
		);
		return;
	}
	sendRpcCommand(
		{ type: "extension_ui_response", id: request.id, value: line },
		true,
	);
}

function handleUserLine(line) {
	if (pendingDialog !== null) {
		answerPendingDialog(line);
		return;
	}

	const trimmed = line.trim();
	if (!trimmed) return;
	if (trimmed === "/quit") {
		terminateAgent(130);
		return;
	}
	if (trimmed === "/abort") {
		sendRpcCommand({ type: "abort" });
		return;
	}
	if (trimmed === "/state") {
		sendRpcCommand({ type: "get_state" });
		return;
	}
	if (trimmed === "/stats") {
		sendRpcCommand({ type: "get_session_stats" });
		return;
	}

	const commandPrefixes = [
		["/prompt ", "prompt"],
		["/steer ", "steer"],
		["/follow ", "follow_up"],
	];
	for (const [prefix, commandType] of commandPrefixes) {
		if (trimmed.startsWith(prefix)) {
			sendRpcCommand({
				type: commandType,
				message: trimmed.slice(prefix.length),
			});
			return;
		}
	}

	sendRpcCommand({ type: agentStreaming ? "steer" : "prompt", message: line });
}

agent.stderr.on("data", (chunk) => process.stderr.write(chunk));
agent.once("error", (error) => {
	process.stderr.write(
		`pi rpc stream: failed to start ${options.piBin}: ${error.message}\n`,
	);
	requestedExitCode = 1;
});
agent.once("exit", (code, signal) => {
	if (forceKillTimer !== null) clearTimeout(forceKillTimer);
	inputInterface?.close();
	if (logDescriptor !== null) closeSync(logDescriptor);
	endAssistantLine();
	if (requestedExitCode !== null) {
		process.exitCode = requestedExitCode;
	} else if (code !== 0) {
		process.stderr.write(
			`pi rpc stream: Pi exited with ${signal ? `signal ${signal}` : `code ${code}`}\n`,
		);
		process.exitCode = 1;
	}
});

attachLfJsonReader(
	agent.stdout,
	(line) => {
		if (!line) return;
		try {
			displayRpcEvent(JSON.parse(line), line);
		} catch (error) {
			process.stderr.write(
				`pi rpc stream: invalid RPC JSON: ${error.message}\n`,
			);
			terminateAgent(1);
		}
	},
	() => {},
);

if (!options.noInput) {
	inputInterface = createInterface({
		input: process.stdin,
		output: process.stderr,
		terminal: process.stdin.isTTY,
	});
	inputInterface.on("line", handleUserLine);
	inputInterface.on("close", () => {
		if (
			options.prompt === null &&
			!agentStreaming &&
			requestedExitCode === null
		)
			terminateAgent(0);
	});
}

process.on("SIGINT", () => {
	const now = Date.now();
	if (now < secondInterruptDeadline) {
		terminateAgent(130);
		return;
	}
	secondInterruptDeadline = now + 1_500;
	sendRpcCommand({ type: "abort" });
	process.stderr.write(
		"pi rpc stream: abort requested; press Ctrl-C again to terminate\n",
	);
});
process.on("SIGTERM", () => terminateAgent(143));

if (options.prompt !== null) {
	sendRpcCommand({ type: "prompt", message: options.prompt });
} else if (!options.raw) {
	process.stderr.write("pi rpc stream: connected; type a prompt or /quit\n");
}
