//! Cross-language conformance suite.
//!
//! Reads every vector in `../conformance/*.json` and checks this crate's
//! behavior against the shared expectations that pin the Swift and TypeScript
//! implementations down. Each vector either describes an expected parsed
//! document, an expected error code, or an expected set of cross-plane links.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::Value;
use threemd::{links, parse, CrossPlaneLink, Document, Plane};

fn conformance_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../conformance")
}

fn expected_string(value: &Value) -> Option<String> {
    match value {
        Value::Null => None,
        Value::String(text) => Some(text.clone()),
        other => panic!("expected string or null, found {other}"),
    }
}

fn expected_number(value: &Value) -> Option<f64> {
    match value {
        Value::Null => None,
        Value::Number(number) => Some(number.as_f64().expect("number convertible to f64")),
        other => panic!("expected number or null, found {other}"),
    }
}

fn expected_map(value: &Value) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    if let Value::Object(object) = value {
        for (key, entry) in object {
            let text = entry
                .as_str()
                .expect("metadata/attribute value is a string");
            map.insert(key.clone(), text.to_string());
        }
    }
    map
}

fn assert_document(name: &str, expected: &Value, actual: &Document) {
    let object = expected.as_object().expect("expected object");

    assert_eq!(
        object["version"].as_str().expect("version string"),
        actual.version,
        "[{name}] version mismatch"
    );
    assert_eq!(
        object["axis"].as_str().expect("axis string"),
        actual.axis,
        "[{name}] axis mismatch"
    );
    assert_eq!(
        expected_string(&object["title"]),
        actual.title,
        "[{name}] title mismatch"
    );
    assert_eq!(
        expected_map(&object["metadata"]),
        actual.metadata,
        "[{name}] metadata mismatch"
    );
    assert_eq!(
        expected_string(&object["preamble"]),
        actual.preamble,
        "[{name}] preamble mismatch"
    );

    let expected_planes = object["planes"].as_array().expect("planes array");
    assert_eq!(
        expected_planes.len(),
        actual.planes.len(),
        "[{name}] plane count mismatch"
    );

    for (index, expected_plane) in expected_planes.iter().enumerate() {
        let actual_plane = &actual.planes[index];
        let expected_plane = Plane {
            z: expected_number(&expected_plane["z"]).expect("z is present"),
            label: expected_string(&expected_plane["label"]),
            x: expected_number(&expected_plane["x"]),
            y: expected_number(&expected_plane["y"]),
            attributes: expected_map(&expected_plane["attributes"]),
            body: expected_plane["body"]
                .as_str()
                .expect("body string")
                .to_string(),
        };
        assert_eq!(
            &expected_plane, actual_plane,
            "[{name}] plane {index} mismatch"
        );
    }
}

fn assert_links(name: &str, expected: &Value, actual: &[CrossPlaneLink]) {
    let expected_array = expected.as_array().expect("links array");
    assert_eq!(
        expected_array.len(),
        actual.len(),
        "[{name}] link count mismatch"
    );

    for (index, expected_link) in expected_array.iter().enumerate() {
        let actual_link = &actual[index];
        let expected_link = CrossPlaneLink {
            source_z: expected_number(&expected_link["sourceZ"]).expect("sourceZ present"),
            target_z: expected_number(&expected_link["targetZ"]).expect("targetZ present"),
            text: expected_string(&expected_link["text"]),
            target_exists: expected_link["targetExists"]
                .as_bool()
                .expect("targetExists bool"),
        };
        assert_eq!(
            &expected_link, actual_link,
            "[{name}] link {index} mismatch"
        );
    }
}

#[test]
fn conformance_vectors_pass() {
    let directory = conformance_dir();
    let mut paths: Vec<PathBuf> = fs::read_dir(&directory)
        .expect("conformance directory is readable")
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| path.extension().and_then(|ext| ext.to_str()) == Some("json"))
        .collect();
    paths.sort();

    assert!(!paths.is_empty(), "no conformance vectors found");

    let mut count = 0;
    for path in paths {
        let contents = fs::read_to_string(&path).expect("vector is readable");
        let vector: Value = serde_json::from_str(&contents).expect("vector is valid JSON");
        let object = vector.as_object().expect("vector is an object");

        let name = object
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or_else(|| path.to_str().unwrap_or("<unknown>"));
        let source = object["source"].as_str().expect("source string");

        if let Some(expected_links) = object.get("links") {
            let document = parse(source).unwrap_or_else(|error| {
                panic!("[{name}] expected a valid document, got error {error:?}")
            });
            let actual = links(&document);
            assert_links(name, expected_links, &actual);
        } else if let Some(expected) = object.get("expected") {
            let document = parse(source).unwrap_or_else(|error| {
                panic!("[{name}] expected a valid document, got error {error:?}")
            });
            assert_document(name, expected, &document);
        } else if let Some(expected_error) = object.get("error") {
            let code = expected_error.as_str().expect("error code string");
            match parse(source) {
                Ok(document) => {
                    panic!("[{name}] expected error '{code}', got document {document:?}")
                }
                Err(error) => assert_eq!(code, error.code(), "[{name}] error code mismatch"),
            }
        } else {
            panic!("[{name}] vector has no links, expected, or error key");
        }

        count += 1;
    }

    assert_eq!(count, 42, "expected exactly 42 conformance vectors");
    println!("conformance: all {count} vectors passed");
}
