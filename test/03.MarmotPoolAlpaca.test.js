const hre = require('hardhat')
const { expect } = require('chai')
const BigNumber = require("bignumber.js");

const fs = require("fs");
const file = fs.createWriteStream("../deploy-logger.js", { 'flags': 'w'});
let logger = new console.Console(file, file);

const decimalStr = (value) => {
  return new BigNumber(value).multipliedBy(10 ** 18).toFixed(0, BigNumber.ROUND_DOWN)
}

const decimalStrUSDT = (value) => {
  return new BigNumber(value).multipliedBy(10 ** 6).toFixed(0, BigNumber.ROUND_DOWN)
}
// rescale
function one(value=1, left=0, right=18) {
    let from = ethers.BigNumber.from('1' + '0'.repeat(left))
    let to = ethers.BigNumber.from('1' + '0'.repeat(right))
    return ethers.BigNumber.from(value).mul(to).div(from)
}

function neg(value) {
    return value.mul(-1)
}

const fastMove = async (moveBlockNum) => {
    var res
    for (let i = 0; i < moveBlockNum; i++) {
      res = await hre.network.provider.send("evm_mine");
    }
    return res
  }


const MAX = ethers.BigNumber.from('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const DEADLINE = parseInt(Date.now() / 1000) + 86400

describe('MarmotPool', function () {

    let deployer
    let alice
    let bob


    let marmot
    let busd
    let wbnb
    let btc
    let alpaca

    let oracleBTCUSD
    let oracleBNBUSD

    let swapperWBNB
    let swapperBTC
    let swapperBUSD
    let swapperALPACA


    let pool

    let alpacaFairLaunchAddrees = "0xac2fefDaF83285EA016BE3f5f1fb039eb800F43D"
    let alpacaVault

    beforeEach(async function() {
        [deployer, alice, bob] = await ethers.getSigners()
        deployer.name = 'deployer'
        alice.name = 'alice'
        bob.name = 'bob'

        // const alpacaVault = await ethers.getContractAt('IAlpacaVault', "0xe5ed8148fE4915cE857FC648b9BdEF8Bb9491Fa5");
        // console.log('alpacaVault', alpacaVault)
        // console.log('alpacaVault.token', await alpacaVault.token())
        // console.log('alpacaVault.totalToken', await alpacaVault.totalToken())
        const alpacaAddress = "0x354b3a11D5Ea2DA89405173977E271F58bE2897D"
        alpaca = await ethers.getContractAt('contracts/interface/IERC20.sol:IERC20', alpacaAddress)
        const busdAddress = "0x0266693F9Df932aD7dA8a9b44C2129Ce8a87E81f"
        busd = await ethers.getContractAt('contracts/interface/IERC20.sol:IERC20', busdAddress)
        const btcAddress ="0xccaf3fc49b0d0f53fe2c08103f75a397052983fb"
        btc = await ethers.getContractAt('contracts/interface/IERC20.sol:IERC20', btcAddress)
        const wbnbAddress = "0xDfb1211E2694193df5765d54350e1145FD2404A1"
        wbnb = await ethers.getContractAt('MockWBNB', wbnbAddress)

        // console.log('balance before', await busd.balanceOf(deployer.address))
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: ["0xb4272fdd6e15018583cf8fb84b4b6d7f5d78302e"],
        });
        const signer = await ethers.getSigner("0xb4272fdd6e15018583cf8fb84b4b6d7f5d78302e")
        await busd.connect(signer).transfer(deployer.address, decimalStr("200")) // 存入200BUSD
        await btc.connect(signer).transfer(deployer.address, decimalStr("0.02")) // 存入0.02BTC
        // console.log('balance after', await busd.balanceOf(deployer.address))

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: ["0xc3F4F641143BD868E4b948Bcdad03ac8508B9D1e"],
        });
        const alpacaSigner = await ethers.getSigner("0xc3F4F641143BD868E4b948Bcdad03ac8508B9D1e")
        await alpaca.connect(alpacaSigner).transfer(deployer.address, decimalStr("20000")) // 存入20000ALPACA
        console.log('alpaca balance after', await alpaca.balanceOf(deployer.address))
        // console.log('wbnb balance after', await wbnb.balanceOf(deployer.address))
        await deployer.sendTransaction({to: wbnbAddress, value: "0x8AC7230489E80000"}) // 存入10WBNB
        // console.log('wbnb balance after', await wbnb.balanceOf(deployer.address))


        // marmot token
        marmot = await (await ethers.getContractFactory('MarmotToken')).deploy()
        await marmot.addMinter(deployer.address)
        marmot.mint(deployer.address, decimalStr("200"))

        const unifactory = await (await ethers.getContractFactory('UniswapV2Factory')).deploy(deployer.address)
        const unirouter = await (await ethers.getContractFactory('UniswapV2Router02')).deploy(unifactory.address, ZERO_ADDRESS)
        //
        //
        for (token of [busd, btc, wbnb, alpaca, marmot])
            await token.connect(deployer).approve(unirouter.address, MAX)

        await unirouter.connect(deployer).addLiquidity(busd.address, wbnb.address, decimalStr("100"), decimalStr("1"), 0, 0, deployer.address, DEADLINE)
        console.log("1")
        await unirouter.connect(deployer).addLiquidity(alpaca.address, wbnb.address, decimalStr("10000"), decimalStr("1"), 0, 0, deployer.address, DEADLINE)
        console.log("2")
        await unirouter.connect(deployer).addLiquidity(wbnb.address, btc.address, decimalStr("1"), decimalStr("0.01"), 0, 0, deployer.address, DEADLINE)
        console.log("3")
        await unirouter.connect(deployer).addLiquidity(wbnb.address, marmot.address, decimalStr("1"), decimalStr("200"), 0, 0, deployer.address, DEADLINE)
        //
        const pair1 = await ethers.getContractAt('contracts/test/UniswapV2Pair.sol:UniswapV2Pair', await unifactory.getPair(busd.address, wbnb.address))
        const pair2 = await ethers.getContractAt('contracts/test/UniswapV2Pair.sol:UniswapV2Pair', await unifactory.getPair(btc.address, wbnb.address))
        const pair3 = await ethers.getContractAt('contracts/test/UniswapV2Pair.sol:UniswapV2Pair', await unifactory.getPair(marmot.address, wbnb.address))
        const pair4 = await ethers.getContractAt('contracts/test/UniswapV2Pair.sol:UniswapV2Pair', await unifactory.getPair(alpaca.address, wbnb.address))


        swapperWBNB = await (await ethers.getContractFactory('BTokenSwapper1')).deploy(
            unirouter.address, pair3.address, wbnb.address, marmot.address, wbnb.address < marmot.address, decimalStr(1), decimalStr(1)
        )

        swapperBUSD = await (await ethers.getContractFactory('BTokenSwapper2')).deploy(
            unirouter.address, pair1.address, pair3.address, busd.address, wbnb.address, marmot.address, busd.address < wbnb.address, marmot.address < wbnb.address, decimalStr(1), decimalStr(1)
        )

        swapperBTC = await (await ethers.getContractFactory('BTokenSwapper2')).deploy(
            unirouter.address, pair2.address, pair3.address, btc.address, wbnb.address, marmot.address, btc.address < wbnb.address, marmot.address < wbnb.address, decimalStr(1), decimalStr(1)
        )

        swapperALPACA = await (await ethers.getContractFactory('BTokenSwapper2')).deploy(
            unirouter.address, pair4.address, pair3.address, alpaca.address, wbnb.address, marmot.address, alpaca.address < wbnb.address, marmot.address < wbnb.address, decimalStr(1), decimalStr(1)
        )

        oracleBTCUSD = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        oracleBNBUSD = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        await oracleBTCUSD.setPrice(decimalStr(20000))
        await oracleBNBUSD.setPrice(decimalStr(300))

        pool = await (await ethers.getContractFactory('MarmotPoolAlpaca')).deploy()
        await pool.initialize(
            marmot.address,
            decimalStr("10"),
            decimalStr("15"),
            100
        )
        await pool.setAlpacaFairLaunch(alpacaFairLaunchAddrees)
        await pool.setWrappedNativeAddr(wbnbAddress)
        await marmot.addMinter(pool.address)
        await marmot.transferOwnership(pool.address)

        await pool.addPool(
            busd.address,
            'busd',
            decimalStr(1),
            ZERO_ADDRESS,
            "0xe5ed8148fE4915cE857FC648b9BdEF8Bb9491Fa5",
            3
            )
        await pool.addPool(
            btc.address,
            'btc',
            decimalStr("0.8"),
            oracleBTCUSD.address,
            "0xB8Eca31D1862B6330E376fA795609056c7421EB0",
            17
            )
        await pool.addPool(
            wbnb.address,
            'wbnb',
            decimalStr("0.8"),
            oracleBNBUSD.address,
            "0xf9d32C5E10Dd51511894b360e6bD39D7573450F9",
            1
            )

        for (token of [busd, btc, wbnb, alpaca, marmot]) {
            await token.connect(deployer).approve(pool.address, MAX)
        }

    })


    it('addLiquidity/removeLiquidity work correctly', async function () {
        console.log('start')
        console.log(await pool.getPoolLength());
        //
        await pool.connect(deployer).deposit(0, decimalStr("100")) //BUSD
        await pool.connect(deployer).deposit(1, decimalStr("0.01")) //BTC
        console.log("deployer bnb balance bef", await ethers.provider.getBalance(deployer.address))
        //"0x53444835EC580000"
        await pool.connect(deployer).deposit(2, decimalStr("6"), {value: decimalStr("6")}) //WBNB
        console.log("deployer bnb balance aft", await ethers.provider.getBalance(deployer.address))
        console.log("fastmove", await fastMove(10));


        // console.log('alpaca balance bef', await alpaca.balanceOf(pool.address))
        // await pool.alpacaHarvest()
        // console.log('alpaca balance aft', await alpaca.balanceOf(pool.address))

        // console.log("pool busd balance bef", await busd.balanceOf(pool.address))
        // await pool.connect(deployer).withdraw(0, decimalStr("100"))
        // console.log("deployer busd balance aft", await busd.balanceOf(deployer.address))
        // console.log("pool busd balance aft", await busd.balanceOf(pool.address))
        // console.log('pool alpaca balance aft', await alpaca.balanceOf(pool.address))
        // await pool.buyBackAndBurn(alpaca.address, swapperALPACA.address)

        console.log("pool bnb balance bef", await ethers.provider.getBalance(pool.address))
        await pool.connect(deployer).withdraw(2, decimalStr("6"))
        console.log("deployer bnb balance aft", await ethers.provider.getBalance(deployer.address))
        console.log("pool bnb balance aft", await ethers.provider.getBalance(pool.address))
        console.log('pool alpaca balance aft', await alpaca.balanceOf(pool.address))
        // await pool.buyBackAndBurn(alpaca.address, swapperALPACA.address)




    })


})
