// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {PermissionedChainlinkOracle} from "src/oracles/PermissionedChainlink.sol";

interface IERC20Meta {
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface IERC4626Like {
    function asset() external view returns (address);
    function convertToAssets(uint256 shares) external view returns (uint256);
}

/// @notice Deploys PermissionedChainlinkOracle instances (8-decimal USD feeds) for the Re/Reserve/Noon
///         subvault-4 assets: reUSDe, reUSD, USD3, sUSD3, sNUSD.
///
/// owner        = curation curator (prodCurator Safe)
/// decimals     = 8
/// minAllowed   = 0.9e8   maxAllowed = 2e8
/// description  = "USD price of <SYMBOL>"
/// initialAnswer= current NAV (8 dec): ERC4626 assets computed on-chain (recursively, base = $1);
///                reUSDe/reUSD are plain Re-Protocol tokens with no on-chain price -> set explicitly below.
///
/// Preview:  forge script scripts/ethereum/oracle/DeployPermissionedChainlink.s.sol --sig "preview()" \
///             --rpc-url $ETH_RPC_URL --via-ir
/// Deploy 1: forge script scripts/ethereum/oracle/DeployPermissionedChainlink.s.sol --sig "deploy(uint256)" <i> \
///             --rpc-url $ETH_RPC_URL --broadcast --verify --chain mainnet --via-ir
///           (i: 0=reUSDe 1=reUSD 2=USD3 3=sUSD3 4=sNUSD)
contract DeployPermissionedChainlink is Script {
    // ---- fixed params ----
    address public constant OWNER = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8; // prodCurator (curation curator)
    uint8 public constant DECIMALS = 8;
    int256 public constant MIN_ANSWER = 0.9e8;
    int256 public constant MAX_ANSWER = 2e8;

    // ---- tokens ----
    address public constant REUSDE = 0xdDC0f880ff6e4e22E4B74632fBb43Ce4DF6cCC5a;
    address public constant REUSD = 0x5086bf358635B81D8C47C66d1C8b9E567Db70c72;
    address public constant USD3 = 0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc;
    address public constant SUSD3 = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;
    address public constant SNUSD = 0x08EFCC2F3e61185D0EA7F8830B3FEc9Bfa2EE313;

    // base $1 assets underlying the vaults (returned by asset())
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant NUSD = 0xE556ABa6fe6036275Ec1f87eda296BE72C811BCE;

    // Explicit NAVs for the non-ERC4626 Re-Protocol tokens (8 dec). Pegged deposit tokens => $1.
    // Override here if the desk provides a different current NAV before broadcasting.
    int256 public constant REUSDE_NAV = 137886000; // $1.37886 (desk-provided current NAV)
    int256 public constant REUSD_NAV = 108653000; // $1.08653 (desk-provided current NAV)

    function _token(uint256 i) internal pure returns (address) {
        if (i == 0) return REUSDE;
        if (i == 1) return REUSD;
        if (i == 2) return USD3;
        if (i == 3) return SUSD3;
        if (i == 4) return SNUSD;
        revert("bad index");
    }

    /// @dev USD price (8 dec) of `token`. Base stables = $1; ERC4626 = convertToAssets(1 share) * assetNav,
    ///      recursing through the asset chain (sUSD3 -> USD3 -> USDC).
    function _navUsd8(address token) public view returns (int256) {
        if (token == USDC || token == NUSD) return 1e8;
        if (token == REUSDE) return REUSDE_NAV;
        if (token == REUSD) return REUSD_NAV;

        uint8 shareDec = IERC20Meta(token).decimals();
        address asset = IERC4626Like(token).asset();
        uint8 assetDec = IERC20Meta(asset).decimals();
        uint256 assetsPerShare = IERC4626Like(token).convertToAssets(10 ** shareDec); // in asset decimals
        int256 assetNav = _navUsd8(asset); // 8 dec USD per whole asset
        return (int256(assetsPerShare) * assetNav) / int256(10 ** uint256(assetDec));
    }

    function preview() external view {
        console.log("=== Proposed PermissionedChainlinkOracle deployments ===");
        console.log("owner:", OWNER);
        console.log("decimals: 8 | min: 90000000 (0.9) | max: 200000000 (2.0)");
        for (uint256 i = 0; i < 5; i++) {
            address t = _token(i);
            string memory sym = IERC20Meta(t).symbol();
            int256 nav = _navUsd8(t);
            console.log("--------------------------------------------");
            console.log(string.concat(" [", vm.toString(i), "] ", sym), t);
            console.log(string.concat("   description:  USD price of ", sym));
            console.log("   initialAnswer (8dec):", vm.toString(nav));
            require(nav >= MIN_ANSWER && nav <= MAX_ANSWER, "NAV out of [min,max]");
        }
    }

    function deploy(uint256 i) external {
        address t = _token(i);
        string memory sym = IERC20Meta(t).symbol();
        int256 nav = _navUsd8(t);
        string memory desc = string.concat("USD price of ", sym);
        require(nav >= MIN_ANSWER && nav <= MAX_ANSWER, "NAV out of [min,max]");

        uint256 pk = vm.envUint("DEPLOYER_KEY");
        console.log("=== Deploying PermissionedChainlinkOracle ===");
        console.log("deployer:", vm.addr(pk));
        console.log(string.concat("token: ", sym), t);
        console.log(string.concat("description: ", desc));
        console.log("initialAnswer (8dec):", vm.toString(nav));
        console.log("owner:", OWNER);

        vm.startBroadcast(pk);
        PermissionedChainlinkOracle oracle =
            new PermissionedChainlinkOracle(OWNER, DECIMALS, nav, MIN_ANSWER, MAX_ANSWER, desc);
        vm.stopBroadcast();

        console.log("=== Deployed at:", address(oracle));
    }
}
