// SPDX-License-Identifier: MIT

pragma solidity =0.8.10;
import "../utils/LSVProxyRegistry.sol";
import "../utils/TokenUtils.sol";
import "../utils/DFSProxyRegistry.sol";

import "../actions/utils/helpers/ActionsUtilHelper.sol";
import "../actions/aaveV3/helpers/AaveV3Helper.sol";
import "../actions/morpho/aaveV3/helpers/MorphoAaveV3Helper.sol";
import "../actions/compoundV3/helpers/CompV3Helper.sol";
import "../utils/helpers/UtilHelper.sol";
import "../actions/lsv/helpers/LSVUtilHelper.sol";
import "../utils/LSVProfitTracker.sol";

struct Position {
    uint8 protocol;
    address proxy;
    address collateralToken;
    address debtToken;
    uint256 collateral;
    uint256 debt;
}

contract LSVView is ActionsUtilHelper, UtilHelper, AaveV3Helper, MorphoAaveV3Helper, CompV3Helper, LSVUtilHelper {
    enum Protocol {
        AAVE_V3,
        MORPHO_AAVE_V3,
        COMPOUND_V3
    }
    using TokenUtils for address;

    function getAllPositionForLSVUser(
        address _user,
        address[] memory _collTokens
    ) public view returns (address[] memory proxies, Position[] memory positions) {
        proxies = LSVProxyRegistry(LSV_PROXY_REGISTRY_ADDRESS).getProxies(_user);
        Position[] memory tempPositions = new Position[](proxies.length * _collTokens.length);
        uint256 positionCounter;

        for (uint i = 0; i < proxies.length; i++) {
            // Aave position
            {
                IPoolV3 lendingPool = getLendingPool(DEFAULT_AAVE_MARKET);
                DataTypes.ReserveData memory wethReserveData = lendingPool.getReserveData(
                    TokenUtils.WETH_ADDR
                );
                for (uint j = 0; j < _collTokens.length; j++) {
                    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
                        _collTokens[j]
                    );
                    if (reserveData.aTokenAddress != address(0)) {
                        uint256 collBalance = reserveData.aTokenAddress.getBalance(proxies[i]);
                        if (collBalance > 0) {
                            uint256 debtBalance = wethReserveData
                                .variableDebtTokenAddress
                                .getBalance(proxies[i]);
                            tempPositions[positionCounter++] = Position(
                                uint8(Protocol.AAVE_V3),
                                proxies[i],
                                _collTokens[j],
                                TokenUtils.WETH_ADDR,
                                collBalance,
                                debtBalance
                            );
                            j = _collTokens.length;
                        }
                    }
                }
            }
            // MorphoAave Position
            {
                address morphoAddr = getMorphoAddressByEmode(1);
                for (uint j = 0; j < _collTokens.length; j++) {
                    uint256 collBalance = IMorphoAaveV3(morphoAddr).collateralBalance(
                        _collTokens[j],
                        proxies[i]
                    );
                    if (collBalance > 0) {
                        uint256 debtBalance = IMorphoAaveV3(morphoAddr).borrowBalance(
                            TokenUtils.WETH_ADDR,
                            proxies[i]
                        );
                        tempPositions[positionCounter++] = Position(
                            uint8(Protocol.MORPHO_AAVE_V3),
                            proxies[i],
                            _collTokens[j],
                            TokenUtils.WETH_ADDR,
                            collBalance,
                            debtBalance
                        );
                        j = _collTokens.length;
                    }
                }
            }
            // Compound V3 Position
            {
                IComet comet = IComet(COMP_ETH_COMET);
                for (uint j = 0; j < _collTokens.length; j++) {
                    uint256 collBalance = comet.collateralBalanceOf(proxies[i], _collTokens[j]);
                    if (collBalance > 0) {
                        uint256 debtBalance = comet.borrowBalanceOf(proxies[i]);
                        tempPositions[positionCounter++] = Position(
                            uint8(Protocol.COMPOUND_V3),
                            proxies[i],
                            _collTokens[j],
                            TokenUtils.WETH_ADDR,
                            collBalance,
                            debtBalance
                        );
                        j = _collTokens.length;
                    }
                }
            }
        }
        positions = new Position[](positionCounter);
        for (uint i = 0; i < positionCounter; i++) {
            positions[i] = tempPositions[i];
        }
    }

    function getAllPositionForDFSUser(
        address _user,
        address[] memory _collTokens
    ) public view returns (address[] memory proxies, Position[] memory positions) {
        (address mcdProxy, address[] memory additionalProxies) = DFSProxyRegistry(
            DFS_PROXY_REGISTRY_ADDR
        ).getAllProxies(_user);

        if (mcdProxy == address(0)) {
            proxies = new address[](additionalProxies.length);
            for (uint256 i = 0; i < proxies.length; i++) {
                proxies[i] = additionalProxies[i];
            }
        } else {
            proxies = new address[](additionalProxies.length + 1);
            uint256 i;
            for (i; i < proxies.length - 1; i++) {
                proxies[i] = additionalProxies[i];
            }
            proxies[i] = mcdProxy;
        }

        Position[] memory tempPositions = new Position[](proxies.length * _collTokens.length);
        uint256 positionCounter;

        for (uint i = 0; i < proxies.length; i++) {
            // Aave position
            {
                IPoolV3 lendingPool = getLendingPool(DEFAULT_AAVE_MARKET);
                DataTypes.ReserveData memory wethReserveData = lendingPool.getReserveData(
                    TokenUtils.WETH_ADDR
                );
                for (uint j = 0; j < _collTokens.length; j++) {
                    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
                        _collTokens[j]
                    );
                    if (reserveData.aTokenAddress != address(0)) {
                        uint256 collBalance = reserveData.aTokenAddress.getBalance(proxies[i]);
                        if (collBalance > 0) {
                            uint256 debtBalance = wethReserveData
                                .variableDebtTokenAddress
                                .getBalance(proxies[i]);
                            tempPositions[positionCounter++] = Position(
                                uint8(Protocol.AAVE_V3),
                                proxies[i],
                                _collTokens[j],
                                TokenUtils.WETH_ADDR,
                                collBalance,
                                debtBalance
                            );
                            j = _collTokens.length;
                        }
                    }
                }
            }
            // MorphoAave Position
            {
                address morphoAddr = getMorphoAddressByEmode(1);
                for (uint j = 0; j < _collTokens.length; j++) {
                    uint256 collBalance = IMorphoAaveV3(morphoAddr).collateralBalance(
                        _collTokens[j],
                        proxies[i]
                    );
                    if (collBalance > 0) {
                        uint256 debtBalance = IMorphoAaveV3(morphoAddr).borrowBalance(
                            TokenUtils.WETH_ADDR,
                            proxies[i]
                        );
                        tempPositions[positionCounter++] = Position(
                            uint8(Protocol.MORPHO_AAVE_V3),
                            proxies[i],
                            _collTokens[j],
                            TokenUtils.WETH_ADDR,
                            collBalance,
                            debtBalance
                        );
                        j = _collTokens.length;
                    }
                }
            }
            // Compound V3 Position
            {
                IComet comet = IComet(COMP_ETH_COMET);
                for (uint j = 0; j < _collTokens.length; j++) {
                    uint256 collBalance = comet.collateralBalanceOf(proxies[i], _collTokens[j]);
                    if (collBalance > 0) {
                        uint256 debtBalance = comet.borrowBalanceOf(proxies[i]);
                        tempPositions[positionCounter++] = Position(
                            uint8(Protocol.COMPOUND_V3),
                            proxies[i],
                            _collTokens[j],
                            TokenUtils.WETH_ADDR,
                            collBalance,
                            debtBalance
                        );
                        j = _collTokens.length;
                    }
                }
            }
        }
        positions = new Position[](positionCounter);
        for (uint i = 0; i < positionCounter; i++) {
            positions[i] = tempPositions[i];
        }
    }

    function getAllPositionForEOA(
        address _user,
        address[] memory _collTokens
    ) public view returns (address[] memory proxies, Position[] memory positions) {
        Position[] memory tempPositions = new Position[](_collTokens.length);
        uint256 positionCounter;

        // Aave position
        {
            IPoolV3 lendingPool = getLendingPool(DEFAULT_AAVE_MARKET);
            DataTypes.ReserveData memory wethReserveData = lendingPool.getReserveData(
                TokenUtils.WETH_ADDR
            );
            for (uint j = 0; j < _collTokens.length; j++) {
                DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
                    _collTokens[j]
                );
                if (reserveData.aTokenAddress != address(0)) {
                    uint256 collBalance = reserveData.aTokenAddress.getBalance(_user);
                    if (collBalance > 0) {
                        uint256 debtBalance = wethReserveData.variableDebtTokenAddress.getBalance(
                            _user
                        );
                        tempPositions[positionCounter++] = Position(
                            uint8(Protocol.AAVE_V3),
                            _user,
                            _collTokens[j],
                            TokenUtils.WETH_ADDR,
                            collBalance,
                            debtBalance
                        );
                        j = _collTokens.length;
                    }
                }
            }
        }
        // MorphoAave Position
        {
            address morphoAddr = getMorphoAddressByEmode(1);
            for (uint j = 0; j < _collTokens.length; j++) {
                uint256 collBalance = IMorphoAaveV3(morphoAddr).collateralBalance(
                    _collTokens[j],
                    _user
                );
                if (collBalance > 0) {
                    uint256 debtBalance = IMorphoAaveV3(morphoAddr).borrowBalance(
                        TokenUtils.WETH_ADDR,
                        _user
                    );
                    tempPositions[positionCounter++] = Position(
                        uint8(Protocol.MORPHO_AAVE_V3),
                        _user,
                        _collTokens[j],
                        TokenUtils.WETH_ADDR,
                        collBalance,
                        debtBalance
                    );
                    j = _collTokens.length;
                }
            }
        }
        // Compound V3 Position
        {
            IComet comet = IComet(COMP_ETH_COMET);
            for (uint j = 0; j < _collTokens.length; j++) {
                uint256 collBalance = comet.collateralBalanceOf(_user, _collTokens[j]);
                if (collBalance > 0) {
                    uint256 debtBalance = comet.borrowBalanceOf(_user);
                    tempPositions[positionCounter++] = Position(
                        uint8(Protocol.COMPOUND_V3),
                        _user,
                        _collTokens[j],
                        TokenUtils.WETH_ADDR,
                        collBalance,
                        debtBalance
                    );
                    j = _collTokens.length;
                }
            }
        }
        positions = new Position[](positionCounter);
        for (uint i = 0; i < positionCounter; i++) {
            positions[i] = tempPositions[i];
        }
    }



    function getInfoForLSVPosition(uint8 _protocol, address _lsvProxy, address[] memory _collTokens) public view returns (uint256 netWorth, int256 unrealisedProfit) {
        unrealisedProfit = LSVProfitTracker(LSV_PROFIT_TRACKER_ADDRESS).unrealisedProfit(_protocol, _lsvProxy);
        (uint256 collBalance, uint256 ethDebtBalance, address collToken) = findCollAndDebtBalance(_protocol, _lsvProxy, _collTokens);
        uint256 collBalanceInETH = getAmountInETHFromLST(collToken, collBalance);
        netWorth = collBalanceInETH  - ethDebtBalance;
    }
    
    function findCollAndDebtBalance(uint8 protocol, address _user, address[] memory _collTokens) public view returns (uint256, uint256, address){
        if (protocol == uint8(Protocol.AAVE_V3)) return findCollAndDebtForAaveV3Position(_user, _collTokens);
        if (protocol == uint8(Protocol.MORPHO_AAVE_V3)) return findCollAndDebtForMorphoAaveV3Position(_user, _collTokens);
        if (protocol == uint8(Protocol.COMPOUND_V3)) return findCollAndDebtForCompV3Position(_user, _collTokens);
    }

    /// @dev we assume it only has one LST token as collateral, and only ETH as debt
    function findCollAndDebtForAaveV3Position(address _user, address[] memory _collTokens) public view returns (uint256, uint256, address) {
        IPoolV3 lendingPool = getLendingPool(DEFAULT_AAVE_MARKET);
        DataTypes.ReserveData memory wethReserveData = lendingPool.getReserveData(
            TokenUtils.WETH_ADDR
        );
        uint256 ethDebtAmount = wethReserveData.variableDebtTokenAddress.getBalance(_user);
        for (uint j = 0; j < _collTokens.length; j++) {
            DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
                _collTokens[j]
            );
            if (reserveData.aTokenAddress != address(0)) {
                uint256 lstCollAmount = reserveData.aTokenAddress.getBalance(_user);
                return (lstCollAmount, ethDebtAmount, _collTokens[j]);
            }
        }
    }

    /// @dev we assume it only has one LST token as collateral, and only ETH as debt
    function findCollAndDebtForMorphoAaveV3Position(address _user, address[] memory _collTokens) public view returns (uint256, uint256, address) {
        address morphoAddr = getMorphoAddressByEmode(1);
        uint256 debtBalance = IMorphoAaveV3(morphoAddr).borrowBalance(
            TokenUtils.WETH_ADDR,
            _user
        );

        for (uint j = 0; j < _collTokens.length; j++) {
            uint256 collBalance = IMorphoAaveV3(morphoAddr).collateralBalance(
                _collTokens[j],
                _user
            );
            if (collBalance > 0) {
                return (collBalance, debtBalance, _collTokens[j]);
            }
        }
    }

    /// @dev we assume it only has one LST token as collateral, and only ETH as debt
    function findCollAndDebtForCompV3Position(address _user, address[] memory _collTokens) public view returns (uint256, uint256, address) {
        IComet comet = IComet(COMP_ETH_COMET);

        uint256 debtBalance = comet.borrowBalanceOf(_user);
        for (uint j = 0; j < _collTokens.length; j++) {
            uint256 collBalance = comet.collateralBalanceOf(_user, _collTokens[j]);
            if (collBalance > 0) {
                return (collBalance, debtBalance, _collTokens[j]);
            }
        }
    }
}
