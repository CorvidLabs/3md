use std::collections::BTreeMap;
use threemd::storage::{
    self, CancellationToken, DocumentDecodeLimits, DocumentStorageError, DocumentStorageFormat,
    OperationOptions,
};
use threemd::{axis, parse, serialize, Document, ParseError};

const FOUNDATION_WHITESPACE: [char; 19] = [
    '\t', ' ', '\u{00a0}', '\u{1680}', '\u{2000}', '\u{2001}', '\u{2002}', '\u{2003}', '\u{2004}',
    '\u{2005}', '\u{2006}', '\u{2007}', '\u{2008}', '\u{2009}', '\u{200a}', '\u{200b}', '\u{202f}',
    '\u{205f}', '\u{3000}',
];

fn decode(source: &str) -> Document {
    storage::decode(
        source.as_bytes(),
        &DocumentDecodeLimits::default(),
        &OperationOptions::default(),
    )
    .unwrap()
}

#[test]
fn raw_and_bounded_parsers_share_foundation_horizontal_whitespace() {
    for whitespace in FOUNDATION_WHITESPACE {
        let source = format!(
            "{whitespace}\n{whitespace}---{whitespace}\n{whitespace}3md{whitespace}:{whitespace}0.1{whitespace}\naxis: {whitespace}FrAmE{whitespace}\n{whitespace}title: {whitespace}Title{whitespace}\n{whitespace}---{whitespace}\n{whitespace}\n@plane z=0 label=\"{whitespace}label{whitespace}\"\n{whitespace}\nBody\n{whitespace}\n"
        );
        let raw = parse(&source).unwrap();
        assert_eq!(raw, decode(&source), "U+{:04X}", u32::from(whitespace));
        assert_eq!(raw.version, "0.1");
        assert_eq!(raw.axis, "frame");
        assert_eq!(raw.title.as_deref(), Some("Title"));
        assert_eq!(raw.planes[0].body, "Body");
        assert_eq!(
            raw.planes[0].label,
            Some(format!("{whitespace}label{whitespace}"))
        );
        assert_eq!(axis(&format!("{whitespace}Time{whitespace}")), "time");
    }
    for excluded in ['\n', '\r', '\u{0085}', '\u{2028}', '\u{2029}', '\u{feff}'] {
        assert_eq!(
            axis(&format!("{excluded}Frame{excluded}")),
            format!("{excluded}frame{excluded}")
        );
    }
    // Directive delimiters remain space/tab only, as the frozen grammar requires.
    let source = "---\n3md: 0.1\n---\n@plane\u{00a0}z=2\nBody\n";
    let raw = parse(source).unwrap();
    assert_eq!(raw, decode(source));
    assert_eq!(raw.planes[0].z, 0.0);
    assert!(raw.planes[0].body.starts_with("@plane\u{00a0}"));
}

#[test]
fn source_unicode_aliases_keep_first_spelling_and_last_value_in_both_parsers() {
    let source = "---\n3md: 0.1\naxis: layer\ne\u{0301}: first\né: last\n---\n@plane z=0 e\u{0301}=first É=last\nBody\n";
    let raw = parse(source).unwrap();
    assert_eq!(raw, decode(source));
    assert_eq!(
        raw.metadata,
        BTreeMap::from([("e\u{0301}".into(), "last".into())])
    );
    assert_eq!(
        raw.planes[0].attributes,
        BTreeMap::from([("e\u{0301}".into(), "last".into())])
    );
    assert_eq!(parse(&serialize(&raw)).unwrap(), raw);

    // An unordered direct BTreeMap cannot identify which Unicode spelling came first.
    let mut ambiguous = raw;
    ambiguous.metadata.insert("é".into(), "other".into());
    assert!(matches!(
        storage::encode(
            &ambiguous,
            DocumentStorageFormat::Text,
            &DocumentDecodeLimits::default(),
            &OperationOptions::default(),
        ),
        Err(DocumentStorageError::InvalidDocument(_))
    ));
}

#[test]
fn legacy_serializer_preserves_quoted_apostrophes_and_boundary_whitespace() {
    let mut document = parse("---\n3md: 0.1\naxis: layer\n---\n@plane z=0\nBody\n").unwrap();
    document.version = "'format'".into();
    document.axis = "'custom'".into();
    for value in [
        "'quoted'",
        "''",
        "\u{00a0}leading",
        "trailing\u{200b}",
        "\u{3000}both\u{1680}",
    ] {
        document.title = Some(value.into());
        document.metadata.insert("value".into(), value.into());
        assert_eq!(parse(&serialize(&document)).unwrap(), document);
    }
    for whitespace in FOUNDATION_WHITESPACE {
        document.version = format!("{whitespace}version{whitespace}");
        document.title = Some(format!("{whitespace}title{whitespace}"));
        assert_eq!(parse(&serialize(&document)).unwrap(), document);
    }
}

#[test]
fn large_unique_plane_sets_and_numeric_duplicate_equality_are_preserved() {
    let mut source = String::from("---\n3md: 0.1\naxis: layer\n---\n");
    for z in 0..40_000 {
        source.push_str(&format!("@plane z={z}\nBody\n"));
    }
    let raw = parse(&source).unwrap();
    assert_eq!(raw.planes.len(), 40_000);
    assert_eq!(raw, decode(&source));
    for numbers in ["0\n@plane z=-0", "1\n@plane z=1.0", "1e3\n@plane z=1000"] {
        let source = format!("---\n3md: 0.1\n---\n@plane z={numbers}\n");
        assert!(matches!(
            parse(&source),
            Err(ParseError::DuplicatePlane { .. })
        ));
        assert!(matches!(
            storage::decode(
                source.as_bytes(),
                &DocumentDecodeLimits::default(),
                &OperationOptions::default(),
            ),
            Err(DocumentStorageError::InvalidText(
                ParseError::DuplicatePlane { .. }
            ))
        ));
    }
}

#[test]
fn bounded_parse_keeps_limits_and_explicit_cancellation() {
    let source = "\u{00a0}---\u{00a0}\n3md: 0.1\n---\n@plane z=0\nBody\n@plane z=1\nBody\n";
    let limits = DocumentDecodeLimits {
        maximum_planes: 1,
        ..Default::default()
    };
    assert_eq!(
        storage::decode(source.as_bytes(), &limits, &OperationOptions::default()).unwrap_err(),
        DocumentStorageError::TooManyPlanes
    );
    let token = CancellationToken::new();
    token.cancel();
    assert_eq!(
        storage::decode(
            source.as_bytes(),
            &DocumentDecodeLimits::default(),
            &OperationOptions::with_cancellation(token)
        )
        .unwrap_err(),
        DocumentStorageError::Cancelled
    );
}
