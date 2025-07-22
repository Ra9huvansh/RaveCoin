//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 MAX_MINTABLE_DSC_SIZE = type(uint96).max;

    address user = makeAddr("user");

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc){
        dsce = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralTokenSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        ERC20Mock collateralToken = _getCollateralTokenFromSeed(collateralTokenSeed);

        // Simulate this user
        vm.startPrank(user);

        // Mint and approve before deposit
        collateralToken.mint(user, amountCollateral);
        collateralToken.approve(address(dsce), amountCollateral);

        dsce.depositCollateral(address(collateralToken), amountCollateral);

        vm.stopPrank();
    }

    /*
     * redeemCollateral never reverts because we are simulating a single user.
     * We are only taking account of depositing and redeeming until now and since there is no DSC minted, 
     * HealthFactor never breaks.
     */
    function redeemCollateral(uint256 collateralTokenSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralTokenFromSeed(collateralTokenSeed);

        vm.startPrank(user);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateralToken), user);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if(amountCollateral == 0){
            vm.stopPrank();
            return;
        }

        // 2. Simulate remaining collateral and calculate health factor
        (uint256 minted, uint256 collateralUsd) = dsce.getAccountInformation(user);
        uint256 redemptionUsd = dsce.getUsdValue(address(collateralToken), amountCollateral);
        uint256 newCollateralUsd = collateralUsd - redemptionUsd;

        // Health factor formula: (collateralAdjusted * 1e18) / minted
        uint256 newHealthFactor = dsce.calculateHealthFactor(minted, newCollateralUsd);

        // 3. If redeem breaks the health factor, skip
        if (newHealthFactor < dsce.getMinHealthFactor()) {
            vm.stopPrank();
            return;
        }

        dsce.redeemCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
    }
    
    function _getCollateralTokenFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
        if(collateralSeed % 2 == 0){
            return weth;
        }
        return wbtc;
    }

    function mintDsc(uint256 amount) public {
        amount = bound(amount, 1, MAX_MINTABLE_DSC_SIZE); // prevent overflow

        vm.startPrank(user);
        (uint256 minted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);

        uint256 totalMintedDsc = minted + amount;

        uint256 healthFactor = dsce.calculateHealthFactor(totalMintedDsc, collateralValueInUsd);
        if (healthFactor < dsce.getMinHealthFactor()) {
            vm.stopPrank();
            return;
        }

        dsce.mintDsc(amount);
        vm.stopPrank();
    }
}