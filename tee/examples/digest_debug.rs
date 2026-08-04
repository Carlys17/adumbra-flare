fn main() {
    // replicate build_digest from main.rs
    use sha3::{Digest, Keccak256};
    let mut buf = Vec::with_capacity(320);
    let mut w = [0u8; 32];
    w[30] = 0x01;
    buf.extend_from_slice(&w);
    for a in [[1u8; 20], [2u8; 20], [3u8; 20]] {
        let mut w = [0u8; 32];
        w[12..].copy_from_slice(&a);
        buf.extend_from_slice(&w);
    }
    for v in [100u128, 99u128, 3601u128, 0u128] {
        let mut w = [0u8; 32];
        w[16..].copy_from_slice(&v.to_be_bytes());
        buf.extend_from_slice(&w);
    }
    let mut w = [0u8; 32];
    w[31] = 7;
    buf.extend_from_slice(&w);
    let mut w = [0u8; 32];
    w[..7].copy_from_slice(b"MEVSwap");
    buf.extend_from_slice(&w);
    println!("{}", hex::encode(Keccak256::digest(&buf)));
}
