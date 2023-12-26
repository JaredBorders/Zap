// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {
    Bootstrap,
    MockSpotMarketProxy,
    MockUSDC,
    MockSUSD
} from "test/utils/Bootstrap.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ISpotMarketProxy} from "../src/interfaces/ISpotMarketProxy.sol";
import {ZapErrors} from "../src/ZapErrors.sol";
import {ZapExposed} from "test/utils/exposed/ZapExposed.sol";

/**
 * @custom:example-wrap-and-unwrap
 *
 * 1 $USDC <-- Synthetix Spot Market: Wrap --> 1e12 $sUSDC
 *                                                ^
 *                                                |
 *                                                |
 *                                    Synthetix Spot Market: Sell
 *                                                |
 *                                                |
 *                                                v
 *                                            1e12 $sUSD
 *
 *
 * @dev
 *
 * IF $USDC has 6 decimals
 * AND $sUSD and $sUSDC have 18 decimals
 * THEN 1e12 $sUSD/$sUSDC = 1 $USDC
 * AND in the context of this system, the DECIMAL_FACTOR would be: 10^(18-6) == 1e12
 */
contract ZapTest is Bootstrap {
    IERC20 internal SUSD;
    IERC20 internal USDC;
    IERC20 internal SUSDC;
    ISpotMarketProxy internal SPOT_MARKET_PROXY;

    MockSpotMarketProxy public mockSpotMarketProxy;
    MockUSDC public mockUSDC;
    MockSUSD public mockSUSD;

    uint256 internal DECIMAL_FACTOR;

    function setUp() public {
        vm.rollFork(BASE_BLOCK_NUMBER);
        initializeBase();

        SUSD = IERC20(ZapExposed(address(zap)).expose_SUSD());
        USDC = IERC20(ZapExposed(address(zap)).expose_USDC());
        SUSDC = IERC20(ZapExposed(address(zap)).expose_SUSDC());
        SPOT_MARKET_PROXY = ISpotMarketProxy(
            ZapExposed(address(zap)).expose_SPOT_MARKET_PROXY()
        );

        mockSpotMarketProxy = new MockSpotMarketProxy();
        mockUSDC = new MockUSDC();
        mockSUSD = new MockSUSD();

        deal(address(SUSD), ACTOR, INITIAL_MINT);
        deal(address(USDC), ACTOR, INITIAL_MINT);

        vm.startPrank(ACTOR);

        USDC.approve(address(zap), type(uint256).max);
        SUSD.approve(address(zap), type(uint256).max);

        vm.stopPrank();

        DECIMAL_FACTOR = ZapExposed(address(zap)).expose_DECIMALS_FACTOR();
    }
}

contract Deployment is ZapTest {
    function test_zap_address() public view {
        assert(address(zap) != address(0));
    }

    function test_hashed_susdc_name() public {
        assertEq(
            ZapExposed(address(zap)).expose_HASHED_SUSDC_NAME(),
            keccak256(abi.encodePacked("Synthetic USD Coin Spot Market"))
        );
    }

    function test_usdc_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(ZapErrors.ZeroAddress.selector));

        new ZapExposed({
            _usdc: address(0),
            _susd: address(mockSUSD),
            _spotMarketProxy: address(mockSpotMarketProxy),
            _sUSDCId: type(uint128).max
        });
    }

    function test_susd_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(ZapErrors.ZeroAddress.selector));

        new ZapExposed({
            _usdc: address(mockUSDC),
            _susd: address(0),
            _spotMarketProxy: address(mockSpotMarketProxy),
            _sUSDCId: type(uint128).max
        });
    }

    function test_spotMarketProxy_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(ZapErrors.ZeroAddress.selector));

        new ZapExposed({
            _usdc: address(mockUSDC),
            _susd: address(mockSUSD),
            _spotMarketProxy: address(0),
            _sUSDCId: type(uint128).max
        });
    }

    function test_usdc_decimals_factor() public view {
        assert(ZapExposed(address(zap)).expose_DECIMALS_FACTOR() != 0);
    }

    function test_sUSDCId_invalid() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ZapErrors.InvalidIdSUSDC.selector, type(uint128).max
            )
        );

        new ZapExposed({
            _usdc: address(mockUSDC),
            _susd: address(mockSUSD),
            _spotMarketProxy: address(mockSpotMarketProxy),
            _sUSDCId: type(uint128).max
        });
    }

    function test_sUSDC_address() public view {
        assert(ZapExposed(address(zap)).expose_SUSDC() != address(0));
    }
}

contract ZapIn is ZapTest {
    function test_zap_in() public {
        vm.startPrank(ACTOR);

        zap.zap(INT_AMOUNT, REFERRER);

        assertEq(SUSD.balanceOf(address(zap)), UINT_AMOUNT * DECIMAL_FACTOR);

        vm.stopPrank();
    }

    function test_zap_in_exceeds_cap() public {
        vm.startPrank(ACTOR);

        try zap.zap(type(int128).max, REFERRER) {}
        catch (bytes memory reason) {
            // assumes type(int128).max always exceeds cap
            assertEq(bytes4(reason), WrapperExceedsMaxAmount.selector);
        }

        vm.stopPrank();
    }

    function test_zap_in_usdc_transfer_fails() public {
        vm.mockCall(
            address(USDC),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, ACTOR, address(zap), UINT_AMOUNT
            ),
            abi.encode(false)
        );

        vm.startPrank(ACTOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZapErrors.TransferFailed.selector,
                address(USDC),
                ACTOR,
                address(zap),
                UINT_AMOUNT
            )
        );

        zap.zap(INT_AMOUNT, REFERRER);

        vm.stopPrank();
    }

    function test_zap_in_usdc_approve_fails() public {
        vm.mockCall(
            address(USDC),
            abi.encodeWithSelector(
                IERC20.approve.selector, address(SPOT_MARKET_PROXY), UINT_AMOUNT
            ),
            abi.encode(false)
        );

        vm.startPrank(ACTOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZapErrors.ApprovalFailed.selector,
                address(USDC),
                address(zap),
                address(SPOT_MARKET_PROXY),
                UINT_AMOUNT
            )
        );

        zap.zap(INT_AMOUNT, REFERRER);

        vm.stopPrank();
    }

    function test_zap_in_susdc_approve_fails() public {
        vm.mockCall(
            address(SUSDC),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(SPOT_MARKET_PROXY),
                UINT_AMOUNT * DECIMAL_FACTOR
            ),
            abi.encode(false)
        );

        vm.startPrank(ACTOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZapErrors.ApprovalFailed.selector,
                address(SUSDC),
                address(zap),
                address(SPOT_MARKET_PROXY),
                UINT_AMOUNT * DECIMAL_FACTOR
            )
        );

        zap.zap(INT_AMOUNT, REFERRER);

        vm.stopPrank();
    }

    function test_zap_in_event() public {
        vm.startPrank(ACTOR);

        vm.expectEmit(true, true, true, true);
        emit ZappedIn(UINT_AMOUNT * DECIMAL_FACTOR);

        zap.zap(INT_AMOUNT, REFERRER);

        vm.stopPrank();
    }
}

contract ZapOut is ZapTest {
    function test_zap_out() public {
        vm.startPrank(ACTOR);

        SUSD.transfer(address(zap), UINT_AMOUNT * DECIMAL_FACTOR);

        zap.zap(-INT_AMOUNT * int256(DECIMAL_FACTOR), REFERRER);

        assertEq(USDC.balanceOf(address(zap)), UINT_AMOUNT);

        vm.stopPrank();
    }

    function test_zap_out_zero() public {
        vm.startPrank(ACTOR);

        vm.expectRevert();

        zap.zap(0, REFERRER);

        vm.stopPrank();
    }

    function test_zap_out_susd_approve_fails() public {
        vm.mockCall(
            address(SUSD),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(SPOT_MARKET_PROXY),
                UINT_AMOUNT * DECIMAL_FACTOR
            ),
            abi.encode(false)
        );

        vm.startPrank(ACTOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZapErrors.ApprovalFailed.selector,
                address(SUSD),
                address(zap),
                address(SPOT_MARKET_PROXY),
                UINT_AMOUNT * DECIMAL_FACTOR
            )
        );

        zap.zap(-INT_AMOUNT * int256(DECIMAL_FACTOR), REFERRER);

        vm.stopPrank();
    }

    function test_zap_out_susdc_approve_fails() public {
        vm.mockCall(
            address(SUSDC),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(SPOT_MARKET_PROXY),
                UINT_AMOUNT * DECIMAL_FACTOR
            ),
            abi.encode(false)
        );

        vm.startPrank(ACTOR);

        SUSD.transfer(address(zap), UINT_AMOUNT * DECIMAL_FACTOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZapErrors.ApprovalFailed.selector,
                address(SUSDC),
                address(zap),
                address(SPOT_MARKET_PROXY),
                UINT_AMOUNT * DECIMAL_FACTOR
            )
        );

        zap.zap(-INT_AMOUNT * int256(DECIMAL_FACTOR), REFERRER);

        vm.stopPrank();
    }

    function test_zap_out_insufficient_amount() public {
        vm.startPrank(ACTOR);

        SUSD.transfer(address(zap), UINT_AMOUNT * DECIMAL_FACTOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZapErrors.InsufficientAmount.selector, DECIMAL_FACTOR - 1
            )
        );

        zap.zap(-int256(DECIMAL_FACTOR - 1), REFERRER);

        vm.stopPrank();
    }

    function test_zap_out_precision_loss(uint256 sUSDLost) public {
        vm.assume(sUSDLost < DECIMAL_FACTOR);

        vm.startPrank(ACTOR);

        SUSD.transfer(address(zap), (UINT_AMOUNT * DECIMAL_FACTOR) + sUSDLost);

        zap.zap(
            -((INT_AMOUNT * int256(DECIMAL_FACTOR)) + int256(sUSDLost)),
            REFERRER
        );

        assertEq(USDC.balanceOf(address(zap)), UINT_AMOUNT);

        vm.stopPrank();
    }

    function test_zap_out_event() public {
        vm.startPrank(ACTOR);

        SUSD.transfer(address(zap), UINT_AMOUNT * DECIMAL_FACTOR);

        vm.expectEmit(true, true, true, true);
        emit ZappedOut(UINT_AMOUNT);

        zap.zap(-INT_AMOUNT * int256(DECIMAL_FACTOR), REFERRER);

        vm.stopPrank();
    }
}
