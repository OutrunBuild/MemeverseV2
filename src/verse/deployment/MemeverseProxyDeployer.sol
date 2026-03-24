// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IMemeverseProxyDeployer} from "../interfaces/IMemeverseProxyDeployer.sol";
import {IMemecoinDaoGovernor} from "../../governance/interfaces/IMemecoinDaoGovernor.sol";
import {IGovernanceCycleIncentivizer} from "../../governance/interfaces/IGovernanceCycleIncentivizer.sol";

/**
 * @title MemeverseProxyDeployer Contract
 */
contract MemeverseProxyDeployer is IMemeverseProxyDeployer, Ownable {
    using Clones for address;

    address public immutable memeverseLauncher;
    address public immutable memecoinImplementation;
    address public immutable polImplementation;
    address public immutable vaultImplementation;
    address public immutable governorImplementation;
    address public immutable incentivizerImplementation;

    uint256 public quorumNumerator;

    modifier onlyMemeverseLauncher() {
        _onlyMemeverseLauncher();
        _;
    }

    function _onlyMemeverseLauncher() internal view {
        require(msg.sender == memeverseLauncher, PermissionDenied());
    }

    constructor(
        address _owner,
        address _memeverseLauncher,
        address _memecoinImplementation,
        address _polImplementation,
        address _vaultImplementation,
        address _governorImplementation,
        address _incentivizerImplementation,
        uint256 _quorumNumerator
    ) Ownable(_owner) {
        memeverseLauncher = _memeverseLauncher;
        memecoinImplementation = _memecoinImplementation;
        polImplementation = _polImplementation;
        vaultImplementation = _vaultImplementation;
        governorImplementation = _governorImplementation;
        incentivizerImplementation = _incentivizerImplementation;
        quorumNumerator = _quorumNumerator;
    }

    /// @notice Predicts where the verse yield vault will be deployed.
    /// @dev Uses the same clone salt and implementation as `deployYieldVault`.
    /// @param uniqueId Verse identifier used as the clone salt.
    /// @return Predicted yield-vault clone address.
    function predictYieldVaultAddress(uint256 uniqueId) external view override returns (address) {
        return vaultImplementation.predictDeterministicAddress(keccak256(abi.encode(uniqueId)));
    }

    /// @notice Predicts where the verse governor and incentivizer proxies will be deployed.
    /// @dev Uses the same Create2 salts and proxy bytecode as `deployGovernorAndIncentivizer`.
    /// @param uniqueId Verse identifier used as the Create2 salt.
    /// @return governor Predicted governor proxy address.
    /// @return incentivizer Predicted incentivizer proxy address.
    function computeGovernorAndIncentivizerAddress(uint256 uniqueId)
        external
        view
        override
        returns (address governor, address incentivizer)
    {
        governor = Create2.computeAddress(
            keccak256(abi.encode(uniqueId)),
            keccak256(abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(governorImplementation, bytes(""))))
        );

        incentivizer = Create2.computeAddress(
            keccak256(abi.encode(uniqueId)),
            keccak256(
                abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(incentivizerImplementation, bytes("")))
            )
        );
    }

    /// @notice Deploys the memecoin clone for a verse.
    /// @dev Restricted to the launcher so each verse is provisioned only through the protocol flow.
    /// @param uniqueId Verse identifier used as the clone salt.
    /// @return memecoin Newly deployed memecoin clone address.
    function deployMemecoin(uint256 uniqueId) external override onlyMemeverseLauncher returns (address memecoin) {
        memecoin = memecoinImplementation.cloneDeterministic(keccak256(abi.encode(uniqueId)));

        emit DeployMemecoin(uniqueId, memecoin);
    }

    /// @notice Deploys the POL clone for a verse.
    /// @dev Restricted to the launcher.
    /// @param uniqueId Verse identifier used as the clone salt.
    /// @return pol Newly deployed POL clone address.
    function deployPOL(uint256 uniqueId) external override onlyMemeverseLauncher returns (address pol) {
        pol = polImplementation.cloneDeterministic(keccak256(abi.encode(uniqueId)));

        emit DeployPOL(uniqueId, pol);
    }

    /// @notice Deploys the yield-vault clone for a verse.
    /// @dev Restricted to the launcher.
    /// @param uniqueId Verse identifier used as the clone salt.
    /// @return yieldVault Newly deployed yield-vault clone address.
    function deployYieldVault(uint256 uniqueId) external override onlyMemeverseLauncher returns (address yieldVault) {
        yieldVault = vaultImplementation.cloneDeterministic(keccak256(abi.encode(uniqueId)));

        emit DeployYieldVault(uniqueId, yieldVault);
    }

    /// @notice Deploys and initializes the verse governor together with its cycle incentivizer.
    /// @dev Both proxies are deployed deterministically from `uniqueId`, then initialized with the freshly deployed
    /// verse token contracts and the current quorum configuration.
    /// @param memecoinName Human-readable memecoin name used to derive the DAO name.
    /// @param UPT Verse fundraising token.
    /// @param memecoin Verse memecoin contract.
    /// @param pol Verse POL contract.
    /// @param yieldVault Verse yield-vault contract.
    /// @param uniqueId Verse identifier used as the Create2 salt.
    /// @param proposalThreshold Minimum voting power required to propose.
    /// @return governor Newly deployed governor proxy address.
    /// @return incentivizer Newly deployed incentivizer proxy address.
    function deployGovernorAndIncentivizer(
        string calldata memecoinName,
        address UPT,
        address memecoin,
        address pol,
        address yieldVault,
        uint256 uniqueId,
        uint256 proposalThreshold
    ) external override onlyMemeverseLauncher returns (address governor, address incentivizer) {
        // Deploy
        governor = Create2.deploy(
            0,
            keccak256(abi.encode(uniqueId)),
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(governorImplementation, bytes("")))
        );
        incentivizer = Create2.deploy(
            0,
            keccak256(abi.encode(uniqueId)),
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(incentivizerImplementation, bytes("")))
        );

        // Initialize
        IMemecoinDaoGovernor(governor)
            .initialize(
                string(abi.encodePacked(memecoinName, " DAO")),
                IVotes(yieldVault),
                1 days,
                1 weeks,
                proposalThreshold,
                quorumNumerator,
                incentivizer
            );
        address[] memory initFundTokens = new address[](4);
        initFundTokens[0] = UPT;
        initFundTokens[1] = memecoin;
        initFundTokens[2] = pol;
        initFundTokens[3] = yieldVault;
        IGovernanceCycleIncentivizer(incentivizer).initialize(governor, initFundTokens);

        emit DeployGovernorAndIncentivizer(uniqueId, governor, incentivizer);
    }

    /// @notice Updates the quorum numerator used for future governor deployments.
    /// @dev Does not retroactively modify already deployed governors.
    /// @param _quorumNumerator New quorum numerator basis points.
    function setQuorumNumerator(uint256 _quorumNumerator) external override onlyOwner {
        require(_quorumNumerator != 0, ZeroInput());

        quorumNumerator = _quorumNumerator;

        emit SetQuorumNumerator(_quorumNumerator);
    }
}
