// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PqcPrecompile} from "./PqcPrecompile.sol";

/// @title Deployable wrapper around the PQCVERIFY precompile (`0x1000`)
/// @notice Use `verify` / `verifyRaw` from another contract or via `eth_call`.
contract PqcVerify {
    error InvalidPqcSignature();

    event PqcVerified(uint64 indexed alg, bool valid);

    function verify(uint64 alg, bytes calldata pubkey, bytes calldata signature, bytes calldata message)
        external
        view
        returns (bool)
    {
        return PqcPrecompile.verify(alg, pubkey, signature, message);
    }

    function verifyRaw(bytes calldata input) external view returns (bool) {
        return PqcPrecompile.verifyRaw(input);
    }

    /// @notice Same as {verify}, but reverts when the signature is invalid.
    function requireValid(uint64 alg, bytes calldata pubkey, bytes calldata signature, bytes calldata message)
        external
        view
    {
        if (!PqcPrecompile.verify(alg, pubkey, signature, message)) {
            revert InvalidPqcSignature();
        }
    }

    /// @notice On-chain verification that emits {PqcVerified} (for a real tx, not just `eth_call`).
    function verifyAndEmit(uint64 alg, bytes calldata pubkey, bytes calldata signature, bytes calldata message)
        external
        returns (bool valid)
    {
        valid = PqcPrecompile.verify(alg, pubkey, signature, message);
        emit PqcVerified(alg, valid);
    }
}
