//! CRC-32/ISO-HDLC (reflected polynomial `0xEDB88320`, initial value and final XOR
//! `0xFFFFFFFF`) with compile-time slicing-by-16 tables, shared by payload kinds 1 and 2.
use crate::storage::{DocumentStorageError, OperationOptions};

/// Payload bytes processed between two cancellation checks (SPEC.md 11.3.13).
const CHECK_INTERVAL: usize = 65_536;

/// The sixteen slicing tables; `TABLES[0]` is the bytewise table.
static TABLES: [[u32; 256]; 16] = tables();

const fn tables() -> [[u32; 256]; 16] {
    let mut table = [[0_u32; 256]; 16];
    let mut index = 0;
    while index < 256 {
        let mut value = index as u32;
        let mut bit = 0;
        while bit < 8 {
            value = if value & 1 != 0 {
                (value >> 1) ^ 0xEDB8_8320
            } else {
                value >> 1
            };
            bit += 1;
        }
        table[0][index] = value;
        index += 1;
    }
    let mut index = 0;
    while index < 256 {
        let mut slice = 1;
        while slice < 16 {
            let previous = table[slice - 1][index];
            table[slice][index] = (previous >> 8) ^ table[0][(previous & 0xff) as usize];
            slice += 1;
        }
        index += 1;
    }
    table
}

#[inline]
fn word(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes([
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
        bytes[offset + 3],
    ])
}

/// One slicing-by-16 step: folds 16 bytes into the raw register.
#[inline(always)]
fn step(crc: u32, chunk: &[u8]) -> u32 {
    let t = &TABLES;
    let a = word(chunk, 0) ^ crc;
    let b = word(chunk, 4);
    let c = word(chunk, 8);
    let d = word(chunk, 12);
    t[15][(a & 0xff) as usize]
        ^ t[14][((a >> 8) & 0xff) as usize]
        ^ t[13][((a >> 16) & 0xff) as usize]
        ^ t[12][(a >> 24) as usize]
        ^ t[11][(b & 0xff) as usize]
        ^ t[10][((b >> 8) & 0xff) as usize]
        ^ t[9][((b >> 16) & 0xff) as usize]
        ^ t[8][(b >> 24) as usize]
        ^ t[7][(c & 0xff) as usize]
        ^ t[6][((c >> 8) & 0xff) as usize]
        ^ t[5][((c >> 16) & 0xff) as usize]
        ^ t[4][(c >> 24) as usize]
        ^ t[3][(d & 0xff) as usize]
        ^ t[2][((d >> 8) & 0xff) as usize]
        ^ t[1][((d >> 16) & 0xff) as usize]
        ^ t[0][(d >> 24) as usize]
}

/// Slicing-by-16 over one stream, then bytewise over the last 0 to 15 bytes.
fn update_single(mut crc: u32, data: &[u8]) -> u32 {
    let (chunks, remainder) = data.as_chunks::<16>();
    for chunk in chunks {
        crc = step(crc, chunk);
    }
    for &byte in remainder {
        crc = (crc >> 8) ^ TABLES[0][((crc ^ u32::from(byte)) & 0xff) as usize];
    }
    crc
}

const POLYNOMIAL: u32 = 0xEDB8_8320;

/// Multiplies two polynomials modulo the CRC polynomial, in the reflected representation
/// where bit 31 is `x^0`. Branch-free, 32 steps.
const fn multiply(a: u32, mut b: u32) -> u32 {
    let mut product = 0_u32;
    let mut bit = 0;
    while bit < 32 {
        product ^= b & 0_u32.wrapping_sub((a >> (31 - bit)) & 1);
        b = (b >> 1) ^ (POLYNOMIAL & 0_u32.wrapping_sub(b & 1));
        bit += 1;
    }
    product
}

/// `x^(8 * bytes)` modulo the CRC polynomial: appending `bytes` zero bytes to a message
/// multiplies its raw register by this value.
const fn shift(bytes: usize) -> u32 {
    let mut exponent = bytes as u64 * 8;
    let mut result = 1_u32 << 31;
    let mut square = 1_u32 << 30;
    while exponent != 0 {
        if exponent & 1 != 0 {
            result = multiply(square, result);
        }
        square = multiply(square, square);
        exponent >>= 1;
    }
    result
}

/// Two-stream lane lengths, largest first, with their precomputed shift operators. Half a
/// cancellation chunk is the largest lane, and 256 bytes the smallest worth interleaving.
const LANES: [(usize, u32); 8] = {
    let mut lanes = [(0_usize, 0_u32); 8];
    let mut index = 0;
    while index < 8 {
        let lane = (CHECK_INTERVAL / 2) >> index;
        lanes[index] = (lane, shift(lane));
        index += 1;
    }
    lanes
};

/// Advances the raw (non-inverted) CRC register over `data`.
///
/// While at least two lanes remain, two interleaved slicing-by-16 streams run over equal
/// halves and are joined with `U(r, A || B) = U(r, A) * x^(8 |B|) XOR U(0, B)`; the rest
/// runs as one stream. The value equals the single-stream loop's.
pub(crate) fn update(mut crc: u32, mut data: &[u8]) -> u32 {
    for (lane, operator) in LANES {
        while data.len() >= 2 * lane {
            let (first, rest) = data.split_at(lane);
            let (second, tail) = rest.split_at(lane);
            let mut right = 0_u32;
            let (first_blocks, _) = first.as_chunks::<16>();
            let (second_blocks, _) = second.as_chunks::<16>();
            for (a, b) in first_blocks.iter().zip(second_blocks) {
                crc = step(crc, a);
                right = step(right, b);
            }
            crc = multiply(operator, crc) ^ right;
            data = tail;
        }
    }
    update_single(crc, data)
}

/// The container checksum: header bytes `0..<36`, then the encoded payload. Cancellation is
/// checked before every 65,536 payload bytes and after the last one.
pub(crate) fn container(
    header: &[u8],
    payload: &[u8],
    options: &OperationOptions,
) -> Result<u32, DocumentStorageError> {
    let mut crc = update(u32::MAX, header);
    for chunk in payload.chunks(CHECK_INTERVAL) {
        options.check()?;
        crc = update(crc, chunk);
    }
    options.check()?;
    Ok(crc ^ u32::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bytewise(data: &[u8]) -> u32 {
        let mut crc = u32::MAX;
        for &byte in data {
            crc ^= u32::from(byte);
            for _ in 0..8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & 0_u32.wrapping_sub(crc & 1));
            }
        }
        crc ^ u32::MAX
    }

    #[test]
    fn check_value_matches_the_specification() {
        assert_eq!(update(u32::MAX, b"123456789") ^ u32::MAX, 0xCBF4_3926);
        assert_eq!(update(u32::MAX, b"") ^ u32::MAX, 0);
        assert_eq!(
            container(b"1234", b"56789", &OperationOptions::default()),
            Ok(0xCBF4_3926)
        );
    }

    #[test]
    fn slicing_matches_the_bytewise_reference_at_every_alignment() {
        let mut state = 0x3d3d_2101_u64;
        let mut next = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        let mut storage = vec![0_u8; 3_000 + 16];
        for round in 0..10_000 {
            for byte in &mut storage[..316] {
                *byte = next() as u8;
            }
            let length = (next() % 301) as usize;
            let offset = round % 16;
            let data = &storage[offset..offset + length];
            assert_eq!(update(u32::MAX, data) ^ u32::MAX, bytewise(data));
            let split = (next() as usize) % (length + 1);
            assert_eq!(
                update(update(u32::MAX, &data[..split]), &data[split..]) ^ u32::MAX,
                bytewise(data)
            );
        }
        // Two-stream lengths, including the full-chunk lane and odd tails.
        for byte in &mut storage {
            *byte = next() as u8;
        }
        for length in (500..3_000)
            .step_by(7)
            .chain([4_095, 8_193, 40_000, 65_535, CHECK_INTERVAL])
        {
            let data: Vec<u8> = (0..length)
                .map(|index| storage[index % storage.len()])
                .collect();
            assert_eq!(
                update(u32::MAX, &data) ^ u32::MAX,
                bytewise(&data),
                "{length}"
            );
        }
        assert_eq!(shift(0), 1 << 31);
        // x^8 * x^8 is x^16, and multiplying by x^0 is the identity.
        assert_eq!(multiply(shift(1), shift(1)), shift(2));
        assert_eq!(multiply(1 << 31, 0x1234_5678), 0x1234_5678);
        assert_eq!(LANES[0].0, CHECK_INTERVAL / 2);
        assert_eq!(LANES[7].0, 256);
    }
}
