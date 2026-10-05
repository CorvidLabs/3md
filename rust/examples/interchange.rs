//! Bounded JSON-lines development adapter for the shared file interchange gate.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};
use threemd::composition::{self, DocumentCompositionLimits};
use threemd::editing::{
    self, CompositionEdit, CompositionPatch, DocumentCompositionSnapshot, DocumentEdit,
    DocumentEditLimits, DocumentPatch, DocumentSnapshot,
};
use threemd::storage::{
    self, DocumentCompression, DocumentDecodeLimits, DocumentStorageFormat, OperationOptions,
};
use threemd::{Document, Plane};

const MAXIMUM_LINE_BYTES: usize = 32 * 1024 * 1024;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Request {
    schema: String,
    kind: String,
    bytes_hex: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Response {
    ok: bool,
    canonical_hex: String,
    binary_hex: String,
    legacy_hex: Option<String>,
    raw_canonical_hex: Option<String>,
    revision_hex: String,
    adopted_hex: String,
    edited_hex: String,
    stale_rejected: bool,
    semantic: Value,
}

fn hex(data: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut result = String::with_capacity(data.len() * 2);
    for byte in data {
        result.push(char::from(DIGITS[usize::from(byte >> 4)]));
        result.push(char::from(DIGITS[usize::from(byte & 15)]));
    }
    result
}

fn unhex(value: &str) -> Result<Vec<u8>, &'static str> {
    fn digit(value: u8) -> Option<u8> {
        match value {
            b'0'..=b'9' => Some(value - b'0'),
            b'a'..=b'f' => Some(value - b'a' + 10),
            _ => None,
        }
    }
    if !value.len().is_multiple_of(2) {
        return Err("adapterFailure");
    }
    value
        .as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| {
            Ok(digit(pair[0]).ok_or("adapterFailure")? * 16
                + digit(pair[1]).ok_or("adapterFailure")?)
        })
        .collect()
}

fn bits(value: f64) -> String {
    format!("{:016x}", if value == 0.0 { 0 } else { value.to_bits() })
}

fn document_semantic(document: &Document) -> Value {
    json!({
        "version": document.version,
        "axis": document.axis,
        "title": document.title,
        "metadata": document.metadata,
        "preamble": document.preamble,
        "planes": document.planes.iter().map(|plane| json!({
            "zBits": bits(plane.z),
            "xBits": plane.x.map(bits),
            "yBits": plane.y.map(bits),
            "label": plane.label,
            "attributes": plane.attributes,
            "body": plane.body,
        })).collect::<Vec<_>>(),
    })
}

fn edit_plane(plane: &Plane) -> Plane {
    let mut edited = plane.clone();
    if !edited.body.is_empty() {
        edited.body.push('\n');
    }
    edited.body.push_str("interchange edited");
    edited
}

fn document_response(bytes: &[u8]) -> Result<Response, &'static str> {
    let limits = DocumentDecodeLimits::default();
    let options = OperationOptions::default();
    let edit_limits = DocumentEditLimits::default();
    let document = storage::decode(bytes, &limits, &options).map_err(|error| error.code())?;
    let canonical = storage::encode(&document, DocumentStorageFormat::Text, &limits, &options)
        .map_err(|error| error.code())?;
    let binary = storage::encode(
        &document,
        DocumentStorageFormat::Binary(DocumentCompression::None),
        &limits,
        &options,
    )
    .map_err(|error| error.code())?;
    let raw_canonical_hex = if storage::is_binary(bytes) {
        None
    } else {
        let source = std::str::from_utf8(bytes).map_err(|_| "invalidUTF8")?;
        let raw = threemd::parse(source).map_err(|error| error.code())?;
        Some(hex(&storage::encode(
            &raw,
            DocumentStorageFormat::Text,
            &limits,
            &options,
        )
        .map_err(|error| error.code())?))
    };
    let adopted =
        editing::adopt_document(&document, &limits, &options).map_err(|error| error.code())?;
    let snapshot =
        DocumentSnapshot::new(adopted, &limits, &options).map_err(|error| error.code())?;
    let adopted_hex = hex(&storage::encode(
        snapshot.document(),
        DocumentStorageFormat::Text,
        &limits,
        &options,
    )
    .map_err(|error| error.code())?);
    let (edited_hex, stale_rejected) = if let Some(plane) = snapshot.document().planes.first() {
        let patch = DocumentPatch {
            expected_revision: snapshot.revision().clone(),
            operations: vec![DocumentEdit::Replace {
                id: plane.stable_id().ok_or("adapterFailure")?.to_owned(),
                plane: edit_plane(plane),
            }],
        };
        let edited =
            editing::apply_document_patch(&patch, &snapshot, &edit_limits, &limits, &options)
                .map_err(|error| error.code())?;
        let stale = editing::apply_document_patch(&patch, &edited, &edit_limits, &limits, &options);
        if !matches!(stale, Err(ref error) if error.code() == "staleRevision") {
            return Err("adapterFailure");
        }
        (
            hex(&storage::encode(
                edited.document(),
                DocumentStorageFormat::Text,
                &limits,
                &options,
            )
            .map_err(|error| error.code())?),
            true,
        )
    } else {
        (adopted_hex.clone(), true)
    };
    Ok(Response {
        ok: true,
        canonical_hex: hex(&canonical),
        binary_hex: hex(&binary),
        legacy_hex: Some(hex(threemd::serialize(&document).as_bytes())),
        raw_canonical_hex,
        revision_hex: hex(snapshot.revision().canonical_content.as_bytes()),
        adopted_hex,
        edited_hex,
        stale_rejected,
        semantic: document_semantic(&document),
    })
}

fn composition_response(bytes: &[u8]) -> Result<Response, &'static str> {
    let limits = DocumentDecodeLimits::default();
    let graph_limits = DocumentCompositionLimits::default();
    let options = OperationOptions::default();
    let edit_limits = DocumentEditLimits::default();
    let profile = storage::decode(bytes, &limits, &options).map_err(|error| error.code())?;
    let graph = composition::decode_document(&profile, &graph_limits, &limits, &options)
        .map_err(|error| error.code())?;
    let canonical = composition::encode(&graph, &graph_limits, &limits, &options)
        .map_err(|error| error.code())?;
    let profile = composition::document(&graph, &graph_limits, &limits, &options)
        .map_err(|error| error.code())?;
    let binary = storage::encode(
        &profile,
        DocumentStorageFormat::Binary(DocumentCompression::None),
        &limits,
        &options,
    )
    .map_err(|error| error.code())?;
    let adopted = editing::adopt_composition(&graph, &graph_limits, &limits, &options)
        .map_err(|error| error.code())?;
    let snapshot = DocumentCompositionSnapshot::new(adopted, &graph_limits, &limits, &options)
        .map_err(|error| error.code())?;
    let adopted_hex =
        hex(
            &composition::encode(snapshot.composition(), &graph_limits, &limits, &options)
                .map_err(|error| error.code())?,
        );
    let root = snapshot.composition().root_entry();
    let (edited_hex, stale_rejected) = if let Some(plane) = root.document.planes.first() {
        let mut entry = root.clone();
        entry.document.planes[0] = edit_plane(plane);
        let patch = CompositionPatch {
            expected_revision: snapshot.revision().clone(),
            operations: vec![CompositionEdit::ReplaceEntry {
                id: root.id.clone(),
                entry,
            }],
        };
        let edited = editing::apply_composition_patch(
            &patch,
            &snapshot,
            &edit_limits,
            &graph_limits,
            &limits,
            &options,
        )
        .map_err(|error| error.code())?;
        let stale = editing::apply_composition_patch(
            &patch,
            &edited,
            &edit_limits,
            &graph_limits,
            &limits,
            &options,
        );
        if !matches!(stale, Err(ref error) if error.code() == "staleRevision") {
            return Err("adapterFailure");
        }
        (
            hex(
                &composition::encode(edited.composition(), &graph_limits, &limits, &options)
                    .map_err(|error| error.code())?,
            ),
            true,
        )
    } else {
        (adopted_hex.clone(), true)
    };
    Ok(Response {
        ok: true,
        canonical_hex: hex(&canonical),
        binary_hex: hex(&binary),
        legacy_hex: None,
        raw_canonical_hex: None,
        revision_hex: hex(snapshot.revision().canonical_content.as_bytes()),
        adopted_hex,
        edited_hex,
        stale_rejected,
        semantic: json!({
            "rootID": graph.root_id(),
            "entries": graph.entries().iter().map(|entry| json!({
                "id": entry.id,
                "document": document_semantic(&entry.document),
                "references": entry.references.iter().map(|reference| json!({
                    "targetID": reference.target_id,
                    "attributes": reference.attributes,
                })).collect::<Vec<_>>(),
            })).collect::<Vec<_>>(),
        }),
    })
}

fn response(line: &[u8]) -> Result<Response, &'static str> {
    let request: Request = serde_json::from_slice(line).map_err(|_| "adapterFailure")?;
    if request.schema != "3md-interchange-1" {
        return Err("adapterFailure");
    }
    let bytes = unhex(&request.bytes_hex)?;
    match request.kind.as_str() {
        "document" => document_response(&bytes),
        "composition" => composition_response(&bytes),
        _ => Err("adapterFailure"),
    }
}

/// Consume one complete line without retaining an oversized request.
fn read_line(reader: &mut impl BufRead, line: &mut Vec<u8>) -> io::Result<Option<bool>> {
    line.clear();
    let mut oversized = false;
    let mut consumed = false;
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return Ok(consumed.then_some(!oversized));
        }
        consumed = true;
        let newline = available.iter().position(|byte| *byte == b'\n');
        let count = newline.unwrap_or(available.len());
        if !oversized && count <= MAXIMUM_LINE_BYTES - line.len() {
            line.extend_from_slice(&available[..count]);
        } else {
            oversized = true;
            line.clear();
        }
        reader.consume(count + usize::from(newline.is_some()));
        if newline.is_some() {
            return Ok(Some(!oversized));
        }
    }
}

/// Serialize into a bounded buffer before publishing any response bytes.
#[derive(Default)]
struct Output(Vec<u8>);

impl Write for Output {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > MAXIMUM_LINE_BYTES - self.0.len() {
            return Err(io::Error::other(
                "interchange response exceeds its line bound",
            ));
        }
        self.0.extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

fn encoded_response(result: Result<Response, &'static str>) -> Vec<u8> {
    let mut output = Output::default();
    match result {
        Ok(response) => {
            if serde_json::to_writer(&mut output, &response).is_ok() {
                output.0
            } else {
                br#"{"ok":false,"error":"adapterFailure"}"#.to_vec()
            }
        }
        Err(error) => serde_json::to_vec(&json!({ "ok": false, "error": error }))
            .expect("static error responses are valid JSON"),
    }
}

fn main() -> io::Result<()> {
    let mut input = io::stdin().lock();
    let mut output = io::stdout().lock();
    let mut line = Vec::new();
    while let Some(within_bound) = read_line(&mut input, &mut line)? {
        let result = if within_bound {
            response(&line)
        } else {
            Err("adapterFailure")
        };
        output.write_all(&encoded_response(result))?;
        output.write_all(b"\n")?;
        output.flush()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_is_exact_and_rejects_uppercase_or_odd_input() {
        assert_eq!(hex(&[0, 0xff, 0x10]), "00ff10");
        assert_eq!(unhex("00ff10").unwrap(), [0, 0xff, 0x10]);
        for invalid in ["0", "0F", "gg", " 0"] {
            assert_eq!(unhex(invalid).unwrap_err(), "adapterFailure");
        }
        assert_eq!(bits(-0.0), "0000000000000000");
    }

    #[test]
    fn oversized_requests_are_consumed_and_responses_are_atomic() {
        let mut input = vec![b' '; MAXIMUM_LINE_BYTES + 1];
        input.extend_from_slice(b"\n{}\n");
        let mut reader = io::Cursor::new(input);
        let mut line = Vec::new();
        assert_eq!(read_line(&mut reader, &mut line).unwrap(), Some(false));
        assert!(line.is_empty());
        assert_eq!(read_line(&mut reader, &mut line).unwrap(), Some(true));
        assert_eq!(line, b"{}");
        assert_eq!(read_line(&mut reader, &mut line).unwrap(), None);
        let mut output = Output(vec![0; MAXIMUM_LINE_BYTES]);
        assert!(output.write_all(b"x").is_err());
        assert_eq!(output.0.len(), MAXIMUM_LINE_BYTES);
    }

    #[test]
    fn document_adapter_edits_and_rejects_stale_patch_for_both_file_formats() {
        let source = b"---\n3md: 0.1\naxis: layer\n---\n@plane z=-0\nBody\n";
        let text = document_response(source).unwrap();
        assert!(text.stale_rejected);
        assert_eq!(text.raw_canonical_hex.as_ref(), Some(&text.canonical_hex));
        assert_eq!(text.revision_hex, text.adopted_hex);
        assert_ne!(text.edited_hex, text.adopted_hex);
        assert_eq!(text.semantic["planes"][0]["zBits"], "0000000000000000");
        let binary = document_response(&unhex(&text.binary_hex).unwrap()).unwrap();
        assert_eq!(binary.canonical_hex, text.canonical_hex);
        assert_eq!(binary.semantic, text.semantic);
        assert_eq!(binary.edited_hex, text.edited_hex);
        assert!(binary.raw_canonical_hex.is_none());
        let empty = document_response(b"---\n3md: 0.1\n---\n").unwrap();
        assert_eq!(empty.edited_hex, empty.adopted_hex);
        assert!(empty.stale_rejected);
    }

    #[test]
    fn composition_adapter_preserves_references_and_binary_parity() {
        let bytes = std::fs::read(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../conformance/extensions/composition-instances.3md"
        ))
        .unwrap();
        let text = composition_response(&bytes).unwrap();
        assert!(text.stale_rejected);
        assert_eq!(text.revision_hex, text.adopted_hex);
        assert_ne!(text.edited_hex, text.adopted_hex);
        assert!(text.legacy_hex.is_none());
        assert!(text.raw_canonical_hex.is_none());
        let binary = composition_response(&unhex(&text.binary_hex).unwrap()).unwrap();
        assert_eq!(binary.canonical_hex, text.canonical_hex);
        assert_eq!(binary.semantic, text.semantic);
        assert_eq!(binary.edited_hex, text.edited_hex);
    }
}
