// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {OutrunSafeERC20} from "../yield/libraries/OutrunSafeERC20.sol";
import {IGovernanceCycleIncentivizer} from "./interfaces/IGovernanceCycleIncentivizer.sol";
import {IMemecoinDaoGovernor} from "./interfaces/IMemecoinDaoGovernor.sol";

/**
 * @dev External expansion of {Governor} for governance cycle incentive.
 */
contract GovernanceCycleIncentivizerUpgradeable is IGovernanceCycleIncentivizer, Initializable, UUPSUpgradeable {
    using OutrunSafeERC20 for IERC20;

    uint256 public constant RATIO = 10000;
    uint256 public constant CYCLE_DURATION = 90 days;
    uint256 public constant MAX_TOKENS_LIMIT = 50;

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.GovernanceCycleIncentivizer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant GOVERNANCE_CYCLE_INCENTIVIZER_STORAGE_LOCATION =
        0x173bbd0db440ff8dcb0efb05aced4279e21e45a07b4974973a371552ef840a00;

    function _getGovernanceCycleIncentivizerStorage()
        private
        pure
        returns (GovernanceCycleIncentivizerStorage storage $)
    {
        assembly {
            $.slot := GOVERNANCE_CYCLE_INCENTIVIZER_STORAGE_LOCATION
        }
    }

    function __GovernanceCycleIncentivizer_init(address governor, address[] calldata initTreasuryTokens)
        internal
        onlyInitializing
    {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        $._currentCycleId = 1;
        $._rewardRatio = 5000;
        uint128 startTime = uint128(block.timestamp);
        uint128 endTime = uint128(block.timestamp + CYCLE_DURATION);
        $._cycles[1].startTime = startTime;
        $._cycles[1].endTime = endTime;
        $._governor = governor;

        uint256 length = initTreasuryTokens.length;
        uint256[] memory balances = new uint256[](length);

        for (uint256 i = 0; i < length;) {
            address token = initTreasuryTokens[i];
            _registerTreasuryToken(token, $);
            unchecked {
                ++i;
            }
        }

        emit CycleStarted(1, startTime, endTime, initTreasuryTokens, balances);
    }

    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    function _onlyGovernance() internal view {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        require(msg.sender == $._governor, PermissionDenied());
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the governanceCycleIncentivizer.
     * @dev Seeds the first cycle metadata and initial treasury token set.
     * @param governor - The DAO Governor
     * @param initFundTokens - The initial DAO fund tokens.
     */
    function initialize(address governor, address[] calldata initFundTokens) external override initializer {
        __GovernanceCycleIncentivizer_init(governor, initFundTokens);
    }

    /**
     * @notice Returns the current cycle identifier.
     * @dev Reads the active cycle from incentivizer storage.
     * @return The active cycle id.
     */
    function currentCycleId() external view override returns (uint256) {
        return _getGovernanceCycleIncentivizerStorage()._currentCycleId;
    }

    /**
     * @notice Returns the incentivizer metadata snapshot.
     * @dev Exposes the current cycle, reward ratio, governor, treasury token list, and reward token list.
     * @return _currentCycleId The active cycle id.
     * @return _rewardRatio The configured reward ratio in basis points.
     * @return _governor The governor contract address.
     * @return _treasuryTokenList The registered treasury token list.
     * @return _rewardTokenList The registered reward token list.
     */
    function metaData()
        external
        view
        override
        returns (
            uint128 _currentCycleId,
            uint128 _rewardRatio,
            address _governor,
            address[] memory _treasuryTokenList,
            address[] memory _rewardTokenList
        )
    {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        _currentCycleId = $._currentCycleId;
        _rewardRatio = $._rewardRatio;
        _governor = $._governor;
        _treasuryTokenList = $._treasuryTokenList;
        _rewardTokenList = $._rewardTokenList;
    }

    /**
     * @notice Returns metadata for a specific cycle.
     * @dev Exposes timing, total votes, treasury token list, and reward token list for the requested cycle.
     * @param cycleId The cycle identifier to inspect.
     * @return startTime The cycle start timestamp.
     * @return endTime The cycle end timestamp.
     * @return totalVotes The total accumulated votes for the cycle.
     * @return treasuryTokenList The treasury token list for the cycle.
     * @return rewardTokenList The reward token list for the cycle.
     */
    function cycleInfo(uint128 cycleId)
        external
        view
        override
        returns (
            uint128 startTime,
            uint128 endTime,
            uint256 totalVotes,
            address[] memory treasuryTokenList,
            address[] memory rewardTokenList
        )
    {
        Cycle storage cycle = _getGovernanceCycleIncentivizerStorage()._cycles[cycleId];
        startTime = cycle.startTime;
        endTime = cycle.endTime;
        totalVotes = cycle.totalVotes;
        treasuryTokenList = cycle.treasuryTokenList;
        rewardTokenList = cycle.rewardTokenList;
    }

    /**
     * @notice Returns the vote count recorded for a user in a cycle.
     * @dev Reads the per-user vote accumulator for the requested cycle.
     * @param user The account to inspect.
     * @param cycleId The cycle identifier to inspect.
     * @return The votes recorded for the user in that cycle.
     */
    function getUserVotesCount(address user, uint128 cycleId) external view override returns (uint256) {
        return _getGovernanceCycleIncentivizerStorage()._cycles[cycleId].userVotes[user];
    }

    /**
     * @notice Returns whether a token is registered as a treasury token for a cycle.
     * @dev Uses the active-set shortcut for the current cycle and historical lists for past cycles.
     * @param cycleId The cycle identifier to inspect.
     * @param token The token address to check.
     * @return Whether the token is a treasury token for the cycle.
     */
    function isTreasuryToken(uint128 cycleId, address token) external view override returns (bool) {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        if (cycleId == $._currentCycleId) {
            return $._treasuryTokens[token];
        } else {
            Cycle storage cycle = $._cycles[cycleId];
            uint256 length = cycle.treasuryTokenList.length;
            for (uint256 i = 0; i < length;) {
                if (token == cycle.treasuryTokenList[i]) return true;
                unchecked {
                    ++i;
                }
            }
        }

        return false;
    }

    /**
     * @notice Returns whether a token is registered as a reward token for a cycle.
     * @dev Uses the active-set shortcut for the current cycle and historical lists for past cycles.
     * @param cycleId The cycle identifier to inspect.
     * @param token The token address to check.
     * @return Whether the token is a reward token for the cycle.
     */
    function isRewardToken(uint128 cycleId, address token) external view override returns (bool) {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        if (cycleId == $._currentCycleId) {
            return $._rewardTokens[token];
        } else {
            Cycle storage cycle = $._cycles[cycleId];
            uint256 length = cycle.rewardTokenList.length;
            for (uint256 i = 0; i < length;) {
                if (token == cycle.rewardTokenList[i]) return true;
                unchecked {
                    ++i;
                }
            }
        }

        return false;
    }

    /**
     * @notice Returns the claimable amount of one reward token for the previous cycle.
     * @dev Computes the user's pro-rata share from the previous cycle reward balances.
     * @param user - The user address
     * @param token - The token address
     * @return The specific token rewards claimable by the user for the previous cycle
     */
    function getClaimableReward(address user, address token) external view override returns (uint256) {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        Cycle storage prevCycle = $._cycles[$._currentCycleId - 1];

        uint256 userVotes = prevCycle.userVotes[user];
        if (userVotes == 0) return 0;
        uint256 rewardBalance = prevCycle.rewardBalances[token];
        if (rewardBalance == 0) return 0;
        uint256 totalVotes = prevCycle.totalVotes;

        return Math.mulDiv(rewardBalance, userVotes, totalVotes);
    }

    /**
     * @notice Returns all registered reward tokens claimable by the user for the previous cycle.
     * @dev Computes the user's pro-rata share for each registered reward token.
     * @param user - The user address
     * @return tokens - Tokens Array of token addresses
     * @return rewards - All registered token rewards
     */
    function getClaimableReward(address user)
        external
        view
        override
        returns (address[] memory tokens, uint256[] memory rewards)
    {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        Cycle storage prevCycle = $._cycles[$._currentCycleId - 1];

        uint256 userVotes = prevCycle.userVotes[user];
        if (userVotes != 0) {
            uint256 totalVotes = prevCycle.totalVotes;
            tokens = prevCycle.rewardTokenList;
            uint256 length = tokens.length;
            rewards = new uint256[](length);
            for (uint256 i = 0; i < length;) {
                address token = tokens[i];
                uint256 rewardBalance = prevCycle.rewardBalances[token];
                rewards[i] = Math.mulDiv(rewardBalance, userVotes, totalVotes);
                unchecked {
                    ++i;
                }
            }
        }
    }

    /**
     * @notice Returns the remaining claimable balance of one reward token for the previous cycle.
     * @dev Exposes the unclaimed reward balance after prior claims have been deducted.
     * @param token - The token address
     * @return remainingReward - The specific token remaining rewards claimable
     */
    function getRemainingClaimableRewards(address token) external view override returns (uint256 remainingReward) {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        Cycle storage prevCycle = $._cycles[$._currentCycleId - 1];

        uint256 totalVotes = prevCycle.totalVotes;
        if (totalVotes != 0) remainingReward = prevCycle.rewardBalances[token];
    }

    /**
     * @notice Returns the remaining claimable balances of all reward tokens for the previous cycle.
     * @dev Exposes all unclaimed reward balances after prior claims have been deducted.
     * @return tokens - Tokens Array of token addresses
     * @return rewards - All registered token rewards
     */
    function getRemainingClaimableRewards()
        external
        view
        override
        returns (address[] memory tokens, uint256[] memory rewards)
    {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        Cycle storage prevCycle = $._cycles[$._currentCycleId - 1];

        uint256 totalVotes = prevCycle.totalVotes;
        if (totalVotes != 0) {
            tokens = prevCycle.rewardTokenList;
            uint256 length = tokens.length;
            rewards = new uint256[](length);
            for (uint256 i = 0; i < length;) {
                address token = tokens[i];
                rewards[i] = prevCycle.rewardBalances[token];
                unchecked {
                    ++i;
                }
            }
        }
    }

    /**
     * @notice Returns the treasury balance of one token for a specific cycle.
     * @dev Reads the cycle treasury balance mapping directly.
     * @param cycleId - The cycle ID
     * @param token - The token address
     * @return The treasury balance for the specific cycle
     */
    function getTreasuryBalance(uint128 cycleId, address token) external view override returns (uint256) {
        return _getGovernanceCycleIncentivizerStorage()._cycles[cycleId].treasuryBalances[token];
    }

    /**
     * @notice Returns all registered treasury token balances for a specific cycle.
     * @dev Uses the live treasury token list for the active cycle and the frozen list for historical cycles.
     * @param cycleId - The cycle ID
     * @return tokens - Tokens Array of token addresses
     * @return balances - Balances Array of corresponding treasury balances
     */
    function getTreasuryBalances(uint128 cycleId)
        external
        view
        override
        returns (address[] memory tokens, uint256[] memory balances)
    {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        Cycle storage cycle = $._cycles[cycleId];
        tokens = cycleId == $._currentCycleId ? $._treasuryTokenList : cycle.treasuryTokenList;

        uint256 length = tokens.length;
        balances = new uint256[](length);

        for (uint256 i = 0; i < length;) {
            address token = tokens[i];
            balances[i] = cycle.treasuryBalances[token];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Records treasury income for the current cycle.
     * @dev Updates accounting only; the governor contract remains responsible for the actual token transfer.
     * @param token - The token address
     * @param amount - The amount
     */
    function recordTreasuryIncome(address token, uint256 amount) external override onlyGovernance {
        require(token != address(0) && amount != 0, ZeroInput());
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        require($._treasuryTokens[token], NonTreasuryToken());

        uint128 _currentCycleId = $._currentCycleId;
        $._cycles[_currentCycleId].treasuryBalances[token] += amount;

        emit TreasuryIncomeRecorded(_currentCycleId, token, msg.sender, amount);
    }

    /**
     * @notice Records a treasury asset transfer for the current cycle.
     * @dev Updates accounting only; the governor contract remains responsible for the actual token transfer. All
     * actions to transfer assets from the DAO treasury must use this entrypoint.
     * @param token - The token address
     * @param to - The receiver address
     * @param amount - The amount to transfer
     */
    function recordTreasuryAssetSpend(address token, address to, uint256 amount) external override onlyGovernance {
        require(token != address(0) && to != address(0) && amount != 0, ZeroInput());
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        require($._treasuryTokens[token], NonTreasuryToken());

        uint128 _currentCycleId = $._currentCycleId;
        Cycle storage currentCycle = $._cycles[_currentCycleId];
        uint256 currentBalance = currentCycle.treasuryBalances[token];

        require(
            currentBalance >= amount && IERC20(token).balanceOf($._governor) >= amount, InsufficientTreasuryBalance()
        );

        // Record
        currentCycle.treasuryBalances[token] = currentBalance - amount;

        emit TreasuryAssetSpendRecorded(_currentCycleId, token, to, amount);
    }

    /**
     * @notice Finalizes the current cycle and starts the next cycle.
     * @dev Rolls leftover rewards forward, snapshots treasury lists, and computes the new reward balances.
     */
    function finalizeCurrentCycle() external override {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        uint128 _currentCycleId = $._currentCycleId;
        uint128 newCycleId = _currentCycleId + 1;
        Cycle storage currentCycle = $._cycles[_currentCycleId];
        require(block.timestamp >= currentCycle.endTime, CycleNotEnded());

        // Process reward distribution
        uint256 treasuryLength = $._treasuryTokenList.length;
        address[] memory treasuryTokens = new address[](treasuryLength);
        uint256[] memory balances = new uint256[](treasuryLength);
        uint256 rewardLength = $._rewardTokenList.length;
        address[] memory rewardTokens = new address[](rewardLength);
        uint256[] memory rewards = new uint256[](rewardLength);

        Cycle storage prevCycle = $._cycles[_currentCycleId - 1];

        uint256 j = 0;
        for (uint256 i = 0; i < treasuryLength;) {
            address token = $._treasuryTokenList[i];

            // Transfer remaining reward balance to current cycle treasury
            uint256 treasuryBalance = currentCycle.treasuryBalances[token];
            uint256 prevRewardBalance = prevCycle.rewardBalances[token];
            if (prevRewardBalance > 0) {
                prevCycle.rewardBalances[token] = 0;
                treasuryBalance += prevRewardBalance;
                currentCycle.treasuryBalances[token] = treasuryBalance;
            }

            // Distribute reward
            uint256 rewardAmount;
            if ($._rewardTokens[token] && treasuryBalance > 0 && currentCycle.totalVotes > 0) {
                rewardAmount = treasuryBalance * $._rewardRatio / RATIO;
                currentCycle.rewardBalances[token] = rewardAmount;
                treasuryBalance -= rewardAmount;

                rewardTokens[j] = token;
                rewards[j] = rewardAmount;
                unchecked {
                    ++j;
                }
            }

            $._cycles[newCycleId].treasuryBalances[token] = treasuryBalance;
            treasuryTokens[i] = token;
            balances[i] = treasuryBalance;
            unchecked {
                ++i;
            }
        }

        currentCycle.treasuryTokenList = treasuryTokens;
        currentCycle.rewardTokenList = rewardTokens;

        emit CycleFinalized(_currentCycleId, uint128(block.timestamp), treasuryTokens, balances, rewardTokens, rewards);

        // Start new cycle
        $._currentCycleId = newCycleId;
        uint128 startTime = uint128(block.timestamp);
        uint128 endTime = uint128(block.timestamp + CYCLE_DURATION);
        $._cycles[newCycleId].startTime = startTime;
        $._cycles[newCycleId].endTime = endTime;

        emit CycleStarted(newCycleId, startTime, endTime, treasuryTokens, balances);
    }

    /**
     * @notice Claims the caller's reward allocation from the previous cycle.
     * @dev The caller claims for itself. Payouts are executed by the governor, which remains the asset custodian.
     */
    function claimReward() external override {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        uint128 prevCycleId = $._currentCycleId - 1;
        Cycle storage prevCycle = $._cycles[prevCycleId];
        address user = msg.sender;

        uint256 userVotes = prevCycle.userVotes[user];
        require(userVotes != 0, NoRewardsToClaim());

        prevCycle.userVotes[user] = 0;
        uint256 totalVotes = prevCycle.totalVotes;
        address[] memory rewardTokenList = prevCycle.rewardTokenList;
        uint256 length = rewardTokenList.length;

        for (uint256 i = 0; i < length;) {
            address token = rewardTokenList[i];
            unchecked {
                ++i;
            }
            uint256 rewardBalance = prevCycle.rewardBalances[token];
            if (rewardBalance > 0) {
                uint256 rewardAmount = Math.mulDiv(rewardBalance, userVotes, totalVotes);
                if (rewardAmount > 0) {
                    prevCycle.rewardBalances[token] = rewardBalance - rewardAmount;
                    IMemecoinDaoGovernor($._governor).disburseReward(token, user, rewardAmount);
                    emit RewardClaimed(user, prevCycleId, token, rewardAmount);
                }
            }
        }
    }

    /**
     * @notice Accumulates voting power for a user in the active cycle.
     * @dev Called by the governor after vote casting succeeds.
     * @param user - The user address
     * @param votes - The number of votes
     */
    function accumCycleVotes(address user, uint256 votes) external override onlyGovernance {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        uint128 _currentCycleId = $._currentCycleId;
        $._cycles[_currentCycleId].userVotes[user] += votes;
        $._cycles[_currentCycleId].totalVotes += votes;

        emit AccumCycleVotes(_currentCycleId, user, votes);
    }

    /**
     * @dev Register for receivable treasury token
     * @param token - The token address
     * @notice Governance must only register reviewed standard ERC20 tokens.
     * @dev This treasury ledger assumes nominal `amount` accounting and does not adapt to fee-on-transfer,
     * rebasing, or other non-standard balance semantics. Registering such a token can distort treasury/reward
     * accounting, and that asset-acceptance risk is borne by governance.
     */
    function registerTreasuryToken(address token) public override onlyGovernance {
        require(token != address(0), ZeroInput());
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        require(!$._treasuryTokens[token], RegisteredToken());
        require($._treasuryTokenList.length < MAX_TOKENS_LIMIT, OutOfMaxTokensLimit());

        _registerTreasuryToken(token, $);
    }

    /**
     * @dev Register for reward token，it MUST first be registered as a treasury token.
     * @param token - The token address
     * @notice Governance must only register reviewed standard ERC20 reward tokens.
     * @dev Reward payout uses nominal `amount` accounting and assumes the recipient receives the quoted amount.
     * Fee-on-transfer, rebasing, or other non-standard balance semantics are unsupported and must not be admitted
     * through governance token registration.
     */
    function registerRewardToken(address token) public override onlyGovernance {
        require(token != address(0), ZeroInput());
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        require(!$._rewardTokens[token], RegisteredToken());
        require($._treasuryTokens[token], NonTreasuryToken());
        require($._rewardTokenList.length < MAX_TOKENS_LIMIT, OutOfMaxTokensLimit());

        _registerRewardToken(token, $);
    }

    /**
     * @notice Unregisters a treasury token from the active cycle configuration.
     * @dev Also clears current-cycle accounting and unregisters the reward token if necessary.
     * @param token - The token address
     */
    function unregisterTreasuryToken(address token) external override onlyGovernance {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        require($._treasuryTokens[token], NonRegisteredToken());

        $._treasuryTokens[token] = false;
        $._cycles[$._currentCycleId].treasuryBalances[token] = 0;

        uint256 length = $._treasuryTokenList.length;
        for (uint256 i = 0; i < length;) {
            if ($._treasuryTokenList[i] == token) {
                $._treasuryTokenList[i] = $._treasuryTokenList[length - 1];
                $._treasuryTokenList.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }

        // Unregister Reward Token
        if ($._rewardTokens[token]) _unregisterRewardToken(token, $);

        emit TreasuryTokenUnregistered(token);
    }

    /**
     * @notice Unregisters a reward token from the active cycle configuration.
     * @dev Clears current-cycle reward accounting for the token.
     * @param token - The token address
     */
    function unregisterRewardToken(address token) external override onlyGovernance {
        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        require($._rewardTokens[token], NonRegisteredToken());

        _unregisterRewardToken(token, $);

        emit RewardTokenUnregistered(token);
    }

    /**
     * @notice Updates the reward ratio used when finalizing a cycle.
     * @dev The ratio is expressed in basis points and capped by `RATIO`.
     * @param newRatio - The new reward ratio (basis points)
     */
    function updateRewardRatio(uint128 newRatio) external override onlyGovernance {
        require(newRatio <= RATIO, InvalidRewardRatio());

        GovernanceCycleIncentivizerStorage storage $ = _getGovernanceCycleIncentivizerStorage();
        uint128 oldRatio = $._rewardRatio;
        $._rewardRatio = newRatio;

        emit RewardRatioUpdated(oldRatio, newRatio);
    }

    function _registerTreasuryToken(address token, GovernanceCycleIncentivizerStorage storage $) internal {
        $._treasuryTokenList.push(token);
        $._treasuryTokens[token] = true;
        $._cycles[$._currentCycleId].treasuryBalances[token] = IERC20(token).balanceOf(address(this));

        emit TreasuryTokenRegistered(token);
    }

    function _registerRewardToken(address token, GovernanceCycleIncentivizerStorage storage $) internal {
        $._rewardTokens[token] = true;
        $._rewardTokenList.push(token);

        emit RewardTokenRegistered(token);
    }

    function _unregisterRewardToken(address token, GovernanceCycleIncentivizerStorage storage $) internal {
        $._rewardTokens[token] = false;
        $._cycles[$._currentCycleId].rewardBalances[token] = 0;

        uint256 length = $._rewardTokenList.length;
        for (uint256 i = 0; i < length;) {
            if ($._rewardTokenList[i] == token) {
                $._rewardTokenList[i] = $._rewardTokenList[length - 1];
                $._rewardTokenList.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Allowing upgrades to the implementation contract only through governance proposals.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}
}
