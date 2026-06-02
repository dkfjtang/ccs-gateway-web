use base64::Engine;
use minisign_verify::{PublicKey, Signature};
use std::{env, fs, process};

fn decode_base64_to_string(label: &str, value: &str) -> Result<String, String> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(value.trim())
        .map_err(|err| format!("{label} is not valid base64: {err}"))?;
    String::from_utf8(bytes).map_err(|err| format!("{label} is not valid UTF-8: {err}"))
}

fn run() -> Result<(), String> {
    let args = env::args().collect::<Vec<_>>();
    if args.len() != 4 {
        return Err(format!(
            "usage: {} <artifact-path> <signature-path> <updater-pubkey>",
            args.first()
                .map(String::as_str)
                .unwrap_or("verify_updater_signature")
        ));
    }

    let artifact = fs::read(&args[1])
        .map_err(|err| format!("failed to read updater artifact '{}': {err}", args[1]))?;
    let signature_base64 = fs::read_to_string(&args[2])
        .map_err(|err| format!("failed to read updater signature '{}': {err}", args[2]))?;
    let pubkey = decode_base64_to_string("updater pubkey", &args[3])?;
    let signature = decode_base64_to_string("updater signature", &signature_base64)?;

    let public_key =
        PublicKey::decode(&pubkey).map_err(|err| format!("invalid updater pubkey: {err}"))?;
    let signature =
        Signature::decode(&signature).map_err(|err| format!("invalid updater signature: {err}"))?;
    public_key
        .verify(&artifact, &signature, true)
        .map_err(|err| format!("updater signature verification failed: {err}"))?;

    println!("updater_signature=valid");
    Ok(())
}

fn main() {
    if let Err(err) = run() {
        eprintln!("{err}");
        process::exit(1);
    }
}
