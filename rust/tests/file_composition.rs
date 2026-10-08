use std::collections::BTreeMap;
use threemd::composition::{
    self, DocumentComposition, DocumentCompositionError, DocumentCompositionLimits, DocumentEntry,
    DocumentReference,
};
use threemd::file_composition::{self, DocumentFileCompositionError as Error, DocumentFileSource};
use threemd::storage::{
    self, CancellationToken, DocumentCompression, DocumentDecodeLimits, DocumentStorageError,
    DocumentStorageFormat, OperationOptions,
};
use threemd::{parse, Document};

fn options() -> OperationOptions {
    OperationOptions::default()
}
fn limits() -> DocumentDecodeLimits {
    DocumentDecodeLimits::default()
}
fn graph_limits() -> DocumentCompositionLimits {
    DocumentCompositionLimits::default()
}
fn document(body: &str, ledger: Option<&str>) -> Document {
    let mut value = parse(&format!("---\n3md: 1.7\naxis: custom\ntitle: Child\nkeep: retained\n---\nPreamble\n@plane z=3 3md-id=plane-original\n{body}\n")).unwrap();
    if let Some(ledger) = ledger {
        value.metadata.insert("3md-files".into(), ledger.into());
    }
    value
}
fn source(path: &str, value: &Document) -> DocumentFileSource {
    DocumentFileSource {
        path: path.into(),
        data: storage::encode(value, DocumentStorageFormat::Text, &limits(), &options()).unwrap(),
    }
}
fn resolve(
    root: &str,
    sources: &[DocumentFileSource],
) -> Result<threemd::DocumentFileCompositionResult, Error> {
    file_composition::resolve(root, sources, &graph_limits(), &limits(), &options())
}
fn entry(id: &str, value: Document, references: Vec<DocumentReference>) -> DocumentEntry {
    DocumentEntry {
        id: id.into(),
        document: value,
        references,
    }
}
fn graph(entries: Vec<DocumentEntry>) -> DocumentComposition {
    DocumentComposition::new(
        "root".into(),
        entries,
        &graph_limits(),
        &limits(),
        &options(),
    )
    .unwrap()
}
fn graph_source(path: &str, graph: &DocumentComposition, binary: bool) -> DocumentFileSource {
    let data = if binary {
        storage::encode(
            &composition::document(graph, &graph_limits(), &limits(), &options()).unwrap(),
            DocumentStorageFormat::Binary(DocumentCompression::None),
            &limits(),
            &options(),
        )
        .unwrap()
    } else {
        composition::encode(graph, &graph_limits(), &limits(), &options()).unwrap()
    };
    DocumentFileSource {
        path: path.into(),
        data,
    }
}
/// The profile envelope as payload kind 1, the ThreeMD 2.0 binary bundle.
fn text_container_graph_source(path: &str, graph: &DocumentComposition) -> DocumentFileSource {
    DocumentFileSource {
        path: path.into(),
        data: storage::encode_text_container(
            &composition::document(graph, &graph_limits(), &limits(), &options()).unwrap(),
            DocumentCompression::None,
            &limits(),
            &options(),
        )
        .unwrap(),
    }
}

#[test]
fn repeated_links_are_deterministic_and_preserve_the_ordinary_document() {
    let parent = document(
        "12",
        Some(r#"{"2":"models/child.data","1":"models/child.data"}"#),
    );
    let child = document("Markdown child", None);
    let mut sources = vec![
        source("root.3md", &parent),
        source("models/child.data", &child),
    ];
    let result = resolve("./root.3md", &sources).unwrap();
    assert_eq!(result.root_path, "root.3md");
    assert_eq!(result.resolved_paths, ["models/child.data", "root.3md"]);
    assert_eq!(result.file_root_ids["models/child.data"], "file-000000");
    assert_eq!(result.file_root_ids["root.3md"], "file-000001");
    let root = result.composition.root_entry();
    let mut expected = parent.clone();
    expected.metadata.remove("3md-files");
    assert_eq!(root.document, expected);
    assert_eq!(result.composition.entries()[0].document, child);
    assert_eq!(root.references.len(), 2);
    for (reference, glyph) in root.references.iter().zip(["1", "2"]) {
        assert_eq!(reference.target_id, "file-000000");
        assert_eq!(
            reference.attributes,
            BTreeMap::from([
                ("glyph".into(), glyph.into()),
                ("source-file".into(), "models/child.data".into())
            ])
        );
        assert!(!reference.attributes.contains_key("3md-id"));
    }
    sources.reverse();
    assert_eq!(resolve("root.3md", &sources).unwrap(), result);
    sources[0] = source("models/child.data", &document("Refreshed", None));
    let refreshed = resolve("root.3md", &sources).unwrap();
    assert_ne!(refreshed.composition, result.composition);
    assert_eq!(result.composition.entries()[0].document, child);
}

#[test]
fn nested_relative_paths_keep_duplicate_basenames_and_use_scalar_order() {
    let sources = vec![
        source(
            "scenes/root.3md",
            &document(
                "root",
                Some(
                    r#"{"a":"../models/a.3md","b":"../other/a.3md","c":"../e\u0301.3md","d":"../\ue000.3md","e":"../\ud83d\ude00.3md"}"#,
                ),
            ),
        ),
        source(
            "models/a.3md",
            &document("A", Some(r#"{"x":"../shared/end%20.data"}"#)),
        ),
        source("other/a.3md", &document("B", None)),
        source("shared/end%20.data", &document("End", None)),
        source("é.3md", &document("Unicode", None)),
        source("\u{e000}.3md", &document("Private", None)),
        source("😀.3md", &document("Emoji", None)),
    ];
    let result = resolve("scenes/root.3md", &sources).unwrap();
    assert_eq!(
        result.resolved_paths,
        [
            "models/a.3md",
            "other/a.3md",
            "scenes/root.3md",
            "shared/end%20.data",
            "é.3md",
            "\u{e000}.3md",
            "😀.3md"
        ]
    );
    assert_eq!(result.file_root_ids["\u{e000}.3md"], "file-000005");
    assert_eq!(result.file_root_ids["😀.3md"], "file-000006");
    let references = &result.composition.root_entry().references;
    assert_eq!(references[2].attributes["source-file"], "é.3md");
    assert_eq!(
        result.composition.entries()[0].references[0].attributes["source-file"],
        "shared/end%20.data"
    );
}

#[test]
fn binary_children_and_nested_bundles_preserve_unused_entries_and_reference_ids() {
    let original = DocumentReference {
        target_id: "leaf".into(),
        attributes: BTreeMap::from([
            ("3md-id".into(), "reference-original".into()),
            ("opaque".into(), "'quoted'\\value".into()),
        ]),
    };
    let bundle = graph(vec![
        entry(
            "root",
            document("Bundle root", Some(r#"{"a":"../leaf.3mdb"}"#)),
            vec![original.clone()],
        ),
        entry("leaf", document("Internal", None), vec![]),
        entry(
            "unused",
            document("Unused", Some(r#"{"z":"../leaf.3mdb"}"#)),
            vec![],
        ),
    ]);
    let external = document("External", None);
    // Children and bundles as text, payload kind 2 (`Binary`) and payload kind 1.
    let structured = storage::encode(
        &external,
        DocumentStorageFormat::Binary(DocumentCompression::None),
        &limits(),
        &options(),
    )
    .unwrap();
    let text_container =
        storage::encode_text_container(&external, DocumentCompression::None, &limits(), &options())
            .unwrap();
    assert_eq!(
        storage::container_info(&structured)
            .unwrap()
            .unwrap()
            .payload_kind,
        2
    );
    assert_eq!(
        storage::container_info(&text_container)
            .unwrap()
            .unwrap()
            .payload_kind,
        1
    );
    for (bundle_format, leaf) in [
        (0, &structured),
        (1, &structured),
        (2, &text_container),
        (1, &text_container),
    ] {
        let bundle_source = match bundle_format {
            0 => graph_source("bundles/child.data", &bundle, false),
            1 => graph_source("bundles/child.data", &bundle, true),
            _ => text_container_graph_source("bundles/child.data", &bundle),
        };
        let sources = vec![
            source(
                "root.3md",
                &document("Parent", Some(r#"{"1":"bundles/child.data"}"#)),
            ),
            bundle_source,
            DocumentFileSource {
                path: "leaf.3mdb".into(),
                data: leaf.clone(),
            },
        ];
        let result = resolve("root.3md", &sources).unwrap();
        assert_eq!(result.composition.entries().len(), 5);
        assert_eq!(result.file_root_ids["bundles/child.data"], "file-000001");
        let imported = result.composition.entry("file-000001").unwrap();
        assert_eq!(imported.references[0].target_id, "file-000000");
        assert_eq!(imported.references[0].attributes, original.attributes);
        assert_eq!(imported.references[1].target_id, "file-000003");
        assert_eq!(
            result.composition.entry("file-000002").unwrap().references[0].target_id,
            "file-000003"
        );
        assert!(result
            .composition
            .entries()
            .iter()
            .all(|entry| !entry.document.metadata.contains_key("3md-files")));
        let text = composition::encode(&result.composition, &graph_limits(), &limits(), &options())
            .unwrap();
        assert_eq!(
            composition::decode(&text, &graph_limits(), &limits(), &options()).unwrap(),
            result.composition
        );
        for detached in [
            graph_source("detached", &result.composition, true),
            text_container_graph_source("detached", &result.composition),
        ] {
            assert_eq!(
                composition::decode(&detached.data, &graph_limits(), &limits(), &options())
                    .unwrap(),
                result.composition
            );
        }
    }
}

#[test]
fn outer_profile_records_are_independent_of_child_record_policy() {
    let bundle = graph(vec![entry("root", document("Small child", None), vec![])]);
    let bundle_source = graph_source("bundle.3md", &bundle, false);
    let child_limits = DocumentDecodeLimits {
        maximum_record_bytes: 128,
        ..limits()
    };
    assert!(
        composition::document(&bundle, &graph_limits(), &limits(), &options())
            .unwrap()
            .planes[0]
            .body
            .len()
            > child_limits.maximum_record_bytes
    );
    let result = file_composition::resolve(
        "bundle.3md",
        &[bundle_source],
        &graph_limits(),
        &child_limits,
        &options(),
    )
    .unwrap();
    assert_eq!(
        result.composition.entries()[0].document.planes[0].body,
        "Small child"
    );
    let oversized = source("ordinary.3md", &document(&"x".repeat(129), None));
    assert!(matches!(
        file_composition::resolve(
            "ordinary.3md",
            &[oversized],
            &graph_limits(),
            &child_limits,
            &options()
        ),
        Err(Error::Storage(DocumentStorageError::OversizedRecord))
    ));
}

#[test]
fn unreachable_content_is_ignored_but_every_supplied_path_is_validated() {
    let root = source("root.3md", &document("Root", None));
    let result = resolve(
        "root.3md",
        &[
            root.clone(),
            DocumentFileSource {
                path: "unused.3md".into(),
                data: vec![0xff],
            },
        ],
    )
    .unwrap();
    assert_eq!(result.resolved_paths, ["root.3md"]);
    assert_eq!(result.composition.entries().len(), 1);
    assert!(matches!(
        resolve(
            "root.3md",
            &[
                root.clone(),
                DocumentFileSource {
                    path: "../invalid".into(),
                    data: vec![]
                }
            ]
        ),
        Err(Error::InvalidPath(_))
    ));
    assert!(matches!(
        resolve(
            "root.3md",
            &[
                root.clone(),
                source("é.3md", &document("One", None)),
                source("e\u{301}.3md", &document("Two", None))
            ]
        ),
        Err(Error::DuplicatePath(_))
    ));
    assert!(matches!(
        resolve(
            "root.3md",
            &[root.clone(), source("./root.3md", &document("Two", None))]
        ),
        Err(Error::DuplicatePath(_))
    ));
    assert!(matches!(
        resolve("Root.3md", &[root]),
        Err(Error::MissingFile(_))
    ));
}

#[test]
fn ledger_is_strict_json_with_ascii_glyph_validation_before_duplicate_checks() {
    let values = file_composition::ledger(
        &document("", Some(r#"{"~":"\ud83d\ude00.3md","!":"a\"b.3md"}"#)),
        &options(),
    )
    .unwrap();
    assert_eq!(values[0].glyph, "!");
    assert_eq!(values[0].source, "a\"b.3md");
    assert_eq!(values[1].source, "😀.3md");
    assert!(file_composition::ledger(&document("", None), &options())
        .unwrap()
        .is_empty());
    for invalid in [
        r#"{"1":"a","\u0031":"b"}"#,
        "[]",
        r#"{"1":3}"#,
        r#"{"1":"a",}"#,
        r#"{"1":"a"} false"#,
        r#"{"1":"\ud800"}"#,
        r#"{"1":"\udc00"}"#,
        r#"{"1":"\q"}"#,
        "{\"1\":\"a\nb\"}",
        "{\"1\":\"a\u{01}b\"}",
        "{\"1\":\"a\tb\"}",
    ] {
        assert!(
            matches!(
                file_composition::ledger(&document("", Some(invalid)), &options()),
                Err(Error::InvalidLedger(_))
            ),
            "{invalid}"
        );
    }
    for invalid in [
        r#"{"":"a"}"#,
        r#"{" ":"a"}"#,
        r#"{"é":"a"}"#,
        r#"{"e\u0301":"a","é":"b"}"#,
        r#"{"ab":"a"}"#,
        r#"{"\u007f":"a"}"#,
    ] {
        assert!(
            matches!(
                file_composition::ledger(&document("", Some(invalid)), &options()),
                Err(Error::InvalidGlyph(_))
            ),
            "{invalid}"
        );
    }
}

#[test]
fn project_paths_have_explicit_rules_and_bounded_standalone_work() {
    assert_eq!(
        file_composition::resolve_path("../models/./e\u{301}.data", "scenes/root.3md", &options())
            .unwrap(),
        "models/é.data"
    );
    assert_eq!(
        file_composition::resolve_path("x%2Fy", "./root", &options()).unwrap(),
        "x%2Fy"
    );
    for invalid in [
        "", "/a", "//a", "a//b", "a/", "a\\b", "a:b", "a\n", "../a", ".", "x/..",
    ] {
        assert!(
            matches!(
                file_composition::resolve_path(invalid, "root", &options()),
                Err(Error::InvalidPath(_))
            ),
            "{invalid:?}"
        );
    }
    let large = "a".repeat(8 * 1024 * 1024 + 1);
    assert_eq!(
        file_composition::resolve_path(&large, "root", &options()).unwrap(),
        large
    );
    let mut value = document("", None);
    value
        .metadata
        .insert("3md-files".into(), format!(r#"{{"1":"{large}"}}"#));
    let ledger = file_composition::ledger(&value, &options()).unwrap();
    assert_eq!(ledger[0].source, large);
}

#[test]
fn missing_files_and_file_cycles_include_ledgers_in_unused_bundle_entries() {
    let root = source("root", &document("Root", Some(r#"{"1":"missing"}"#)));
    assert!(matches!(resolve("root", &[root]), Err(Error::MissingFile(path)) if path == "missing"));
    let competing = source(
        "root",
        &document("Root", Some(r#"{"a":"missing","b":"/invalid"}"#)),
    );
    assert!(
        matches!(resolve("root", &[competing]), Err(Error::MissingFile(path)) if path == "missing")
    );
    let cycle = vec![
        source("a", &document("A", Some(r#"{"1":"b"}"#))),
        source("b", &document("B", Some(r#"{"1":"a"}"#))),
    ];
    assert!(matches!(
        resolve("a", &cycle),
        Err(Error::Composition(DocumentCompositionError::Cycle(_)))
    ));
    let bundle = graph(vec![
        entry("root", document("Root", None), vec![]),
        entry(
            "unused",
            document("Unused", Some(r#"{"1":"bundle"}"#)),
            vec![],
        ),
    ]);
    assert!(matches!(
        resolve("bundle", &[graph_source("bundle", &bundle, false)]),
        Err(Error::Composition(DocumentCompositionError::Cycle(_)))
    ));
}

#[test]
fn supplied_and_resolved_policies_are_checked_before_returning_a_bundle() {
    let root = source("root", &document("Root", None));
    let mut policy = graph_limits();
    policy.maximum_definitions = 1;
    assert!(matches!(
        file_composition::resolve(
            "root",
            &[
                root.clone(),
                DocumentFileSource {
                    path: "/bad".into(),
                    data: vec![]
                }
            ],
            &policy,
            &limits(),
            &options()
        ),
        Err(Error::InputLimit)
    ));
    policy = graph_limits();
    policy.maximum_profile_bytes = 3;
    assert!(matches!(
        file_composition::resolve(
            "root",
            std::slice::from_ref(&root),
            &policy,
            &limits(),
            &options()
        ),
        Err(Error::InputLimit)
    ));
    policy.maximum_profile_bytes = root.data.len() - 1;
    assert!(matches!(
        file_composition::resolve(
            "root",
            std::slice::from_ref(&root),
            &policy,
            &limits(),
            &options()
        ),
        Err(Error::InputLimit)
    ));
    policy.maximum_profile_bytes = root.data.len() + 1;
    assert!(matches!(
        file_composition::resolve(
            "root",
            std::slice::from_ref(&root),
            &policy,
            &limits(),
            &options()
        ),
        Err(Error::Composition(
            DocumentCompositionError::ProfileBytesExceeded
        ))
    ));
    let bundle = graph(vec![
        entry("root", document("Root", None), vec![]),
        entry("unused", document("Unused", None), vec![]),
    ]);
    policy = graph_limits();
    policy.maximum_definitions = 1;
    assert!(matches!(
        file_composition::resolve(
            "bundle",
            &[graph_source("bundle", &bundle, false)],
            &policy,
            &limits(),
            &options()
        ),
        Err(Error::Composition(
            DocumentCompositionError::TooManyDefinitions
        ))
    ));
    let sources = vec![
        source(
            "root",
            &document("Root", Some(r#"{"1":"child","2":"child"}"#)),
        ),
        source("child", &document("Child", None)),
    ];
    policy = graph_limits();
    policy.maximum_references = 1;
    assert!(matches!(
        file_composition::resolve("root", &sources, &policy, &limits(), &options()),
        Err(Error::Composition(
            DocumentCompositionError::TooManyReferences
        ))
    ));
    policy = graph_limits();
    policy.maximum_reference_attributes = 1;
    assert!(matches!(
        file_composition::resolve("root", &sources, &policy, &limits(), &options()),
        Err(Error::Composition(
            DocumentCompositionError::ReferenceAttributesExceeded
        ))
    ));
    policy = graph_limits();
    policy.maximum_traversal_occurrences = 2;
    assert!(matches!(
        file_composition::resolve("root", &sources, &policy, &limits(), &options()),
        Err(Error::Composition(
            DocumentCompositionError::TraversalOccurrencesExceeded
        ))
    ));
}

#[test]
fn final_depth_checks_include_cached_dependencies_and_cancelled_operations_are_atomic() {
    let sources = vec![
        source("root", &document("Root", Some(r#"{"1":"a","2":"b"}"#))),
        source("a", &document("A", None)),
        source("b", &document("B", Some(r#"{"1":"a"}"#))),
    ];
    let mut policy = graph_limits();
    policy.maximum_depth = 2;
    assert!(matches!(
        file_composition::resolve("root", &sources, &policy, &limits(), &options()),
        Err(Error::Composition(DocumentCompositionError::DepthExceeded))
    ));
    policy.maximum_depth = 3;
    assert!(file_composition::resolve("root", &sources, &policy, &limits(), &options()).is_ok());
    let token = CancellationToken::new();
    token.cancel();
    let cancelled = OperationOptions::with_cancellation(token);
    for error in [
        file_composition::resolve("root", &sources, &graph_limits(), &limits(), &cancelled)
            .unwrap_err(),
        file_composition::resolve_path("child", "root", &cancelled).unwrap_err(),
        file_composition::ledger(&document("", None), &cancelled).unwrap_err(),
    ] {
        assert_eq!(error.code(), "cancelled");
        assert!(matches!(
            error,
            Error::Storage(DocumentStorageError::Cancelled)
        ));
    }
    assert_eq!(
        resolve("root", &sources)
            .unwrap()
            .composition
            .entries()
            .len(),
        3
    );
}

#[test]
fn outer_recognition_preserves_child_byte_and_line_policy_precedence_over_planes() {
    let value = parse("---\n3md: 1\naxis: space\n---\n@plane z=0\nA\n@plane z=1\nB\n").unwrap();
    // Text and payload kind 1 check lines while decoding text; payload kind 2 checks the
    // plane count at S8, before the line count at L5.
    for (data, planes_before_lines) in [
        (
            storage::encode(&value, DocumentStorageFormat::Text, &limits(), &options()).unwrap(),
            false,
        ),
        (
            storage::encode_text_container(
                &value,
                DocumentCompression::None,
                &limits(),
                &options(),
            )
            .unwrap(),
            false,
        ),
        (
            storage::encode(
                &value,
                DocumentStorageFormat::Binary(DocumentCompression::None),
                &limits(),
                &options(),
            )
            .unwrap(),
            true,
        ),
    ] {
        let input = DocumentFileSource {
            path: "root".into(),
            data,
        };
        let policies = [
            (
                DocumentDecodeLimits {
                    maximum_encoded_bytes: 1,
                    maximum_planes: 1,
                    ..limits()
                },
                DocumentStorageError::OversizedInput,
            ),
            (
                DocumentDecodeLimits {
                    maximum_decoded_bytes: 1,
                    maximum_planes: 1,
                    ..limits()
                },
                DocumentStorageError::OversizedOutput,
            ),
            (
                DocumentDecodeLimits {
                    maximum_lines: 1,
                    maximum_planes: 1,
                    ..limits()
                },
                if planes_before_lines {
                    DocumentStorageError::TooManyPlanes
                } else {
                    DocumentStorageError::TooManyLines
                },
            ),
        ];
        for (policy, expected) in policies {
            let error = file_composition::resolve(
                "root",
                std::slice::from_ref(&input),
                &graph_limits(),
                &policy,
                &options(),
            )
            .unwrap_err();
            assert_eq!(error, Error::Storage(expected));
        }
    }
}

#[test]
fn disconnected_embedded_ledgers_use_actual_entry_depth_and_repeated_cached_files() {
    let embedded = graph(vec![
        entry("root", document("Root", None), vec![]),
        entry("unused", document("Unused", Some(r#"{"1":"x"}"#)), vec![]),
    ]);
    let sources = vec![
        source(
            "root",
            &document("Parent", Some(r#"{"1":"bundle","2":"bundle"}"#)),
        ),
        graph_source("bundle", &embedded, false),
        source("x", &document("Child", None)),
    ];
    let mut policy = graph_limits();
    policy.maximum_depth = 2;
    let result =
        file_composition::resolve("root", &sources, &policy, &limits(), &options()).unwrap();
    assert_eq!(result.resolved_paths, ["bundle", "root", "x"]);
    assert_eq!(result.composition.entries().len(), 4);
    assert_eq!(
        result
            .composition
            .root_entry()
            .references
            .iter()
            .map(|value| value.target_id.as_str())
            .collect::<Vec<_>>(),
        ["file-000000", "file-000000"]
    );
    assert_eq!(
        result.composition.entry("file-000001").unwrap().references[0].target_id,
        "file-000003"
    );
}

#[test]
fn repeated_cached_files_validate_final_depth_and_missing_discovery_precedence() {
    let mut sources = vec![
        source(
            "root",
            &document("Root", Some(r#"{"1":"short","2":"long"}"#)),
        ),
        source("short", &document("Short", Some(r#"{"1":"leaf"}"#))),
        source(
            "long",
            &document("Long", Some(r#"{"1":"short","2":"short"}"#)),
        ),
        source("leaf", &document("Leaf", None)),
    ];
    let mut policy = graph_limits();
    policy.maximum_depth = 3;
    assert!(matches!(
        file_composition::resolve("root", &sources, &policy, &limits(), &options()),
        Err(Error::Composition(DocumentCompositionError::DepthExceeded))
    ));
    policy.maximum_depth = 4;
    let result =
        file_composition::resolve("root", &sources, &policy, &limits(), &options()).unwrap();
    assert_eq!(result.composition.entries().len(), 4);
    assert_eq!(
        result
            .composition
            .entry("file-000001")
            .unwrap()
            .references
            .iter()
            .map(|value| value.target_id.as_str())
            .collect::<Vec<_>>(),
        ["file-000003", "file-000003"]
    );
    sources[2] = source(
        "long",
        &document("Long", Some(r#"{"1":"short","2":"missing"}"#)),
    );
    policy.maximum_depth = 3;
    assert!(
        matches!(file_composition::resolve("root", &sources, &policy, &limits(), &options()), Err(Error::MissingFile(path)) if path == "missing")
    );
}

#[test]
fn fixed_file_discovery_ceiling_bounds_disconnected_chains() {
    let files = |count: usize| -> Vec<DocumentFileSource> {
        (0..count)
            .map(|index| {
                let ledger = format!(r#"{{"1":"f{}"}}"#, index + 1);
                let bundle = graph(vec![
                    entry("root", document("Root", None), vec![]),
                    entry(
                        "unused",
                        document(
                            "Unused",
                            if index + 1 < count {
                                Some(&ledger)
                            } else {
                                None
                            },
                        ),
                        vec![],
                    ),
                ]);
                graph_source(&format!("f{index}"), &bundle, false)
            })
            .collect()
    };
    let mut policy = graph_limits();
    policy.maximum_depth = 2;
    assert_eq!(
        file_composition::resolve("f0", &files(64), &policy, &limits(), &options())
            .unwrap()
            .composition
            .entries()
            .len(),
        128
    );
    assert!(matches!(
        file_composition::resolve("f0", &files(65), &policy, &limits(), &options()),
        Err(Error::Composition(DocumentCompositionError::DepthExceeded))
    ));
}

fn ledger_json(fields: &[(&str, &str)]) -> String {
    let mut map = serde_json::Map::new();
    for (glyph, path) in fields {
        map.insert((*glyph).into(), serde_json::Value::String((*path).into()));
    }
    serde_json::Value::Object(map).to_string()
}
fn composition_source(path: &str, root: &str, entries: Vec<DocumentEntry>) -> DocumentFileSource {
    let value =
        DocumentComposition::new(root.into(), entries, &graph_limits(), &limits(), &options())
            .unwrap();
    graph_source(path, &value, false)
}
fn glyphs() -> Vec<String> {
    (33_u8..=126)
        .map(|byte| char::from(byte).to_string())
        .collect()
}

#[test]
fn owner_directory_resolution_keeps_parent_dot_and_grammar_semantics() {
    for (source, owner, expected) in [
        ("../../x", "a/b/c/owner", "a/x"),
        ("x/..", "a/owner", "a"),
        ("../c", "a/\u{301}b/owner", "a/c"),
        ("./x/./y", "a/./b/owner", "a/b/x/y"),
        ("child", "owner", "child"),
        ("x/../../y", "a/b/owner", "a/y"),
    ] {
        assert_eq!(
            file_composition::resolve_path(source, owner, &options()).unwrap(),
            expected
        );
    }
    for (source, owner) in [
        ("../..", "a/b/owner"),
        ("x/../..", "a/owner"),
        ("..", "owner"),
        ("../../..", "a/b/o"),
    ] {
        assert_eq!(
            file_composition::resolve_path(source, owner, &options()),
            Err(Error::InvalidPath(source.into()))
        );
    }
}

#[test]
fn long_owner_path_with_many_references_resolves_every_reference_in_its_directory() {
    let fields: Vec<(String, &str)> = glyphs()
        .into_iter()
        .map(|glyph| (glyph, "leaf.3md"))
        .collect();
    let borrowed: Vec<(&str, &str)> = fields
        .iter()
        .map(|(glyph, path)| (glyph.as_str(), *path))
        .collect();
    let ledger = ledger_json(&borrowed);
    let mut entries: Vec<DocumentEntry> = (0..3)
        .map(|index| entry(&format!("e{index}"), document("E", Some(&ledger)), vec![]))
        .collect();
    let references = entries
        .iter()
        .map(|value| DocumentReference {
            target_id: value.id.clone(),
            attributes: BTreeMap::new(),
        })
        .collect();
    entries.push(entry("m", document("Main", None), references));
    let owner = format!("owner/{}.3md", "\u{e9}".repeat(200_000));
    let result = resolve(
        &owner,
        &[
            composition_source(&owner, "m", entries),
            source("owner/leaf.3md", &document("Leaf", None)),
        ],
    )
    .unwrap();
    assert_eq!(
        result.resolved_paths,
        vec!["owner/leaf.3md".to_owned(), owner]
    );
    let edges: Vec<_> = result
        .composition
        .entries()
        .iter()
        .flat_map(|value| &value.references)
        .filter(|reference| reference.attributes.contains_key("glyph"))
        .collect();
    assert_eq!(edges.len(), 3 * 94);
    assert!(edges
        .iter()
        .all(|reference| reference.attributes["source-file"] == "owner/leaf.3md"));
}

#[test]
fn refusals_follow_entry_id_then_glyph_discovery_order() {
    assert_eq!(
        resolve(
            "root",
            &[source(
                "root",
                &document("R", Some(r#"{"a":"missing","b":"/x"}"#))
            )]
        ),
        Err(Error::MissingFile("missing".into()))
    );
    assert_eq!(
        resolve(
            "root",
            &[source(
                "root",
                &document("R", Some(r#"{"a":"/x","b":"missing"}"#))
            )]
        ),
        Err(Error::InvalidPath("/x".into()))
    );
    for (first, second, expected) in [
        ("missing", "/x", Error::MissingFile("missing".into())),
        ("/x", "missing", Error::InvalidPath("/x".into())),
    ] {
        let entries = vec![
            entry("m", document("M", None), vec![]),
            entry(
                "a",
                document("A", Some(&ledger_json(&[("z", first)]))),
                vec![],
            ),
            entry(
                "b",
                document("B", Some(&ledger_json(&[("a", second)]))),
                vec![],
            ),
        ];
        assert_eq!(
            resolve("root", &[composition_source("root", "m", entries)]),
            Err(expected)
        );
    }
}

#[test]
fn root_and_unreachable_supplied_paths_use_the_ledger_path_grammar() {
    let leaf = source("root.3md", &document("Leaf", None));
    for path in [
        "/root.3md",
        ".",
        "../root.3md",
        "",
        "a\\b.3md",
        "a:b.3md",
        "a\u{7f}b.3md",
        "a\u{0}b.3md",
    ] {
        assert_eq!(
            resolve(path, std::slice::from_ref(&leaf)),
            Err(Error::InvalidPath(path.into()))
        );
        let unreachable = DocumentFileSource {
            path: path.into(),
            data: leaf.data.clone(),
        };
        assert_eq!(
            resolve("root.3md", &[leaf.clone(), unreachable]),
            Err(Error::InvalidPath(path.into()))
        );
    }
    let percent = resolve(
        "root",
        &[
            source("root", &document("R", Some(r#"{"1":"%2e%2e/leaf"}"#))),
            source("%2e%2e/leaf", &document("Leaf", None)),
        ],
    )
    .unwrap();
    assert_eq!(percent.resolved_paths, ["%2e%2e/leaf", "root"]);
    let distinct = resolve(
        "root",
        &[
            source("root", &document("R", Some(r#"{"1":"Leaf","2":"leaf"}"#))),
            source("Leaf", &document("Upper", None)),
            source("leaf", &document("Lower", None)),
        ],
    )
    .unwrap();
    assert_eq!(distinct.resolved_paths, ["Leaf", "leaf", "root"]);
}

#[test]
fn ledger_escapes_decode_before_path_grammar() {
    let leaf = source("models/leaf", &document("Leaf", None));
    let with = |ledger: &str, extra: &[DocumentFileSource]| {
        let mut sources = vec![source("root", &document("R", Some(ledger)))];
        sources.extend_from_slice(extra);
        resolve("root", &sources)
    };
    let slash = with(
        r#"{"1":"models\/leaf","2":"models/leaf"}"#,
        std::slice::from_ref(&leaf),
    )
    .unwrap();
    assert_eq!(slash.resolved_paths, ["models/leaf", "root"]);
    let root = slash.composition.root_entry();
    assert_eq!(root.references[0].target_id, root.references[1].target_id);
    assert_eq!(
        with(r#"{"1":"models\\leaf"}"#, std::slice::from_ref(&leaf)),
        Err(Error::InvalidPath("models\\leaf".into()))
    );
    assert_eq!(
        with(r#"{"1":"a\u0001b"}"#, &[]),
        Err(Error::InvalidPath("a\u{1}b".into()))
    );
    // The ledger text holds the escape pair itself, exercising the hand-written surrogate decoder.
    let escaped = format!(r#"{{"1":"{0}ud83d{0}ude00"}}"#, '\u{5c}');
    assert!(!escaped.contains('\u{1f600}'));
    let pair = with(&escaped, &[source("\u{1f600}", &document("Emoji", None))]).unwrap();
    assert_eq!(pair.resolved_paths, ["root", "\u{1f600}"]);
    assert!(matches!(
        with(r#"{"\ud800":"leaf"}"#, &[]),
        Err(Error::InvalidLedger(_))
    ));
}

#[test]
fn self_and_alias_cycles_compare_normalized_paths() {
    for ledger in [r#"{"1":"root.3md"}"#, r#"{"1":"./root.3md"}"#] {
        assert_eq!(
            resolve(
                "root.3md",
                &[source("root.3md", &document("R", Some(ledger)))]
            ),
            Err(Error::Composition(DocumentCompositionError::Cycle(
                "root.3md".into()
            )))
        );
    }
    for (child, link) in [
        ("models/child.3md", "../root.3md"),
        ("child.3md", "models/../root.3md"),
    ] {
        assert_eq!(
            resolve(
                "root.3md",
                &[
                    source(
                        "root.3md",
                        &document("R", Some(&ledger_json(&[("1", child)])))
                    ),
                    source(child, &document("C", Some(&ledger_json(&[("1", link)])))),
                ],
            ),
            Err(Error::Composition(DocumentCompositionError::Cycle(
                "root.3md".into()
            )))
        );
    }
}

#[test]
fn cached_subtree_is_charged_at_its_deeper_occurrence_against_the_discovery_ceiling() {
    // `last` is the final file's ledger fields.
    let chain = |prefix: &str, count: usize, last: &[(&str, &str)]| -> Vec<DocumentFileSource> {
        (1..=count)
            .map(|index| {
                let ledger = if index < count {
                    Some(ledger_json(&[("1", &format!("{prefix}{}", index + 1))]))
                } else if last.is_empty() {
                    None
                } else {
                    Some(ledger_json(last))
                };
                composition_source(
                    &format!("{prefix}{index}"),
                    "r",
                    vec![
                        entry("r", document("R", None), vec![]),
                        entry("u", document("U", ledger.as_deref()), vec![]),
                    ],
                )
            })
            .collect()
    };
    let root = source("root", &document("Root", Some(r#"{"1":"a1","2":"b1"}"#)));
    let long = chain("a", 40, &[]);
    let sources = |count, last: &[(&str, &str)]| {
        let mut all = vec![root.clone()];
        all.extend(long.iter().cloned());
        all.extend(chain("b", count, last));
        all
    };
    assert_eq!(
        resolve("root", &sources(24, &[("1", "a1")])),
        Err(Error::Composition(DocumentCompositionError::DepthExceeded))
    );
    // Only the cache-hit height check can refuse before b24's second glyph names a missing file.
    assert_eq!(
        resolve("root", &sources(24, &[("1", "a1"), ("2", "missing")])),
        Err(Error::Composition(DocumentCompositionError::DepthExceeded))
    );
    assert_eq!(
        resolve("root", &sources(23, &[("1", "a1")]))
            .unwrap()
            .composition
            .entries()
            .len(),
        127
    );
}

#[test]
fn existing_edges_precede_ledger_edges_and_embedded_ledgers_resolve_from_their_bundle_folder() {
    let attributes = BTreeMap::from([
        ("glyph".to_owned(), "1".to_owned()),
        ("opaque".to_owned(), "keep".to_owned()),
    ]);
    let group = composition_source(
        "models/group",
        "m",
        vec![
            entry(
                "m",
                document("M", Some(r#"{"2":"leaf"}"#)),
                vec![DocumentReference {
                    target_id: "c".into(),
                    attributes: attributes.clone(),
                }],
            ),
            entry("c", document("Kept", None), vec![]),
        ],
    );
    let result = resolve(
        "root",
        &[
            source("root", &document("R", Some(r#"{"1":"models/group"}"#))),
            group,
            source("models/leaf", &document("Leaf", None)),
        ],
    )
    .unwrap();
    let id = &result.file_root_ids["models/group"];
    let bundled = result.composition.entry(id).unwrap();
    assert_eq!(bundled.references[0].attributes, attributes);
    assert_eq!(
        bundled.references[1].target_id,
        result.file_root_ids["models/leaf"]
    );
    assert_eq!(
        bundled.references[1].attributes["source-file"],
        "models/leaf"
    );
}

#[test]
fn resolver_output_rebundles_with_opaque_glyph_and_source_file_attributes() {
    let first = resolve(
        "root.3md",
        &[
            source("root.3md", &document("R", Some(r#"{"1":"leaf.3md"}"#))),
            source("leaf.3md", &document("Leaf", None)),
        ],
    )
    .unwrap();
    let second = resolve(
        "root.3md",
        &[
            source(
                "root.3md",
                &document("R", Some(r#"{"1":"archive/bundle.3md"}"#)),
            ),
            graph_source("archive/bundle.3md", &first.composition, false),
        ],
    )
    .unwrap();
    assert_eq!(second.resolved_paths, ["archive/bundle.3md", "root.3md"]);
    assert_eq!(second.composition.entries().len(), 3);
    let archived = second
        .composition
        .entry(&second.file_root_ids["archive/bundle.3md"])
        .unwrap();
    assert_eq!(
        archived.references[0].attributes,
        BTreeMap::from([
            ("glyph".to_owned(), "1".to_owned()),
            ("source-file".to_owned(), "leaf.3md".to_owned()),
        ])
    );
}

#[test]
fn source_file_attribute_bound_counts_normalized_utf8_bytes() {
    // glyph (5) + "1" (1) + source-file (11) + path: a 16,367-byte NFC path exactly fills 16,384 bytes.
    let attempt = |padding: usize, policy: &DocumentCompositionLimits| {
        let path = format!("models/{}{}", "e\u{301}".repeat(8_000), "a".repeat(padding));
        let ledger = ledger_json(&[("1", &path)]);
        file_composition::resolve(
            "root",
            &[
                source("root", &document("R", Some(&ledger))),
                source(&path, &document("Leaf", None)),
            ],
            policy,
            &limits(),
            &options(),
        )
    };
    let exact = attempt(360, &graph_limits()).unwrap();
    assert_eq!(
        exact.composition.root_entry().references[0].attributes["source-file"].len(),
        16_367
    );
    assert_eq!(
        attempt(361, &graph_limits()),
        Err(Error::Composition(
            DocumentCompositionError::ReferenceAttributesExceeded
        ))
    );
    let mut lowered = graph_limits();
    lowered.maximum_reference_attribute_bytes = 16_383;
    assert_eq!(
        attempt(360, &lowered),
        Err(Error::Composition(
            DocumentCompositionError::ReferenceAttributesExceeded
        ))
    );
}

#[test]
fn lowered_policy_charges_original_path_bytes_before_grammar_and_rejects_invalid_limits_first() {
    let root = source("/root", &document("R", None));
    let mut policy = graph_limits();
    policy.maximum_profile_bytes = 9;
    assert_eq!(
        file_composition::resolve(
            "/root",
            std::slice::from_ref(&root),
            &policy,
            &limits(),
            &options()
        ),
        Err(Error::InputLimit)
    );
    policy.maximum_profile_bytes = 10;
    assert_eq!(
        file_composition::resolve(
            "/root",
            std::slice::from_ref(&root),
            &policy,
            &limits(),
            &options()
        ),
        Err(Error::InvalidPath("/root".into()))
    );
    policy.maximum_depth = 0;
    assert_eq!(
        file_composition::resolve("/root", &[root], &policy, &limits(), &options())
            .map_err(|error| error.code()),
        Err("invalidLimits")
    );
    let mut attributes = graph_limits();
    attributes.maximum_reference_attributes = 1;
    assert_eq!(
        file_composition::resolve(
            "root",
            &[
                source("root", &document("R", Some(r#"{"1":"leaf"}"#))),
                source("leaf", &document("Leaf", None)),
            ],
            &attributes,
            &limits(),
            &options(),
        ),
        Err(Error::Composition(
            DocumentCompositionError::ReferenceAttributesExceeded
        ))
    );
}

#[test]
fn discovery_ceiling_is_the_standard_maximum_depth() {
    // The ceiling is derived from the default policy, not from a caller's lowered depth.
    assert_eq!(graph_limits().maximum_depth, 64);
    let mut policy = graph_limits();
    policy.maximum_depth = 2;
    let chain: Vec<DocumentFileSource> = (0..64)
        .map(|index| {
            let ledger = (index < 63).then(|| ledger_json(&[("1", &format!("f{}", index + 1))]));
            composition_source(
                &format!("f{index}"),
                "r",
                vec![
                    entry("r", document("R", None), vec![]),
                    entry("u", document("U", ledger.as_deref()), vec![]),
                ],
            )
        })
        .collect();
    assert!(file_composition::resolve("f0", &chain, &policy, &limits(), &options()).is_ok());
}

#[test]
fn cancellation_from_another_thread_during_resolution_returns_no_result() {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::time::Instant;

    // About 16 KB per file, fanned out through ledgers in a composition root.
    let files: usize = 200;
    let body = "abcdefghij".repeat(1_600);
    let mut sources: Vec<DocumentFileSource> = (0..files)
        .map(|index| source(&format!("f/{index}"), &document(&body, None)))
        .collect();
    let glyphs = glyphs();
    let mut entries = Vec::new();
    for group in 0..files.div_ceil(glyphs.len()) {
        let fields: Vec<(String, String)> = glyphs
            .iter()
            .enumerate()
            .filter(|(offset, _)| group * glyphs.len() + offset < files)
            .map(|(offset, glyph)| {
                (
                    glyph.clone(),
                    format!("../f/{}", group * glyphs.len() + offset),
                )
            })
            .collect();
        let borrowed: Vec<(&str, &str)> = fields
            .iter()
            .map(|(glyph, path)| (glyph.as_str(), path.as_str()))
            .collect();
        entries.push(entry(
            &format!("g{group}"),
            document("G", Some(&ledger_json(&borrowed))),
            vec![],
        ));
    }
    let references = entries
        .iter()
        .map(|value| DocumentReference {
            target_id: value.id.clone(),
            attributes: BTreeMap::new(),
        })
        .collect();
    entries.push(entry("root", document("Root", None), references));
    sources.push(composition_source("m/root", "root", entries));

    // The uncancelled duration sets the cancellation delay, so the run cannot finish within it.
    let baseline_start = Instant::now();
    assert_eq!(
        resolve("m/root", &sources).unwrap().resolved_paths.len(),
        files + 1
    );
    let delay = baseline_start.elapsed() / 4;

    let token = CancellationToken::new();
    let started = Arc::new(AtomicBool::new(false));
    let worker = {
        let options = OperationOptions::with_cancellation(token.clone());
        let started = Arc::clone(&started);
        std::thread::spawn(move || {
            started.store(true, Ordering::SeqCst);
            let call_start = Instant::now();
            let result =
                file_composition::resolve("m/root", &sources, &graph_limits(), &limits(), &options);
            (result, call_start)
        })
    };
    while !started.load(Ordering::SeqCst) {
        std::thread::yield_now();
    }
    std::thread::sleep(delay);
    let cancel_at = Instant::now();
    token.cancel();
    let (result, call_start) = worker.join().unwrap();
    assert!(
        matches!(result, Err(Error::Storage(DocumentStorageError::Cancelled))),
        "{result:?}"
    );
    // The call had been running for at least half the delay when cancellation arrived, so this is a
    // mid-run interruption, not a check at entry. A thread descheduled for that long between recording
    // `call_start` and entering the call would defeat the assertion; that residual is accepted.
    assert!(cancel_at > call_start);
    assert!(cancel_at - call_start >= delay / 2);
}

#[test]
fn over_bound_ledger_edge_is_refused_while_resolving_before_later_refusals() {
    // A 40-byte policy leaves 23 bytes for a target after "glyph", the glyph and "source-file".
    let mut tight = graph_limits();
    tight.maximum_reference_attribute_bytes = 40;
    let long = format!("{}.3md", "x".repeat(30));
    let attempt = |root: &str, sources: &[DocumentFileSource]| {
        file_composition::resolve(root, sources, &tight, &limits(), &options())
    };
    let target = source(&long, &document("T", None));
    let over_bound = Err(Error::Composition(
        DocumentCompositionError::ReferenceAttributesExceeded,
    ));
    let ledger = |fields: &[(&str, &str)]| document("R", Some(&ledger_json(fields)));
    assert_eq!(
        attempt(
            "root",
            &[
                source("root", &ledger(&[("a", &long), ("b", "missing")])),
                target.clone()
            ]
        ),
        over_bound
    );
    assert_eq!(
        attempt(
            "root",
            &[
                source("root", &ledger(&[("a", "missing"), ("b", &long)])),
                target.clone()
            ]
        ),
        Err(Error::MissingFile("missing".into()))
    );
    assert_eq!(
        attempt("root", &[source("root", &ledger(&[("1", &long)]))]),
        over_bound
    );
    assert_eq!(
        attempt(
            &long,
            &[source(&long, &ledger(&[("1", &format!("./{long}"))]))]
        ),
        over_bound
    );
    assert_eq!(
        attempt(
            "root",
            &[source("root", &ledger(&[("1", &format!("{long}/"))]))]
        ),
        Err(Error::InvalidPath(format!("{long}/")))
    );
}

#[test]
fn attribute_bound_counts_normalized_directory_prefix_bytes() {
    // Twelve decomposed é become 24 NFC bytes, so "é…/leaf" is 29 bytes and needs a 46-byte policy.
    let directory = "e\u{301}".repeat(12);
    let root = format!("{directory}/root");
    let sources = [
        source(&root, &document("R", Some(r#"{"1":"leaf","2":"../top"}"#))),
        source(&format!("{directory}/leaf"), &document("Leaf", None)),
        source("top", &document("Top", None)),
    ];
    let mut policy = graph_limits();
    policy.maximum_reference_attribute_bytes = 46;
    let result =
        file_composition::resolve(&root, &sources, &policy, &limits(), &options()).unwrap();
    assert_eq!(
        result.composition.root_entry().references[0].attributes["source-file"].len(),
        29
    );
    policy.maximum_reference_attribute_bytes = 45;
    assert_eq!(
        file_composition::resolve(&root, &sources, &policy, &limits(), &options()),
        Err(Error::Composition(
            DocumentCompositionError::ReferenceAttributesExceeded
        ))
    );
}

#[test]
fn long_directory_owners_resolve_repeated_sources_once_and_refuse_over_bound_targets_early() {
    let fields: Vec<(String, &str)> = glyphs()
        .into_iter()
        .map(|glyph| (glyph, "leaf.3md"))
        .collect();
    let borrowed: Vec<(&str, &str)> = fields
        .iter()
        .map(|(glyph, path)| (glyph.as_str(), *path))
        .collect();
    let ledger = ledger_json(&borrowed);
    let owner = |directory: &str, count: usize| {
        let mut entries: Vec<DocumentEntry> = (0..count)
            .map(|index| entry(&format!("e{index}"), document("E", Some(&ledger)), vec![]))
            .collect();
        let references = entries
            .iter()
            .map(|value| DocumentReference {
                target_id: value.id.clone(),
                attributes: BTreeMap::new(),
            })
            .collect();
        entries.push(entry("m", document("Main", None), references));
        vec![
            composition_source(&format!("{directory}/root"), "m", entries),
            source(&format!("{directory}/leaf.3md"), &document("Leaf", None)),
        ]
    };
    let in_bound = "d".repeat(8_000);
    let result = resolve(&format!("{in_bound}/root"), &owner(&in_bound, 3)).unwrap();
    let edges: Vec<_> = result
        .composition
        .entries()
        .iter()
        .flat_map(|value| &value.references)
        .filter(|reference| reference.attributes.contains_key("glyph"))
        .collect();
    assert_eq!(edges.len(), 3 * 94);
    let expected = format!("{in_bound}/leaf.3md");
    assert!(edges
        .iter()
        .all(|reference| reference.attributes["source-file"] == expected));
    let over_bound = "d".repeat(262_144);
    assert_eq!(
        resolve(&format!("{over_bound}/root"), &owner(&over_bound, 170)),
        Err(Error::Composition(
            DocumentCompositionError::ReferenceAttributesExceeded
        ))
    );
}
