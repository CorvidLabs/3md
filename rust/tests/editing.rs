use std::collections::BTreeMap;
use threemd::composition::{
    DocumentComposition, DocumentCompositionLimits, DocumentEntry, DocumentReference,
};
use threemd::diagnostics;
use threemd::editing::{
    self, CompositionEdit, CompositionPatch, DocumentCompositionSnapshot, DocumentEdit,
    DocumentEditLimits, DocumentHeader, DocumentPatch, DocumentSnapshot,
};
use threemd::storage::{
    self, CancellationToken, DocumentCompression, DocumentDecodeLimits, DocumentStorageFormat,
    OperationOptions,
};
use threemd::{parse, Document, Plane};

fn options() -> OperationOptions {
    OperationOptions::default()
}
fn document_limits() -> DocumentDecodeLimits {
    DocumentDecodeLimits::default()
}
fn graph_limits() -> DocumentCompositionLimits {
    DocumentCompositionLimits::default()
}
fn edit_limits() -> DocumentEditLimits {
    DocumentEditLimits::default()
}
fn document() -> Document {
    parse("---\n3md: 1.0\naxis: layer\n---\n@plane z=0 3md-id=first id=opaque\nFirst\n@plane z=1 3md-id=second\nSecond\n").unwrap()
}
fn plane(id: &str, z: f64) -> Plane {
    Plane {
        z,
        label: None,
        x: None,
        y: None,
        attributes: BTreeMap::from([("3md-id".into(), id.into())]),
        body: "Inserted".into(),
    }
}
fn reference(id: &str, target: &str) -> DocumentReference {
    DocumentReference {
        target_id: target.into(),
        attributes: BTreeMap::from([("3md-id".into(), id.into())]),
    }
}
fn entry(id: &str, references: Vec<DocumentReference>) -> DocumentEntry {
    DocumentEntry {
        id: id.into(),
        document: document(),
        references,
    }
}
fn snapshot() -> DocumentSnapshot {
    DocumentSnapshot::new(document(), &document_limits(), &options()).unwrap()
}
fn graph_snapshot() -> DocumentCompositionSnapshot {
    let graph = DocumentComposition::new(
        "root".into(),
        vec![
            entry(
                "root",
                vec![reference("left", "leaf"), reference("right", "leaf")],
            ),
            entry("leaf", vec![]),
        ],
        &graph_limits(),
        &document_limits(),
        &options(),
    )
    .unwrap();
    DocumentCompositionSnapshot::new(graph, &graph_limits(), &document_limits(), &options())
        .unwrap()
}
fn apply_doc(operations: Vec<DocumentEdit>) -> DocumentSnapshot {
    let snapshot = snapshot();
    let patch = DocumentPatch {
        expected_revision: snapshot.revision().clone(),
        operations,
    };
    editing::apply_document_patch(
        &patch,
        &snapshot,
        &edit_limits(),
        &document_limits(),
        &options(),
    )
    .unwrap()
}
fn doc_error(operations: Vec<DocumentEdit>) -> threemd::DocumentEditError {
    let snapshot = snapshot();
    let patch = DocumentPatch {
        expected_revision: snapshot.revision().clone(),
        operations,
    };
    editing::apply_document_patch(
        &patch,
        &snapshot,
        &edit_limits(),
        &document_limits(),
        &options(),
    )
    .unwrap_err()
}

#[test]
fn all_document_operations_preserve_source_order_and_header_fields() {
    let result = apply_doc(vec![
        DocumentEdit::Insert {
            plane: plane("third", 3.0),
            at: 1,
        },
        DocumentEdit::Move {
            id: "first".into(),
            to: 2,
        },
        DocumentEdit::Remove {
            id: "second".into(),
        },
        DocumentEdit::Replace {
            id: "third".into(),
            plane: plane("third", -1.0),
        },
    ]);
    assert_eq!(
        result
            .document()
            .planes
            .iter()
            .map(Plane::stable_id)
            .collect::<Vec<_>>(),
        [Some("third"), Some("first")]
    );
    assert_eq!(result.document().planes[1].attributes["id"], "opaque");
    let mut header = DocumentHeader::from(&document());
    header.title = Some("Retitled 🐦".into());
    let result = apply_doc(vec![DocumentEdit::ReplaceHeader(header)]);
    assert_eq!(result.document().title.as_deref(), Some("Retitled 🐦"));
    assert_eq!(result.document().planes, document().planes);
}

#[test]
fn document_operation_failures_are_structured_and_do_not_mutate_input() {
    let mut missing_id = plane("third", 3.0);
    missing_id.attributes.clear();
    for (operation, expected) in [
        (
            DocumentEdit::Insert {
                plane: plane("third", 3.0),
                at: -1,
            },
            "invalidIndex",
        ),
        (
            DocumentEdit::Insert {
                plane: missing_id,
                at: 2,
            },
            "missingIdentity",
        ),
        (
            DocumentEdit::Insert {
                plane: plane("first", 3.0),
                at: 2,
            },
            "duplicateIdentity",
        ),
        (
            DocumentEdit::Remove {
                id: "../first".into(),
            },
            "invalidIdentity",
        ),
        (
            DocumentEdit::Remove {
                id: "missing".into(),
            },
            "missingTarget",
        ),
        (
            DocumentEdit::Replace {
                id: "first".into(),
                plane: plane("different", 0.0),
            },
            "identityChanged",
        ),
        (
            DocumentEdit::Move {
                id: "first".into(),
                to: 2,
            },
            "invalidIndex",
        ),
    ] {
        let error = doc_error(vec![operation]);
        assert_eq!(error.code(), expected);
        assert_eq!(
            error.diagnostic().unwrap().path.as_deref(),
            Some("operations[0]")
        );
    }
    let input = snapshot();
    let original = input.clone();
    let patch = DocumentPatch {
        expected_revision: input.revision().clone(),
        operations: vec![
            DocumentEdit::Remove { id: "first".into() },
            DocumentEdit::Remove {
                id: "missing".into(),
            },
        ],
    };
    assert_eq!(
        editing::apply_document_patch(
            &patch,
            &input,
            &edit_limits(),
            &document_limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "missingTarget"
    );
    assert_eq!(input, original);
}

#[test]
fn identity_adoption_is_explicit_and_scoped() {
    let mut input = document();
    input.planes[0]
        .attributes
        .insert("3md-id".into(), "plane-1".into());
    input.planes[1].attributes.remove("3md-id");
    let adopted = editing::adopt_document(&input, &document_limits(), &options()).unwrap();
    assert_eq!(adopted.planes[0].stable_id(), Some("plane-1"));
    assert_eq!(adopted.planes[1].stable_id(), Some("plane-2"));
    assert_eq!(adopted.planes[0].attributes["id"], "opaque");
    assert_eq!(
        editing::adopt_document(&adopted, &document_limits(), &options()).unwrap(),
        adopted
    );
    let mut duplicate = input.clone();
    duplicate.planes[1]
        .attributes
        .insert("3md-id".into(), "plane-1".into());
    assert_eq!(
        editing::adopt_document(&duplicate, &document_limits(), &options())
            .unwrap_err()
            .code(),
        "duplicateIdentity"
    );
    let root = entry("root", vec![reference("same", "leaf")]);
    let owner = entry("owner", vec![reference("same", "leaf")]);
    let composition = DocumentComposition::new(
        "root".into(),
        vec![root, owner, entry("leaf", vec![])],
        &graph_limits(),
        &document_limits(),
        &options(),
    )
    .unwrap();
    assert!(DocumentCompositionSnapshot::new(
        composition,
        &graph_limits(),
        &document_limits(),
        &options()
    )
    .is_ok());
}

#[test]
fn all_composition_operations_validate_the_final_graph_atomically() {
    let snapshot = graph_snapshot();
    let patch = CompositionPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![
            CompositionEdit::InsertEntry(entry("new", vec![])),
            CompositionEdit::InsertReference {
                owner_id: "root".into(),
                reference: reference("middle", "new"),
                at: 1,
            },
            CompositionEdit::MoveReference {
                owner_id: "root".into(),
                id: "right".into(),
                to: 0,
            },
            CompositionEdit::ReplaceReference {
                owner_id: "root".into(),
                id: "left".into(),
                reference: reference("left", "new"),
            },
            CompositionEdit::RemoveReference {
                owner_id: "root".into(),
                id: "right".into(),
            },
            CompositionEdit::ReplaceEntry {
                id: "new".into(),
                entry: entry("new", vec![]),
            },
            CompositionEdit::RemoveEntry { id: "leaf".into() },
            CompositionEdit::SelectRoot { id: "new".into() },
        ],
    };
    let result = editing::apply_composition_patch(
        &patch,
        &snapshot,
        &edit_limits(),
        &graph_limits(),
        &document_limits(),
        &options(),
    )
    .unwrap();
    assert_eq!(result.composition().root_id(), "new");
    assert!(result.composition().entry("leaf").is_none());
    assert_eq!(
        result
            .composition()
            .entry("root")
            .unwrap()
            .references
            .iter()
            .map(DocumentReference::stable_id)
            .collect::<Vec<_>>(),
        [Some("left"), Some("middle")]
    );
    assert!(snapshot.composition().entry("leaf").is_some());
    let patch = CompositionPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![
            CompositionEdit::ReplaceReference {
                owner_id: "root".into(),
                id: "left".into(),
                reference: reference("left", "future"),
            },
            CompositionEdit::InsertEntry(entry("future", vec![])),
        ],
    };
    assert!(editing::apply_composition_patch(
        &patch,
        &snapshot,
        &edit_limits(),
        &graph_limits(),
        &document_limits(),
        &options()
    )
    .is_ok());
}

#[test]
fn graph_failures_validate_counts_identity_and_reference_existence() {
    let snapshot = graph_snapshot();
    for (operation, expected) in [
        (
            CompositionEdit::InsertEntry(entry("leaf", vec![])),
            "duplicateIdentity",
        ),
        (
            CompositionEdit::ReplaceEntry {
                id: "leaf".into(),
                entry: entry("new", vec![]),
            },
            "identityChanged",
        ),
        (
            CompositionEdit::InsertReference {
                owner_id: "root".into(),
                reference: reference("left", "leaf"),
                at: 1,
            },
            "duplicateIdentity",
        ),
        (
            CompositionEdit::InsertReference {
                owner_id: "root".into(),
                reference: DocumentReference {
                    target_id: "leaf".into(),
                    attributes: BTreeMap::new(),
                },
                at: 1,
            },
            "missingIdentity",
        ),
        (
            CompositionEdit::InsertReference {
                owner_id: "root".into(),
                reference: reference("new", "leaf"),
                at: -1,
            },
            "invalidIndex",
        ),
        (
            CompositionEdit::MoveReference {
                owner_id: "root".into(),
                id: "left".into(),
                to: 2,
            },
            "invalidIndex",
        ),
        (
            CompositionEdit::ReplaceReference {
                owner_id: "root".into(),
                id: "left".into(),
                reference: reference("changed", "leaf"),
            },
            "identityChanged",
        ),
        (
            CompositionEdit::RemoveReference {
                owner_id: "leaf".into(),
                id: "left".into(),
            },
            "missingTarget",
        ),
    ] {
        let patch = CompositionPatch {
            expected_revision: snapshot.revision().clone(),
            operations: vec![operation],
        };
        let error = editing::apply_composition_patch(
            &patch,
            &snapshot,
            &edit_limits(),
            &graph_limits(),
            &document_limits(),
            &options(),
        )
        .unwrap_err();
        assert_eq!(error.code(), expected);
        assert_eq!(
            error.diagnostic().unwrap().path.as_deref(),
            Some("operations[0]")
        );
    }
    let patch = CompositionPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![CompositionEdit::RemoveEntry { id: "leaf".into() }],
    };
    let error = editing::apply_composition_patch(
        &patch,
        &snapshot,
        &edit_limits(),
        &graph_limits(),
        &document_limits(),
        &options(),
    )
    .unwrap_err();
    assert_eq!(error.code(), "invalidComposition");
    assert_eq!(
        error.diagnostic().unwrap().path.as_deref(),
        Some("entries[0].references[0].targetID")
    );
    let patch = CompositionPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![CompositionEdit::InsertReference {
            owner_id: "root".into(),
            reference: reference("new", "leaf"),
            at: 0,
        }],
    };
    let error = editing::apply_composition_patch(
        &patch,
        &snapshot,
        &edit_limits(),
        &DocumentCompositionLimits {
            maximum_references: 2,
            ..graph_limits()
        },
        &document_limits(),
        &options(),
    )
    .unwrap_err();
    assert_eq!(error.code(), "payloadLimit");
}

#[test]
fn operation_payload_and_final_document_policies_are_enforced() {
    let snapshot = snapshot();
    let patch = DocumentPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![DocumentEdit::Remove { id: "first".into() }],
    };
    for (policy, code) in [
        (
            DocumentEditLimits {
                maximum_operations: 0,
                ..edit_limits()
            },
            "operationLimit",
        ),
        (
            DocumentEditLimits {
                maximum_payload_bytes: 1,
                ..edit_limits()
            },
            "payloadLimit",
        ),
        (
            DocumentEditLimits {
                maximum_diagnostics: 0,
                ..edit_limits()
            },
            "invalidLimits",
        ),
    ] {
        assert_eq!(
            editing::apply_document_patch(
                &patch,
                &snapshot,
                &policy,
                &document_limits(),
                &options()
            )
            .unwrap_err()
            .code(),
            code
        );
    }
    let patch = DocumentPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![DocumentEdit::Insert {
            plane: plane("third", 3.0),
            at: 2,
        }],
    };
    assert_eq!(
        editing::apply_document_patch(
            &patch,
            &snapshot,
            &edit_limits(),
            &DocumentDecodeLimits {
                maximum_planes: 2,
                ..document_limits()
            },
            &options()
        )
        .unwrap_err()
        .code(),
        "payloadLimit"
    );
    let patch = DocumentPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![DocumentEdit::Replace {
            id: "first".into(),
            plane: plane("first", f64::NAN),
        }],
    };
    assert_eq!(
        editing::apply_document_patch(
            &patch,
            &snapshot,
            &edit_limits(),
            &document_limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "invalidDocument"
    );
    let patch = DocumentPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![
            DocumentEdit::Replace {
                id: "first".into(),
                plane: plane("first", f64::NAN),
            },
            DocumentEdit::Replace {
                id: "second".into(),
                plane: plane("second", f64::NAN),
            },
        ],
    };
    assert_eq!(
        editing::apply_document_patch(
            &patch,
            &snapshot,
            &edit_limits(),
            &document_limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "invalidDocument"
    );
}

#[test]
fn graph_revision_roundtrip_diagnostics_and_cancellation() {
    let snapshot = graph_snapshot();
    let profile = threemd::composition::document(
        snapshot.composition(),
        &graph_limits(),
        &document_limits(),
        &options(),
    )
    .unwrap();
    let binary = storage::encode(
        &profile,
        DocumentStorageFormat::Binary(DocumentCompression::None),
        &document_limits(),
        &options(),
    )
    .unwrap();
    let reopened =
        threemd::composition::decode(&binary, &graph_limits(), &document_limits(), &options())
            .unwrap();
    assert_eq!(
        DocumentCompositionSnapshot::new(reopened, &graph_limits(), &document_limits(), &options())
            .unwrap(),
        snapshot
    );
    assert!(diagnostics::inspect_composition(
        snapshot.composition(),
        &edit_limits(),
        &graph_limits(),
        &document_limits(),
        &options()
    )
    .unwrap()
    .diagnostics
    .is_empty());
    let token = CancellationToken::new();
    token.cancel();
    let cancelled = OperationOptions::with_cancellation(token);
    let patch = CompositionPatch {
        expected_revision: snapshot.revision().clone(),
        operations: vec![],
    };
    assert_eq!(
        editing::apply_composition_patch(
            &patch,
            &snapshot,
            &edit_limits(),
            &graph_limits(),
            &document_limits(),
            &cancelled
        )
        .unwrap_err()
        .code(),
        "cancelled"
    );
    assert_eq!(
        diagnostics::inspect_composition(
            snapshot.composition(),
            &edit_limits(),
            &graph_limits(),
            &document_limits(),
            &cancelled
        )
        .unwrap_err()
        .code(),
        "cancelled"
    );
    assert_eq!(
        editing::adopt_composition(
            snapshot.composition(),
            &graph_limits(),
            &document_limits(),
            &cancelled
        )
        .unwrap_err()
        .code(),
        "cancelled"
    );
}

#[test]
fn direct_btree_maps_reject_ambiguous_canonically_equivalent_keys() {
    let mut document = document();
    document.metadata = BTreeMap::from([
        ("e\u{301}".into(), "first".into()),
        ("é".into(), "second".into()),
    ]);
    assert_eq!(
        storage::validate(&document, &document_limits(), &options())
            .unwrap_err()
            .code(),
        "invalidDocument"
    );
    let mut root = entry("root", vec![reference("left", "leaf")]);
    root.references[0].attributes = BTreeMap::from([
        ("e\u{301}".into(), "first".into()),
        ("é".into(), "second".into()),
    ]);
    assert_eq!(
        DocumentComposition::new(
            "root".into(),
            vec![root, entry("leaf", vec![])],
            &graph_limits(),
            &document_limits(),
            &options()
        )
        .unwrap_err()
        .code(),
        "invalidDocument"
    );
}
