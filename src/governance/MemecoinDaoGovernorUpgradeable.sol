// SPDX-License-Identifier: GPL-3.0
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {
    GovernorVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {
    GovernorStorageUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorStorageUpgradeable.sol";
import {
    GovernorSettingsUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {
    GovernorCountingFractionalUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingFractionalUpgradeable.sol";
import {
    GovernorVotesQuorumFractionUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";

import {OutrunSafeERC20} from "../yield/libraries/OutrunSafeERC20.sol";
import {IVotes, IMemecoinDaoGovernor, IGovernanceCycleIncentivizer} from "./interfaces/IMemecoinDaoGovernor.sol";

/**
 * @title Memecoin DAO Governor
 * @notice This contract is a modified version of the GovernorUpgradeable contract from OpenZeppelin.
 * @dev It is used to manage the DAO of the Memecoin project, also as Memecoin DAO Treasury.
 */
contract MemecoinDaoGovernorUpgradeable is
    IMemecoinDaoGovernor,
    Initializable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingFractionalUpgradeable,
    GovernorStorageUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    UUPSUpgradeable
{
    using OutrunSafeERC20 for IERC20;

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.MemecoinDaoGovernor")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MemecoinDaoGovernorStorageLocation =
        0x173bbd0db440ff8dcb0efb05aced4279e21e45a07b4974973a371552ef840a00;

    function _getMemecoinDaoGovernorStorage() private pure returns (MemecoinDaoGovernorStorage storage $) {
        assembly {
            $.slot := MemecoinDaoGovernorStorageLocation
        }
    }

    function __MemecoinDaoGovernor_init(address _governanceCycleIncentivizer) internal onlyInitializing {
        MemecoinDaoGovernorStorage storage $ = _getMemecoinDaoGovernorStorage();
        $._governanceCycleIncentivizer = IGovernanceCycleIncentivizer(_governanceCycleIncentivizer);
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the governor.
     * @dev Wires the OpenZeppelin governor mixins and stores the incentivizer address.
     * @param _name - The name of the governor.
     * @param _token - The vote token of the governor.
     * @param _votingDelay - The voting delay.
     * @param _votingPeriod - The voting period.
     * @param _proposalThreshold - The proposal threshold.
     * @param _quorumNumerator - The quorum numerator.
     * @param _governanceCycleIncentivizer - The governanceCycleIncentivizer.
     */
    function initialize(
        string memory _name,
        IVotes _token,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumNumerator,
        address _governanceCycleIncentivizer
    ) external override initializer {
        __Governor_init(_name);
        __GovernorSettings_init(_votingDelay, _votingPeriod, _proposalThreshold);
        __GovernorCountingFractional_init();
        __GovernorStorage_init();
        __GovernorVotes_init(_token);
        __GovernorVotesQuorumFraction_init(_quorumNumerator);
        __MemecoinDaoGovernor_init(_governanceCycleIncentivizer);
    }

    /// @notice Returns the configured voting delay.
    /// @dev Delegates to the OpenZeppelin governor settings implementation.
    /// @return The voting delay in clock units.
    function votingDelay() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingDelay();
    }

    /// @notice Returns the configured voting period.
    /// @dev Delegates to the OpenZeppelin governor settings implementation.
    /// @return The voting period in clock units.
    function votingPeriod() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingPeriod();
    }

    /// @notice Returns the quorum required at a given block number.
    /// @dev Delegates to the quorum-fraction governor extension.
    /// @param blockNumber The block number used for the quorum snapshot.
    /// @return The required quorum amount.
    function quorum(uint256 blockNumber)
        public
        view
        override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    /// @notice Returns the configured proposal threshold.
    /// @dev Delegates to the OpenZeppelin governor settings implementation.
    /// @return The minimum voting power required to propose.
    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    /// @notice Returns the configured governance cycle incentivizer.
    /// @dev Exposes the incentivizer address stored in governor-specific storage.
    /// @return The incentivizer contract address.
    function governanceCycleIncentivizer() external view override returns (address) {
        return address(_getMemecoinDaoGovernorStorage()._governanceCycleIncentivizer);
    }

    /// @notice Creates a new governance proposal for the caller.
    /// @dev Prevents a proposer from opening a new proposal while a previous one is still unresolved.
    /// @param targets The call targets for the proposal actions.
    /// @param values The ETH values for the proposal actions.
    /// @param calldatas The calldata payloads for the proposal actions.
    /// @param description The proposal description.
    /// @return proposalId The created proposal identifier.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        // Restrict each address from submitting new proposals while it has unfinalized proposal
        MemecoinDaoGovernorStorage storage $ = _getMemecoinDaoGovernorStorage();
        uint256 unfinalizedProposalId = $.userUnfinalizedProposalId[msg.sender];
        require(
            unfinalizedProposalId == 0 || state(unfinalizedProposalId) == ProposalState.Defeated,
            UserHasUnfinalizedProposal()
        );

        uint256 proposalId = super.propose(targets, values, calldatas, description);
        $.userUnfinalizedProposalId[msg.sender] = proposalId;

        return proposalId;
    }

    /// @notice Executes a queued proposal and clears the proposer's outstanding proposal marker.
    /// @dev Delegates execution to OpenZeppelin governor core before updating local bookkeeping.
    /// @param targets The proposal action targets.
    /// @param values The ETH values for the proposal actions.
    /// @param calldatas The calldata payloads for the proposal actions.
    /// @param descriptionHash The hash of the proposal description.
    /// @return proposalId The executed proposal identifier.
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable override returns (uint256) {
        uint256 proposalId = super.execute(targets, values, calldatas, descriptionHash);

        _getMemecoinDaoGovernorStorage().userUnfinalizedProposalId[proposalProposer(proposalId)] = 0;

        return proposalId;
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override returns (uint256) {
        uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);

        _getMemecoinDaoGovernorStorage().userUnfinalizedProposalId[proposalProposer(proposalId)] = 0;

        return proposalId;
    }

    /**
     * @notice Receives treasury income for the DAO treasury.
     * @dev Notifies the incentivizer before pulling the tokens into the governor treasury.
     * @param _token - The token address
     * @param _amount - The amount
     */
    function receiveTreasuryIncome(address _token, uint256 _amount) external override {
        IGovernanceCycleIncentivizer _governanceCycleIncentivizer =
        _getMemecoinDaoGovernorStorage()._governanceCycleIncentivizer;
        _governanceCycleIncentivizer.receiveTreasuryIncome(_token, _amount);

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice Transfers treasury assets to another address through governance.
     * @dev Notifies the incentivizer before sending the tokens from the governor treasury. All actions to transfer
     * treasury assets from the DAO treasury must use this entrypoint.
     * @param _token - The token address
     * @param _to - The receiver address
     * @param _amount - The amount to transfer
     */
    function sendTreasuryAssets(address _token, address _to, uint256 _amount) external override onlyGovernance {
        IGovernanceCycleIncentivizer _governanceCycleIncentivizer =
        _getMemecoinDaoGovernorStorage()._governanceCycleIncentivizer;
        _governanceCycleIncentivizer.sendTreasuryAssets(_token, _to, _amount);

        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override(GovernorUpgradeable, GovernorStorageUpgradeable) returns (uint256) {
        return super._propose(targets, values, calldatas, description, proposer);
    }

    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        override
        returns (uint256)
    {
        uint256 votes = super._castVote(proposalId, account, support, reason, params);
        _getMemecoinDaoGovernorStorage()._governanceCycleIncentivizer.accumCycleVotes(account, votes);
        return votes;
    }

    /**
     * @dev Allowing upgrades to the implementation contract only through governance proposals.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}
}
