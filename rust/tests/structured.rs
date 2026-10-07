//! Payload kind 2 (SPEC.md 11.3): goldens, the shared vectors, the unit checklist of the
//! ThreeMD 2.1 test plan (sections 1 to 5), seeded property tests, cancellation and
//! thread safety.
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use threemd::composition::{self, DocumentCompositionLimits};
use threemd::storage::{
    self, CancellationToken, DocumentCompression, DocumentContainerInfo, DocumentDecodeLimits,
    DocumentStorageError, DocumentStorageFormat, OperationOptions,
};
use threemd::{Document, Plane};

// MARK: - Helpers

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("..")
}
fn read(path: &str) -> Vec<u8> {
    fs::read(root().join(path)).unwrap_or_else(|error| panic!("{path}: {error}"))
}
fn json(path: &str) -> Value {
    serde_json::from_slice(&read(path)).unwrap()
}
fn options() -> OperationOptions {
    OperationOptions::default()
}
fn limits() -> DocumentDecodeLimits {
    DocumentDecodeLimits::default()
}
fn graph_limits() -> DocumentCompositionLimits {
    DocumentCompositionLimits::default()
}
/// The limits composition decode applies to a profile envelope.
fn profile_limits() -> DocumentDecodeLimits {
    let bytes = graph_limits().maximum_profile_bytes;
    DocumentDecodeLimits {
        maximum_encoded_bytes: bytes,
        maximum_decoded_bytes: bytes,
        maximum_planes: 1,
        maximum_record_bytes: bytes,
        ..limits()
    }
}
fn decode(data: &[u8]) -> Result<Document, DocumentStorageError> {
    storage::decode(data, &limits(), &options())
}
fn decode_with(
    data: &[u8],
    limits: &DocumentDecodeLimits,
) -> Result<Document, DocumentStorageError> {
    storage::decode(data, limits, &options())
}
fn binary(document: &Document) -> Result<Vec<u8>, DocumentStorageError> {
    binary_with(document, &limits())
}
fn binary_with(
    document: &Document,
    limits: &DocumentDecodeLimits,
) -> Result<Vec<u8>, DocumentStorageError> {
    storage::encode(
        document,
        DocumentStorageFormat::Binary(DocumentCompression::None),
        limits,
        &options(),
    )
}
fn text(document: &Document) -> Result<Vec<u8>, DocumentStorageError> {
    storage::encode(document, DocumentStorageFormat::Text, &limits(), &options())
}
fn code<Value>(result: &Result<Value, DocumentStorageError>) -> &'static str {
    match result {
        Ok(_) => "ok",
        Err(error) => error.code(),
    }
}
/// Rust `==` plus the bit patterns of every coordinate.
fn assert_same(actual: &Document, expected: &Document, context: &str) {
    assert_eq!(actual, expected, "{context}");
    for (left, right) in actual.planes.iter().zip(&expected.planes) {
        assert_eq!(left.z.to_bits(), right.z.to_bits(), "{context}");
        assert_eq!(
            left.x.map(f64::to_bits),
            right.x.map(f64::to_bits),
            "{context}"
        );
        assert_eq!(
            left.y.map(f64::to_bits),
            right.y.map(f64::to_bits),
            "{context}"
        );
    }
}
fn header(bytes: &[u8]) -> DocumentContainerInfo {
    storage::container_info(bytes).unwrap().unwrap()
}
/// Recomputes lengths and CRC after editing a container.
fn reseal(mut file: Vec<u8>) -> Vec<u8> {
    let length = (file.len() - 40) as u64;
    file[20..28].copy_from_slice(&length.to_le_bytes());
    file[28..36].copy_from_slice(&length.to_le_bytes());
    let mut data = file[..36].to_vec();
    data.extend_from_slice(&file[40..]);
    let crc = crc32(&data);
    file[36..40].copy_from_slice(&crc.to_le_bytes());
    file
}
/// A bytewise table CRC-32/ISO-HDLC reference, independent of the library's slicing loop.
fn crc32(data: &[u8]) -> u32 {
    static TABLE: std::sync::OnceLock<[u32; 256]> = std::sync::OnceLock::new();
    let table = TABLE.get_or_init(|| {
        std::array::from_fn(|index| {
            (0..8).fold(index as u32, |crc, _| {
                (crc >> 1) ^ (0xEDB8_8320 & 0_u32.wrapping_sub(crc & 1))
            })
        })
    });
    !data.iter().fold(u32::MAX, |crc, &byte| {
        (crc >> 8) ^ table[((crc ^ u32::from(byte)) & 0xff) as usize]
    })
}
/// A kind-2 file around a raw payload.
fn container(payload: &[u8]) -> Vec<u8> {
    let mut file = b"3mdbin\r\n\x01\x00\x02\x00".to_vec();
    file.resize(40, 0);
    file.extend_from_slice(payload);
    reseal(file)
}
fn plane(z: f64, body: &str) -> Plane {
    Plane {
        z,
        label: None,
        x: None,
        y: None,
        attributes: BTreeMap::new(),
        body: body.into(),
    }
}
fn document(planes: Vec<Plane>) -> Document {
    Document {
        version: "1".into(),
        axis: String::new(),
        title: None,
        metadata: BTreeMap::new(),
        preamble: None,
        planes,
    }
}
fn map(entries: &[(&str, &str)]) -> BTreeMap<String, String> {
    entries
        .iter()
        .map(|(key, value)| ((*key).into(), (*value).into()))
        .collect()
}

/// FIPS 180-4 SHA-256, for the manifest digests (the crate adds no dependency).
fn sha256(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut state: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    let mut message = data.to_vec();
    message.push(0x80);
    while message.len() % 64 != 56 {
        message.push(0);
    }
    message.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    let (blocks, _) = message.as_chunks::<64>();
    for block in blocks {
        let mut w = [0_u32; 64];
        let (words, _) = block.as_chunks::<4>();
        for (index, word) in words.iter().enumerate() {
            w[index] = u32::from_be_bytes(*word);
        }
        for index in 16..64 {
            let s0 = w[index - 15].rotate_right(7)
                ^ w[index - 15].rotate_right(18)
                ^ (w[index - 15] >> 3);
            let s1 = w[index - 2].rotate_right(17)
                ^ w[index - 2].rotate_right(19)
                ^ (w[index - 2] >> 10);
            w[index] = w[index - 16]
                .wrapping_add(s0)
                .wrapping_add(w[index - 7])
                .wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = state;
        for index in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let choice = (e & f) ^ (!e & g);
            let t1 = h
                .wrapping_add(s1)
                .wrapping_add(choice)
                .wrapping_add(K[index])
                .wrapping_add(w[index]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let majority = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(majority);
            h = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        for (slot, value) in state.iter_mut().zip([a, b, c, d, e, f, g, h]) {
            *slot = slot.wrapping_add(value);
        }
    }
    state.iter().map(|word| format!("{word:08x}")).collect()
}

// MARK: - Worked examples (SPEC.md 11.3.17)

fn worked(name: &str) -> Document {
    match name {
        "document" => Document {
            version: "1.0".into(),
            axis: "time".into(),
            title: Some("Week".into()),
            metadata: map(&[("owner", "ops")]),
            preamble: None,
            planes: vec![
                Plane {
                    label: Some("Mon".into()),
                    ..plane(0.0, "# Standup")
                },
                Plane {
                    label: Some("Tue".into()),
                    x: Some(-2.0),
                    attributes: map(&[("kind", "note")]),
                    ..plane(1.5, "Ship it")
                },
            ],
        },
        "numbers" => Document {
            version: "1.0".into(),
            axis: "layer".into(),
            planes: vec![Plane {
                x: Some(0.5),
                y: Some(268_435_456.0),
                attributes: map(&[("note", "say \"hi\"")]),
                ..plane(0.1, "")
            }],
            ..document(vec![])
        },
        "keys" => Document {
            metadata: map(&[("z", "1"), ("e\u{301}", "2")]),
            planes: vec![Plane {
                attributes: map(&[("b", "x"), ("a", "y")]),
                ..plane(-3.0, "")
            }],
            ..document(vec![])
        },
        other => panic!("unknown worked example {other}"),
    }
}

// MARK: - Goldens (test plan section 1)

#[test]
fn every_golden_is_reproduced_byte_for_byte_and_decodes_to_the_text_decode() {
    let manifest = json("conformance/structured/manifest.json");
    assert_eq!(manifest["schema"], "3md-structured-golden-1");
    let files = manifest["files"].as_array().unwrap();
    assert_eq!(files.len(), 54);
    let mut composition_count = 0;
    for entry in files {
        let id = entry["id"].as_str().unwrap();
        let file = read(entry["kind2File"].as_str().unwrap());
        assert_eq!(file.len() as u64, entry["bytes"].as_u64().unwrap(), "{id}");
        assert_eq!(sha256(&file), entry["sha256"].as_str().unwrap(), "{id}");
        let is_composition = entry["kind"] == "composition";
        let (expected, encode_limits, source_graph) = if entry["set"] == "worked" {
            let name = id.strip_prefix("worked-").unwrap();
            (worked(name), limits(), None)
        } else if is_composition {
            composition_count += 1;
            let source = read(entry["sourceFile"].as_str().unwrap());
            let graph = composition::decode(&source, &graph_limits(), &limits(), &options())
                .unwrap_or_else(|error| panic!("{id}: {error:?}"));
            let envelope =
                composition::document(&graph, &graph_limits(), &limits(), &options()).unwrap();
            (envelope, profile_limits(), Some(graph))
        } else {
            let source = read(entry["sourceFile"].as_str().unwrap());
            let raw = decode(&source).unwrap_or_else(|error| panic!("{id}: {error:?}"));
            (decode(&text(&raw).unwrap()).unwrap(), limits(), None)
        };
        let canonical = text(&expected).unwrap();
        assert_eq!(
            canonical.len() as u64,
            entry["canonicalBytes"].as_u64().unwrap(),
            "{id}"
        );
        // 1. The writer reproduces the anchor.
        assert_eq!(
            binary_with(&expected, &encode_limits).unwrap(),
            file,
            "{id}"
        );
        // 2. The anchor decodes to the bounded text decode of the canonical text.
        let decoded = decode(&file).unwrap_or_else(|error| panic!("{id}: {error:?}"));
        assert_same(&decoded, &expected, id);
        assert_same(&decode(&canonical).unwrap(), &decoded, id);
        assert_eq!(
            decoded.planes.len() as u64,
            entry["planes"].as_u64().unwrap(),
            "{id}"
        );
        // 3. Re-encoding the decoded value is byte-identical (P2).
        assert_eq!(binary(&decoded).unwrap(), file, "{id}");
        // 4. The raw header fields.
        let info = header(&file);
        let payload = file.len() as u64 - 40;
        assert_eq!(info.container_version, 1, "{id}");
        assert_eq!(
            info.payload_kind,
            storage::PAYLOAD_KIND_STRUCTURED_DOCUMENT,
            "{id}"
        );
        assert_eq!(
            (info.compression, info.flags, info.reserved),
            (0, 0, 0),
            "{id}"
        );
        assert_eq!(info.encoded_payload_byte_count, payload, "{id}");
        assert_eq!(info.decoded_payload_byte_count, payload, "{id}");
        assert_eq!(
            format!("{:08x}", info.checksum),
            entry["crc32"].as_str().unwrap(),
            "{id}"
        );
        assert_eq!(payload, entry["payloadBytes"].as_u64().unwrap(), "{id}");
        // 5. The kind-1 sibling decodes to the same value and is reproduced by the 2.0 writer.
        if let Some(path) = entry["textContainerFile"].as_str() {
            let kind1 = read(path);
            assert_eq!(header(&kind1).payload_kind, 1, "{id}");
            assert_same(&decode(&kind1).unwrap(), &expected, id);
            assert_eq!(
                storage::encode_text_container(
                    &expected,
                    DocumentCompression::None,
                    &encode_limits,
                    &options()
                )
                .unwrap(),
                kind1,
                "{id}"
            );
        }
        // 6. A composition envelope reopens as the composition of its readable source.
        if let Some(graph) = source_graph {
            let reopened =
                composition::decode(&file, &graph_limits(), &limits(), &options()).unwrap();
            assert_eq!(reopened, graph, "{id}");
            assert_eq!(
                composition::encode(&reopened, &graph_limits(), &limits(), &options()).unwrap(),
                composition::encode(&graph, &graph_limits(), &limits(), &options()).unwrap(),
                "{id}"
            );
        }
    }
    assert_eq!(composition_count, 4);
}

#[test]
fn worked_examples_have_the_specified_bytes() {
    let document = binary(&worked("document")).unwrap();
    assert_eq!(document.len(), 113);
    assert_eq!(
        &document[40..67],
        b"\x01\x031.0\x04time\x04Week\x01\x05owner\x03ops\x02"
    );
    assert_eq!(header(&document).checksum, 0x8A5B_3B70);
    let numbers = binary(&worked("numbers")).unwrap();
    assert_eq!(numbers.len(), 86);
    assert_eq!(numbers[53], 0x2b);
    assert_eq!(header(&numbers).checksum, 0xDB5A_2326);
    let keys = binary(&worked("keys")).unwrap();
    assert_eq!(keys.len(), 68);
    assert_eq!(
        &keys[40..],
        b"\x00\x011\x00\x02\x03e\xcc\x81\x012\x01z\x011\x01\x01\x05\x02\x01a\x01y\x01b\x01x\x00"
    );
    assert_eq!(header(&keys).checksum, 0x649E_B26B);
    // Storing the metadata keys in text order is not canonical.
    let mut text_order = keys[40..].to_vec();
    text_order.splice(5..15, b"\x01z\x011\x03e\xcc\x81\x012".iter().copied());
    assert_eq!(
        decode(&container(&text_order)),
        Err(DocumentStorageError::InvalidContainer)
    );
}

// MARK: - Vectors (test plan section 2)

fn vector_limits(value: &Value) -> DocumentDecodeLimits {
    let mut result = limits();
    if let Some(fields) = value.as_object() {
        for (name, value) in fields {
            let value = value.as_u64().unwrap() as usize;
            match name.as_str() {
                "maximumEncodedBytes" => result.maximum_encoded_bytes = value,
                "maximumDecodedBytes" => result.maximum_decoded_bytes = value,
                "maximumLines" => result.maximum_lines = value,
                "maximumPlanes" => result.maximum_planes = value,
                "maximumRecordBytes" => result.maximum_record_bytes = value,
                other => panic!("unknown limit {other}"),
            }
        }
    }
    result
}

#[test]
fn every_vector_reports_its_code_under_its_limits() {
    let manifest = json("conformance/structured/vectors.json");
    assert_eq!(manifest["schema"], "3md-structured-vectors-1");
    let vectors = manifest["vectors"].as_array().unwrap();
    assert_eq!(vectors.len(), 156);
    let mut failures = Vec::new();
    let mut with_limits = 0;
    for vector in vectors {
        let name = vector["name"].as_str().unwrap();
        let data = read(vector["file"].as_str().unwrap());
        if vector.get("limits").is_some() {
            with_limits += 1;
        }
        let policy = vector_limits(&vector["limits"]);
        let result = decode_with(&data, &policy);
        let expected = vector["expected"].as_str().unwrap();
        if code(&result) != expected {
            failures.push(format!(
                "{name} ({}): {result:?}, expected {expected}",
                vector["rule"]
            ));
        }
        if let Ok(document) = &result {
            // An accepted vector re-encodes to its own bytes under the same limits.
            if binary_with(document, &policy).as_deref() != Ok(data.as_slice()) {
                failures.push(format!("{name}: re-encode differs"));
            }
        }
    }
    assert!(failures.is_empty(), "{failures:#?}");
    assert_eq!(with_limits, 29);
}

// MARK: - Container inspection (test plan section 3)

#[test]
fn container_info_reports_raw_fields_without_validation() {
    assert_eq!(storage::container_info(b""), Ok(None));
    assert_eq!(storage::container_info(b"3mdbin\r"), Ok(None));
    assert_eq!(storage::container_info(b"---\n3md: 1\n---\n"), Ok(None));
    let mut file = b"3mdbin\r\n".to_vec();
    for length in 8..40 {
        file.resize(length, 0xee);
        assert_eq!(
            storage::container_info(&file),
            Err(DocumentStorageError::InvalidContainer),
            "{length}"
        );
    }
    file.resize(40, 0);
    file[8..10].copy_from_slice(&2_u16.to_le_bytes());
    file[10] = 7;
    file[11] = 3;
    file[12..16].copy_from_slice(&5_u32.to_le_bytes());
    file[16..20].copy_from_slice(&9_u32.to_le_bytes());
    file[20..28].copy_from_slice(&u64::MAX.to_le_bytes());
    file[28..36].copy_from_slice(&0x0102_0304_0506_0708_u64.to_le_bytes());
    file[36..40].copy_from_slice(&0xdead_beef_u32.to_le_bytes());
    file.extend_from_slice(b"ignored trailing bytes");
    let info = header(&file);
    assert_eq!(info.container_version, 2);
    assert_eq!(info.payload_kind, 7);
    assert_eq!(info.compression, 3);
    assert_eq!(info.flags, 5);
    assert_eq!(info.reserved, 9);
    assert_eq!(info.encoded_payload_byte_count, u64::MAX);
    assert_eq!(info.decoded_payload_byte_count, 0x0102_0304_0506_0708);
    assert_eq!(info.checksum, 0xdead_beef);
    assert_eq!(header(&file[..40]), info);
    assert!(!storage::SUPPORTED_PAYLOAD_KINDS.contains(&info.payload_kind));
    assert_eq!(
        threemd::SUPPORTED_PAYLOAD_KINDS,
        [
            threemd::PAYLOAD_KIND_CANONICAL_TEXT,
            threemd::PAYLOAD_KIND_STRUCTURED_DOCUMENT
        ]
    );
    let kind1 = read("conformance/extensions/document-unicode.3mdb");
    assert_eq!(
        header(&kind1).payload_kind,
        storage::PAYLOAD_KIND_CANONICAL_TEXT
    );
}

#[test]
fn payload_kind_dispatch_and_the_decoded_length_bound() {
    let source = worked("document");
    let kind1 =
        storage::encode_text_container(&source, DocumentCompression::None, &limits(), &options())
            .unwrap();
    let kind2 = binary(&source).unwrap();
    assert_eq!(decode(&kind1).unwrap(), source);
    assert_eq!(decode(&kind2).unwrap(), source);
    for kind in [0_u8, 3, 4, 255] {
        for file in [&kind1, &kind2] {
            let mut changed = file.clone();
            changed[10] = kind;
            assert_eq!(
                decode(&changed),
                Err(DocumentStorageError::UnsupportedPayloadKind(kind))
            );
        }
    }
    // Byte 10 is covered by the CRC: switching kinds 1 and 2 is a checksum failure.
    let mut changed = kind1.clone();
    changed[10] = 2;
    assert_eq!(
        decode(&changed),
        Err(DocumentStorageError::ChecksumMismatch)
    );
    let mut changed = kind2.clone();
    changed[10] = 1;
    assert_eq!(
        decode(&changed),
        Err(DocumentStorageError::ChecksumMismatch)
    );
    // D10: kind 1 is bounded by Dmax, kind 2 by min(Emax - 40, 2 * Dmax).
    let text_length = kind1.len() - 40;
    let lowered = DocumentDecodeLimits {
        maximum_decoded_bytes: text_length - 1,
        ..limits()
    };
    assert_eq!(
        decode_with(&kind1, &lowered),
        Err(DocumentStorageError::OversizedOutput)
    );
    let payload = kind2.len() - 40;
    let bound = |maximum_decoded_bytes, maximum_encoded_bytes| DocumentDecodeLimits {
        maximum_decoded_bytes,
        maximum_encoded_bytes,
        ..limits()
    };
    // 2 * Dmax below the payload length: rejected before the CRC is read.
    let mut corrupt = kind2.clone();
    corrupt[36] ^= 1;
    assert_eq!(
        decode_with(&corrupt, &bound(payload / 2 - 1, kind2.len())),
        Err(DocumentStorageError::OversizedOutput)
    );
    // Dmax below the payload but 2 * Dmax above it: D10 passes and the CRC decides.
    assert_eq!(
        decode_with(&corrupt, &bound(payload / 2 + 1, kind2.len())),
        Err(DocumentStorageError::ChecksumMismatch)
    );
    // A declared decoded length of Emax - 39 is over the Emax - 40 bound.
    let mut claimed = kind2.clone();
    claimed[28..36].copy_from_slice(&((kind2.len() - 39) as u64).to_le_bytes());
    assert_eq!(
        decode_with(
            &claimed,
            &bound(limits().maximum_decoded_bytes, kind2.len())
        ),
        Err(DocumentStorageError::OversizedOutput)
    );
    // Compression byte 1 is LZFSE, unavailable in Rust after the CRC check.
    let mut lzfse = kind2.clone();
    lzfse[11] = 1;
    let lzfse = reseal(lzfse);
    assert_eq!(
        decode(&lzfse),
        Err(DocumentStorageError::CompressionUnavailable(
            DocumentCompression::Lzfse
        ))
    );
}

// MARK: - Writers (test plan section 3)

#[test]
fn writer_cap_negative_zero_and_compression_follow_w1_to_w6() {
    let minimal = document(vec![Plane {
        z: -0.0,
        ..plane(0.0, "a")
    }]);
    let file = binary(&minimal).unwrap();
    assert_eq!(
        &file[40..],
        [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x61]
    );
    assert_eq!(decode(&file).unwrap().planes[0].z.to_bits(), 0);
    let with_emax = |maximum_encoded_bytes| DocumentDecodeLimits {
        maximum_encoded_bytes,
        ..limits()
    };
    assert_eq!(
        binary_with(&minimal, &with_emax(39)),
        Err(DocumentStorageError::OversizedInput)
    );
    assert_eq!(
        binary_with(&minimal, &with_emax(file.len())),
        Ok(file.clone())
    );
    assert_eq!(
        binary_with(&minimal, &with_emax(file.len() - 1)),
        Err(DocumentStorageError::OversizedInput)
    );
    let lzfse = |document: &Document| {
        storage::encode(
            document,
            DocumentStorageFormat::Binary(DocumentCompression::Lzfse),
            &limits(),
            &options(),
        )
    };
    assert_eq!(
        lzfse(&minimal),
        Err(DocumentStorageError::CompressionUnavailable(
            DocumentCompression::Lzfse
        ))
    );
    let mut invalid = minimal.clone();
    invalid.version.clear();
    assert!(matches!(
        lzfse(&invalid),
        Err(DocumentStorageError::InvalidDocument(_))
    ));
    // Non-finite coordinates are emitted (infinity as form 2, NaN as form 3) and rejected
    // by the self-check, unless the emission already exceeds the cap.
    for (value, size) in [(f64::INFINITY, 4), (f64::NEG_INFINITY, 4), (f64::NAN, 8)] {
        let mut document = minimal.clone();
        document.planes[0].z = value;
        assert!(
            matches!(
                binary(&document),
                Err(DocumentStorageError::InvalidDocument(_))
            ),
            "{value}"
        );
        let cap = 40 + 6 + size;
        assert_eq!(
            binary_with(&document, &with_emax(cap - 1)),
            Err(DocumentStorageError::OversizedInput),
            "{value}"
        );
        assert!(matches!(
            binary_with(&document, &with_emax(cap + 5)),
            Err(DocumentStorageError::InvalidDocument(_))
        ));
    }
    // Rust has no insertion history for equivalent spellings: W2 rejects them before W3.
    let mut equivalent = minimal.clone();
    equivalent.metadata = map(&[("e\u{301}", "first"), ("\u{e9}", "last")]);
    assert!(matches!(
        binary(&equivalent),
        Err(DocumentStorageError::InvalidDocument(_))
    ));
    assert!(matches!(
        binary_with(&equivalent, &with_emax(40)),
        Err(DocumentStorageError::InvalidDocument(_))
    ));
    let mut equivalent = minimal.clone();
    equivalent.planes[0].attributes = map(&[("k", "v"), ("\u{212a}", "w")]);
    assert!(matches!(
        binary(&equivalent),
        Err(DocumentStorageError::InvalidDocument(_))
    ));
    // Kind 2 compares the file, never the canonical text, with Emax.
    let empty_planes = document((0..80).map(|z| plane(f64::from(z), "")).collect());
    let small = binary_with(&empty_planes, &with_emax(1_000)).unwrap();
    assert!(small.len() <= 1_000);
    assert!(text(&empty_planes).unwrap().len() > 1_000);
    assert_eq!(decode_with(&small, &with_emax(1_000)), Ok(empty_planes));
}

#[test]
fn text_container_writer_keeps_the_2_0_bytes_and_error_order() {
    let source = worked("document");
    let canonical = text(&source).unwrap();
    let encode = |document: &Document, compression, limits: &DocumentDecodeLimits| {
        storage::encode_text_container(document, compression, limits, &options())
    };
    let file = encode(&source, DocumentCompression::None, &limits()).unwrap();
    assert_eq!(&file[40..], canonical.as_slice());
    assert_eq!(&file[..8], b"3mdbin\r\n");
    assert_eq!(&file[8..12], [1, 0, 1, 0]);
    assert_eq!(
        header(&file).checksum,
        crc32(&[&file[..36], &file[40..]].concat())
    );
    let with_emax = |maximum_encoded_bytes| DocumentDecodeLimits {
        maximum_encoded_bytes,
        ..limits()
    };
    assert_eq!(
        encode(&source, DocumentCompression::None, &with_emax(file.len())),
        Ok(file.clone())
    );
    assert_eq!(
        encode(
            &source,
            DocumentCompression::None,
            &with_emax(file.len() - 1)
        ),
        Err(DocumentStorageError::OversizedInput)
    );
    assert_eq!(
        encode(&source, DocumentCompression::Lzfse, &with_emax(39)),
        Err(DocumentStorageError::OversizedInput)
    );
    assert_eq!(
        encode(&source, DocumentCompression::Lzfse, &limits()),
        Err(DocumentStorageError::CompressionUnavailable(
            DocumentCompression::Lzfse
        ))
    );
    let mut invalid = source.clone();
    invalid.planes[1].z = 0.0;
    assert!(matches!(
        encode(&invalid, DocumentCompression::Lzfse, &with_emax(39)),
        Err(DocumentStorageError::InvalidDocument(_))
    ));
    assert_eq!(
        encode(
            &source,
            DocumentCompression::None,
            &DocumentDecodeLimits {
                maximum_decoded_bytes: canonical.len() - 1,
                ..limits()
            }
        ),
        Err(DocumentStorageError::OversizedOutput)
    );
    assert_eq!(
        encode(
            &source,
            DocumentCompression::None,
            &DocumentDecodeLimits {
                maximum_planes: 0,
                ..limits()
            }
        ),
        Err(DocumentStorageError::InvalidLimits)
    );
    // Every kind-1 file of the interchange catalog is reproduced. Catalog schema 1 names the
    // kind-1 files `binaryFile`; schema 2 renames them `textContainerFile`.
    let catalog = json("conformance/interchange/manifest.json");
    let field = if catalog["schema"] == "3md-interchange-catalog-1" {
        "binaryFile"
    } else {
        "textContainerFile"
    };
    let mut reproduced = 0;
    for case in catalog["cases"].as_array().unwrap() {
        let Some(path) = case[field].as_str() else {
            continue;
        };
        let expected = read(path);
        assert_eq!(header(&expected).payload_kind, 1, "{path}");
        let (document, policy) = if case["kind"] == "composition" {
            let graph =
                composition::decode(&expected, &graph_limits(), &limits(), &options()).unwrap();
            let envelope =
                composition::document(&graph, &graph_limits(), &limits(), &options()).unwrap();
            (envelope, profile_limits())
        } else {
            (decode(&expected).unwrap(), limits())
        };
        assert_eq!(
            encode(&document, DocumentCompression::None, &policy).unwrap(),
            expected,
            "{path}"
        );
        reproduced += 1;
    }
    assert_eq!(reproduced, 22);
}

// MARK: - Strings (test plan section 3)

/// A body of `length` bytes with a four-byte scalar starting at `at`.
fn body_with_scalar(length: usize, at: usize) -> String {
    let mut body = "a".repeat(at);
    body.push('\u{1F600}');
    body.push_str(&"b".repeat(length - at - 4));
    body
}

#[test]
fn chunked_utf8_validation_agrees_with_whole_string_validation() {
    for length in [65_535_usize, 65_536, 65_537, 200_000] {
        let mut positions: Vec<usize> = (65_530..65_540).collect();
        positions.extend(131_066..131_076);
        positions.push(length - 4);
        for at in positions.into_iter().filter(|at| at + 4 <= length) {
            let body = body_with_scalar(length, at);
            let mut source = document(vec![plane(0.0, &body)]);
            source.planes[0].label = Some(body.clone());
            let file = binary(&source).unwrap();
            assert_eq!(decode(&file).as_ref(), Ok(&source), "{length} {at}");
            // Truncate the scalar: replace its last byte, in the body and in the label. The
            // label follows flags, version, axis, both counts, plane flags, z and its 3-byte
            // length prefix.
            let body_start = file.len() - length;
            let label_start = 40 + 8 + 3;
            assert_eq!(&file[label_start..label_start + length], body.as_bytes());
            for start in [body_start, label_start] {
                let mut damaged = file.clone();
                let offset = start + at + 3;
                damaged[offset] = b'x';
                let damaged = reseal(damaged);
                assert!(std::str::from_utf8(&damaged[start..start + length]).is_err());
                assert_eq!(
                    decode(&damaged),
                    Err(DocumentStorageError::InvalidUtf8),
                    "{length} {at} {offset}"
                );
            }
        }
    }
}

#[test]
fn a_truncated_tail_never_carries_into_the_next_string_or_call() {
    for length in [65_535_usize, 65_536, 65_537, 200_000] {
        let mut body = "a".repeat(length - 2).into_bytes();
        body.extend_from_slice(&[0xE2, 0x82]);
        let mut payload = vec![0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00];
        let mut prefix = Vec::new();
        let mut value = length;
        while value >= 0x80 {
            prefix.push((value & 0x7f) as u8 | 0x80);
            value >>= 7;
        }
        prefix.push(value as u8);
        payload.extend_from_slice(&prefix);
        payload.extend_from_slice(&body);
        assert_eq!(
            decode(&container(&payload)),
            Err(DocumentStorageError::InvalidUtf8),
            "{length}"
        );
        // The next call's version starts with a continuation byte.
        let next = container(&[0x00, 0x02, 0xAC, 0x62, 0x00, 0x00, 0x00]);
        assert_eq!(decode(&next), Err(DocumentStorageError::InvalidUtf8));
    }
    // A scalar split across two fields is ill-formed in both.
    let split = container(&[0x00, 0x02, 0x31, 0xE2, 0x02, 0x82, 0xAC, 0x00, 0x00]);
    assert_eq!(decode(&split), Err(DocumentStorageError::InvalidUtf8));
}

#[test]
fn var_prefixes_at_size_boundaries_round_trip_through_bodies() {
    for (length, prefix) in [
        (127_usize, vec![0x7f]),
        (128, vec![0x80, 0x01]),
        (16_383, vec![0xff, 0x7f]),
        (16_384, vec![0x80, 0x80, 0x01]),
        (2_097_151, vec![0xff, 0xff, 0x7f]),
        (2_097_152, vec![0x80, 0x80, 0x80, 0x01]),
    ] {
        let source = document(vec![plane(0.0, &"x".repeat(length))]);
        let file = binary(&source).unwrap();
        let start = file.len() - length - prefix.len();
        assert_eq!(
            &file[start..file.len() - length],
            prefix.as_slice(),
            "{length}"
        );
        assert_eq!(decode(&file).unwrap(), source);
    }
}

// MARK: - Seeded generator (test plan section 4)

/// Mulberry32, the generator the TypeScript fuzzers use, so seeds read the same everywhere.
struct Random(u32);

impl Random {
    fn next(&mut self) -> f64 {
        self.0 = self.0.wrapping_add(0x6d2b_79f5);
        let seed = self.0;
        let mut t = (seed ^ (seed >> 15)).wrapping_mul(1 | seed);
        t = t.wrapping_add((t ^ (t >> 7)).wrapping_mul(61 | t)) ^ t;
        f64::from(t ^ (t >> 14)) / 4_294_967_296.0
    }
    fn below(&mut self, count: usize) -> usize {
        (self.next() * count as f64) as usize
    }
    fn between(&mut self, low: usize, high: usize) -> usize {
        low + self.below(high - low + 1)
    }
    fn pick<'a, Item>(&mut self, items: &'a [Item]) -> &'a Item {
        &items[self.below(items.len())]
    }
    fn chance(&mut self, probability: f64) -> bool {
        self.next() < probability
    }
}

/// CI volume by default; `THREEMD_FUZZ_SCALE` multiplies it for release-candidate runs.
fn volume(count: usize) -> usize {
    std::env::var("THREEMD_FUZZ_SCALE")
        .ok()
        .and_then(|scale| scale.parse::<usize>().ok())
        .map_or(count, |scale| count * scale)
}

const SEGMENT_LINES: &[&str] = &[
    "",
    " ",
    "\t",
    "\u{a0}",
    "\u{3000}",
    "text",
    "@plane",
    "@plane z=1",
    "@plane\tz",
    "@planet",
    " @plane z=1",
    "\u{a0}@plane z=1",
    "```",
    "~~~",
    "  ```js",
    "\u{3000}~~~",
    "``",
    "\r",
    "a\r",
    "# h",
    "---",
    "\u{2002}",
    "x\u{200b}",
    "\u{200b}",
    "  ~~~~",
    "```` four",
    "caf\u{e9}",
    "e\u{301}",
    "\u{feff}",
    "[[z=1]]",
    "\u{85}",
    "\u{2028}",
    "\u{180e}",
    "\u{1680}x",
    "\u{b}",
    "\u{c}",
    "\0",
];
const VALUES: &[&str] = &[
    "v",
    "",
    " lead",
    "trail ",
    "\"q\"",
    "a\\b",
    "\\",
    "'s'",
    "a\nb",
    "a\rb",
    " ",
    "x y",
    "\u{a0}",
    "caf\u{e9}",
    "\u{1F600}",
    "\u{feff}",
];
const META_KEYS: &[&str] = &[
    "",
    "a",
    "B",
    "view",
    "3md",
    "AXIS",
    "Title",
    "#c",
    " k",
    "k ",
    "a:b",
    "\u{e9}",
    "e\u{301}",
    "\u{fffd}",
    "\u{1F600}",
    "\u{a0}k",
    "k\u{3000}",
    "x\ry",
    "k#",
    "caf\u{e9}",
    "tItle",
    "axis2",
    "Key",
    "1",
    "10",
    "__proto__",
    "\u{ff61}",
    "K",
    "\u{212a}",
    "z",
    "Z",
    "\u{200b}k",
    "k\u{85}",
    "\u{c5}",
    "\u{212b}",
    "A\u{30a}",
];
const ATTRIBUTE_KEYS: &[&str] = &[
    "a",
    "A",
    "",
    "z",
    "Label",
    "x",
    "a b",
    "a'b c'd",
    "'a\\'b'",
    "a\"b",
    "k=v",
    " k",
    "k ",
    "\u{df}",
    "\u{1c5}",
    "\u{e9}",
    "e\u{301}",
    "\u{a0}k",
    "k\u{3a3}",
    "k\u{3c3}",
    "key",
    "data-x",
    "'",
    "a''",
    "\"x y\"",
    "\u{130}",
    "i\u{307}",
    "3md-id",
    "\u{ff61}",
    "\u{1F600}",
    "k",
    "\u{212a}",
    "q''",
    "a\tb",
    "k\u{2000}",
    "\u{2160}",
    "\u{24b6}",
    "k\u{3c2}",
];
const NUMBERS: &[f64] = &[
    0.0,
    -0.0,
    1.0,
    1.5,
    -2.0,
    0.1,
    9_007_199_254_740_992.0,
    9_007_199_254_740_994.0,
    5e-324,
    f64::MAX,
    -1.5,
    1e21,
    1e-7,
    123_456_789.125,
];
const EXTRA_NUMBERS: &[f64] = &[
    7.174_648_137_343_064e-43,
    134_217_727.0,
    -134_217_728.0,
    134_217_728.0,
    16_777_217.0,
    3.402_823_466_385_288_6e38,
    1.401_298_464_324_817e-45,
    0.5,
    -0.25,
    1e15,
    1e16,
    9_007_199_254_740_991.0,
    123.456,
];
const SAFE_VALUES: &[&str] = &[
    "v",
    "x y",
    "\"q\"",
    "a\\b",
    "it's",
    "",
    "caf\u{e9}",
    "\u{1F600}",
    "a=b",
    "'s'",
    " lead",
    "trail ",
    "\"",
    "\\",
    "a \"b\" c",
];
const SAFE_LINES: &[&str] = &[
    "text",
    "# h",
    "- item",
    "caf\u{e9}",
    "a  b",
    "> quote",
    "x\u{200b}y",
    "[[z=1]]",
    "\u{feff}bom",
    "a\rb",
    "  indented",
    "\t tab",
];
const RISKY_LINES: &[&str] = &[
    "",
    " ",
    "\u{3000}",
    "@plane z=9",
    "@plane",
    "@plane\tz",
    " @plane z=9",
    "@planet",
    "```",
    "~~~",
    " ```",
    "\u{a0}~~~",
    "````",
    "~~ ~",
    "``",
    "\r",
    "a\r",
    "\u{2028}",
    "---",
];
const QUOTE_KEYS: &[&str] = &[
    "a\"b",
    "a'b",
    "\"",
    "'",
    "a\"b\"c\"",
    "x\\\"",
    "\"a b\"",
    "'a b'",
    "a'b c'd",
    "'a\\'b'",
    "k\"=",
    "q\"\"",
    "a\"\\\"b",
    "\"\\\"",
    "data-x",
    "key",
    "k_1",
    "\u{e9}",
    "e\u{301}",
    "\u{df}",
    "\u{130}",
    "i\u{307}",
    "k\u{3c3}",
    "\u{2160}",
    "\u{24b6}",
    "a''b",
    "z'",
    "label'",
];

fn generated_map(
    random: &mut Random,
    keys: &[&str],
    values: &[&str],
    count: usize,
) -> BTreeMap<String, String> {
    (0..count)
        .map(|_| ((*random.pick(keys)).into(), (*random.pick(values)).into()))
        .collect()
}

fn generated_segment(random: &mut Random) -> String {
    if random.chance(0.08) {
        return String::new();
    }
    let mut text = String::new();
    for index in 0..random.between(1, 5) {
        if index > 0 {
            text.push_str(if random.chance(0.1) { "\r\n" } else { "\n" });
        }
        let line: &&str = random.pick(SEGMENT_LINES);
        text.push_str(line);
    }
    if random.chance(0.05) {
        text.push('\r');
    }
    if random.chance(0.03) {
        text.insert(0, '\n');
    }
    text
}

fn generated_document(random: &mut Random) -> Document {
    let mut planes = Vec::new();
    for index in 0..random.between(0, 4) {
        let z = if random.chance(0.03) {
            *random.pick(&[f64::NAN, f64::INFINITY])
        } else if random.chance(0.5) {
            index as f64
        } else {
            *random.pick(NUMBERS)
        };
        let label = (!random.chance(0.5)).then(|| (*random.pick(VALUES)).into());
        let x = (!random.chance(0.7)).then(|| *random.pick(NUMBERS));
        let y = (!random.chance(0.7)).then(|| *random.pick(NUMBERS));
        let count = if random.chance(0.5) {
            0
        } else {
            random.between(1, 3)
        };
        let attributes = generated_map(random, ATTRIBUTE_KEYS, VALUES, count);
        let body = generated_segment(random);
        planes.push(Plane {
            z,
            label,
            x,
            y,
            attributes,
            body,
        });
    }
    let version = (*random.pick(&[
        "1.0", "1.0", "1.0", "", " 1.0", "1\r", "v\n2", "0.1", "\u{e9}",
    ]))
    .into();
    let axis = (*random.pick(&[
        "layer",
        "time",
        "",
        "Time",
        " time",
        "time ",
        "\ttime",
        "t\u{ef}me",
        "T\u{cf}ME",
        "\u{a0}time",
        "ti me",
        "\u{130}",
        "time\u{200b}",
    ]))
    .into();
    let title = (!random.chance(0.5)).then(|| (*random.pick(VALUES)).into());
    let count = if random.chance(0.4) {
        0
    } else {
        random.between(1, 4)
    };
    let metadata = generated_map(random, META_KEYS, VALUES, count);
    let preamble = (!random.chance(0.7)).then(|| generated_segment(random));
    Document {
        version,
        axis,
        title,
        metadata,
        preamble,
        planes,
    }
}

fn focused_segment(random: &mut Random) -> String {
    let lines: Vec<&str> = (0..random.between(1, 4))
        .map(|_| {
            if random.chance(0.25) {
                *random.pick(RISKY_LINES)
            } else {
                *random.pick(SAFE_LINES)
            }
        })
        .collect();
    let mut text = lines.join(if random.chance(0.05) { "\r\n" } else { "\n" });
    if random.chance(0.03) {
        text.push('\r');
    }
    text
}

/// Mostly representable documents with one or two risky fields, to probe the boundary.
fn focused_document(random: &mut Random) -> Document {
    let count = random.between(1, 4);
    let mut planes = Vec::new();
    for index in 0..count {
        let z = if random.chance(0.1) {
            *random.pick(NUMBERS)
        } else {
            index as f64 * 1.5
        };
        let label = (!random.chance(0.5)).then(|| (*random.pick(SAFE_VALUES)).into());
        let x = (!random.chance(0.8)).then(|| *random.pick(NUMBERS));
        let y = (!random.chance(0.8)).then(|| *random.pick(NUMBERS));
        let keys: &[&str] = if random.chance(0.6) {
            QUOTE_KEYS
        } else {
            &["key", "data-x", "tags", "k_1"]
        };
        let pairs = random.between(0, 3);
        let attributes = generated_map(random, keys, SAFE_VALUES, pairs);
        let body = if random.chance(0.1) {
            String::new()
        } else {
            focused_segment(random)
        };
        planes.push(Plane {
            z,
            label,
            x,
            y,
            attributes,
            body,
        });
    }
    let version = if random.chance(0.05) {
        (*random.pick(&["", " 1.0", "1\r"])).into()
    } else {
        "1.0".into()
    };
    let axis = if random.chance(0.1) {
        *random.pick(&["Time", " time", "t\u{ef}me", "\u{130}", "ti me", "\u{a0}x"])
    } else {
        *random.pick(&["layer", "time", ""])
    }
    .into();
    let title = (!random.chance(0.5)).then(|| (*random.pick(SAFE_VALUES)).into());
    let keys: &[&str] = if random.chance(0.3) {
        META_KEYS
    } else {
        &["author", "view", "palette", "k"]
    };
    let pairs = random.between(0, 3);
    let metadata = generated_map(random, keys, SAFE_VALUES, pairs);
    let preamble = (!random.chance(0.6)).then(|| focused_segment(random));
    Document {
        version,
        axis,
        title,
        metadata,
        preamble,
        planes,
    }
}

fn with_numbers(random: &mut Random, document: &mut Document) {
    for (index, plane) in document.planes.iter_mut().enumerate() {
        if random.chance(0.3) {
            let value = if random.chance(0.5) {
                *random.pick(NUMBERS)
            } else {
                *random.pick(EXTRA_NUMBERS)
            };
            let sign = if random.chance(0.5) { 1.0 } else { -1.0 };
            let offset = if random.chance(0.5) {
                0.0
            } else {
                index as f64 * 1000.0
            };
            plane.z = value * sign + offset;
        }
        if random.chance(0.2) {
            plane.x = Some(*random.pick(EXTRA_NUMBERS));
        }
    }
}

fn normalized(document: &Document) -> Document {
    let zero = |value: f64| if value == 0.0 { 0.0 } else { value };
    let mut result = document.clone();
    for plane in &mut result.planes {
        plane.z = zero(plane.z);
        plane.x = plane.x.map(zero);
        plane.y = plane.y.map(zero);
    }
    result
}

fn lowered_limits(random: &mut Random) -> DocumentDecodeLimits {
    DocumentDecodeLimits {
        maximum_record_bytes: random.between(1, 120),
        maximum_decoded_bytes: random.between(20, 700),
        maximum_lines: random.between(1, 40),
        maximum_planes: random.between(1, 5),
        ..limits()
    }
}

/// P5 and P6: the writer accepts exactly what the 2.1 `validate` accepts, its output decodes
/// to the normalized document and to the text decode, and re-encodes byte for byte.
fn writer_equivalence(seed: u32, total: usize, lowered: bool) -> (usize, Vec<String>) {
    let mut random = Random(seed);
    let mut accepted = 0;
    let mut failures = Vec::new();
    for index in 0..total {
        let mut document = if index % 2 == 0 {
            generated_document(&mut random)
        } else {
            focused_document(&mut random)
        };
        if random.chance(0.3) {
            with_numbers(&mut random, &mut document);
        }
        let policy = if lowered {
            lowered_limits(&mut random)
        } else {
            limits()
        };
        let validated = storage::validate(&document, &policy, &options());
        let encoded = binary_with(&document, &policy);
        if validated.is_ok() != encoded.is_ok() {
            failures.push(format!(
                "#{index}: validate {:?} binary {:?} limits {policy:?} {document:?}",
                validated.err(),
                encoded.as_ref().err()
            ));
            continue;
        }
        let Ok(bytes) = encoded else {
            continue;
        };
        accepted += 1;
        let decoded = decode_with(&bytes, &policy);
        let canonical =
            storage::encode(&document, DocumentStorageFormat::Text, &policy, &options())
                .and_then(|source| decode_with(&source, &policy));
        match (&decoded, &canonical) {
            (Ok(decoded), Ok(canonical)) => {
                let expected = normalized(&document);
                if decoded != &expected || decoded != canonical {
                    failures.push(format!("#{index}: value mismatch {document:?}"));
                } else if binary_with(decoded, &policy).as_ref() != Ok(&bytes) {
                    failures.push(format!("#{index}: re-encode differs {document:?}"));
                }
            }
            _ => failures.push(format!(
                "#{index}: decode {:?} text {:?} {document:?}",
                decoded.err(),
                canonical.err()
            )),
        }
    }
    (accepted, failures)
}

#[test]
fn p5_p6_writer_acceptance_equals_validate_under_standard_limits() {
    let total = volume(10_000);
    let (accepted, failures) = writer_equivalence(0x3d3d_2101, total, false);
    eprintln!("P6 standard limits, seed 0x3d3d2101: {accepted} of {total} accepted");
    assert!(
        failures.is_empty(),
        "{} failures: {:#?}",
        failures.len(),
        &failures[..failures.len().min(10)]
    );
    assert!(accepted * 20 > total, "only {accepted} of {total} accepted");
}

#[test]
fn p5_p6_writer_acceptance_equals_validate_under_lowered_limits() {
    let total = volume(30_000);
    let (accepted, failures) = writer_equivalence(0x3d3d_2102, total, true);
    eprintln!("P6 lowered limits, seed 0x3d3d2102: {accepted} of {total} accepted");
    assert!(
        failures.is_empty(),
        "{} failures: {:#?}",
        failures.len(),
        &failures[..failures.len().min(10)]
    );
    assert!(accepted * 50 > total, "only {accepted} of {total} accepted");
}

// MARK: - P1 to P4: the mutation corpus (test plan section 4)

const MUTATION_SEED: u32 = 0x51a7;
const MUTATIONS_PER_BASE: usize = 300;
const MUTATION_COUNT: usize = 102_600;
/// FNV-1a 64 over the expected outcome lines (`code` or `ok`, each with a trailing LF) of
/// every mutant, and of every tenth mutant, as reported identically by the TypeScript, Rust
/// and Swift prototypes for seed 0x51a7 with 300 mutants per base.
const OUTCOMES_DIGEST: u64 = 0xb5a7_341c_1617_ec21;
const SAMPLED_OUTCOMES_DIGEST: u64 = 0x17f8_22d9_a195_3cdf;

fn fnv1a(hash: &mut u64, bytes: &[u8]) {
    for &byte in bytes {
        *hash ^= u64::from(byte);
        *hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
}

/// The 342 bases: the kind-2 encoding of every `Examples/*.3md` file in name order, then the
/// 49 interchange anchors in the order of their specification-package file names.
fn mutation_bases() -> Vec<Vec<u8>> {
    let examples = root().join("Examples");
    let mut names: Vec<String> = fs::read_dir(&examples)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().into_string().unwrap())
        .filter(|name| name.ends_with(".3md"))
        .collect();
    names.sort();
    assert_eq!(names.len(), 293);
    let mut bases: Vec<Vec<u8>> = names
        .iter()
        .map(|name| binary(&decode(&fs::read(examples.join(name)).unwrap()).unwrap()).unwrap())
        .collect();
    let manifest = json("conformance/structured/manifest.json");
    let mut anchors: Vec<(String, String)> = manifest["files"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|entry| entry["set"] == "interchange")
        .map(|entry| {
            (
                format!("{}.3mdb", entry["id"].as_str().unwrap()),
                entry["kind2File"].as_str().unwrap().to_owned(),
            )
        })
        .collect();
    anchors.sort();
    bases.extend(anchors.iter().map(|(_, path)| read(path)));
    assert_eq!(bases.len(), 342);
    bases
}

/// The specification package's `mutate.ts`, operation for operation, with JavaScript array
/// semantics: assignment past the end appends, and `splice` clamps its start. Returns the
/// mutated payload; the caller reseals it behind the base header.
fn mutate(random: &mut Random, base: &[u8]) -> Vec<u8> {
    let mut payload = base[40..].to_vec();
    let set = |payload: &mut Vec<u8>, at: usize, value: u8| {
        if at < payload.len() {
            payload[at] = value;
        } else {
            payload.push(value);
        }
    };
    let get = |payload: &[u8], at: usize| payload.get(at).copied().unwrap_or(0);
    for _ in 0..random.between(1, 3) {
        let at = random.below(payload.len().max(1));
        match random.between(0, 10) {
            0 => {
                let value = get(&payload, at) ^ (1 << random.between(0, 7));
                set(&mut payload, at, value);
            }
            1 => {
                let value = random.between(0, 255) as u8;
                set(&mut payload, at, value);
            }
            2 => {
                let value = *random.pick(&[
                    0x00_u8, 0x0a, 0x0d, 0x20, 0x22, 0x27, 0x3d, 0x3a, 0x40, 0x60, 0x7e, 0x7f,
                    0x80, 0xc0, 0xed, 0xff,
                ]);
                set(&mut payload, at, value);
            }
            3 => {
                let value = random.between(0, 255) as u8;
                payload.insert(at.min(payload.len()), value);
            }
            4 => {
                let count = random.between(1, 4);
                let start = at.min(payload.len());
                let end = (start + count).min(payload.len());
                payload.drain(start..end);
            }
            5 => payload.truncate(at),
            6 => {
                let from = random.below(payload.len());
                let count = random.between(1, 12);
                let span: Vec<u8> = payload
                    .get(from..(from + count).min(payload.len()))
                    .unwrap_or_default()
                    .to_vec();
                let start = at.min(payload.len());
                payload.splice(start..start, span);
            }
            7 => {
                let delta = *random.pick(&[-1_i32, 1]);
                let value = (i32::from(get(&payload, at)) + delta) & 0xff;
                set(&mut payload, at, value as u8);
            }
            8 => {
                let first = 0x80 | random.between(0, 127) as u8;
                let second = random.between(0, 3) as u8;
                let start = at.min(payload.len());
                let end = (start + 1).min(payload.len());
                payload.splice(start..end, [first, second]);
            }
            9 => {
                let from = random.below(payload.len());
                let count = random.between(1, 6);
                let end = (from + count).min(payload.len());
                let span: Vec<u8> = payload.drain(from..end).collect();
                let start = at.min(payload.len());
                payload.splice(start..start, span);
            }
            _ => {
                let value = random.between(0, 255) as u8;
                payload.push(value);
            }
        }
    }
    payload
}

/// Generates the corpus and calls `visit(index, mutant)` for every `stride`-th mutant.
fn for_each_mutant(stride: usize, mut visit: impl FnMut(usize, &[u8])) {
    let mut random = Random(MUTATION_SEED);
    let mut index = 0;
    for base in mutation_bases() {
        for _ in 0..MUTATIONS_PER_BASE {
            let payload = mutate(&mut random, &base);
            if index % stride == 0 {
                let mut file = base[..40].to_vec();
                file.extend_from_slice(&payload);
                visit(index, &reseal(file));
            }
            index += 1;
        }
    }
    assert_eq!(index, MUTATION_COUNT);
}

/// P1 (one value or one typed error), P2 (an accepted mutant re-encodes to itself) and P3
/// (an accepted mutant equals the text decode of its canonical text) for one mutant.
fn mutation_outcome(mutant: &[u8]) -> String {
    match decode(mutant) {
        Ok(document) => {
            let canonical = text(&document).and_then(|source| decode(&source));
            if binary(&document).as_deref() != Ok(mutant) {
                "ok-p2-failure".into()
            } else if canonical.as_ref() != Ok(&document) {
                "ok-p3-failure".into()
            } else {
                "ok".into()
            }
        }
        Err(error) => error.code().into(),
    }
}

#[test]
fn p1_to_p4_mutants_report_the_shared_outcomes() {
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    for_each_mutant(10, |_, mutant| {
        let outcome = mutation_outcome(mutant);
        fnv1a(&mut hash, outcome.as_bytes());
        fnv1a(&mut hash, b"\n");
        *counts.entry(outcome).or_default() += 1;
    });
    assert_eq!(counts.get("ok"), Some(&1_336), "{counts:?}");
    assert_eq!(counts.values().sum::<usize>(), 10_260);
    assert_eq!(hash, SAMPLED_OUTCOMES_DIGEST, "{counts:?}");
}

/// The full corpus (release volume of the prototypes). With `THREEMD_P4_BLOB` the generated
/// mutants are also compared with `mutations.bin` from `node mutate.ts 300 0x51a7`, and with
/// `THREEMD_P4_OUTCOMES` the outcomes with that run's `ts-mutations.txt`, line by line.
#[test]
#[ignore = "102,600 decodes; run with --release -- --ignored"]
fn p1_to_p4_every_mutant_reports_the_shared_outcome() {
    let blob = std::env::var_os("THREEMD_P4_BLOB").map(|path| fs::read(path).unwrap());
    let expected: Option<Vec<String>> = std::env::var_os("THREEMD_P4_OUTCOMES").map(|path| {
        fs::read_to_string(path)
            .unwrap()
            .lines()
            .map(str::to_owned)
            .collect()
    });
    let mut offset = 0;
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    let mut mismatches = Vec::new();
    for_each_mutant(1, |index, mutant| {
        if let Some(blob) = &blob {
            let length = u32::from_le_bytes([
                blob[offset],
                blob[offset + 1],
                blob[offset + 2],
                blob[offset + 3],
            ]) as usize;
            assert_eq!(
                &blob[offset + 4..offset + 4 + length],
                mutant,
                "mutant {index}"
            );
            offset += 4 + length;
        }
        let outcome = mutation_outcome(mutant);
        if let Some(expected) = &expected {
            if expected[index] != outcome && mismatches.len() < 20 {
                mismatches.push(format!("{index}: {outcome} != {}", expected[index]));
            }
        }
        fnv1a(&mut hash, outcome.as_bytes());
        fnv1a(&mut hash, b"\n");
    });
    assert!(mismatches.is_empty(), "{mismatches:#?}");
    assert_eq!(hash, OUTCOMES_DIGEST);
}

// MARK: - Metrics and sizes (test plan section 3, perf gate G6)

fn examples() -> Vec<(String, Vec<u8>)> {
    let directory = root().join("Examples");
    let mut names: Vec<String> = fs::read_dir(&directory)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().into_string().unwrap())
        .filter(|name| name.ends_with(".3md"))
        .collect();
    names.sort();
    names
        .into_iter()
        .map(|name| {
            let source = fs::read(directory.join(&name)).unwrap();
            (format!("Examples/{name}"), source)
        })
        .collect()
}

/// The smallest value of one limit that `accepts`, by bisection between 1 and `high`.
fn threshold(high: usize, accepts: impl Fn(usize) -> bool) -> usize {
    assert!(accepts(high));
    let (mut low, mut high) = (0, high);
    while high - low > 1 {
        let middle = low + (high - low) / 2;
        if accepts(middle) {
            high = middle;
        } else {
            low = middle;
        }
    }
    high
}

/// T, Lines and R of a kind-2 file equal those of its canonical text: at each metric the
/// kind-2 reader starts to accept exactly where the 2.0 text reader does. T and Lines are
/// counted on the text; R (the largest frontmatter line, directive line, scalar, preamble
/// or body) is bisected on the kind-2 file.
fn assert_metrics(name: &str, file: &[u8], canonical: &[u8]) {
    let lines = canonical.iter().filter(|byte| **byte == b'\n').count() + 1;
    let accepts = |policy: DocumentDecodeLimits| decode_with(file, &policy).is_ok();
    let text_accepts = |policy: DocumentDecodeLimits| decode_with(canonical, &policy).is_ok();
    let both = |policy: DocumentDecodeLimits| (accepts(policy.clone()), text_accepts(policy));
    let decoded = |maximum_decoded_bytes| DocumentDecodeLimits {
        maximum_decoded_bytes,
        ..limits()
    };
    let line_limit = |maximum_lines| DocumentDecodeLimits {
        maximum_lines,
        ..limits()
    };
    let record = |maximum_record_bytes| DocumentDecodeLimits {
        maximum_record_bytes,
        ..limits()
    };
    // T: the canonical text's length.
    let t = canonical.len();
    assert_eq!(both(decoded(t)), (true, true), "{name} T={t}");
    assert_eq!(both(decoded(t - 1)), (false, false), "{name} T={t}");
    // Lines: the canonical text's line count.
    assert_eq!(
        both(line_limit(lines)),
        (true, true),
        "{name} Lines={lines}"
    );
    if lines > 1 {
        assert_eq!(
            both(line_limit(lines - 1)),
            (false, false),
            "{name} Lines={lines}"
        );
    }
    // R: frontmatter and directive lines, scalars, the preamble and bodies.
    let r = threshold(canonical.len(), |value| accepts(record(value)));
    assert!(
        text_accepts(record(r)) && (r == 1 || !text_accepts(record(r - 1))),
        "{name} R={r}"
    );
}

#[test]
fn metrics_equal_the_canonical_text_on_every_example() {
    for (name, source) in examples() {
        let document = decode(&source).unwrap();
        let canonical = text(&document).unwrap();
        let file = binary(&document).unwrap();
        // The bisected kind-2 thresholds land on the text's T and Lines.
        let accepts = |policy: DocumentDecodeLimits| decode_with(&file, &policy).is_ok();
        let t = threshold(canonical.len() * 2, |maximum_decoded_bytes| {
            accepts(DocumentDecodeLimits {
                maximum_decoded_bytes,
                ..limits()
            })
        });
        assert_eq!(t, canonical.len(), "{name}");
        let l = threshold(100_000, |maximum_lines| {
            accepts(DocumentDecodeLimits {
                maximum_lines,
                ..limits()
            })
        });
        assert_eq!(
            l,
            canonical.iter().filter(|byte| **byte == b'\n').count() + 1
        );
        assert_metrics(&name, &file, &canonical);
    }
}

/// The metrics on generated documents (test plan section 3): every accepted document as a
/// whole, then each plane alone with an empty body, where its directive line (DirLen) sets
/// R, and the frontmatter alone, where its longest line sets R.
#[test]
fn metrics_equal_the_canonical_text_on_generated_documents() {
    let mut random = Random(0x6d65_7472);
    let total = volume(100_000);
    let mut accepted = 0;
    let mut isolated = 0;
    let mut by_kind = [0_usize; 2];
    for index in 0..total {
        let generated = index % 2 == 0;
        let mut document = if generated {
            generated_document(&mut random)
        } else {
            focused_document(&mut random)
        };
        if random.chance(0.3) {
            with_numbers(&mut random, &mut document);
        }
        let Ok(file) = binary(&document) else {
            continue;
        };
        accepted += 1;
        by_kind[usize::from(generated)] += 1;
        let canonical = text(&document).unwrap();
        assert_metrics(&format!("#{index} {document:?}"), &file, &canonical);
        let mut parts: Vec<Document> = document
            .planes
            .iter()
            .map(|plane| Document {
                version: "1".into(),
                axis: String::new(),
                title: None,
                metadata: BTreeMap::new(),
                preamble: None,
                planes: vec![Plane {
                    body: String::new(),
                    ..plane.clone()
                }],
            })
            .collect();
        parts.push(Document {
            preamble: None,
            planes: Vec::new(),
            ..document.clone()
        });
        for part in parts {
            let file = binary(&part).unwrap();
            let canonical = text(&part).unwrap();
            assert_metrics(&format!("#{index} part {part:?}"), &file, &canonical);
            isolated += 1;
        }
    }
    eprintln!(
        "metrics, seed 0x6d657472: {accepted} of {total} accepted ({} focused, {} generated), \
         {isolated} parts",
        by_kind[0], by_kind[1]
    );
    assert!(accepted * 20 > total, "only {accepted} of {total} accepted");
}

#[test]
fn g6_kind_2_sizes_match_sizes_json() {
    let sizes = json("conformance/structured/sizes.json");
    let expected: BTreeMap<String, (u64, u64)> = sizes["perFile"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| {
            (
                entry["file"].as_str().unwrap().to_owned(),
                (
                    entry["canonical"].as_u64().unwrap(),
                    entry["kind2"].as_u64().unwrap(),
                ),
            )
        })
        .collect();
    let (mut canonical_total, mut kind2_total) = (0_u64, 0_u64);
    let examples = examples();
    assert_eq!(examples.len(), expected.len());
    for (name, source) in examples {
        let document = decode(&source).unwrap();
        let canonical = text(&document).unwrap().len() as u64;
        let kind2 = binary(&document).unwrap().len() as u64;
        assert_eq!(expected[&name], (canonical, kind2), "{name}");
        assert!(kind2 <= canonical, "{name}");
        canonical_total += canonical;
        kind2_total += kind2;
    }
    assert_eq!(
        canonical_total,
        sizes["examples"]["canonical"].as_u64().unwrap()
    );
    assert_eq!(kind2_total, sizes["examples"]["kind2"].as_u64().unwrap());
    assert!(kind2_total as f64 <= 0.98 * canonical_total as f64);
    // The two generated inputs, when `THREEMD_BENCH_INPUTS` names the directory that
    // `scripts/bench/generate-{synthetic,sculpt}.mjs --out` wrote.
    if let Some(directory) = std::env::var_os("THREEMD_BENCH_INPUTS") {
        for (file, key, ratio) in [
            ("synthetic-2000.3md", "synthetic-2000", 0.995),
            ("sculpt-4096.3md", "sculpt-4096-32x20", 0.98),
        ] {
            let source = fs::read(Path::new(&directory).join(file)).unwrap();
            let document = decode(&source).unwrap();
            let canonical = text(&document).unwrap().len() as u64;
            let kind2 = binary(&document).unwrap().len() as u64;
            assert_eq!(
                canonical,
                sizes["large"][key]["canonical"].as_u64().unwrap()
            );
            assert_eq!(kind2, sizes["large"][key]["kind2"].as_u64().unwrap());
            assert!(kind2 as f64 <= ratio * canonical as f64, "{file}");
        }
    }
}

// MARK: - Keys, numbers and Unicode (test plan sections 2 and 3)

const KEY_POOL: &[&str] = &[
    "a",
    "b",
    "B",
    "z",
    "e\u{301}",
    "\u{e9}",
    "K",
    "\u{212a}",
    "k",
    "\u{c5}",
    "\u{212b}",
    "A\u{30a}",
    "\u{ff61}",
    "\u{1F600}",
    "\u{ffff}",
    "\u{10000}",
    "\u{e000}",
    "\u{7f}",
    "\u{80}",
    "\u{1e0b}\u{323}",
    "\u{1e0d}\u{307}",
    "d\u{323}\u{307}",
    "q",
    "\u{fb01}",
    "fi",
];

#[test]
fn keys_are_written_in_byte_order_and_equivalent_spellings_are_rejected() {
    let mut random = Random(0x6b65_7973);
    for _ in 0..volume(4_000) {
        let count = random.between(1, 5);
        let keys: Vec<&str> = (0..count).map(|_| *random.pick(KEY_POOL)).collect();
        let source = Document {
            metadata: keys.iter().map(|key| ((*key).into(), "v".into())).collect(),
            ..document(vec![plane(0.0, "")])
        };
        let mut forms = std::collections::HashSet::new();
        let mut equivalent = false;
        for key in source.metadata.keys() {
            use unicode_normalization::UnicodeNormalization;
            equivalent |= !forms.insert(key.nfc().collect::<String>());
        }
        let result = binary(&source);
        assert_eq!(
            matches!(result, Err(DocumentStorageError::InvalidDocument(_))),
            equivalent,
            "{keys:?} {result:?}"
        );
        assert_eq!(
            result.is_ok(),
            storage::validate(&source, &limits(), &options()).is_ok()
        );
        let Ok(file) = result else {
            continue;
        };
        // Stored order is raw byte order, which is code point order and not UTF-16 order.
        let stored: Vec<&String> = source.metadata.keys().collect();
        for pair in stored.windows(2) {
            assert!(pair[0].as_bytes() < pair[1].as_bytes());
            assert!(pair[0].chars().lt(pair[1].chars()));
        }
        assert_eq!(decode(&file).as_ref(), Ok(&source));
        // Swapping the first two stored keys is not canonical.
        if stored.len() >= 2 {
            let first = [&[stored[0].len() as u8][..], stored[0].as_bytes(), b"\x01v"].concat();
            let second = [&[stored[1].len() as u8][..], stored[1].as_bytes(), b"\x01v"].concat();
            let mut swapped = file[40..].to_vec();
            let start = 5;
            assert_eq!(&swapped[start..start + first.len()], first.as_slice());
            swapped.splice(
                start..start + first.len() + second.len(),
                [second.clone(), first.clone()].concat(),
            );
            assert_eq!(
                decode(&container(&swapped)),
                Err(DocumentStorageError::InvalidContainer),
                "{keys:?}"
            );
        }
    }
}

#[test]
fn number_forms_round_trip_bit_exactly_and_spell_canonically() {
    let mut random = Random(0x6e75_6d73);
    let mut bits = || {
        let high = (random.next() * 4_294_967_296.0) as u64;
        let low = (random.next() * 4_294_967_296.0) as u64;
        (high << 32) | low
    };
    let mut values: Vec<f64> = NUMBERS.iter().chain(EXTRA_NUMBERS).copied().collect();
    for exponent in -1074..=1023 {
        values.push(2_f64.powi(exponent));
        values.push(-(2_f64.powi(exponent)));
    }
    while values.len() < 2_200 + volume(10_000) {
        let value = f64::from_bits(bits());
        if value.is_finite() {
            values.push(value);
        }
    }
    let expected_form = |value: f64| {
        if value.trunc() == value && (-134_217_728.0..=134_217_727.0).contains(&value) {
            1
        } else if f64::from(value as f32) == value {
            2
        } else {
            3
        }
    };
    for (index, chunk) in values.chunks(64).enumerate() {
        let source = document(
            chunk
                .iter()
                .enumerate()
                .map(|(offset, value)| Plane {
                    x: Some(*value),
                    ..plane(offset as f64, "")
                })
                .collect(),
        );
        let file = binary(&source).unwrap();
        let decoded = decode(&file).unwrap();
        for (plane, value) in decoded.planes.iter().zip(chunk) {
            let expected = if *value == 0.0 { 0.0 } else { *value };
            assert_eq!(
                plane.x.map(f64::to_bits),
                Some(expected.to_bits()),
                "#{index}"
            );
        }
        // The x form occupies bits 2 and 3 of the first plane's flags (payload offset 6).
        let first = if chunk[0] == 0.0 { 0.0 } else { chunk[0] };
        assert_eq!((file[46] >> 2) & 3, expected_form(first), "{first:e}");
    }
    // The canonical spelling (P8) parses back exactly and uses the shortest digits.
    for value in values.iter().step_by(7) {
        let mut source = document(vec![plane(*value, "")]);
        source.planes[0].z = *value;
        let canonical = String::from_utf8(text(&source).unwrap()).unwrap();
        let spelled = canonical
            .lines()
            .find_map(|line| line.strip_prefix("@plane z="))
            .unwrap();
        let parsed: f64 = spelled.parse().unwrap();
        let expected = if *value == 0.0 { 0.0 } else { *value };
        assert_eq!(parsed.to_bits(), expected.to_bits(), "{spelled}");
        let digits = |text: &str| {
            let mantissa = text.split(['e', 'E']).next().unwrap();
            mantissa
                .trim_start_matches('-')
                .replace('.', "")
                .trim_start_matches('0')
                .trim_end_matches('0')
                .len()
        };
        if expected.abs() >= 1e15 || expected.fract() != 0.0 {
            assert_eq!(
                digits(spelled),
                digits(&format!("{expected:e}")),
                "{spelled}"
            );
        }
    }
}

#[test]
fn unicode_skew_vectors_follow_this_toolchains_data() {
    // Recorded with Rust 1.95 and unicode-normalization 0.1.25, both Unicode 17.0 data. Both
    // code point groups were assigned in Unicode 16.0,
    // so the results hold for any toolchain with at least that data. They are outside the
    // Unicode 13.0 cross-port set and never appear in the shared vectors (SPEC.md 11.3.15).
    assert!(
        char::UNICODE_VERSION >= (16, 0, 0),
        "{:?}",
        char::UNICODE_VERSION
    );
    assert!(unicode_normalization::UNICODE_VERSION >= (16, 0, 0));
    // U+0897 (combining class 230) after U+0316 (220) is the reordered form of the reverse.
    let skew = Document {
        metadata: map(&[("a\u{316}\u{897}", "1"), ("a\u{897}\u{316}", "2")]),
        ..document(vec![plane(0.0, "")])
    };
    assert!(matches!(
        binary(&skew),
        Err(DocumentStorageError::InvalidDocument(_))
    ));
    // The Garay case pair: the capital letter fails R9, the small letter passes.
    let attribute = |key: &str| Document {
        planes: vec![Plane {
            attributes: map(&[(key, "v")]),
            ..plane(0.0, "")
        }],
        ..document(vec![])
    };
    assert!(matches!(
        binary(&attribute("k\u{10d50}")),
        Err(DocumentStorageError::InvalidDocument(_))
    ));
    let small = attribute("k\u{10d70}");
    let file = binary(&small).unwrap();
    assert_eq!(decode(&file), Ok(small));
}

// MARK: - Compositions and resolver (SPEC.md 11.5 and 12)

#[test]
fn compositions_accept_kind_1_and_2_envelopes_and_refuse_kind_3() {
    let source = read("Examples/Extensions/shared-grove.3md");
    let graph = composition::decode(&source, &graph_limits(), &limits(), &options()).unwrap();
    let envelope = composition::document(&graph, &graph_limits(), &limits(), &options()).unwrap();
    let kind2 = binary(&envelope).unwrap();
    let kind1 =
        storage::encode_text_container(&envelope, DocumentCompression::None, &limits(), &options())
            .unwrap();
    assert_eq!(
        kind2,
        read("Examples/Extensions/shared-grove.structured.3mdb")
    );
    for file in [&kind1, &kind2] {
        assert_eq!(
            composition::decode(file, &graph_limits(), &limits(), &options()).as_ref(),
            Ok(&graph)
        );
    }
    let mut kind3 = kind2.clone();
    kind3[10] = 3;
    assert_eq!(
        composition::decode(&kind3, &graph_limits(), &limits(), &options()),
        Err(composition::DocumentCompositionError::Storage(
            DocumentStorageError::UnsupportedPayloadKind(3)
        ))
    );
    let child = |data: Vec<u8>| threemd::DocumentFileSource {
        path: "child.3mdb".into(),
        data,
    };
    let mut parent = decode(&read("Examples/Extensions/canopy.3md")).unwrap();
    parent
        .metadata
        .insert("3md-files".into(), r#"{"1":"child.3mdb"}"#.into());
    let parent = threemd::DocumentFileSource {
        path: "root.3md".into(),
        data: text(&parent).unwrap(),
    };
    let leaf = document(vec![plane(0.0, "Leaf")]);
    for data in [binary(&leaf).unwrap(), {
        storage::encode_text_container(&leaf, DocumentCompression::None, &limits(), &options())
            .unwrap()
    }] {
        let resolved = threemd::file_composition::resolve(
            "root.3md",
            &[parent.clone(), child(data)],
            &graph_limits(),
            &limits(),
            &options(),
        );
        assert!(resolved.is_ok(), "{resolved:?}");
    }
    let mut refused = binary(&leaf).unwrap();
    refused[10] = 3;
    assert_eq!(
        threemd::file_composition::resolve(
            "root.3md",
            &[parent, child(refused)],
            &graph_limits(),
            &limits(),
            &options(),
        )
        .map(|_| ()),
        Err(threemd::DocumentFileCompositionError::Storage(
            DocumentStorageError::UnsupportedPayloadKind(3)
        ))
    );
}

// MARK: - Cancellation and concurrency (test plan section 5)

#[test]
fn cancellation_returns_no_value_and_leaves_inputs_reusable() {
    let token = CancellationToken::new();
    let cancelled = OperationOptions::with_cancellation(token.clone());
    token.cancel();
    let source = worked("document");
    let file = binary(&source).unwrap();
    assert_eq!(
        storage::decode(&file, &limits(), &cancelled),
        Err(DocumentStorageError::Cancelled)
    );
    for compression in [DocumentCompression::None, DocumentCompression::Lzfse] {
        assert_eq!(
            storage::encode(
                &source,
                DocumentStorageFormat::Binary(compression),
                &limits(),
                &cancelled
            ),
            Err(DocumentStorageError::Cancelled)
        );
    }
    assert_eq!(
        storage::encode_text_container(&source, DocumentCompression::None, &limits(), &cancelled),
        Err(DocumentStorageError::Cancelled)
    );
    // Invalid limits are reported before cancellation, as in 2.0.
    assert_eq!(
        storage::decode(
            &file,
            &DocumentDecodeLimits {
                maximum_lines: 0,
                ..limits()
            },
            &cancelled
        ),
        Err(DocumentStorageError::InvalidLimits)
    );
    // A helper thread cancels a large decode and a large encode while they run. Each
    // operation is retried with a shorter delay if it finished first; the deterministic
    // per-check cancellation tests live with the reader's unit tests.
    let large = document(
        (0..7)
            .map(|z| plane(f64::from(z), &"x".repeat(8 * 1024 * 1024 - 64)))
            .collect(),
    );
    let large_file = binary(&large).unwrap();
    for encode in [false, true] {
        let cancelled = [2_u64, 1, 0, 0, 0].iter().any(|delay| {
            let token = CancellationToken::new();
            let operation_options = OperationOptions::with_cancellation(token.clone());
            let start = std::sync::Barrier::new(2);
            std::thread::scope(|scope| {
                scope.spawn(|| {
                    start.wait();
                    std::thread::sleep(std::time::Duration::from_millis(*delay));
                    token.cancel();
                });
                start.wait();
                let result = if encode {
                    storage::encode(
                        &large,
                        DocumentStorageFormat::Binary(DocumentCompression::None),
                        &limits(),
                        &operation_options,
                    )
                    .map(|_| ())
                } else {
                    storage::decode(&large_file, &limits(), &operation_options).map(|_| ())
                };
                assert!(matches!(
                    result,
                    Ok(()) | Err(DocumentStorageError::Cancelled)
                ));
                result.is_err()
            })
        });
        assert!(cancelled, "encode: {encode}");
    }
    assert_eq!(decode(&large_file).as_ref(), Ok(&large));
}

#[test]
fn new_types_are_send_and_sync_and_codecs_run_from_32_threads() {
    fn assert_send_sync<Value: Send + Sync>() {}
    assert_send_sync::<DocumentContainerInfo>();
    assert_send_sync::<DocumentStorageError>();
    assert_send_sync::<Document>();
    assert_send_sync::<OperationOptions>();
    let mut random = Random(0x3232);
    let documents: Vec<Document> = (0..32)
        .map(|_| loop {
            let candidate = focused_document(&mut random);
            if binary(&candidate).is_ok() {
                break candidate;
            }
        })
        .collect();
    let expected: Vec<Vec<u8>> = documents
        .iter()
        .map(|document| binary(document).unwrap())
        .collect();
    std::thread::scope(|scope| {
        let handles: Vec<_> = documents
            .iter()
            .zip(&expected)
            .map(|(document, bytes)| {
                scope.spawn(move || {
                    for _ in 0..50 {
                        assert_eq!(binary(document).as_ref(), Ok(bytes));
                        assert_eq!(
                            decode(bytes).map(|decoded| normalized(&decoded)),
                            Ok(normalized(document))
                        );
                    }
                })
            })
            .collect();
        for handle in handles {
            handle.join().unwrap();
        }
    });
}

#[test]
fn segment_rules_agree_with_the_text_round_trip_on_random_bodies() {
    let mut random = Random(0x5e67_0001);
    let mut accepted = 0;
    let total = volume(100_000);
    for index in 0..total {
        let segment = if index % 2 == 0 {
            generated_segment(&mut random)
        } else {
            focused_segment(&mut random)
        };
        let mut source = document(vec![plane(0.0, "first"), plane(1.0, "last")]);
        match index % 3 {
            0 => source.preamble = Some(segment.clone()),
            1 => source.planes[0].body = segment.clone(),
            _ => source.planes[1].body = segment.clone(),
        }
        let validated = storage::validate(&source, &limits(), &options());
        let encoded = binary(&source);
        assert_eq!(
            validated.is_ok(),
            encoded.is_ok(),
            "role {} {segment:?}: {validated:?} {encoded:?}",
            index % 3
        );
        if let Ok(file) = encoded {
            accepted += 1;
            assert_eq!(decode(&file).as_ref(), Ok(&source), "{segment:?}");
        }
    }
    assert!(accepted * 10 > total, "{accepted} of {total}");
}
