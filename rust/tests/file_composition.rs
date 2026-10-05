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
    let binary = storage::encode(
        &external,
        DocumentStorageFormat::Binary(DocumentCompression::None),
        &limits(),
        &options(),
    )
    .unwrap();
    for binary_bundle in [false, true] {
        let sources = vec![
            source(
                "root.3md",
                &document("Parent", Some(r#"{"1":"bundles/child.data"}"#)),
            ),
            graph_source("bundles/child.data", &bundle, binary_bundle),
            DocumentFileSource {
                path: "leaf.3mdb".into(),
                data: binary.clone(),
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
        let binary = graph_source("detached", &result.composition, true).data;
        assert_eq!(
            composition::decode(&binary, &graph_limits(), &limits(), &options()).unwrap(),
            result.composition
        );
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
    let large = "a".repeat(limits().maximum_record_bytes);
    assert!(matches!(
        file_composition::resolve_path(&large, "root", &options()),
        Err(Error::InputLimit)
    ));
    let mut value = document("", None);
    value.metadata.insert(
        "3md-files".into(),
        " ".repeat(limits().maximum_record_bytes + 1),
    );
    assert!(matches!(
        file_composition::ledger(&value, &options()),
        Err(Error::InputLimit)
    ));
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
fn depth_checks_include_cached_dependencies_and_cancelled_operations_are_atomic() {
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
