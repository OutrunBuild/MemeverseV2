// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {IGovernanceCycleIncentivizer} from "./IGovernanceCycleIncentivizer.sol";

/**
 * @title MemecoinDaoGovernor interface
 */
interface IMemecoinDaoGovernor {
    struct MemecoinDaoGovernorStorage {
        IGovernanceCycleIncentivizer _governanceCycleIncentivizer;
        mapping(address => uint256) userUnfinalizedProposalId;
    }

    /**
     * @notice Initializes governor parameters and binds the cycle incentivizer.
     * @dev Called once during verse deployment; wires governance token and quorum configuration.
     * @param _name Governor name used in proposal domain metadata.
     * @param _token Voting power token implementing IVotes.
     * @param _votingDelay Delay between proposal creation and vote start.
     * @param _votingPeriod Voting duration measured in governor timepoints.
     * @param _proposalThreshold Minimum votes required to create proposals.
     * @param _quorumNumerator Quorum numerator used by governor quorum math.
     * @param _governanceCycleIncentivizer Incentivizer contract address paired to this governor.
     */
    function initialize(
        string calldata _name,
        IVotes _token,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumNumerator,
        address _governanceCycleIncentivizer
    ) external;

    /**
     * @notice Returns the paired governance cycle incentivizer address.
     * @dev Incentivizer receives treasury and voting accounting callbacks from governor flows.
     * @return Incentivizer contract address.
     */
    function governanceCycleIncentivizer() external view returns (address);

    /**
     * @notice Records treasury income received by governor-controlled flows.
     * @dev Expected to forward accounting updates into the incentivizer ledger.
     * @param token Treasury token address received.
     * @param amount Amount received for treasury accounting.
     */
    function receiveTreasuryIncome(address token, uint256 amount) external;

    /**
     * @notice Sends treasury assets and records the corresponding spend.
     * @dev Enforces governance-controlled payout semantics before token transfer.
     * @param token Treasury token address spent.
     * @param to Recipient address.
     * @param amount Amount transferred from treasury custody.
     */
    function sendTreasuryAssets(address token, address to, uint256 amount) external;

    /// @notice Disburse user rewards from governor custody.
    /// @dev Only the paired incentivizer may call this payout path.
    /// @param token Reward token being transferred.
    /// @param to Reward recipient.
    /// @param amount Reward amount to transfer.
    function disburseReward(address token, address to, uint256 amount) external;

    error UserHasUnfinalizedProposal();

    error UnauthorizedRewardPayout();
}
