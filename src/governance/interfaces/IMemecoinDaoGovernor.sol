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
        uint256 _minQuorum;
        uint256 _governanceStartTime;
        uint256 _maxTreasurySpendRatio;
        uint256 _upgradeSupermajorityRatio;
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
     * @param _minQuorum Absolute minimum quorum floor based on total supply.
     * @param _bootstrapPeriod Delay after deployment before proposals are accepted.
     */
    function initialize(
        string calldata _name,
        IVotes _token,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumNumerator,
        address _governanceCycleIncentivizer,
        uint256 _minQuorum,
        uint256 _bootstrapPeriod,
        uint256 _maxTreasurySpendRatio,
        uint256 _upgradeSupermajorityRatio
    ) external;

    /**
     * @notice Returns the paired governance cycle incentivizer address.
     * @return Incentivizer contract address.
     */
    function governanceCycleIncentivizer() external view returns (address);

    /**
     * @notice Returns the absolute minimum quorum floor.
     * @return Minimum quorum in vote units.
     */
    function minQuorum() external view returns (uint256);

    /**
     * @notice Returns the timestamp when governance proposals become active.
     * @return Start timestamp for governance.
     */
    function governanceStartTime() external view returns (uint256);

    function maxTreasurySpendRatio() external view returns (uint256);

    function upgradeSupermajorityRatio() external view returns (uint256);

    /**
     * @notice Records treasury income received by governor-controlled flows.
     * @param token Treasury token address received.
     * @param amount Amount received for treasury accounting.
     */
    function receiveTreasuryIncome(address token, uint256 amount) external;

    /**
     * @notice Sends treasury assets and records the corresponding spend.
     * @param token Treasury token address spent.
     * @param to Recipient address.
     * @param amount Amount transferred from treasury custody.
     */
    function sendTreasuryAssets(address token, address to, uint256 amount) external;

    /// @notice Disburse user rewards from governor custody.
    /// @param token Reward token being transferred.
    /// @param to Reward recipient.
    /// @param amount Reward amount to transfer.
    function disburseReward(address token, address to, uint256 amount) external;

    error UserHasUnfinalizedProposal();
    error UnauthorizedRewardPayout();
    error GovernanceNotStarted();
    error InvalidGovernanceParams();
    error TreasurySpendExceedsLimit(address token, uint256 spent, uint256 limit);
    error UpgradeSupermajorityRequired(uint256 forVotes, uint256 totalVotes, uint256 requiredRatio);
}
