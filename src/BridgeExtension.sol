// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@zkevm/interfaces/IBridgeMessageReceiver.sol";
import "@zkevm/PolygonZkEVMBridge.sol";

import {JumpPoint} from "./JumpPoint.sol";

contract BridgeExtension is IBridgeMessageReceiver, Ownable {
    using SafeERC20 for IERC20;

    PolygonZkEVMBridge public immutable bridge;

    /// @notice The counterparty network, i.e. network that this instance interacts with.
    uint32 public immutable counterpartyNetwork;

    /// @notice Address of the BridgeExtension in the counterparty network.
    address public counterpartyExtension;

    constructor(
        address owner_,
        address bridge_,
        uint32 cpNetwork
    ) Ownable(owner_) {
        require(bridge_ != address(0), "INVALID_BRIDGE");

        bridge = PolygonZkEVMBridge(bridge_);
        counterpartyNetwork = cpNetwork;
    }

    /// @notice Setter for `counterpartyExtension`.
    function setCounterpartyExtension(address cpExtension) external onlyOwner {
        counterpartyExtension = cpExtension;
    }

    /// @notice Bridge and call from this function.
    function bridgeAndCall(
        address token,
        uint256 amount,
        bytes calldata permitData,
        uint32 destinationNetwork,
        address callAddress,
        bytes calldata callData,
        bool forceUpdateGlobalExitRoot
    ) external payable {
        // transfer assets from caller to this extension
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // calculate the depends on index based on the number of bridgeAssets we're doing
        uint256 dependsOnIndex = bridge.depositCount() + 1;

        // allow the bridge to take the assets
        IERC20(token).approve(address(bridge), amount);

        // pre-compute the address of the JumpPoint contract so we can bridge the assets
        address jumpPointAddr = _computeJumpPointAddress(
            counterpartyExtension,
            dependsOnIndex,
            token,
            callAddress,
            callData
        );
        // bridge the assets
        bridge.bridgeAsset(
            destinationNetwork,
            jumpPointAddr,
            amount,
            token,
            forceUpdateGlobalExitRoot,
            permitData
        );

        // assert that the index is correct - avoid any potential reentrancy caused by bridgeAsset
        require(dependsOnIndex == bridge.depositCount(), "INVALID_INDEX");

        // bridge the message (which gets encoded with extra data)
        bytes memory encodedMsg = abi.encode(
            dependsOnIndex,
            callAddress,
            token,
            callData
        );
        bridge.bridgeMessage(
            destinationNetwork,
            counterpartyExtension,
            forceUpdateGlobalExitRoot,
            encodedMsg
        );
    }

    /// @dev Helper function to pre-compute the jumppoint address (the contract pseudo-deployed using create2).
    function _computeJumpPointAddress(
        address deployer,
        uint256 dependsOnIndex,
        address originAssetAddress,
        address callAddress,
        bytes memory callData
    ) internal view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(JumpPoint).creationCode,
            abi.encode(
                address(bridge),
                bridge.networkID(), // current network
                originAssetAddress,
                callAddress,
                callData
            )
        );

        // precompute address that will be the receiver of the assets
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer, // deployer = counterparty bridge extension OR "this"
                bytes32(dependsOnIndex), // salt = the depends on index
                keccak256(bytecode)
            )
        );
        // cast last 20 bytes of hash to address
        return address(uint160(uint(hash)));
    }

    /// @notice `IBridgeMessageReceiver`'s callback. This is only executed if `bridgeAndCall`'s
    /// `destinationAddressMessage` is the BridgeExtension (in the destination network).
    function onMessageReceived(
        address originAddress,
        uint32 originNetwork,
        bytes calldata data
    ) external payable {
        require(msg.sender == address(bridge), "NOT_BRIDGE");
        require(originNetwork == counterpartyNetwork, "INVALID_NETWORK");
        require(originAddress == counterpartyExtension, "INVALID_ADDRESS");

        // decode the index for bridgeAsset, and check that it has been claimed
        (
            uint256 dependsOnIndex,
            address callAddress,
            address originAssetAddress,
            bytes memory callData
        ) = abi.decode(data, (uint256, address, address, bytes));
        require(bridge.isClaimed(dependsOnIndex), "UNCLAIMED_ASSET");

        // the remaining bytes have the selector+args
        new JumpPoint{salt: bytes32(dependsOnIndex)}(
            address(bridge),
            originNetwork,
            originAssetAddress,
            callAddress,
            callData
        );
    }
}
