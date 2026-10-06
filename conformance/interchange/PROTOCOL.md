# Development interchange protocol

This protocol is a test adapter, not a public JSON snapshot or patch format.
One JSON object per line is written to stdin and one response per line to stdout.
Adapters use only their public library APIs and do not log to stdout.

Request: `{"schema":"3md-interchange-1","kind":"document","bytesHex":"..."}`.
Kinds are document, composition and files. Exact bytes are lowercase hexadecimal.
For files, bytesHex contains UTF-8 JSON with exactly rootPath (string) and files
(array of records with exactly path and bytesHex string fields). Libraries resolve
these explicitly supplied bytes under docs/FILE-COMPOSITION.md, then emit normal
composition responses. Produced text/binary/adopted/edited bundles are consumed
as composition kind, with no source inputs. File failures use filePath,
fileLedger, missingFile and fileLimit; malformed protocol fields are adapterFailure.
Both text and uncompressed binary input must be detected by the storage codec.
Composition input first uses storage decode, then composition decode.

Successful response fields:

- `ok`: true.
- `canonicalHex`: canonical document text or composition profile UTF-8 bytes.
- `binaryHex`: the same document/profile wrapped in uncompressed binary.
- `legacyHex`: legacy Serializer/serialize output for documents, null for composition.
- `rawCanonicalHex`: document source parsed through raw Parser/parse then canonical storage encoded when the input is text; null for binary/composition. This catches disagreements masked by bounded decoder reconstruction.
- `revisionHex`: exact UTF-8 revision of the explicitly adopted snapshot.
- `adoptedHex`: canonical document/profile after public identity adoption.
- `editedHex`: canonical document/profile after the deterministic edit below.
- `staleRejected`: true when reusing that patch against the edited snapshot fails as stale; true for a no-op fixture with no editable plane.
- `semantic`: document or composition semantic value described below.

Document semantic fields are version, axis, title, metadata, preamble and planes.
Optional fields are null. Plane fields are zBits, xBits, yBits, label, attributes
and body. Numbers are 16-digit lowercase IEEE754 hex; signed zero normalizes to
0000000000000000, matching the existing wire contract. Metadata and attributes
are JSON objects with exact Unicode key/value spelling. A composition value
has rootID and entries sorted by ID, each with id, document and references
(targetID, attributes). Dictionary output order is ignored, key bytes are not.

Document edit: adopt identities; if any plane exists, replace the first plane
by stable ID with identical fields except body appended with `\ninterchange edited`
(or `interchange edited` if initially empty). Apply through the public editor.
Composition edit: adopt identities; edit the first plane of the root document
as above, replace the root entry through the composition editor preserving its
ID and references. If its document has no planes, keep the adopted graph.
Revision is the adopted pre-edit snapshot revision, not a hash.

Failure response: `{"ok":false,"error":"stableCode"}`. Stable storage,
composition, parser and editing codes use the existing camel-case names.
Unclassified adapter failures use adapterFailure and must fail the gate.
Input requests and response lines are bounded to 32 MiB for this development
tool. The coordinator enforces process deadlines and manifest completeness.
Swift streams requests in bounded chunks, rejects malformed/oversized lines with
adapterFailure and continues the next line. Oversized replies use the same
bounded failure record. The coordinator rejects blank/extra/oversized reply
lines and duplicate or Unicode-equivalent semantic JSON keys before dictionary
decoding. File-backed process I/O avoids pipe deadlocks; stdout and stderr have
separate budgets. Unix watchdogs terminate, escalate and reap owned children on
timeout, cancellation or output overflow. Windows watchdog hard-stop behavior
is not established by this development gate; library file codecs remain portable.
