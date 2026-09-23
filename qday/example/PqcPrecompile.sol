// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title QDay PQCVERIFY precompile helpers
/// @notice Calls the post-quantum signature verifier at address `0x1000`.
///
/// Input layout (no length prefixes):
///     alg (8 bytes, big-endian uint64) || pubkey || signature || message
///
/// pubkey and signature lengths are fixed per algorithm; message is the remainder.
/// Success returns 32-byte left-padded `0x01`; invalid/malformed input returns empty.
library PqcPrecompile {
    address internal constant VERIFY = address(0x1000);

    uint64 internal constant ALG_MLDSA44 = 1;
    uint64 internal constant ALG_MLDSA65 = 2;
    uint64 internal constant ALG_MLDSA87 = 3;
    uint64 internal constant ALG_FALCON512 = 7;
    uint64 internal constant ALG_FALCON1024 = 8;
    uint64 internal constant ALG_FALCON_PADDED512 = 9;
    uint64 internal constant ALG_FALCON_PADDED1024 = 10;

    uint256 internal constant MLDSA44_PK_LEN = 1312;
    uint256 internal constant MLDSA44_SIG_LEN = 2420;
    uint256 internal constant MLDSA65_PK_LEN = 1952;
    uint256 internal constant MLDSA65_SIG_LEN = 3309;
    uint256 internal constant MLDSA87_PK_LEN = 2592;
    uint256 internal constant MLDSA87_SIG_LEN = 4627;
    uint256 internal constant FALCON512_PK_LEN = 897;
    uint256 internal constant FALCON512_SIG_LEN = 666;
    uint256 internal constant FALCON1024_PK_LEN = 1793;
    uint256 internal constant FALCON1024_SIG_LEN = 1280;

    /// @notice Verify a PQC signature via the precompile.
    /// @param alg Algorithm id (see `ALG_*` constants).
    /// @param pubkey Raw public key bytes (fixed length per `alg`).
    /// @param signature Raw signature bytes (fixed length per `alg`).
    /// @param message Signed message (arbitrary length, including empty).
    function verify(uint64 alg, bytes memory pubkey, bytes memory signature, bytes memory message)
        internal
        view
        returns (bool)
    {
        return verifyRaw(abi.encodePacked(alg, pubkey, signature, message));
    }

    /// @notice Call `0x1000` with a pre-encoded payload:
    /// `alg (uint64 BE) || pubkey || signature || message`.
    function verifyRaw(bytes memory input) internal view returns (bool valid) {
        address target = VERIFY;
        assembly ("memory-safe") {
            mstore(0x00, 0)
            let ok := staticcall(gas(), target, add(input, 0x20), mload(input), 0x00, 0x20)
            valid := and(ok, eq(mload(0x00), 1))
        }
    }
}
