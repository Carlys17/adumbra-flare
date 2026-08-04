/// MEV-Safe FXRP Swap Router — TEE Service
///
/// This binary runs inside a Trusted Execution Environment (e.g. Intel SGX
/// or AWS Nitro Enclave). It receives swap intents from the wallet UI,
/// calculates the optimal multi-hop route privately, signs the resulting
/// order with the enclave's attested key, and returns the signed order.
///
/// The route details never leave the enclave — MEV bots only see the final
/// on-chain transaction which reveals `(tokenIn, tokenOut, amountIn, minAmountOut)`.
use clap::Parser;
use k256::ecdsa::SigningKey;
use serde::{Deserialize, Serialize};
use sha3::{Digest, Keccak256};

/// A swap intent coming from the wallet UI.
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct SwapIntent {
    user: String,
    /// token symbol used for rate lookup, e.g. "FXRP"
    symbol_in: String,
    symbol_out: String,
    /// actual on-chain token addresses (hex)
    token_in: String,
    token_out: String,
    /// input amount in wei (decimal string)
    amount_in: String,
    /// slippage tolerance in basis points, e.g. 50 = 0.5%
    slippage_bps: u16,
    /// on-chain nonce (optional — CLI takes nonce from flag, HTTP from body)
    #[serde(default)]
    nonce: Option<u64>,
}

/// The signed order that goes on-chain (matches MEVSwapRouter.SwapOrder).
#[derive(Debug, Serialize)]
struct SignedSwapOrder {
    user: String,
    token_in: String,
    token_out: String,
    /// wei
    amount_in: String,
    /// wei
    min_amount_out: String,
    deadline: u64,
    order_nonce: String,
    /// ECDSA signature (r || s || v) over the Keccak256 digest, hex-encoded
    signature: String,
    /// Informational only: what the TEE did (never on-chain)
    #[serde(rename = "tee_report")]
    tee_report: String,
}

/// Simulate fetching the best price from multiple DEX pools.
/// In production this queries real Flare AMMs (e.g. SparkDEX, BlazeSwap).
fn simulate_best_rate(symbol_in: &str, symbol_out: &str) -> f64 {
    match (symbol_in, symbol_out) {
        // hardcoded dev rates — replace with live oracle/quoter queries
        ("FXRP", "USDC") => 0.52,
        ("FXRP", "ETH") => 0.00015,
        ("USDC", "FXRP") => 1.92,
        _ => 0.01,
    }
}

fn parse_addr(s: &str) -> anyhow::Result<[u8; 20]> {
    let bytes = hex::decode(s.trim_start_matches("0x"))?;
    anyhow::ensure!(bytes.len() == 20, "address must be 20 bytes");
    let mut out = [0u8; 20];
    out.copy_from_slice(&bytes);
    Ok(out)
}

/// Reproduce the exact on-chain digest:
/// keccak256(abi.encode("MEVSwap", user, tokenIn, tokenOut, amountIn, minAmountOut, deadline, orderNonce))
fn build_digest(
    user: [u8; 20],
    token_in: [u8; 20],
    token_out: [u8; 20],
    amount_in: u128,
    min_amount_out: u128,
    deadline: u64,
    order_nonce: u64,
) -> [u8; 32] {
    let mut buf = Vec::with_capacity(320);

    // Word 0: offset to the dynamic string = 8 * 32 = 0x100
    let mut w = [0u8; 32];
    w[30] = 0x01; // big-endian: 0x0100 = 256
    buf.extend_from_slice(&w);

    // Addresses (left-padded to 32 bytes)
    for a in [user, token_in, token_out] {
        let mut w = [0u8; 32];
        w[12..].copy_from_slice(&a);
        buf.extend_from_slice(&w);
    }

    // uint256 fields (big-endian, 32 bytes)
    for v in [
        amount_in,
        min_amount_out,
        deadline as u128,
        order_nonce as u128,
    ] {
        let mut w = [0u8; 32];
        w[16..].copy_from_slice(&v.to_be_bytes());
        buf.extend_from_slice(&w);
    }

    // String length word
    let mut w = [0u8; 32];
    w[31] = 7;
    buf.extend_from_slice(&w);

    // String data ("MEVSwap", right-padded to 32 bytes)
    let mut w = [0u8; 32];
    w[..7].copy_from_slice(b"MEVSwap");
    buf.extend_from_slice(&w);

    Keccak256::digest(&buf).into()
}

/// Sign a swap intent and return a signed order.  The nonce is provided
/// externally (either from the CLI flag or the request body) so the same
/// function can be used by both one-shot and server modes.
fn sign_intent(
    intent: &SwapIntent,
    signing_key: &SigningKey,
    deadline: u64,
    nonce: u64,
) -> anyhow::Result<SignedSwapOrder> {
    let rate = simulate_best_rate(&intent.symbol_in, &intent.symbol_out);
    let amount_in: u128 = intent.amount_in.parse()?;
    let expected_out = amount_in as f64 * rate;
    let min_amount_out =
        (expected_out * (1.0 - intent.slippage_bps as f64 / 10000.0)) as u128;

    let deadline = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs()
        + deadline;

    let user = parse_addr(&intent.user)?;
    let token_in = parse_addr(&intent.token_in)?;
    let token_out = parse_addr(&intent.token_out)?;

    let digest = build_digest(user, token_in, token_out, amount_in, min_amount_out, deadline, nonce);

    let (sig, recid) = signing_key.sign_prehash_recoverable(&digest)?;
    let sig_bytes = sig.to_bytes();
    let r = hex::encode(&sig_bytes[0..32]);
    let s = hex::encode(&sig_bytes[32..64]);
    let v = recid.to_byte() + 27;

    let signer_pubkey = signing_key.verifying_key();
    let encoded = signer_pubkey.to_encoded_point(false);
    let pubkey_hex = hex::encode(&encoded.as_bytes()[1..]);
    let signer_short = format!("0x{}", &pubkey_hex[0..10]);

    Ok(SignedSwapOrder {
        user: intent.user.clone(),
        token_in: intent.token_in.clone(),
        token_out: intent.token_out.clone(),
        amount_in: amount_in.to_string(),
        min_amount_out: min_amount_out.to_string(),
        deadline,
        order_nonce: nonce.to_string(),
        signature: format!("0x{r}{s}{v:02x}"),
        tee_report: format!(
            "Enclave {s} routed {sym_in} -> {sym_out} at rate {rate:.6}",
            s = signer_short,
            sym_in = intent.symbol_in,
            sym_out = intent.symbol_out,
            rate = rate
        ),
    })
}

/// CLI arguments
#[derive(Parser)]
#[command(about = "MEV-Safe FXRP Swap - TEE signing service")]
struct Cli {
    /// Path to a JSON file containing SwapIntent, or "-" for stdin
    #[arg(short, long, default_value = "-")]
    intent: String,

    /// Enclave private key hex (dev-only; production: SGX/Nitro attestation key)
    #[arg(long, env = "ENCLAVE_KEY")]
    enclave_key: String,

    /// Deadline offset in seconds from now
    #[arg(long, default_value = "3600")]
    deadline: u64,

    /// Current on-chain nonce
    #[arg(long, default_value = "0")]
    nonce: u64,

    /// Start HTTP server on port 7070 instead of one-shot CLI mode
    #[arg(long)]
    serve: bool,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    let key_bytes = hex::decode(cli.enclave_key.trim_start_matches("0x"))?;
    let signing_key = SigningKey::from_slice(&key_bytes)?;

    if cli.serve {
        run_server(&signing_key, cli.deadline)
    } else {
        run_oneshot(&cli, &signing_key)
    }
}

fn run_oneshot(cli: &Cli, signing_key: &SigningKey) -> anyhow::Result<()> {
    let intent: SwapIntent = if cli.intent == "-" {
        serde_json::from_reader(std::io::stdin())?
    } else {
        serde_json::from_str(&std::fs::read_to_string(&cli.intent)?)?
    };

    let order = sign_intent(&intent, signing_key, cli.deadline, cli.nonce)?;
    println!("{}", serde_json::to_string_pretty(&order)?);
    Ok(())
}

fn run_server(signing_key: &SigningKey, deadline_offset: u64) -> anyhow::Result<()> {
    let addr = "0.0.0.0:7070";
    let server =
        tiny_http::Server::http(addr).map_err(|e| anyhow::anyhow!("failed to bind {addr}: {e}"))?;
    eprintln!("TEE signing server listening on http://{addr}");

    for mut request in server.incoming_requests() {
        let is_options = request.method() == &tiny_http::Method::Options;

        let cors_header = tiny_http::Header::from_bytes(
            &b"Access-Control-Allow-Origin"[..],
            &b"*"[..],
        )
        .unwrap();

        if is_options {
            let response = tiny_http::Response::from_string("")
                .with_status_code(204)
                .with_header(cors_header)
                .with_header(
                    tiny_http::Header::from_bytes(
                        &b"Access-Control-Allow-Methods"[..],
                        &b"POST, OPTIONS"[..],
                    )
                    .unwrap(),
                )
                .with_header(
                    tiny_http::Header::from_bytes(
                        &b"Access-Control-Allow-Headers"[..],
                        &b"Content-Type"[..],
                    )
                    .unwrap(),
                );
            request.respond(response)?;
            continue;
        }

        // Only respond to POST /sign
        if request.method() != &tiny_http::Method::Post || request.url() != "/sign" {
            let response = tiny_http::Response::from_string("Not Found")
                .with_status_code(404)
                .with_header(cors_header);
            request.respond(response)?;
            continue;
        }

        let mut body = String::new();
        request.as_reader().read_to_string(&mut body)?;

        match serde_json::from_str::<SwapIntent>(&body) {
            Ok(intent) => {
                let nonce = intent.nonce.unwrap_or(0);
                match sign_intent(&intent, signing_key, deadline_offset, nonce) {
                    Ok(order) => {
                        let payload = serde_json::to_string(&order)?;
                        let response = tiny_http::Response::from_string(payload)
                            .with_status_code(200)
                            .with_header(cors_header)
                            .with_header(
                                tiny_http::Header::from_bytes(
                                    &b"Content-Type"[..],
                                    &b"application/json"[..],
                                )
                                .unwrap(),
                            );
                        request.respond(response)?;
                    }
                    Err(e) => {
                        let msg =
                            serde_json::json!({"error": format!("signing failed: {e}")}).to_string();
                        let response = tiny_http::Response::from_string(msg)
                            .with_status_code(500)
                            .with_header(cors_header)
                            .with_header(
                                tiny_http::Header::from_bytes(
                                    &b"Content-Type"[..],
                                    &b"application/json"[..],
                                )
                                .unwrap(),
                            );
                        request.respond(response)?;
                    }
                }
            }
            Err(e) => {
                let msg = serde_json::json!({"error": format!("invalid JSON: {e}")}).to_string();
                let response = tiny_http::Response::from_string(msg)
                    .with_status_code(400)
                    .with_header(cors_header)
                    .with_header(
                        tiny_http::Header::from_bytes(
                            &b"Content-Type"[..],
                            &b"application/json"[..],
                        )
                        .unwrap(),
                    );
                request.respond(response)?;
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_digest_deterministic() {
        let u = [1u8; 20];
        let d1 = build_digest(u, [2u8; 20], [3u8; 20], 100, 99, 3601, 0);
        let d2 = build_digest(u, [2u8; 20], [3u8; 20], 100, 99, 3601, 0);
        assert_eq!(d1, d2);
    }

    #[test]
    fn test_digest_changes_with_amount() {
        let u = [1u8; 20];
        let d1 = build_digest(u, [2u8; 20], [3u8; 20], 100, 99, 3601, 0);
        let d2 = build_digest(u, [2u8; 20], [3u8; 20], 101, 99, 3601, 0);
        assert_ne!(d1, d2);
    }
}