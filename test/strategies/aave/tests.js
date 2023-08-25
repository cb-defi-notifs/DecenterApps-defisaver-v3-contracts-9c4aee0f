const hre = require('hardhat');
const { expect } = require('chai');

const { configure } = require('@defisaver/sdk');
const {
    assets,
    getAssetInfo,
    utils: { compare }
} = require('@defisaver/tokens');

const {
    getProxy,
    redeploy,
    redeployCore,
    setBalance,
    openStrategyAndBundleStorage,
    fetchAmountinUSDPrice,
    resetForkToBlock,
    network,
    addrs,
    chainIds,
    Float2BN,
    nullAddress,
    setNewExchangeWrapper,
    getLocalTokenPrice,
    balanceOf,
    BN2Float,
    takeSnapshot,
    revertToSnapshot,
    ETH_ADDR,
} = require('../../utils');

const {
    addBotCaller,
    createStrategy,
    createBundle,
    activateSub,
} = require('../../utils-strategies');

const {
    createAaveV3CloseToCollWithMaximumGasPriceStrategy,
    createAaveV3FLCloseToCollWithMaximumGasPriceStrategy,
} = require('../../strategies');

const {
    aaveV3Supply,
    aaveV3Borrow,
} = require('../../actions');

const { RATIO_STATE_OVER } = require('../../triggers');
const { subAaveV3CloseWithMaximumGasPriceBundle } = require('../../strategy-subs');
const { callAaveCloseToCollWithMaximumGasPriceStrategy } = require('../../strategy-calls');

const testPairs = [
    {
        collAsset: 'WETH',
        debtAsset: 'DAI',
    },
    {
        collAsset: 'WBTC',
        debtAsset: 'USDC',
    },
    {
        collAsset: 'DAI',
        debtAsset: 'WETH',
    },
];

const deployCloseToCollWithMaximumGasPriceBundle = async (proxy, isFork = undefined) => {
    await openStrategyAndBundleStorage(isFork);

    const closeStrategy = createAaveV3CloseToCollWithMaximumGasPriceStrategy();

    const flCloseStrategy = createAaveV3FLCloseToCollWithMaximumGasPriceStrategy();

    const aaveV3CloseToCollStrategyId = await createStrategy(
        proxy,
        ...closeStrategy,
        false,
    );
    const aaveV3FLCloseToCollStrategyId = await createStrategy(
        proxy,
        ...flCloseStrategy,
        false,
    );
    const aaveV3CloseToCollBundleId = await createBundle(
        proxy,
        [aaveV3CloseToCollStrategyId, aaveV3FLCloseToCollStrategyId],
    );

    return aaveV3CloseToCollBundleId;
};
const aaveV3CloseToCollWithMaximumGasPriceStrategyTest = async (numTestPairs) => {
    describe('AaveV3-Close-to-Coll-With-Maximum-Gas-Price-Strategy-Test', function () {
        this.timeout(1200000);

        const USD_COLL_OPEN = '25000';
        const USD_DEBT_OPEN = '10000';
        const ALLOWED_SLIPPAGE = 0.05;
        const EXPECTED_MAX_INTEREST = 1e-6;
        const EXPECTED_MAX_FEE = 1e-2; // gas + dfs fee
        const RATE_MODE = 2;

        let strategyExecutorByBot;
        let senderAcc;
        let proxy;
        let proxyAddr;
        let botAcc;
        let strategyExecutor;
        let pool;
        let subId;
        let sub;
        let collAssetId;
        let debtAssetId;
        let bundleId;
        let snapshotId;

        before(async () => {
            console.log(`Network: ${network}`);

            await resetForkToBlock();

            configure({
                chainId: chainIds[network],
                testMode: true,
            });

            senderAcc = (await hre.ethers.getSigners())[0];
            proxy = await getProxy(senderAcc.address);
            proxyAddr = proxy.address;

            console.log({
                eoa: senderAcc.address,
                proxy: proxyAddr
            });

            const aaveMarketContract = await hre.ethers.getContractAt('IPoolAddressesProvider', addrs[network].AAVE_MARKET);
            const poolAddress = await aaveMarketContract.getPool();

            pool = await hre.ethers.getContractAt('IPoolV3', poolAddress);

            strategyExecutor = await redeployCore();

            await redeploy('AaveV3QuotePriceTrigger');
            await redeploy('GasPriceTrigger');

            const { address: mockWrapperAddr } = await redeploy('MockExchangeWrapper');

            await setNewExchangeWrapper(senderAcc, mockWrapperAddr);

            botAcc = (await hre.ethers.getSigners())[1];
            await addBotCaller(botAcc.address);

            strategyExecutorByBot = strategyExecutor.connect(botAcc);

            bundleId = await deployCloseToCollWithMaximumGasPriceBundle(proxy);

            const linkInfo = getAssetInfo('LINK', chainIds[network]);
            const amountLINK = Float2BN(
                fetchAmountinUSDPrice(
                    linkInfo.symbol,
                    USD_COLL_OPEN,
                ),
                linkInfo.decimals,
            );
            await setBalance(linkInfo.address, senderAcc.address, amountLINK);

            const reserveDataLINK = await pool.getReserveData(linkInfo.address);
            const linkAssetId = reserveDataLINK.id;

            await aaveV3Supply(
                proxy,
                addrs[network].AAVE_MARKET,
                amountLINK,
                linkInfo.address,
                linkAssetId,
                senderAcc.address,
            );

            snapshotId = await takeSnapshot();
        });

        for (let i = 0; i < numTestPairs; ++i) {
            const collAssetInfo = assets.find((c) => c.symbol === testPairs[i].collAsset);
            const debtAssetInfo = assets.find((c) => c.symbol === testPairs[i].debtAsset);
            const collAddr = collAssetInfo.addresses[chainIds[network]];
            const debtAddr = debtAssetInfo.addresses[chainIds[network]];

            it('... should subscribe to AaveV3 Close With Maximum Gas Price strategy', async () => {
                await revertToSnapshot(snapshotId);
                snapshotId = await takeSnapshot();

                const amount = Float2BN(
                    fetchAmountinUSDPrice(testPairs[i].collAsset, USD_COLL_OPEN),
                    collAssetInfo.decimals,
                );
                await setBalance(collAddr, senderAcc.address, amount);

                const reserveData = await pool.getReserveData(collAddr);
                collAssetId = reserveData.id;

                await aaveV3Supply(
                    proxy,
                    addrs[network].AAVE_MARKET,
                    amount,
                    collAddr,
                    collAssetId,
                    senderAcc.address,
                );

                const reserveDataDebt = await pool.getReserveData(debtAddr);

                const amountDebt = Float2BN(
                    fetchAmountinUSDPrice(testPairs[i].debtAsset, USD_DEBT_OPEN),
                    debtAssetInfo.decimals,
                );
                debtAssetId = reserveDataDebt.id;

                await aaveV3Borrow(
                    proxy,
                    addrs[network].AAVE_MARKET,
                    amountDebt,
                    senderAcc.address,
                    RATE_MODE,
                    debtAssetId,
                );

                await setBalance(debtAddr, senderAcc.address, Float2BN('0'));

                const triggerPrice = Float2BN(
                    `${(getLocalTokenPrice(collAssetInfo.symbol) * 0.8).toFixed(8)}`,
                    8,
                );

                ({
                    subId,
                    strategySub: sub
                } = await subAaveV3CloseWithMaximumGasPriceBundle(
                    proxy,
                    bundleId,
                    collAddr,
                    nullAddress,
                    triggerPrice,
                    RATIO_STATE_OVER,
                    300000000000,
                    collAddr,
                    collAssetId,
                    debtAddr,
                    debtAssetId,
                ));

                await activateSub(proxy, subId);
            });

            it('... should call AaveV3 Close With Maximum Gas Price strategy', async () => {
                snapshotId4partial = await takeSnapshot();
                // eslint-disable-next-line max-len
                const usdRepayAmount = USD_DEBT_OPEN * (1 + EXPECTED_MAX_INTEREST);
                const usdSwapAmount = usdRepayAmount * (1 + ALLOWED_SLIPPAGE);
                const swapAmount = Float2BN(
                    fetchAmountinUSDPrice(
                        collAssetInfo.symbol,
                        usdSwapAmount,
                    ),
                    collAssetInfo.decimals,
                );

                const collAssetBalanceBefore = await balanceOf(
                    compare(collAddr, getAssetInfo('WETH', chainIds[network]).address) ? ETH_ADDR : collAddr,
                    senderAcc.address,
                );

                const debtAssetBalanceBefore = await balanceOf(
                    compare(debtAddr, getAssetInfo('WETH', chainIds[network]).address, chainIds[network]) ? ETH_ADDR : debtAddr,
                    senderAcc.address,
                );

                await callAaveCloseToCollWithMaximumGasPriceStrategy(
                    strategyExecutorByBot,
                    subId,
                    sub,
                    swapAmount,
                    collAssetInfo,
                    debtAssetInfo,
                );

                const {
                    collAssetBalance,
                    collAssetBalanceFloat
                } = await balanceOf(
                    compare(collAddr, getAssetInfo('WETH', chainIds[network]).address) ? ETH_ADDR : collAddr,
                    senderAcc.address,
                )
                    .then((e) => Object({
                        collAssetBalance: e.sub(collAssetBalanceBefore),
                        collAssetBalanceFloat: BN2Float(
                            e.sub(collAssetBalanceBefore), collAssetInfo.decimals,
                        ),
                    }));

                const {
                    debtAssetBalance,
                    debtAssetBalanceFloat
                } = await balanceOf(
                    compare(debtAddr, getAssetInfo('WETH', chainIds[network]).address, chainIds[network]) ? ETH_ADDR : debtAddr,
                    senderAcc.address,
                )
                    .then((e) => Object({
                        debtAssetBalance: e.sub(debtAssetBalanceBefore),
                        debtAssetBalanceFloat: BN2Float(
                            e.sub(debtAssetBalanceBefore), debtAssetInfo.decimals,
                        ),
                    }));

                console.log('-----sender coll/debt assets after close-----');
                console.log(`${collAssetInfo.symbol} balance: ${collAssetBalanceFloat} ($${collAssetBalanceFloat * getLocalTokenPrice(collAssetInfo.symbol)})`);
                console.log(`${debtAssetInfo.symbol} balance: ${debtAssetBalanceFloat} ($${debtAssetBalanceFloat * getLocalTokenPrice(debtAssetInfo.symbol)})`);
                console.log('---------------------------------------------');

                expect(await balanceOf(collAddr, proxyAddr))
                    .to
                    .be
                    .eq(Float2BN('0'));
                expect(await balanceOf(debtAddr, proxyAddr))
                    .to
                    .be
                    .eq(Float2BN('0'));
                expect(
                    collAssetBalance,
                )
                    .to
                    .be
                    .gt(
                        Float2BN(
                            fetchAmountinUSDPrice(
                                collAssetInfo.symbol,
                                (USD_COLL_OPEN - usdSwapAmount) * (1 - EXPECTED_MAX_FEE),
                            ),
                            collAssetInfo.decimals,
                        ),
                    );
                expect(debtAssetBalance)
                    .to
                    .be
                    .lte(
                        Float2BN(
                            fetchAmountinUSDPrice(
                                debtAssetInfo.symbol,
                                usdRepayAmount * ALLOWED_SLIPPAGE,
                            ),
                            debtAssetInfo.decimals,
                        ),
                    );
            });
        }
    });
};

module.exports = {
    aaveV3CloseToCollWithMaximumGasPriceStrategyTest,
};
