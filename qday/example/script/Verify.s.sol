// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PqcVerify} from "../PqcVerify.sol";

interface Vm {
    function envOr(string calldata name, address defaultValue) external view returns (address);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
    function envBytes(string calldata name) external view returns (bytes memory);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Broadcasts `PqcVerify.verifyAndEmit` against a deployed wrapper.
///
/// Load params from `.env` (written by `genvector.go`): PQC_VERIFY, ALG,
/// PUBKEY, SIGNATURE, MESSAGE.
///
/// Foundry's local EVM does not implement PQCVERIFY (`0x1000`), so the inner
/// precompile call fails during script collection. The call is sent with a
/// low-level `call` so the revert is not bubbled; the real node executes it.
/// Use `--broadcast --skip-simulation`.
contract VerifyScript {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant DEFAULT_PQC_VERIFY = 0x610178dA211FEF7D417bC0e6FeD39F05609AD788;

    function run() external {
        address target = vm.envOr("PQC_VERIFY", DEFAULT_PQC_VERIFY);
        uint64 alg = uint64(vm.envOr("ALG", uint256(2))); // ML-DSA-65
        bytes memory data = abi.encodeWithSelector(
            PqcVerify.verifyAndEmit.selector,
            alg,
            vm.envBytes("PUBKEY"),
            vm.envBytes("SIGNATURE"),
            vm.envBytes("MESSAGE")
        );

        vm.startBroadcast();
        (bool ok,) = target.call(data);
        vm.stopBroadcast();
        ok; // local Foundry has no 0x1000; success is the on-chain receipt
    }
}
