// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IExpectedOutCalculator} from "./IExpectedOutCalculator.sol";

interface IAddressProvider {
    function get_registry() external view returns (address);
}

interface IRegistry {
    function find_pool_for_coins(address _from, address _to)
        external
        view
        returns (address);

    function get_underlying_coins(address _pool)
        external
        view
        returns (address[8] memory);
}

interface ICurvePool {
    function get_dy_underlying(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
}

contract CurveExpectedOutCalculator is IExpectedOutCalculator {
    using SafeMath for uint256;

    IAddressProvider internal constant ADDRESS_PROVIDER =
        IAddressProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);
    IRegistry public registry;

    uint256 internal constant MAX_BPS = 10_000;

    constructor() {
        updateRegistry();
    }

    // anyone can call this
    function updateRegistry() public {
        registry = IRegistry(ADDRESS_PROVIDER.get_registry());
    }

    /**
     * @dev This expected out calculator can only be used for Curve pools that use `int128`
     *      for `i` and `j`, which contains most but not all pools.
     *
     *      A separate calculator can be deployed for the pools that use `uint256`.
     */
    function getExpectedOut(
        uint256 _amountIn,
        address _fromToken,
        address _toToken,
        bytes calldata
    ) external view override returns (uint256) {
        address _pool = registry.find_pool_for_coins(_fromToken, _toToken);
        require(_pool != address(0)); // dev: no Curve pool for this swap

        return _getExpectedOut(_pool, _fromToken, _toToken, _amountIn);
    }

    function _getExpectedOut(
        address _pool,
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) internal view returns (uint256) {
        int128 _i;
        int128 _j;
        {
            // block scoping to prevent stack too deep
            address[8] memory _tokensInPool = registry.get_underlying_coins(
                _pool
            );
            for (int128 _x = 0; _x < 8; _x++) {
                address _currentToken = _tokensInPool[uint256(_x)];
                if (_currentToken == address(0)) {
                    break;
                } else if (_currentToken == _fromToken) {
                    _i = _x;
                } else if (_currentToken == _toToken) {
                    _j = _x;
                }
            }
            require(_i != 0 || _j != 0); // dev: something went wrong
        }
        return ICurvePool(_pool).get_dy_underlying(_i, _j, _amountIn);
    }
}
