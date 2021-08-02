require('@nomiclabs/hardhat-ethers')
const hre = require('hardhat')

// rescale
function one(value=1, left=0, right=18) {
    let from = ethers.BigNumber.from('1' + '0'.repeat(left))
    let to = ethers.BigNumber.from('1' + '0'.repeat(right))
    return ethers.BigNumber.from(value).mul(to).div(from)
}

const MAX = ethers.BigNumber.from('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const DEADLINE = parseInt(Date.now() / 1000) + 86400

let network
let deployer

async function logTransaction(title, transaction) {
    let receipt = await transaction.wait()
    if (receipt.contractAddress != null) {
        title = `${title}: ${receipt.contractAddress}`
    }
    let gasEthers = transaction.gasPrice.mul(receipt.gasUsed)
    console.log('='.repeat(80))
    console.log(title)
    console.log('='.repeat(80))
    console.log(receipt)
    console.log(`Gas: ${ethers.utils.formatUnits(transaction.gasPrice, 'gwei')} GWei / ${receipt.gasUsed} / ${ethers.utils.formatEther(gasEthers)}`)
    console.log('')
    await new Promise(resolve => setTimeout(resolve, 2000))
}

async function getNetwork() {
    network = await ethers.provider.getNetwork()
    if (network.chainId === 97)
        network.name = 'bsctestnet'
    else if (network.chainId === 256)
        network.name = 'hecotestnet'
    deployer = (await ethers.getSigners())[0]

    console.log('='.repeat(80))
    console.log('Network and Deployer')
    console.log('='.repeat(80))
    console.log('Network:', network.name, network.chainId)
    console.log('Deployer:', deployer.address)
    console.log('Deployer Balance:', ethers.utils.formatEther(await deployer.getBalance()))
    console.log('')
}

parameters = {
    decimals0:                 18,
    minBToken0Ratio:           one(2, 1),
    minPoolMarginRatio:        one(),
    minInitialMarginRatio:     one(1, 1),
    minMaintenanceMarginRatio: one(5, 2),
    minLiquidationReward:      0,
    maxLiquidationReward:      one(1000),
    liquidationCutRatio:       one(5, 1),
    protocolFeeCollectRatio:   one(2, 1),
}

addresses = {
    busd:                 '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56',
    liquidatorQualifier:  '0x0000000000000000000000000000000000000000',
    protocolFeeCollector: '0xeBCbC6B9B782F3DFD61FFf70b2aAA0aE8D8b2a8D',

    // oracleSignatory:      '0xBfF0Bab15d23651e058f3a5441c9060AF4eB6E7A',
    // oracleBTCUSD:         '0x46198ffF8374587764e678Bddcd7863F02086b53',
    // oracleETHUSD:         '0xEc8df89aD16a40622db191A45821c0496c0DFF1a',

    // wooracle old
    oracleBTCUSD:         '0xFB395C51eb2b89e873e97E5CD4ca81B0756147BB',
    oracleETHUSD:         '0xC8e3a84927593c047239c2437A3893e6BC5050F0',

    lToken:               '0x6f8F1C2781b555B63F1A1BE85BF99aEe27d87cB2',
    pToken:               '0x2AA5865BF556ab3f6Cd9405e565099f70234dF05',
    router:               '0xC9C234243f48Fa05A993c29B4F5f93048f5b07E4',
    perpetualPool:        '0x19c2655A0e1639B189FB0CF06e02DC0254419D92',
}

async function deploySymbolOracleOffChain() {
    oracleBTCUSD = await (await ethers.getContractFactory('SymbolOracleOffChain')).deploy(
        'BTCUSD', addresses.oracleSignatory, 60
    )
    await logTransaction('oracleBTCUSD', oracleBTCUSD.deployTransaction)

    await new Promise(resolve => setTimeout(resolve, 30000))
    await hre.run('verify:verify', {
        address: oracleBTCUSD.address,
        constructorArguments: ['BTCUSD', addresses.oracleSignatory, 60]
    })

    oracleETHUSD = await (await ethers.getContractFactory('SymbolOracleOffChain')).deploy(
        'ETHUSD', addresses.oracleSignatory, 60
    )
    await logTransaction('oracleETHUSD', oracleETHUSD.deployTransaction)
}

async function deploySymbolOracleWooOld() {
    oracleBTCUSD = await (await ethers.getContractFactory('SymbolOracleWooOld')).deploy('0xe3C58d202D4047Ba227e437b79871d51982deEb7')
    await logTransaction('oracleBTCUSD', oracleBTCUSD.deployTransaction)

    await new Promise(resolve => setTimeout(resolve, 30000))
    await hre.run('verify:verify', {
        address: oracleBTCUSD.address,
        constructorArguments: ['0xe3C58d202D4047Ba227e437b79871d51982deEb7']
    })

    oracleETHUSD = await (await ethers.getContractFactory('SymbolOracleWooOld')).deploy('0x9BA8966B706c905E594AcbB946Ad5e29509f45EB')
    await logTransaction('oracleETHUSD', oracleETHUSD.deployTransaction)
}

async function deployLToken() {
    lToken = await (await ethers.getContractFactory('LToken')).deploy('DeriV2 Liquidity Token', 'DLT', 0)
    await logTransaction('lToken', lToken.deployTransaction)

    await new Promise(resolve => setTimeout(resolve, 30000))
    await hre.run('verify:verify', {
        address: lToken.address,
        constructorArguments: ['DeriV2 Liquidity Token', 'DLT', 0]
    })
}

async function deployPToken() {
    pToken = await (await ethers.getContractFactory('PToken')).deploy('DeriV2 Position Token', 'DPT', 0, 0)
    await logTransaction('pToken', pToken.deployTransaction)

    await new Promise(resolve => setTimeout(resolve, 30000))
    await hre.run('verify:verify', {
        address: pToken.address,
        constructorArguments: ['DeriV2 Position Token', 'DPT', 0, 0]
    })
}

async function deployPerpetualPoolRouter() {
    router = await (await ethers.getContractFactory('PerpetualPoolRouter')).deploy(
        addresses.lToken,
        addresses.pToken,
        addresses.liquidatorQualifier
    )
    await logTransaction('router', router.deployTransaction)

    await new Promise(resolve => setTimeout(resolve, 30000))
    await hre.run('verify:verify', {
        address: router.address,
        constructorArguments: [addresses.lToken, addresses.pToken, addresses.liquidatorQualifier]
    })
}

async function deployPerpetualPool() {
    perpetualPool = await (await ethers.getContractFactory('PerpetualPool')).deploy(
        [
            parameters.decimals0,
            parameters.minBToken0Ratio,
            parameters.minPoolMarginRatio,
            parameters.minInitialMarginRatio,
            parameters.minMaintenanceMarginRatio,
            parameters.minLiquidationReward,
            parameters.maxLiquidationReward,
            parameters.liquidationCutRatio,
            parameters.protocolFeeCollectRatio
        ],
        [
            addresses.lToken,
            addresses.pToken,
            addresses.router,
            addresses.protocolFeeCollector
        ]
    )
    await logTransaction('PerpetualPool', perpetualPool.deployTransaction)

    await new Promise(resolve => setTimeout(resolve, 30000))
    await hre.run('verify:verify', {
        address: perpetualPool.address,
        constructorArguments: [
            [
                parameters.decimals0,
                parameters.minBToken0Ratio,
                parameters.minPoolMarginRatio,
                parameters.minInitialMarginRatio,
                parameters.minMaintenanceMarginRatio,
                parameters.minLiquidationReward,
                parameters.maxLiquidationReward,
                parameters.liquidationCutRatio,
                parameters.protocolFeeCollectRatio
            ],
            [
                addresses.lToken,
                addresses.pToken,
                addresses.router,
                addresses.protocolFeeCollector
            ]
        ]
    })
}

async function setPool() {
    lToken = await ethers.getContractAt('LToken', addresses.lToken)
    tx = await lToken.setPool(addresses.perpetualPool)
    await logTransaction('LToken setPool', tx)

    pToken = await ethers.getContractAt('PToken', addresses.pToken)
    tx = await pToken.setPool(addresses.perpetualPool)
    await logTransaction('PToken setPool', tx)

    router = await ethers.getContractAt('PerpetualPoolRouter', addresses.router)
    tx = await router.setPool(addresses.perpetualPool)
    await logTransaction('Router setPool', tx)
}

async function addBToken() {
    router = await ethers.getContractAt('PerpetualPoolRouter', addresses.router)
    tx = await router.addBToken(addresses.busd, ZERO_ADDRESS, ZERO_ADDRESS, one())
    await logTransaction('Add BToken0', tx)
}

async function addSymbol() {
    router = await ethers.getContractAt('PerpetualPoolRouter', addresses.router)

    tx = await router.addSymbol(
        'BTCUSD',
        addresses.oracleBTCUSD,
        one(1, 4),
        one(5, 4),
        one(5, 7)
    )
    await logTransaction('add BTCUSD', tx)

    tx = await router.addSymbol(
        'ETHUSD',
        addresses.oracleETHUSD,
        one(1, 3),
        one(5, 4),
        one(75, 8)
    )
    await logTransaction('add ETHUSD', tx)
}

async function setSymbolParameters() {
    router = await ethers.getContractAt('PerpetualPoolRouter', addresses.router)

    tx = await router.setSymbolParameters(0, addresses.oracleBTCUSD, one(1, 3), one(5, 7))
    await logTransaction('setSymbolParameters 0', tx)

    tx = await router.setSymbolParameters(1, addresses.oracleETHUSD, one(1, 3), one(75, 8))
    await logTransaction('setSymbolParameters 1', tx)
}

async function main() {
    await getNetwork()

    // await deploySymbolOracleOffChain()
    await deploySymbolOracleWooOld()
    // await deployLToken()
    // await deployPToken()
    // await deployPerpetualPoolRouter()
    // await deployPerpetualPool()
    // await setPool()
    // await addBToken()
    // await addSymbol()
    // await setSymbolParameters()
}

main()
.then(() => process.exit(0))
.catch(error => {
    console.error(error);
    process.exit(1);
});


