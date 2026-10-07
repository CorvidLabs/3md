# Binary input, convert and inspect for ThreeMD 2.1

## ADDED

### REQUIREMENT REQ-ThreeMDCLI-011

The validate, info, html, links and check-links subcommands SHALL read their input as bytes from a path or standard input, SHALL decode input that starts with the binary magic through DocumentStorageCodec.decode with standard limits, and SHALL keep the 2.0 path and output byte for byte for every other input. A storage failure SHALL print `threemd: <path>: <code>: <description>` to stderr and exit 1, and with --json its error object SHALL carry code and message, plus detail and line only when they exist. (Change requirement SB-25.)

Acceptance Criteria:
- Each subcommand on conformance/structured/worked-document.3mdb prints the same stdout as on that document's canonical text, and works on a kind-1 file.
- A kind-2 file with a corrupt CRC prints the exact stderr line and, with --json, error.code checksumMismatch with no detail or line keys; a kind-3 header gives unsupportedPayloadKind with detail "3"; invalidText gives the inner ParseError code and line.
- Binary standard input works, and every existing CLI behavior on text keeps its output.

### REQUIREMENT REQ-ThreeMDCLI-012

`threemd convert <input> <output> [--format text|binary|text-container] [--lzfse] [--force]` SHALL write the library encoder's output for the chosen format, SHALL infer the format from a .3md or .3mdb output path, SHALL exit 1 with the usage line when it cannot infer the format or when --lzfse meets text output, SHALL refuse an existing output without --force, SHALL write through a temporary file and a rename so that a failure leaves no output, and SHALL write to standard output for `-` only when --format is given. (Change requirement SB-26.)

Acceptance Criteria:
- Text to binary, binary to text, binary to text-container and text-container to binary outputs are byte-equal to the library encoders.
- An uninferable output path, or `-` without --format, exits 1 with the usage line and creates nothing; an existing output without --force exits 1 and stays unchanged; --lzfse reports compressionUnavailable on Linux.

### REQUIREMENT REQ-ThreeMDCLI-013

`threemd inspect [--json] <file>` SHALL read the header with containerInfo, SHALL decode the whole input with standard limits, SHALL report a failed decode inside its output, and SHALL exit 0 only when the decode succeeds. Its JSON output SHALL have exactly one of three shapes: binary input, a truncated binary header with null header fields, or text input. (Change requirement SB-27.)

Acceptance Criteria:
- Text, kind 1, kind 2, a corrupt CRC and a truncated header give the documented plain and JSON output, with JSON key snapshots for the three shapes.
- The exit status follows decode.ok.
