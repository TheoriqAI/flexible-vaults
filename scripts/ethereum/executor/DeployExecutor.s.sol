// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Executor} from "./Executor.sol";

contract DeployExecutor is Script {
    address constant OWNER = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("HOT_DEPLOYER");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Owner:", OWNER);

        vm.startBroadcast(deployerPrivateKey);

        Executor executor = new Executor(OWNER);

        vm.stopBroadcast();

        console.log("Executor deployed at:", address(executor));
        console.log("Executor OWNER:", executor.OWNER());
    }
}
