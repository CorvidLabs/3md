//! Peak heap of payload kind 2 decoding for the 64 MiB worst cases of the ThreeMD 2.1 test
//! plan (section 5): the reader must stay under four times the input. This file holds a single
//! test so that no concurrent test disturbs the counting allocator.
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering};
use threemd::storage::{self, DocumentDecodeLimits, DocumentStorageError, OperationOptions};

struct Counting;

static CURRENT: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);

fn grow(bytes: usize) {
    let now = CURRENT.fetch_add(bytes, Ordering::Relaxed) + bytes;
    PEAK.fetch_max(now, Ordering::Relaxed);
}

// SAFETY: every call forwards to the system allocator with the caller's arguments unchanged;
// the wrapper only counts bytes.
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // SAFETY: forwarded unchanged.
        let pointer = unsafe { System.alloc(layout) };
        if !pointer.is_null() {
            grow(layout.size());
        }
        pointer
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // SAFETY: forwarded unchanged.
        let pointer = unsafe { System.alloc_zeroed(layout) };
        if !pointer.is_null() {
            grow(layout.size());
        }
        pointer
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        // SAFETY: forwarded unchanged.
        unsafe { System.dealloc(pointer, layout) };
        CURRENT.fetch_sub(layout.size(), Ordering::Relaxed);
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        // SAFETY: forwarded unchanged.
        let result = unsafe { System.realloc(pointer, layout, new_size) };
        if !result.is_null() {
            CURRENT.fetch_sub(layout.size(), Ordering::Relaxed);
            grow(new_size);
        }
        result
    }
}

#[global_allocator]
static ALLOCATOR: Counting = Counting;

/// Heap bytes allocated at the peak of `operation`, above what was live before it.
fn peak_during<Value>(operation: impl FnOnce() -> Value) -> (Value, usize) {
    let baseline = CURRENT.load(Ordering::Relaxed);
    PEAK.store(baseline, Ordering::Relaxed);
    let value = operation();
    (value, PEAK.load(Ordering::Relaxed) - baseline)
}

fn var(output: &mut Vec<u8>, mut value: usize) {
    while value >= 0x80 {
        output.push((value & 0x7f) as u8 | 0x80);
        value >>= 7;
    }
    output.push(value as u8);
}

/// A kind-2 file: header, then `payload`, with resealed lengths and CRC.
fn container(payload: Vec<u8>) -> Vec<u8> {
    let mut file = b"3mdbin\r\n\x01\x00\x02\x00".to_vec();
    file.resize(40, 0);
    let length = payload.len() as u64;
    file[20..28].copy_from_slice(&length.to_le_bytes());
    file[28..36].copy_from_slice(&length.to_le_bytes());
    let table: [u32; 256] = std::array::from_fn(|index| {
        (0..8).fold(index as u32, |crc, _| {
            (crc >> 1) ^ (0xEDB8_8320 & 0_u32.wrapping_sub(crc & 1))
        })
    });
    let crc = file[..36]
        .iter()
        .chain(&payload)
        .fold(u32::MAX, |crc, &byte| {
            (crc >> 8) ^ table[((crc ^ u32::from(byte)) & 0xff) as usize]
        });
    file[36..40].copy_from_slice(&(!crc).to_le_bytes());
    file.extend_from_slice(&payload);
    file
}

#[test]
fn kind_2_decoding_stays_under_four_times_the_input() {
    // A 64 MiB sample of the reader's memory behavior. It is not a library size ceiling.
    let limits = DocumentDecodeLimits {
        maximum_encoded_bytes: 64 * 1024 * 1024,
        maximum_decoded_bytes: 64 * 1024 * 1024,
        maximum_lines: 100_000,
        maximum_planes: 65_536,
        maximum_record_bytes: 8 * 1024 * 1024,
    };
    let options = OperationOptions::default();
    let budget = limits.maximum_encoded_bytes - 40;

    // One plane with as many 7-byte attribute keys as fit the 64 MiB container.
    let count = (budget - 16) / 9;
    let mut payload = vec![0x00, 0x01, b'1', 0x00, 0x00, 0x01, 0x01, 0x00];
    var(&mut payload, count);
    let mut key = *b"aaaaaaa";
    for _ in 0..count {
        payload.push(7);
        payload.extend_from_slice(&key);
        payload.push(0);
        for digit in key.iter_mut().rev() {
            if *digit == b'z' {
                *digit = b'a';
            } else {
                *digit += 1;
                break;
            }
        }
    }
    payload.push(0);
    let file = container(payload);
    assert!(file.len() <= limits.maximum_encoded_bytes);
    let started = std::time::Instant::now();
    let (result, peak) = peak_during(|| storage::decode(&file, &limits, &options));
    eprintln!(
        "attributes: decoded in {:?}, peak {peak}",
        started.elapsed()
    );
    assert_eq!(result, Err(DocumentStorageError::OversizedRecord));
    assert!(
        peak < 3 * file.len(),
        "attributes: {peak} for {}",
        file.len()
    );

    // The same with keys that are not NFC (`e` + U+0301 and 4 printable ASCII bytes), so P7a
    // checks the whole map for canonically equivalent keys before L3 rejects the directive.
    // With `equivalent`, the first two keys are the equivalent pair a+U+0301+U+0316 and
    // a+U+0316+U+0301, and the check must find it without keeping every key's NFC form.
    // The check keeps one hash slot per key, so peak over input is the same at any size whose
    // key count sits just past a power-of-two table boundary, as both of these do (2.25 times
    // in hash slots). Debug builds use the 8 MiB size, because NFC is slow unoptimized.
    let scaled = if cfg!(debug_assertions) {
        8 * 1024 * 1024 - 40
    } else {
        budget
    };
    for equivalent in [false, true] {
        let mut keys: Vec<Vec<u8>> = Vec::new();
        if equivalent {
            keys.push("a\u{301}\u{316}".as_bytes().to_vec());
            keys.push("a\u{316}\u{301}".as_bytes().to_vec());
        }
        let count = (scaled - 16) / 9;
        let mut suffix = [b'!'; 4];
        while keys.len() < count {
            let mut key = "e\u{301}".as_bytes().to_vec();
            key.extend_from_slice(&suffix);
            keys.push(key);
            for digit in suffix.iter_mut().rev() {
                if *digit == b'~' {
                    *digit = b'!';
                } else {
                    *digit += 1;
                    break;
                }
            }
        }
        let mut payload = vec![0x00, 0x01, b'1', 0x00, 0x00, 0x01, 0x01, 0x00];
        var(&mut payload, keys.len());
        for key in &keys {
            var(&mut payload, key.len());
            payload.extend_from_slice(key);
            payload.push(0);
        }
        payload.push(0);
        drop(keys);
        let file = container(payload);
        assert!(file.len() <= limits.maximum_encoded_bytes);
        let started = std::time::Instant::now();
        let (result, peak) = peak_during(|| storage::decode(&file, &limits, &options));
        eprintln!(
            "attributes, not NFC, equivalent {equivalent}: decoded in {:?}, peak {peak}",
            started.elapsed()
        );
        let expected = if equivalent {
            Err(DocumentStorageError::InvalidDocument(
                "Canonically equivalent dictionary keys cannot be represented faithfully.".into(),
            ))
        } else {
            Err(DocumentStorageError::OversizedRecord)
        };
        assert_eq!(result, expected);
        assert!(
            peak < 3 * file.len(),
            "attributes, not NFC, equivalent {equivalent}: {peak} for {}",
            file.len()
        );
    }

    // The most planes a container can declare, each with a one-line body: Phase S keeps one
    // small view per plane, and L4 rejects the canonical text before anything is built.
    let planes = limits.maximum_planes;
    let body = budget / planes - 8;
    let mut payload = vec![0x00, 0x01, b'1', 0x00, 0x00];
    var(&mut payload, planes);
    for z in 0..planes {
        payload.push(0x01);
        var(&mut payload, z << 1);
        payload.push(0);
        var(&mut payload, body);
        payload.resize(payload.len() + body, b'x');
    }
    let file = container(payload);
    assert!(file.len() <= limits.maximum_encoded_bytes);
    let (result, peak) = peak_during(|| storage::decode(&file, &limits, &options));
    assert_eq!(result, Err(DocumentStorageError::OversizedOutput));
    assert!(peak < 3 * file.len(), "planes: {peak} for {}", file.len());

    // One 8 MiB body, decoded into its document.
    let body = limits.maximum_record_bytes;
    let mut payload = vec![0x00, 0x01, b'1', 0x00, 0x00, 0x01, 0x01, 0x00, 0x00];
    var(&mut payload, body);
    payload.resize(payload.len() + body, b'x');
    let file = container(payload);
    let (result, peak) = peak_during(|| storage::decode(&file, &limits, &options));
    assert_eq!(
        result.map(|document| document.planes[0].body.len()),
        Ok(body)
    );
    assert!(peak < 3 * file.len(), "body: {peak} for {}", file.len());
}
