use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use threemd::composition::{
    self, DocumentComposition, DocumentCompositionError, DocumentCompositionLimits, DocumentEntry,
    DocumentReference,
};
use threemd::diagnostics;
use threemd::editing::{
    self, CompositionEdit, CompositionPatch, DocumentCompositionSnapshot, DocumentEdit,
    DocumentEditLimits, DocumentPatch, DocumentRevision, DocumentSnapshot,
};
use threemd::storage::{
    self, CancellationToken, DocumentCompression, DocumentDecodeLimits, DocumentStorageError,
    DocumentStorageFormat, OperationOptions,
};
use threemd::{parse, Document, Plane};

fn options() -> OperationOptions {
    OperationOptions::default()
}
fn limits() -> DocumentDecodeLimits {
    DocumentDecodeLimits::default()
}
fn graph_limits() -> DocumentCompositionLimits {
    DocumentCompositionLimits::default()
}
fn edit_limits() -> DocumentEditLimits {
    DocumentEditLimits::default()
}
fn fixture(name: &str) -> Vec<u8> {
    fs::read(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../conformance/extensions")
            .join(name),
    )
    .unwrap()
}
fn json_fixture(name: &str) -> Value {
    serde_json::from_slice(&fixture(name)).unwrap()
}
fn optional_string(value: &Value) -> Option<String> {
    value.as_str().map(str::to_owned)
}
fn map(value: &Value) -> BTreeMap<String, String> {
    value
        .as_object()
        .map(|values| {
            values
                .iter()
                .map(|(key, value)| (key.clone(), value.as_str().unwrap().into()))
                .collect()
        })
        .unwrap_or_default()
}
fn plane(value: &Value) -> Plane {
    Plane {
        z: value["z"].as_f64().unwrap(),
        label: optional_string(&value["label"]),
        x: value["x"].as_f64(),
        y: value["y"].as_f64(),
        attributes: map(&value["attributes"]),
        body: value["body"].as_str().unwrap().into(),
    }
}
fn document(value: &Value) -> Document {
    Document {
        version: value["version"].as_str().unwrap().into(),
        axis: value["axis"].as_str().unwrap().into(),
        title: optional_string(&value["title"]),
        metadata: map(&value["metadata"]),
        preamble: optional_string(&value["preamble"]),
        planes: value["planes"]
            .as_array()
            .unwrap()
            .iter()
            .map(plane)
            .collect(),
    }
}
fn reference(value: &Value) -> DocumentReference {
    DocumentReference {
        target_id: value["targetID"].as_str().unwrap().into(),
        attributes: map(&value["attributes"]),
    }
}
fn graph(value: &Value) -> DocumentComposition {
    let entries = value["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|value| DocumentEntry {
            id: value["id"].as_str().unwrap().into(),
            document: document(&value["document"]),
            references: value["references"]
                .as_array()
                .unwrap()
                .iter()
                .map(reference)
                .collect(),
        })
        .collect();
    DocumentComposition::new(
        value["rootID"].as_str().unwrap().into(),
        entries,
        &graph_limits(),
        &limits(),
        &options(),
    )
    .unwrap()
}
fn sample() -> Document {
    parse("---\n3md: 1.0\naxis: layer\n---\n@plane z=0 3md-id=first\nFirst\n@plane z=1 3md-id=second\nSecond\n").unwrap()
}
fn entry(id: &str, targets: &[&str]) -> DocumentEntry {
    DocumentEntry {
        id: id.into(),
        document: sample(),
        references: targets
            .iter()
            .map(|target| DocumentReference {
                target_id: (*target).into(),
                attributes: BTreeMap::new(),
            })
            .collect(),
    }
}
fn encode(document: &Document) -> Vec<u8> {
    storage::encode(document, DocumentStorageFormat::Text, &limits(), &options()).unwrap()
}
/// Payload kind 2, the 2.1 `Binary` writer.
fn encode_structured(document: &Document) -> Vec<u8> {
    storage::encode(
        document,
        DocumentStorageFormat::Binary(DocumentCompression::None),
        &limits(),
        &options(),
    )
    .unwrap()
}
/// Payload kind 1, the 2.0 binary bytes.
fn encode_text_container(document: &Document) -> Vec<u8> {
    storage::encode_text_container(document, DocumentCompression::None, &limits(), &options())
        .unwrap()
}
fn profile(json: &str) -> Vec<u8> {
    let document = Document {
        version: "0.1".into(),
        axis: "layer".into(),
        title: None,
        metadata: BTreeMap::from([("profile".into(), "3md-composition-1".into())]),
        preamble: None,
        planes: vec![Plane {
            z: 0.0,
            label: Some("Composition".into()),
            x: None,
            y: None,
            attributes: BTreeMap::new(),
            body: format!("```json\n{json}\n```"),
        }],
    };
    encode(&document)
}

#[test]
fn swift_numeric_vectors_match_exact_storage_spelling() {
    let vectors = json_fixture("numeric-vectors.json");
    assert_eq!(vectors["schema"], "3md-canonical-numbers-1");
    for vector in vectors["vectors"].as_array().unwrap() {
        let bits = u64::from_str_radix(vector["bitPattern"].as_str().unwrap(), 16).unwrap();
        let z = f64::from_bits(bits);
        let mut document = sample();
        document.planes.truncate(1);
        document.planes[0].z = z;
        let source = String::from_utf8(encode(&document)).unwrap();
        let directive = source
            .lines()
            .find(|line| line.starts_with("@plane"))
            .unwrap();
        let actual = directive
            .split_whitespace()
            .nth(1)
            .unwrap()
            .strip_prefix("z=")
            .unwrap();
        assert_eq!(
            actual,
            vector["formatted"].as_str().unwrap(),
            "{}",
            vector["name"]
        );
    }
}

#[test]
fn every_signed_power_of_two_and_ten_matches_the_shared_canonical_spelling() {
    let vectors = json_fixture("numeric-powers.json");
    assert_eq!(vectors["schema"], "3md-canonical-numbers-1");
    let vectors = vectors["vectors"].as_array().unwrap();
    assert_eq!(vectors.len(), 4_318);
    let mut mismatches = Vec::new();
    for vector in vectors {
        let bits = u64::from_str_radix(vector["bitPattern"].as_str().unwrap(), 16).unwrap();
        let mut document = sample();
        document.planes.truncate(1);
        document.planes[0].z = f64::from_bits(bits);
        let expected = vector["formatted"].as_str().unwrap();
        let actual = match storage::encode(
            &document,
            DocumentStorageFormat::Text,
            &limits(),
            &options(),
        ) {
            Ok(source) => String::from_utf8(source)
                .unwrap()
                .lines()
                .find(|line| line.starts_with("@plane"))
                .and_then(|line| line.split_whitespace().nth(1))
                .and_then(|token| token.strip_prefix("z="))
                .unwrap()
                .to_owned(),
            Err(error) => format!("{error:?}"),
        };
        if actual != expected {
            mismatches.push(format!("{}: {actual} != {expected}", vector["name"]));
        }
    }
    assert!(mismatches.is_empty(), "{mismatches:#?}");
}

#[test]
fn canonical_decimal_ties_use_nearest_even_shortest_spelling() {
    for (bits, expected) in [
        (0xc303_45da_fa96_cd52, "-678103920859562.2"),
        (0x42ef_bda3_f10a_8034, "279194878104577.62"),
        (0x430d_5779_8162_e67a, "1032369212251343.2"),
    ] {
        let mut document = sample();
        document.planes.truncate(1);
        document.planes[0].z = f64::from_bits(bits);
        let encoded = encode(&document);
        let source = String::from_utf8(encoded).unwrap();
        let directive = source
            .lines()
            .find(|line| line.starts_with("@plane"))
            .unwrap();
        let actual = directive
            .split_whitespace()
            .nth(1)
            .unwrap()
            .strip_prefix("z=")
            .unwrap();
        assert_eq!(actual, expected);
    }
}

#[test]
fn swift_document_and_composition_goldens_are_byte_identical() {
    let expected = document(&json_fixture("document-unicode.json"));
    let text = fixture("document-unicode.3md");
    let binary = fixture("document-unicode.3mdb");
    assert_eq!(
        storage::decode(&text, &limits(), &options()).unwrap(),
        expected
    );
    assert_eq!(
        storage::decode(&binary, &limits(), &options()).unwrap(),
        expected
    );
    assert_eq!(encode(&expected), text);
    assert_eq!(encode_text_container(&expected), binary);
    let structured = fixture("document-unicode.structured.3mdb");
    assert_eq!(
        storage::decode(&structured, &limits(), &options()).unwrap(),
        expected
    );
    assert_eq!(encode_structured(&expected), structured);
    let expected = graph(&json_fixture("composition-instances.json"));
    let text = fixture("composition-instances.3md");
    let binary = fixture("composition-instances.3mdb");
    let structured = fixture("composition-instances.structured.3mdb");
    assert_eq!(
        composition::decode(&text, &graph_limits(), &limits(), &options()).unwrap(),
        expected
    );
    assert_eq!(
        composition::decode(&binary, &graph_limits(), &limits(), &options()).unwrap(),
        expected
    );
    assert_eq!(
        composition::encode(&expected, &graph_limits(), &limits(), &options()).unwrap(),
        text
    );
    assert_eq!(
        composition::decode(&structured, &graph_limits(), &limits(), &options()).unwrap(),
        expected
    );
    let profile = composition::document(&expected, &graph_limits(), &limits(), &options()).unwrap();
    assert_eq!(encode_text_container(&profile), binary);
    assert_eq!(encode_structured(&profile), structured);
}

#[test]
fn swift_unicode_key_order_and_source_collision_semantics_match() {
    let expected = document(&json_fixture("unicode-key-order.json"));
    let text = fixture("unicode-key-order.3md");
    let binary = fixture("unicode-key-order.3mdb");
    assert_eq!(
        storage::decode(&text, &limits(), &options()).unwrap(),
        expected
    );
    assert_eq!(
        storage::decode(&binary, &limits(), &options()).unwrap(),
        expected
    );
    assert_eq!(encode(&expected), text);
    assert_eq!(encode_text_container(&expected), binary);
    // Payload kind 2 stores the keys in raw UTF-8 byte order, not the text's NFC order.
    let structured = fixture("unicode-key-order.structured.3mdb");
    assert_eq!(
        storage::decode(&structured, &limits(), &options()).unwrap(),
        expected
    );
    assert_eq!(encode_structured(&expected), structured);
    let collision = fixture("unicode-source-collision.3md");
    let decoded = storage::decode(&collision, &limits(), &options()).unwrap();
    assert_eq!(
        decoded,
        document(&json_fixture("unicode-source-collision.json"))
    );
    assert_eq!(
        decoded.metadata.get("e\u{301}").map(String::as_str),
        Some("last")
    );
    assert!(!decoded.metadata.contains_key("é"));
    assert_eq!(
        storage::decode(&encode(&decoded), &limits(), &options()).unwrap(),
        decoded
    );
    // The merged map (first spelling, last value) as payload kind 2.
    let structured = fixture("unicode-source-collision.structured.3mdb");
    assert_eq!(encode_structured(&decoded), structured);
    assert_eq!(
        storage::decode(&structured, &limits(), &options()).unwrap(),
        decoded
    );
    // Raw and bounded parsing now share Swift's source-order key semantics.
    let raw = parse(std::str::from_utf8(&collision).unwrap()).unwrap();
    assert_eq!(raw, decoded);
    assert!(raw.metadata.contains_key("e\u{301}"));
    assert_eq!(
        composition::decode(
            &fixture("unicode-composition-duplicate.3md"),
            &graph_limits(),
            &limits(),
            &options()
        )
        .unwrap_err(),
        DocumentCompositionError::InvalidProfile("duplicate JSON object key".into())
    );
}

#[test]
fn original_extension_artifacts_and_lzfse_unavailability() {
    let base = Path::new(env!("CARGO_MANIFEST_DIR")).join("../Examples/Extensions");
    for name in ["canopy", "shared-grove"] {
        let text = fs::read(base.join(format!("{name}.3md"))).unwrap();
        let binary = fs::read(base.join(format!("{name}.3mdb"))).unwrap();
        let structured = fs::read(base.join(format!("{name}.structured.3mdb"))).unwrap();
        let document = storage::decode(&text, &limits(), &options()).unwrap();
        assert_eq!(encode(&document), text);
        assert_eq!(
            storage::decode(&binary, &limits(), &options()).unwrap(),
            document
        );
        assert_eq!(encode_text_container(&document), binary);
        assert_eq!(
            storage::decode(&structured, &limits(), &options()).unwrap(),
            document
        );
        assert_eq!(encode_structured(&document), structured);
        let compressed = fs::read(base.join(format!("{name}.lzfse.3mdb"))).unwrap();
        assert_eq!(
            storage::decode(&compressed, &limits(), &options()),
            Err(DocumentStorageError::CompressionUnavailable(
                DocumentCompression::Lzfse
            ))
        );
        assert_eq!(
            storage::encode(
                &document,
                DocumentStorageFormat::Binary(DocumentCompression::Lzfse),
                &limits(),
                &options()
            ),
            Err(DocumentStorageError::CompressionUnavailable(
                DocumentCompression::Lzfse
            ))
        );
        assert_eq!(
            storage::encode_text_container(
                &document,
                DocumentCompression::Lzfse,
                &limits(),
                &options()
            ),
            Err(DocumentStorageError::CompressionUnavailable(
                DocumentCompression::Lzfse
            ))
        );
    }
}

fn assert_header_corruption_is_rejected(original: &[u8], kind: u8) {
    for count in 8..40 {
        assert_eq!(
            storage::decode(&original[..count], &limits(), &options()),
            Err(DocumentStorageError::InvalidContainer)
        );
    }
    // Byte 10 is covered by the CRC: the other supported kind is a checksum failure, and a
    // reserved kind is rejected at D6 before the CRC.
    for (offset, byte, expected) in [
        (8, 2, DocumentStorageError::UnsupportedVersion(2)),
        (10, 3, DocumentStorageError::UnsupportedPayloadKind(3)),
        (10, 3 - kind, DocumentStorageError::ChecksumMismatch),
        (11, 255, DocumentStorageError::UnsupportedCompression(255)),
        (12, 1, DocumentStorageError::UnsupportedFlags(1)),
        (16, 1, DocumentStorageError::NonzeroReserved),
        (36, original[36] ^ 1, DocumentStorageError::ChecksumMismatch),
        (40, original[40] ^ 1, DocumentStorageError::ChecksumMismatch),
    ] {
        let mut changed = original.to_vec();
        changed[offset] = byte;
        assert_eq!(
            storage::decode(&changed, &limits(), &options()),
            Err(expected),
            "kind {kind}, byte {offset}"
        );
    }
    let mut changed = original.to_vec();
    changed[28..36].copy_from_slice(&u64::MAX.to_le_bytes());
    assert_eq!(
        storage::decode(&changed, &limits(), &options()),
        Err(DocumentStorageError::OversizedOutput)
    );
    let mut changed = original.to_vec();
    changed[20..28].copy_from_slice(&u64::MAX.to_le_bytes());
    assert_eq!(
        storage::decode(&changed, &limits(), &options()),
        Err(DocumentStorageError::LengthMismatch)
    );
    let mut changed = original.to_vec();
    changed.push(0);
    assert_eq!(
        storage::decode(&changed, &limits(), &options()),
        Err(DocumentStorageError::LengthMismatch)
    );
    assert_eq!(
        storage::decode(&original[..original.len() - 1], &limits(), &options()),
        Err(DocumentStorageError::LengthMismatch)
    );
}

#[test]
fn binary_header_fields_and_corruption_are_rejected() {
    let original = fixture("document-unicode.3mdb");
    assert_eq!(original[10], 1);
    assert_header_corruption_is_rejected(&original, 1);
    let structured = fixture("document-unicode.structured.3mdb");
    assert_eq!(structured[10], 2);
    assert_header_corruption_is_rejected(&structured, 2);
    assert!(!storage::is_binary(b"3MDB"));
    assert!(!storage::is_binary(b"3mdbin\r"));
    assert_eq!(
        storage::decode(&[0xff], &limits(), &options()),
        Err(DocumentStorageError::InvalidUtf8)
    );
}

#[test]
fn storage_resource_policies_and_faithful_value_validation() {
    let source = encode(&sample());
    for (policy, expected) in [
        (
            DocumentDecodeLimits {
                maximum_encoded_bytes: source.len() - 1,
                ..limits()
            },
            DocumentStorageError::OversizedInput,
        ),
        (
            DocumentDecodeLimits {
                maximum_decoded_bytes: source.len() - 1,
                ..limits()
            },
            DocumentStorageError::OversizedOutput,
        ),
        (
            DocumentDecodeLimits {
                maximum_lines: 2,
                ..limits()
            },
            DocumentStorageError::TooManyLines,
        ),
        (
            DocumentDecodeLimits {
                maximum_planes: 1,
                ..limits()
            },
            DocumentStorageError::TooManyPlanes,
        ),
        (
            DocumentDecodeLimits {
                maximum_record_bytes: 4,
                ..limits()
            },
            DocumentStorageError::OversizedRecord,
        ),
        (
            DocumentDecodeLimits {
                maximum_planes: 0,
                ..limits()
            },
            DocumentStorageError::InvalidLimits,
        ),
    ] {
        assert_eq!(storage::decode(&source, &policy, &options()), Err(expected));
    }
    let mut invalid_values = Vec::new();
    let mut document = sample();
    document.version.clear();
    invalid_values.push(document);
    let mut document = sample();
    document.planes[0].z = f64::INFINITY;
    invalid_values.push(document);
    let mut document = sample();
    document.planes[1].z = -0.0;
    invalid_values.push(document);
    let mut document = sample();
    document.planes[0].body = "\nbody\n".into();
    invalid_values.push(document);
    let mut document = sample();
    document.metadata.insert("TITLE".into(), "shadow".into());
    invalid_values.push(document);
    let mut document = sample();
    document.planes[0]
        .attributes
        .insert("Style".into(), "red".into());
    invalid_values.push(document);
    let mut document = sample();
    document.title = Some("a\rb".into());
    invalid_values.push(document);
    for document in invalid_values {
        assert!(matches!(
            storage::validate(&document, &limits(), &options()),
            Err(DocumentStorageError::InvalidDocument(_))
        ));
    }
    let legacy =
        "---\n3md: 1.0\ncustom: first\ncustom: last\n---\n@plane z=0 id=first id=last\nbody\n";
    assert_eq!(
        storage::decode(legacy.as_bytes(), &limits(), &options()).unwrap(),
        parse(legacy).unwrap()
    );
    let malformed = format!("---\n3md: 1.0\n---\n@plane z={}x\n", "1".repeat(4096));
    assert!(matches!(
        storage::decode(malformed.as_bytes(), &limits(), &options()),
        Err(DocumentStorageError::InvalidText(_))
    ));
}

#[test]
fn graph_validates_unused_entries_cycles_and_resource_limits() {
    assert_eq!(
        DocumentComposition::new(
            "root".into(),
            vec![entry("root", &[]), entry("unused", &["missing"])],
            &graph_limits(),
            &limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "missingTarget"
    );
    assert_eq!(
        DocumentComposition::new(
            "root".into(),
            vec![entry("root", &[]), entry("unused", &["unused"])],
            &graph_limits(),
            &limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "cycle"
    );
    assert_eq!(
        DocumentComposition::new(
            "../root".into(),
            vec![entry("root", &[])],
            &graph_limits(),
            &limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "invalidID"
    );
    let entries = vec![entry("root", &["leaf", "leaf"]), entry("leaf", &[])];
    for (policy, expected) in [
        (
            DocumentCompositionLimits {
                maximum_definitions: 1,
                ..graph_limits()
            },
            "tooManyDefinitions",
        ),
        (
            DocumentCompositionLimits {
                maximum_references: 1,
                ..graph_limits()
            },
            "tooManyReferences",
        ),
        (
            DocumentCompositionLimits {
                maximum_depth: 1,
                ..graph_limits()
            },
            "depthExceeded",
        ),
        (
            DocumentCompositionLimits {
                maximum_traversal_occurrences: 2,
                ..graph_limits()
            },
            "traversalOccurrencesExceeded",
        ),
        (
            DocumentCompositionLimits {
                maximum_definition_bytes: 1,
                ..graph_limits()
            },
            "definitionBytesExceeded",
        ),
    ] {
        assert_eq!(
            DocumentComposition::new(
                "root".into(),
                entries.clone(),
                &policy,
                &limits(),
                &options()
            )
            .unwrap_err()
            .code(),
            expected
        );
    }
    let mut attributed = entries.clone();
    attributed[0].references[0]
        .attributes
        .insert("a".into(), "b".into());
    assert_eq!(
        DocumentComposition::new(
            "root".into(),
            attributed.clone(),
            &DocumentCompositionLimits {
                maximum_reference_attributes: 0,
                ..graph_limits()
            },
            &limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "referenceAttributesExceeded"
    );
    assert_eq!(
        DocumentComposition::new(
            "root".into(),
            attributed,
            &DocumentCompositionLimits {
                maximum_reference_attribute_bytes: 1,
                ..graph_limits()
            },
            &limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "referenceAttributesExceeded"
    );
}

#[test]
fn composition_json_is_strict_and_rejects_decoded_duplicate_keys() {
    let empty = r#"{"schema":"3md-composition-1","rootID":"root","entries":[]}"#;
    let duplicate =
        r#"{"schema":"3md-composition-1","rootID":"root","\u0072ootID":"root","entries":[]}"#;
    for json in [
        duplicate,
        r#"{"schema":"3md-composition-1","rootID":"root","entries":[],"extra":false}"#,
        r#"{"schema":1,"rootID":"root","entries":[]}"#,
        r#"{"schema":"3md-composition-1","rootID":"root","entries":[]} []"#,
    ] {
        assert!(matches!(
            composition::decode(&profile(json), &graph_limits(), &limits(), &options()),
            Err(DocumentCompositionError::InvalidProfile(_))
        ));
    }
    assert_eq!(
        composition::decode(&profile(duplicate), &graph_limits(), &limits(), &options())
            .unwrap_err(),
        DocumentCompositionError::InvalidProfile("duplicate JSON object key".into())
    );
    assert_eq!(
        composition::decode(&profile(empty), &graph_limits(), &limits(), &options())
            .unwrap_err()
            .code(),
        "missingRoot"
    );
    let mut value: Value = serde_json::from_str(empty).unwrap();
    value["schema"] = Value::String("future".into());
    assert_eq!(
        composition::decode(
            &profile(&value.to_string()),
            &graph_limits(),
            &limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "unsupportedProfile"
    );
    let child = String::from_utf8(encode(&sample())).unwrap();
    let valid = serde_json::json!({"schema":"3md-composition-1","rootID":"root","entries":[{"id":"root","source":child,"references":[]}]}).to_string();
    assert!(composition::decode(&profile(&valid), &graph_limits(), &limits(), &options()).is_ok());
    let duplicate_attributes = valid.replace("\"references\":[]", "\"references\":[{\"targetID\":\"root\",\"attributes\":{\"a\":\"first\",\"\\u0061\":\"second\"}}]");
    assert_eq!(
        composition::decode(
            &profile(&duplicate_attributes),
            &graph_limits(),
            &limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "invalidProfile"
    );
    for escape in ["\\ud800", "\\udc00", "\\ud800\\u0041"] {
        let malformed = valid.replace("\"rootID\":\"root\"", &format!("\"rootID\":\"{escape}\""));
        assert!(matches!(
            composition::decode(&profile(&malformed), &graph_limits(), &limits(), &options()),
            Err(DocumentCompositionError::InvalidProfile(_))
        ));
    }
}

fn document_operations(values: &Value) -> Vec<DocumentEdit> {
    values
        .as_array()
        .unwrap()
        .iter()
        .map(|value| match value["kind"].as_str().unwrap() {
            "replace" => DocumentEdit::Replace {
                id: value["id"].as_str().unwrap().into(),
                plane: plane(&value["plane"]),
            },
            "move" => DocumentEdit::Move {
                id: value["id"].as_str().unwrap().into(),
                to: value["to"].as_i64().unwrap() as isize,
            },
            other => panic!("unexpected document command {other}"),
        })
        .collect()
}
fn composition_operations(values: &Value) -> Vec<CompositionEdit> {
    values
        .as_array()
        .unwrap()
        .iter()
        .map(|value| {
            let owner_id = value["ownerID"].as_str().unwrap().into();
            let id = value["id"].as_str().unwrap().into();
            match value["kind"].as_str().unwrap() {
                "replaceReference" => CompositionEdit::ReplaceReference {
                    owner_id,
                    id,
                    reference: reference(&value["reference"]),
                },
                "moveReference" => CompositionEdit::MoveReference {
                    owner_id,
                    id,
                    to: value["to"].as_i64().unwrap() as isize,
                },
                "removeReference" => CompositionEdit::RemoveReference { owner_id, id },
                other => panic!("unexpected graph command {other}"),
            }
        })
        .collect()
}

#[test]
fn swift_adoption_transactions_and_failures_match_semantics() {
    let vectors = json_fixture("editing-vectors.json");
    let input = document(&vectors["documentAdoption"]["input"]);
    assert_eq!(
        editing::adopt_document(&input, &limits(), &options()).unwrap(),
        document(&vectors["documentAdoption"]["expected"])
    );
    let input = graph(&vectors["compositionAdoption"]["input"]);
    assert_eq!(
        editing::adopt_composition(&input, &graph_limits(), &limits(), &options()).unwrap(),
        graph(&vectors["compositionAdoption"]["expected"])
    );
    let document_snapshot = DocumentSnapshot::new(
        document(&json_fixture("document-unicode.json")),
        &limits(),
        &options(),
    )
    .unwrap();
    let graph_snapshot = DocumentCompositionSnapshot::new(
        graph(&json_fixture("composition-instances.json")),
        &graph_limits(),
        &limits(),
        &options(),
    )
    .unwrap();
    for vector in vectors["documentTransactions"].as_array().unwrap() {
        let patch = DocumentPatch {
            expected_revision: document_snapshot.revision().clone(),
            operations: document_operations(&vector["operations"]),
        };
        let result = editing::apply_document_patch(
            &patch,
            &document_snapshot,
            &edit_limits(),
            &limits(),
            &options(),
        )
        .unwrap();
        assert_eq!(
            result.document(),
            &document(&vector["expected"]),
            "{}",
            vector["name"]
        );
    }
    for vector in vectors["compositionTransactions"].as_array().unwrap() {
        let patch = CompositionPatch {
            expected_revision: graph_snapshot.revision().clone(),
            operations: composition_operations(&vector["operations"]),
        };
        let result = editing::apply_composition_patch(
            &patch,
            &graph_snapshot,
            &edit_limits(),
            &graph_limits(),
            &limits(),
            &options(),
        )
        .unwrap();
        assert_eq!(
            result.composition(),
            &graph(&vector["expected"]),
            "{}",
            vector["name"]
        );
    }
    for vector in vectors["failures"].as_array().unwrap() {
        let suffix = vector["expectedRevisionSuffix"].as_str().unwrap_or("");
        let error = if vector["scope"] == "document" {
            let patch = DocumentPatch {
                expected_revision: DocumentRevision {
                    canonical_content: format!(
                        "{}{suffix}",
                        document_snapshot.revision().canonical_content
                    ),
                },
                operations: document_operations(&vector["operations"]),
            };
            editing::apply_document_patch(
                &patch,
                &document_snapshot,
                &edit_limits(),
                &limits(),
                &options(),
            )
            .unwrap_err()
        } else {
            let patch = CompositionPatch {
                expected_revision: DocumentRevision {
                    canonical_content: format!(
                        "{}{suffix}",
                        graph_snapshot.revision().canonical_content
                    ),
                },
                operations: composition_operations(&vector["operations"]),
            };
            editing::apply_composition_patch(
                &patch,
                &graph_snapshot,
                &edit_limits(),
                &graph_limits(),
                &limits(),
                &options(),
            )
            .unwrap_err()
        };
        assert_eq!(
            error.code(),
            vector["expectedCode"].as_str().unwrap(),
            "{}",
            vector["name"]
        );
        assert_eq!(
            error.diagnostic().unwrap().path.as_deref(),
            vector["expectedPath"].as_str(),
            "{}",
            vector["name"]
        );
    }
    assert_eq!(
        document_snapshot.document(),
        &document(&json_fixture("document-unicode.json"))
    );
    assert_eq!(
        graph_snapshot.composition(),
        &graph(&json_fixture("composition-instances.json"))
    );
}

#[test]
fn exact_utf8_revision_reopen_and_forged_snapshot_validation() {
    let document = document(&json_fixture("document-unicode.json"));
    let snapshot = DocumentSnapshot::new(document.clone(), &limits(), &options()).unwrap();
    let reopened =
        storage::decode(&fixture("document-unicode.3mdb"), &limits(), &options()).unwrap();
    assert_eq!(
        DocumentSnapshot::new(reopened, &limits(), &options()).unwrap(),
        snapshot
    );
    let different_bytes = DocumentRevision {
        canonical_content: snapshot
            .revision()
            .canonical_content
            .replace("café", "cafe\u{301}"),
    };
    assert_ne!(&different_bytes, snapshot.revision());
    let patch = DocumentPatch {
        expected_revision: different_bytes,
        operations: vec![],
    };
    assert_eq!(
        editing::apply_document_patch(&patch, &snapshot, &edit_limits(), &limits(), &options())
            .unwrap_err()
            .code(),
        "staleRevision"
    );
    assert_eq!(
        DocumentSnapshot::from_parts(
            document,
            DocumentRevision {
                canonical_content: "forged".into()
            },
            &limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "staleRevision"
    );
}

#[test]
fn bounded_diagnostics_preserve_real_parser_lines_and_legacy_ids() {
    let report = diagnostics::inspect_source(
        "---\n3md: 1.0\n---\n@plane x=1\n",
        &edit_limits(),
        &limits(),
        &options(),
    )
    .unwrap();
    assert_eq!(report.diagnostics[0].source_line, Some(4));
    assert_eq!(report.diagnostics[0].code.as_str(), "parseFailure");
    let report =
        diagnostics::inspect_source("plain", &edit_limits(), &limits(), &options()).unwrap();
    assert_eq!(report.diagnostics[0].source_line, None);
    let mut document = sample();
    document.planes[1]
        .attributes
        .insert("3md-id".into(), "first".into());
    document.planes[1].z = 0.0;
    let report =
        diagnostics::inspect_document(&document, &edit_limits(), &limits(), &options()).unwrap();
    assert_eq!(
        report
            .diagnostics
            .iter()
            .map(|issue| issue.code.as_str())
            .collect::<Vec<_>>(),
        ["duplicateIdentity", "duplicatePosition"]
    );
    assert!(report
        .diagnostics
        .iter()
        .all(|issue| issue.source_line.is_none()));
    let report = diagnostics::inspect_document(
        &document,
        &DocumentEditLimits {
            maximum_diagnostics: 1,
            ..edit_limits()
        },
        &limits(),
        &options(),
    )
    .unwrap();
    assert!(report.is_truncated);
    assert_eq!(report.diagnostics.len(), 1);
    let legacy = parse("---\n3md: 1.0\n---\n@plane z=0 id=opaque\nLegacy\n").unwrap();
    assert!(
        diagnostics::inspect_document(&legacy, &edit_limits(), &limits(), &options())
            .unwrap()
            .diagnostics
            .is_empty()
    );
    assert_eq!(
        diagnostics::inspect_source(
            "long source",
            &DocumentEditLimits {
                maximum_diagnostic_bytes: 1,
                ..edit_limits()
            },
            &limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "payloadLimit"
    );
}

#[test]
fn cancellation_propagates_without_publishing_values() {
    let token = CancellationToken::new();
    let cancelled = OperationOptions::with_cancellation(token.clone());
    token.cancel();
    assert_eq!(
        storage::encode(
            &sample(),
            DocumentStorageFormat::Text,
            &limits(),
            &cancelled
        ),
        Err(DocumentStorageError::Cancelled)
    );
    assert_eq!(
        storage::decode(&encode(&sample()), &limits(), &cancelled),
        Err(DocumentStorageError::Cancelled)
    );
    assert_eq!(
        DocumentComposition::new(
            "root".into(),
            vec![entry("root", &[])],
            &graph_limits(),
            &limits(),
            &cancelled
        )
        .unwrap_err()
        .code(),
        "cancelled"
    );
    assert_eq!(
        editing::adopt_document(&sample(), &limits(), &cancelled)
            .unwrap_err()
            .code(),
        "cancelled"
    );
    assert_eq!(
        diagnostics::inspect_document(&sample(), &edit_limits(), &limits(), &cancelled)
            .unwrap_err()
            .code(),
        "cancelled"
    );
    let snapshot = DocumentSnapshot::new(sample(), &limits(), &options()).unwrap();
    let patch = DocumentPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![DocumentEdit::Remove { id: "first".into() }],
    };
    assert_eq!(
        editing::apply_document_patch(&patch, &snapshot, &edit_limits(), &limits(), &cancelled)
            .unwrap_err()
            .code(),
        "cancelled"
    );
    assert_eq!(snapshot.document(), &sample());
    let mut large = sample();
    large.planes[0].body = "x".repeat(7 * 1024 * 1024);
    let token = CancellationToken::new();
    let operation_options = OperationOptions::with_cancellation(token.clone());
    std::thread::scope(|scope| {
        scope.spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(1));
            token.cancel();
        });
        assert_eq!(
            storage::encode(
                &large,
                DocumentStorageFormat::Text,
                &limits(),
                &operation_options
            ),
            Err(DocumentStorageError::Cancelled)
        );
    });
    assert_eq!(large.planes[0].body.len(), 7 * 1024 * 1024);
}
